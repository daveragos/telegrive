import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/player/data/stream_server.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/secure_store.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

/// TDLib stand-in: files whose bytes are `i % 251`, which only become
/// readable a moment after something asks to download them. It keeps every
/// download asked for and every download called off.
class _FakeTelegram extends TelegramClient {
  _FakeTelegram(this.sizes) : super(SecureStore());

  final Map<int, int> sizes;
  final Map<int, int> _available = {};
  final _files = StreamController<td.File>.broadcast();
  final downloads = <({int fileId, int offset, int limit})>[];
  final cancels = <({int fileId, bool onlyIfPending})>[];

  /// Signed in from the start, so streaming finds its files at once.
  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<td.File> get fileUpdates => _files.stream;

  td.File _file(int id) => td.File(
    id: id,
    size: sizes[id]!,
    expectedSize: sizes[id]!,
    local: td.LocalFile(
      path: '',
      canBeDownloaded: true,
      canBeDeleted: true,
      isDownloadingActive: false,
      isDownloadingCompleted: (_available[id] ?? 0) >= sizes[id]!,
      downloadOffset: 0,
      downloadedPrefixSize: 0,
      downloadedSize: _available[id] ?? 0,
    ),
    remote: const td.RemoteFile(
      id: '',
      uniqueId: '',
      isUploadingActive: false,
      isUploadingCompleted: true,
      uploadedSize: 0,
    ),
  );

  @override
  Future<T> send<T extends td.TdObject>(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = switch (function) {
      td.GetFile(:final fileId) => _file(fileId),
      td.DownloadFile(:final fileId, :final offset, :final limit) => () {
        downloads.add((fileId: fileId, offset: offset, limit: limit));
        Timer(const Duration(milliseconds: 30), () {
          _available[fileId] = sizes[fileId]!;
          _files.add(_file(fileId));
        });
        return _file(fileId);
      }(),
      td.GetFileDownloadedPrefixSize(:final fileId, :final offset) =>
        td.FileDownloadedPrefixSize(
          size: ((_available[fileId] ?? 0) - offset).clamp(0, 1 << 40),
        ),
      td.CancelDownloadFile(:final fileId, :final onlyIfPending) => () {
        cancels.add((fileId: fileId, onlyIfPending: onlyIfPending));
        return const td.Ok();
      }(),
      td.ReadFilePart(:final fileId, :final offset, :final count) => td.FilePart(
        data: base64Encode([
          for (var i = offset; i < offset + count && i < (_available[fileId] ?? 0); i++)
            i % 251,
        ]),
      ),
      _ => throw UnsupportedError('$function'),
    };
    return result as T;
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late _FakeTelegram telegram;
  const partOne = 700 * 1024;
  const partTwo = 300 * 1024;
  const mib = 1024 * 1024;
  const long = 64 * mib;

  /// A container whose stream server asks [metered] whether the network
  /// is metered (Wi-Fi when not given), hears from Transfers that it is
  /// [fetching] whatever is asked, and stops downloads [grace] after their
  /// last reader.
  ProviderContainer containerFor({
    bool Function()? metered,
    bool fetching = false,
    Duration grace = const Duration(seconds: 3),
  }) => ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      telegramClientProvider.overrideWithValue(telegram),
      streamServerProvider.overrideWith(
        (ref) => StreamServer(
          ref,
          isMetered: metered ?? () => false,
          fetchingElsewhere: (_) => fetching,
          cancelGrace: grace,
        ),
      ),
    ],
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    telegram = _FakeTelegram({101: partOne, 102: partTwo, 103: long});
    container = containerFor();
    final now = DateTime(2026, 9, 26);
    for (final (index, tdFile, size) in [(0, 101, partOne), (1, 102, partTwo)]) {
      await db.upsertFilePart(
        DriveFilesCompanion.insert(
          id: 'movie',
          name: 'movie.mp4',
          mimeType: 'video/mp4',
          kind: FileKind.video,
          size: partOne + partTwo,
          createdAt: now,
          modifiedAt: now,
          partCount: const Value(2),
        ),
        FilePartsCompanion.insert(
          fileId: 'movie',
          partIndex: index,
          messageId: 10 + index,
          tdFileId: tdFile,
          size: size,
        ),
      );
    }
    await db.upsertFilePart(
      DriveFilesCompanion.insert(
        id: 'long',
        name: 'long.mp4',
        mimeType: 'video/mp4',
        kind: FileKind.video,
        size: long,
        createdAt: now,
        modifiedAt: now,
      ),
      FilePartsCompanion.insert(
        fileId: 'long',
        partIndex: 0,
        messageId: 20,
        tdFileId: 103,
        size: long,
      ),
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<(int, Map<String, String>, List<int>)> get(Uri url, {String? range}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      final body = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
      final headers = <String, String>{};
      response.headers.forEach((name, values) => headers[name] = values.join(','));
      return (response.statusCode, headers, body);
    } finally {
      client.close(force: true);
    }
  }

