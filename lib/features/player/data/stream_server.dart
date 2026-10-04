import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/database/app_database.dart' show PartRow;
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../transfers/data/transfer_queue.dart';

/// Serves drive files over HTTP on the phone's own loopback address, reading
/// each byte range from Telegram only when the player asks for it. That is
/// how a video starts in a second instead of after a full download, and why
/// seeking jumps straight to the middle. Split files play straight through
/// their parts.
///
/// TDLib is asked for what is read and little more. A range with an end
/// gets exactly its bytes, which is how the PDF reader pulls a page at a
/// time. A range that runs to the end of the file, the way a player reads,
/// gets a window of read-ahead on mobile data that moves along as playing
/// does, and the whole rest of the file on Wi-Fi. A few seconds after the
/// last reader of a file hangs up, TDLib stops fetching it, unless a
/// download in Transfers needs it; what it has fetched stays on the phone.
///
/// Only this app can use it: it listens on 127.0.0.1 and every URL carries
/// a random token made fresh each launch. Android's file picker, which runs
/// in Telegrive's own picker process, learns the port and token from
/// [endpoint] through a file only this app can read.
class StreamServer {
  StreamServer(
    this._ref, {
    bool Function()? isMetered,
    bool Function(int tdFileId)? fetchingElsewhere,
    this._cancelGrace = const Duration(seconds: 3),
  }) : _isMetered =
           isMetered ?? (() => _ref.read(networkStatusProvider).metered),
       _fetchingElsewhere =
           fetchingElsewhere ??
           ((id) => _ref.read(transferQueueProvider.notifier).isFetching(id)) {
    _ref.onDispose(() {
      for (final timer in _cancels.values) {
        timer.cancel();
      }
      _cancels.clear();
    });
  }

  final Ref _ref;
  final bool Function() _isMetered;
  final bool Function(int tdFileId) _fetchingElsewhere;

  /// How long TDLib's download of a file outlives its last reader. A player
  /// seeking closes one request and opens the next straight away, and the
  /// PDF reader asks for one block after another, so a short gap must not
  /// stop the download about to be needed.
  final Duration _cancelGrace;
  final String _token = _randomToken();
  Future<HttpServer>? _server;

  /// Requests reading each TDLib file right now.
  final Map<int, int> _readers = {};

  /// Downloads to stop once their file's grace period is over.
  final Map<int, Timer> _cancels = {};

  static const int _chunk = 512 * 1024;

  /// Read-ahead on mobile data: a few seconds of 4K video, several minutes
  /// of music.
  static const int _meteredWindow = 16 * 1024 * 1024;

  TelegramClient get _client => _ref.read(telegramClientProvider);
  DriveRepository get _repository => _ref.read(driveRepositoryProvider);

  /// The port this server listens on and the token every URL starts with,
  /// starting the server if it isn't running yet.
  Future<({int port, String token})> endpoint() async {
    final server = await (_server ??= _start());
    return (port: server.port, token: _token);
  }

