import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/mount/data/dav_server.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:xml/xml.dart';

import 'support/fake_telegram.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

/// A queue that keeps what it is asked to send, and whose uploads never
/// end unless a test ends them.
class _Queue extends TransferQueue {
  final List<({UploadRequest request, String? folderId})> sent = [];
  final List<String> cancelled = [];

  @override
  TransfersState build() => TransfersState(const []);

  @override
  Future<List<String>> enqueueUploads(List<UploadRequest> requests, {String? folderId}) async => [
    for (final request in requests) ...[
      'upload-${(sent..add((request: request, folderId: folderId))).length}',
    ],
  ];

  @override
  Future<TransferRow> whenFinished(String id) => Completer<TransferRow>().future;

  @override
  Future<void> cancel(String id) async => cancelled.add(id);
}

void main() {
  late Directory scratch;
  late AppDatabase db;
  late FakeTelegram telegram;
  late ProviderContainer container;
  late DriveRepository repository;
  late _Queue queue;
  late Uri base;
  late HttpClient client;

  Future<void> receive(td.Message message) async {
    telegram.messages[message.id] = message;
    await repository.ingest(message);
  }

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('dav_server_test');
    PathProviderPlatform.instance = _Paths(scratch.path);
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    telegram = FakeTelegram();
    queue = _Queue();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
        transferQueueProvider.overrideWith(() => queue),
        davServerProvider.overrideWith((ref) => DavServer(ref, settleFor: const Duration(milliseconds: 50))),
      ],
    );
    repository = container.read(driveRepositoryProvider);
    await receive(textMessage(1, 'tgfolder2;id=trips;name=Trips;added=1700000000000'));
    await receive(textMessage(2, 'tgfolder2;id=secret;name=Secret;added=1700000000000;private=1'));
    for (final (id, caption) in [
      (10, 'tgfile2;id=a;name=beach.jpg;folder=trips;type=image/jpeg;size=9;added=1700000000000'),
      (11, 'tgfile2;id=r1;name=Report.pdf;type=application/pdf;size=9;added=1700000000000'),
      (12, 'tgfile2;id=r2;name=report.pdf;type=application/pdf;size=9;added=1700000000000'),
    ]) {
      await receive(documentMessage(id, caption, fileName: 'f.bin', mimeType: 'application/pdf'));
    }
    base = await container.read(davServerProvider).start();
    client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      container.dispose();
      await db.close();
      await scratch.delete(recursive: true);
    });
  });

  Future<({int status, String body, HttpHeaders headers})> call(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = await client.openUrl(method, base.resolve(path));
    headers.forEach(request.headers.set);
    if (body != null) request.add(body);
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (status: response.statusCode, body: text, headers: response.headers);
  }

  /// The names a PROPFIND of [path] lists, the folder itself first.
  Future<List<String>> list(String path, {String depth = '1'}) async {
    final answer = await call('PROPFIND', path, headers: {'Depth': depth});
    expect(answer.status, 207, reason: answer.body);
    return [
      for (final name in XmlDocument.parse(answer.body).findAllElements('displayname', namespaceUri: 'DAV:'))
        name.innerText,
    ];
  }

  Future<void> settled() => Future<void>.delayed(const Duration(milliseconds: 200));

  test('the top lists folders and files, two of one name told apart, and Private left out', () async {
    expect(await list(''), ['Telegrive', 'Trips', 'Report.pdf', 'report (2).pdf']);
    expect(await list('Trips/'), ['Trips', 'beach.jpg']);
    expect(await list('', depth: '0'), ['Telegrive']);
    final top = await call('PROPFIND', '', headers: {'Depth': '0'});
    expect(top.body, contains('quota-available-bytes'));
  });

  test('only the token and the drive under it answer', () async {
    final token = base.pathSegments.first;
    expect((await call('PROPFIND', '/$token/', headers: {'Depth': '1'})).body, contains('/$token/Telegrive/'));
    expect((await call('PROPFIND', '/wrong/Telegrive/')).status, 404);
    expect((await call('GET', '/wrong/Telegrive/Report.pdf')).status, 404);
    final options = await call('OPTIONS', '/');
    expect(options.headers.value('dav'), '1, 2');
  });

  test('a new folder, a rename, a move and a delete become the drive\'s', () async {
    expect((await call('MKCOL', 'Work')).status, 201);
    expect(await list(''), contains('Work'));

    final rename = await call('MOVE', 'Report.pdf', headers: {'Destination': base.resolve('Q3 report.pdf').toString()});
    expect(rename.status, 201);
    expect((await repository.fileById('r1'))!.name, 'Q3 report.pdf');

    final move = await call('MOVE', 'Q3%20report.pdf', headers: {'Destination': base.resolve('Trips/Q3 report.pdf').toString()});
    expect(move.status, 201);
    expect((await repository.fileById('r1'))!.folderId, 'trips');

    expect((await call('DELETE', 'Trips/beach.jpg')).status, 204);
    expect(await list('Trips/'), ['Trips', 'Q3 report.pdf']);
    expect((await repository.watchTrash().first).files.map((f) => f.id), contains('a'));
  });

  test('a file written in shows at once and goes up once it settles', () async {
    expect((await call('PUT', 'Trips/notes.txt', body: utf8.encode('hello'))).status, 201);
    expect(await list('Trips/'), ['Trips', 'beach.jpg', 'notes.txt']);
    expect((await call('GET', 'Trips/notes.txt')).body, 'hello');
    await settled();
    expect(queue.sent.single.request.name, 'notes.txt');
    expect(queue.sent.single.request.ownsSource, isTrue);
    expect(queue.sent.single.folderId, 'trips');
  });

  test('Explorer\'s empty file and then its bytes go up once, an empty file never', () async {
    await call('PUT', 'draft.txt', body: const []);
    await call('PUT', 'draft.txt', body: utf8.encode('draft'));
    await call('PUT', 'empty.txt', body: const []);
    await settled();
    expect([for (final s in queue.sent) s.request.name], ['draft.txt']);
    expect(await list(''), containsAll(['draft.txt', 'empty.txt']));
  });

  test('writing over a drive file replaces it', () async {
    expect((await call('PUT', 'Trips/beach.jpg', body: [1, 2, 3])).status, 204);
    await settled();
    expect(queue.sent.single.request.replacesFileId, 'a');
    expect(queue.sent.single.request.name, 'beach.jpg');
  });

  test('what the system leaves behind is kept here and never sent', () async {
    await call('PUT', '._Report.pdf', body: [7]);
    await call('PUT', '.DS_Store', body: [8]);
    expect((await call('MKCOL', '.Trashes')).status, 201);
    await settled();
    expect(queue.sent, isEmpty);
    expect(await list(''), containsAll(['._Report.pdf', '.DS_Store', '.Trashes']));
    expect((await call('GET', '.DS_Store')).body, String.fromCharCode(8));
    expect((await call('DELETE', '.DS_Store')).status, 204);
    expect(await list(''), isNot(contains('.DS_Store')));
  });

  test('a save through a temporary file goes up under the name it is moved to', () async {
    await call('PUT', 'Report.pdf.tmp', body: [1, 2]);
    final move = await call('MOVE', 'Report.pdf.tmp', headers: {'Destination': base.resolve('Trips/Final.pdf').toString()});
    expect(move.status, 201);
    await settled();
    expect(queue.sent.single.request.name, 'Final.pdf');
    expect(queue.sent.single.folderId, 'trips');
  });

  test('a lock on a new name makes an empty file the write fills, and settles on unlock', () async {
    final lock = await call('LOCK', 'new.txt', body: utf8.encode('<?xml version="1.0"?><D:lockinfo xmlns:D="DAV:"><D:lockscope><D:exclusive/></D:lockscope><D:locktype><D:write/></D:locktype><D:owner>me</D:owner></D:lockinfo>'));
    expect(lock.status, 201);
    expect(lock.headers.value('lock-token'), startsWith('<opaquelocktoken:'));
    expect(lock.body, contains('<D:owner>me</D:owner>'));
    await call('PUT', 'new.txt', body: utf8.encode('text'));
    expect((await call('UNLOCK', 'new.txt')).status, 204);
    await settled();
    expect(queue.sent.single.request.name, 'new.txt');
  });

  test('Explorer\'s times are taken, in its own namespace', () async {
    final answer = await call(
      'PROPPATCH',
      'Report.pdf',
      body: utf8.encode(
        '<?xml version="1.0"?><D:propertyupdate xmlns:D="DAV:" xmlns:Z="urn:schemas-microsoft-com:">'
        '<D:set><D:prop><Z:Win32LastModifiedTime>Wed, 18 Nov 2026 10:00:00 GMT</Z:Win32LastModifiedTime>'
        '</D:prop></D:set></D:propertyupdate>',
      ),
    );
    expect(answer.status, 207);
    final doc = XmlDocument.parse(answer.body);
    expect(doc.findAllElements('Win32LastModifiedTime', namespaceUri: 'urn:schemas-microsoft-com:'), hasLength(1));
  });

  test('a move onto a file that is there sends that one to Trash, unless told not to', () async {
    final refused = await call(
      'MOVE',
      'report%20(2).pdf',
      headers: {'Destination': base.resolve('Report.pdf').toString(), 'Overwrite': 'F'},
    );
    expect(refused.status, 412);
    final moved = await call('MOVE', 'report%20(2).pdf', headers: {'Destination': base.resolve('Trips/beach.jpg').toString()});
    expect(moved.status, 204);
    expect((await repository.fileById('r2'))!.name, 'beach.jpg');
    expect((await repository.watchTrash().first).files.map((f) => f.id), contains('a'));
  });
}
