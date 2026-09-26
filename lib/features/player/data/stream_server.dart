import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/database/app_database.dart' show PartRow;
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';

/// Serves drive files over HTTP on the phone's own loopback address, reading
/// each byte range from Telegram only when the player asks for it. That is
/// how a video starts in a second instead of after a full download, and why
/// seeking jumps straight to the middle. Split files play straight through
/// their parts.
///
/// Only this app can use it: it listens on 127.0.0.1 and every URL carries
/// a random token made fresh each launch.
class StreamServer {
  StreamServer(this._ref);

  final Ref _ref;
  final String _token = _randomToken();
  Future<HttpServer>? _server;

  static const int _chunk = 512 * 1024;

  TelegramClient get _client => _ref.read(telegramClientProvider);
  DriveRepository get _repository => _ref.read(driveRepositoryProvider);

  /// A URL the player can stream [file] from.
  Future<Uri> urlFor(DriveFile file) async {
    final server = await (_server ??= _start());
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      // The name's extension helps the player pick a format.
      pathSegments: [_token, file.id, DeviceStorage.safeName(file.name)],
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
      final file = segments.length >= 2 && segments[0] == _token
          ? await _repository.fileById(segments[1])
          : null;
      final parts = file == null ? const <PartRow>[] : await _repository.partsOf(file.id);
      if (file == null || parts.isEmpty) {
        response.statusCode = HttpStatus.notFound;
        return;
      }

      final total = file.size;
      var start = 0;
      var end = total - 1;
      final range = RegExp(r'bytes=(\d*)-(\d*)')
          .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      if (range != null) {
        final from = int.tryParse(range[1]!);
        final to = int.tryParse(range[2]!);
        if (from != null) {
          start = from;
          if (to != null) end = math.min(to, total - 1);
        } else if (to != null) {
          // "bytes=-500": the last 500 bytes.
          start = math.max(0, total - to);
        }
        if (start > end || start >= total) {
          response
            ..statusCode = HttpStatus.requestedRangeNotSatisfiable
            ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
          return;
        }
        response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
      }
      response.headers
        ..contentType = ContentType.parse(file.mimeType)
        ..contentLength = end - start + 1
        ..set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (request.method == 'HEAD') return;
      await _pipe(parts, start, end, response);
    } catch (e) {
      // Usually the player closing a connection to seek elsewhere.
      if (e is! HttpException && e is! SocketException) debugPrint('[Stream] $e');
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Writes bytes [start]..[end] (inclusive) of a file made of [parts].
  Future<void> _pipe(List<PartRow> parts, int start, int end, HttpResponse out) async {
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
        );
      }
      base = partEnd;
    }
  }

  /// Streams one part's bytes [from]..[to) as TDLib fetches them.
  Future<void> _pipePart(int fileId, int from, int to, HttpResponse out) async {
    var position = from;
    await _fetchFrom(fileId, position);
    while (position < to) {
      final ready = await _waitForBytes(fileId, position);
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
  }

  /// Points TDLib's download of [fileId] at [offset]; it carries on to the
  /// end from there at the highest priority.
  Future<void> _fetchFrom(int fileId, int offset) => _client.send<td.File>(
    td.DownloadFile(
      fileId: fileId,
      priority: 32,
      offset: offset,
      limit: 0,
      synchronous: false,
    ),
  );

  /// How many bytes TDLib has at [offset], once it has any.
  Future<int> _waitForBytes(int fileId, int offset) async {
    final stalledSince = DateTime.now();
    var nudged = DateTime.now();
    while (true) {
      final ready = await _client.send<td.FileDownloadedPrefixSize>(
        td.GetFileDownloadedPrefixSize(fileId: fileId, offset: offset),
      );
      if (ready.size > 0) return ready.size;

      final now = DateTime.now();
      if (now.difference(stalledSince) > const Duration(minutes: 2)) {
        throw TimeoutException('No data from Telegram');
      }
      // Another request for the same file may have moved TDLib's download
      // elsewhere; bring it back.
      if (now.difference(nudged) > const Duration(seconds: 2)) {
        nudged = now;
        await _fetchFrom(fileId, offset);
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