  List<int> expected(int from, int to) => [
    for (var i = from; i < to; i++) (i < partOne ? i : i - partOne) % 251,
  ];

  test('a range across two parts streams the right bytes', () async {
    final file = (await container.read(driveRepositoryProvider).fileById('movie'))!;
    final url = await container.read(streamServerProvider).urlFor(file);
    expect(url.host, '127.0.0.1');

    final from = partOne - 1000;
    final to = partOne + 5000;
    final (status, headers, body) = await get(url, range: 'bytes=$from-${to - 1}');
    expect(status, HttpStatus.partialContent);
    expect(headers['content-range'], 'bytes $from-${to - 1}/${partOne + partTwo}');
    expect(headers['accept-ranges'], 'bytes');
    expect(body, expected(from, to));
    // Each part was asked for from where the reading started in it.
    expect(telegram.downloads.map((d) => d.offset), containsAllInOrder([from, 0]));
  });

  test('the whole file, and the last bytes', () async {
    final file = (await container.read(driveRepositoryProvider).fileById('movie'))!;
    final url = await container.read(streamServerProvider).urlFor(file);

    final (status, headers, body) = await get(url);
    expect(status, HttpStatus.ok);
    expect(headers['content-type'], startsWith('video/mp4'));
    expect(body.length, partOne + partTwo);
    expect(body.sublist(partOne - 3, partOne + 3), [
      ...expected(partOne - 3, partOne),
      ...expected(partOne, partOne + 3),
    ]);

    final (_, _, tail) = await get(url, range: 'bytes=-100');
    expect(tail, expected(partOne + partTwo - 100, partOne + partTwo));
  });

  test('strangers and ranges past the end are refused', () async {
    final file = (await container.read(driveRepositoryProvider).fileById('movie'))!;
    final url = await container.read(streamServerProvider).urlFor(file);

    final wrongToken = url.replace(pathSegments: ['nope', ...url.pathSegments.skip(1)]);
    expect((await get(wrongToken)).$1, HttpStatus.notFound);
    final (status, _, _) = await get(url, range: 'bytes=${partOne + partTwo}-');
    expect(status, HttpStatus.requestedRangeNotSatisfiable);
  });

  group('the file picker', () {
    /// A URL on the server's own endpoint, the way the picker builds one
    /// from the bridge file.
    Future<Uri> at(List<String> Function(String token) segments) async {
      final (:port, :token) = await container.read(streamServerProvider).endpoint();
      return Uri(scheme: 'http', host: '127.0.0.1', port: port, pathSegments: segments(token));
    }

    test('finds the server at the port and token its URLs carry', () async {
      final server = container.read(streamServerProvider);
      final file = (await container.read(driveRepositoryProvider).fileById('movie'))!;
      final url = await server.urlFor(file);
      final (:port, :token) = await server.endpoint();
      expect(url.port, port);
      expect(url.pathSegments.first, token);
      expect(await server.endpoint(), (port: port, token: token));
    });

    test('gets an answer to its ping only with the token', () async {
      expect((await get(await at((token) => [token, 'ping']))).$1, HttpStatus.noContent);
      expect((await get(await at((_) => ['wrong', 'ping']))).$1, HttpStatus.notFound);
    });

    test('reads a range through the endpoint', () async {
      final (status, headers, body) = await get(
        await at((token) => [token, 'movie', 'movie.mp4']),
        range: 'bytes=${partOne - 10}-${partOne + 9}',
      );
      expect(status, HttpStatus.partialContent);
      expect(headers['content-range'], 'bytes ${partOne - 10}-${partOne + 9}/${partOne + partTwo}');
      expect(body, expected(partOne - 10, partOne + 10));
    });
  });