  /// A URL the player, or the PDF reader, can read [file] from.
  Future<Uri> urlFor(DriveFile file) async {
    final (:port, :token) = await endpoint();
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      // The name's extension helps the player pick a format.
      pathSegments: [token, file.id, DeviceStorage.safeName(file.name)],
    );
  }

  Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => unawaited(_handle(request)));
    return server;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      // The file picker asks this to tell a running app from a bridge file
      // left behind by one that has gone. Without the token it gets the 404
      // any stranger does.
      if (segments.length == 2 && segments[0] == _token && segments[1] == 'ping') {
        response.statusCode = HttpStatus.noContent;
        return;
      }
      final file = segments.length >= 2 && segments[0] == _token
          ? await _repository.fileById(segments[1])
          : null;
      final parts = file == null
          ? const <PartRow>[]
          : await _repository.partsOf(file.id);
      if (file == null || parts.isEmpty) {
        response.statusCode = HttpStatus.notFound;
        return;
      }

      final total = file.size;
      var start = 0;
      var end = total - 1;
      // Without an end, the reader takes the file from there on as it needs
      // it, so how far ahead to fetch is this server's call.
      var openEnded = true;
      final range = RegExp(r'bytes=(\d*)-(\d*)')
          .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      if (range != null) {
        final from = int.tryParse(range[1]!);
        final to = int.tryParse(range[2]!);
        if (from != null) {
          start = from;
          if (to != null) {
            end = math.min(to, total - 1);
            openEnded = false;
          }
        } else if (to != null) {
          // "bytes=-500": the last 500 bytes.
          start = math.max(0, total - to);
          openEnded = false;
        }
        if (start > end || start >= total) {
          response
            ..statusCode = HttpStatus.requestedRangeNotSatisfiable
            ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
          return;
        }
        response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/$total',
          );
      }
      response.headers
        ..contentType = ContentType.parse(file.mimeType)
        ..contentLength = end - start + 1
        ..set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (request.method == 'HEAD') return;
      await _pipe(parts, start, end, response, openEnded: openEnded);
    } catch (e) {
      // Usually the player closing a connection to seek elsewhere.
      if (e is! HttpException && e is! SocketException) {
        debugPrint('[Stream] $e');
      }
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Writes bytes [start]..[end] (inclusive) of a file made of [parts].
  Future<void> _pipe(
    List<PartRow> parts,
    int start,
    int end,
    HttpResponse out, {
    required bool openEnded,
  }) async {
    var base = 0;
    for (final part in parts) {
      final partEnd = base + part.size;
      if (end < base) break;
      if (start < partEnd) {
        final tdFile = await _repository.resolveTdFile(part);
        await _pipePart(
          tdFile.id,
          math.max(start, base) - base,
          math.min(end + 1, partEnd) - base,
          out,
          openEnded: openEnded,
        );
      }
      base = partEnd;
    }
  }

  /// Streams one part's bytes [from]..[to) as TDLib fetches them. TDLib is
  /// asked for the bytes up to `requestedUntil`, which moves along half a
  /// window before reading reaches it, so playing never waits on a request
  /// that hasn't been made.
  ///
  /// TDLib ends a download that Transfers is waiting on as soon as the
  /// same file is asked for with another offset or limit. So a player
  /// reading a file Transfers is fetching gets no window, since the whole
  /// file is coming down anyway, and a range with an end of such a file is
  /// asked for as Transfers asked, from the start to the end, and waits for
  /// that one download to reach it.
  Future<void> _pipePart(
    int fileId,
    int from,
    int to,
    HttpResponse out, {
    required bool openEnded,
  }) async {
    _readers[fileId] = (_readers[fileId] ?? 0) + 1;
    _cancels.remove(fileId)?.cancel();
    try {
      bool windowed() => _isMetered() && !_fetchingElsewhere(fileId);
      // 0 leaves TDLib to fetch to the end of the file.
      var window = openEnded ? (windowed() ? _meteredWindow : 0) : to - from;
      var position = from;
      var requestedUntil = window == 0 ? to : math.min(from + window, to);
      int limit() => window == 0 ? 0 : requestedUntil - position;

      await _fetchFrom(fileId, position, limit: limit(), openEnded: openEnded);
      while (position < to) {
        if (openEnded && window == 0 && windowed()) {
          // The phone moved onto mobile data while playing, or Transfers
          // stopped fetching the file: from here on only a window ahead is
          // fetched, not the rest of the file.
          window = _meteredWindow;
          requestedUntil = math.min(position + window, to);
          await _fetchFrom(
            fileId,
            position,
            limit: limit(),
            openEnded: openEnded,
          );
        } else if (window > 0 &&
            requestedUntil < to &&
            requestedUntil - position < window ~/ 2) {
          requestedUntil = math.min(position + window, to);
          await _fetchFrom(
            fileId,
            position,
            limit: limit(),
            openEnded: openEnded,
          );
        }
        final ready = await _waitForBytes(
          fileId,
          position,
          limit: limit(),
          openEnded: openEnded,
        );
        final count = math.min(math.min(ready, _chunk), to - position);
        final part = await _client.send<td.FilePart>(
          td.ReadFilePart(fileId: fileId, offset: position, count: count),
        );
        final bytes = base64Decode(part.data);
        if (bytes.isEmpty) continue;
        out.add(bytes);
        // Waits for the player to take them; throws once it hangs up.
        await out.flush();
        position += bytes.length;
      }
    } finally {
      _hangUp(fileId);
    }
  }

  /// One reader of [fileId] is done. When it was the last, TDLib's download
  /// of the file stops after [_cancelGrace], unless another reader has come
  /// along by then or a download in Transfers is fetching it.
  void _hangUp(int fileId) {
    // With the provider gone there is nothing left to stop.
    if (!_ref.mounted) return;
    final left = (_readers[fileId] ?? 1) - 1;
    if (left > 0) {
      _readers[fileId] = left;
      return;
    }
    _readers.remove(fileId);
    _cancels[fileId]?.cancel();
    _cancels[fileId] = Timer(_cancelGrace, () {
      _cancels.remove(fileId);
      if (_readers.containsKey(fileId) || _fetchingElsewhere(fileId)) return;
      unawaited(
        _client
            .send<td.Ok>(
              td.CancelDownloadFile(fileId: fileId, onlyIfPending: false),
            )
            .then<void>((_) {}, onError: (Object _) {}),
      );
    });
  }

  /// Points TDLib's download of [fileId] at [offset], at the highest
  /// priority, for [limit] bytes from there, or to the end with 0. A range
  /// with an end of a file Transfers is fetching keeps to the whole file
  /// from the start, which TDLib takes as the download already running.
  Future<void> _fetchFrom(
    int fileId,
    int offset, {
    required int limit,
    required bool openEnded,
  }) {
    final shared = !openEnded && _fetchingElsewhere(fileId);
    return _client.send<td.File>(
      td.DownloadFile(
        fileId: fileId,
        priority: 32,
        offset: shared ? 0 : offset,
        limit: shared ? 0 : limit,
        synchronous: false,
      ),
    );
  }

  /// How many bytes TDLib has at [offset], once it has any. [limit] and
  /// [openEnded] describe the reader's request, made again whenever the
  /// download has to be pointed back here.
  Future<int> _waitForBytes(
    int fileId,
    int offset, {
    required int limit,
    required bool openEnded,
  }) async {
    var stalledSince = DateTime.now();
    var nudged = DateTime.now();
    while (true) {
      final ready = await _client.send<td.FileDownloadedPrefixSize>(
        td.GetFileDownloadedPrefixSize(fileId: fileId, offset: offset),
      );
      if (ready.size > 0) return ready.size;

      final now = DateTime.now();
      // A download in Transfers brings the file down from its start, so
      // bytes far into it are on their way however long they take.
      if (_fetchingElsewhere(fileId)) stalledSince = now;
      if (now.difference(stalledSince) > const Duration(minutes: 2)) {
        throw TimeoutException('No data from Telegram');
      }
      // Another request for the same file may have moved TDLib's download
      // elsewhere; bring it back.
      if (now.difference(nudged) > const Duration(seconds: 2)) {
        nudged = now;
        await _fetchFrom(fileId, offset, limit: limit, openEnded: openEnded);
      }
      try {
        await _client.fileUpdates
            .firstWhere((f) => f.id == fileId)
            .timeout(const Duration(milliseconds: 400));
      } on TimeoutException {
        // Poll again.
      }
    }
  }

  static String _randomToken() {
    final random = math.Random.secure();
    return base64Url.encode(List.generate(18, (_) => random.nextInt(256)));
  }
}

final streamServerProvider = Provider<StreamServer>(StreamServer.new);
