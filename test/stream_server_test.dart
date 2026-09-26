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
/// readable a moment after something asks to download them.
class _FakeTelegram extends TelegramClient {
  _FakeTelegram(this.sizes) : super(SecureStore());

  final Map<int, int> sizes;
  final Map<int, int> _available = {};
  final _files = StreamController<td.File>.broadcast();
  final requestedOffsets = <int>[];

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
      td.DownloadFile(:final fileId, :final offset) => () {
        requestedOffsets.add(offset);
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

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    telegram = _FakeTelegram({101: partOne, 102: partTwo});
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
      ],
    );
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
    expect(telegram.requestedOffsets, containsAllInOrder([from, 0]));
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
}