  group('what TDLib is asked for', () {
    Future<Uri> urlOf(
      String fileId, {
      bool Function()? metered,
      bool fetching = false,
    }) async {
      final scoped = containerFor(
        metered: metered,
        fetching: fetching,
        grace: const Duration(milliseconds: 10),
      );
      addTearDown(scoped.dispose);
      final file = (await scoped.read(driveRepositoryProvider).fileById(fileId))!;
      return scoped.read(streamServerProvider).urlFor(file);
    }

    /// Reads [url] from the start the way a player does, with no end to
    /// the range, telling [onChunk] how much has arrived so far, and hangs
    /// up once [bytes] have arrived.
    Future<void> readThenHangUp(
      Uri url,
      int bytes, {
      void Function(int received)? onChunk,
    }) async {
      final client = HttpClient();
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
      final response = await request.close();
      var received = 0;
      final enough = Completer<void>();
      final subscription = response.listen((chunk) {
        received += chunk.length;
        onChunk?.call(received);
        if (received >= bytes && !enough.isCompleted) enough.complete();
      });
      await enough.future;
      await subscription.cancel();
      client.close(force: true);
    }

    Future<void> until(bool Function() condition) async {
      for (var i = 0; i < 200 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(condition(), isTrue);
    }

    /// Long enough for the server to have noticed a hang-up and for any
    /// grace period after it to be over.
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 200));

    test('a range with an end asks for exactly its bytes', () async {
      final url = await urlOf('movie', metered: () => true);
      final (status, _, body) = await get(url, range: 'bytes=100-199');
      expect(status, HttpStatus.partialContent);
      expect(body, expected(100, 200));
      expect(telegram.downloads.first, (fileId: 101, offset: 100, limit: 100));
    });

    test('on mobile data, a player is fetched 16 MiB ahead as it reads', () async {
      final url = await urlOf('long', metered: () => true);
      await readThenHangUp(url, 12 * mib);

      expect(telegram.downloads.first, (fileId: 103, offset: 0, limit: 16 * mib));
      // Once reading passed half the window, the window moved along.
      final next = telegram.downloads[1];
      expect(next.offset, greaterThan(8 * mib));
      expect(next.offset, lessThan(16 * mib));
      expect(next.limit, 16 * mib);
      await until(() => telegram.cancels.isNotEmpty);
    });

    test('on Wi-Fi, a player is fetched to the end', () async {
      final url = await urlOf('movie');
      final (_, _, body) = await get(url, range: 'bytes=0-');
      expect(body.length, partOne + partTwo);
      expect(telegram.downloads.map((d) => d.limit), [0, 0]);
    });

    test('a player that moves onto mobile data keeps 16 MiB ahead from there', () async {
      var metered = false;
      final url = await urlOf('long', metered: () => metered);
      // Reading goes on for well over what the sockets between can hold,
      // so the server reads on after the move.
      await readThenHangUp(
        url,
        16 * mib,
        onChunk: (received) {
          if (received >= mib) metered = true;
        },
      );

      expect(telegram.downloads.first, (fileId: 103, offset: 0, limit: 0));
      // From where playing had got to, for a window rather than the rest
      // of the file.
      final narrowed = telegram.downloads[1];
      expect(narrowed.offset, greaterThanOrEqualTo(mib));
      expect(narrowed.limit, 16 * mib);
      await until(() => telegram.cancels.isNotEmpty);
    });

    test('on mobile data, a file Transfers is fetching is asked for to the end', () async {
      final url = await urlOf('long', metered: () => true, fetching: true);
      await readThenHangUp(url, 12 * mib);
      await settle();

      // Only what Transfers asked for too, which TDLib takes as the same
      // download and leaves running.
      expect(telegram.downloads, [(fileId: 103, offset: 0, limit: 0)]);
    });

    test('a range with an end of a file Transfers is fetching is asked for as Transfers asked', () async {
      final url = await urlOf('movie', metered: () => true, fetching: true);
      final (status, _, body) = await get(url, range: 'bytes=100-199');
      expect(status, HttpStatus.partialContent);
      expect(body, expected(100, 200));
      expect(telegram.downloads, [(fileId: 101, offset: 0, limit: 0)]);
    });

    test('hanging up stops the download once the grace period is over', () async {
      final url = await urlOf('long', metered: () => true);
      await readThenHangUp(url, mib);
      await until(() => telegram.cancels.isNotEmpty);
      expect(telegram.cancels, [(fileId: 103, onlyIfPending: false)]);
    });

    test('a download Transfers needs is left running', () async {
      final url = await urlOf('long', metered: () => true, fetching: true);
      await readThenHangUp(url, mib);
      await settle();
      expect(telegram.cancels, isEmpty);
    });
  });
}
