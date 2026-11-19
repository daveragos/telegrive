import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/transfers/data/ios_background_transfers.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart'
    show TransferKind, TransferOrigin, TransferRow, TransferStatus;

TransferItem _item(
  String id, {
  TransferKind kind = TransferKind.upload,
  TransferOrigin origin = TransferOrigin.manual,
  TransferStatus status = TransferStatus.running,
  int total = 100,
  int done = 0,
  double speed = 0,
}) => TransferItem(
  TransferRow(
    id: id,
    kind: kind,
    status: status,
    name: '$id.pdf',
    mimeType: 'application/pdf',
    fileId: id,
    ownsSource: false,
    wifiOnly: false,
    totalBytes: total,
    doneBytes: done,
    partCount: 1,
    completedParts: 0,
    createdAt: DateTime(2026, 11, 20),
    origin: origin,
  ),
  bytesPerSecond: speed,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('telegrive/background_transfers');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late bool onScreen;
  late IosBackgroundTransfers keeper;
  final t0 = DateTime(2026, 11, 20, 9);

  setUp(() {
    calls = [];
    onScreen = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'begin' ? true : null;
    });
    keeper = IosBackgroundTransfers(onScreen: () => onScreen, channel: channel);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  List<String> methods() => [for (final call in calls) call.method];

  test('begins on screen with an upload, moves on with it, and ends when it is done', () async {
    await keeper.follow(TransfersState([_item('a', done: 10)]), now: t0);
    expect(methods(), ['begin']);
    expect(calls.single.arguments, containsPair('title', 'Uploading 1 file'));
    expect(calls.single.arguments, containsPair('done', 100));

    await keeper.follow(TransfersState([_item('a', done: 60, speed: 2000)]), now: t0.add(const Duration(seconds: 2)));
    expect(methods(), ['begin', 'update']);
    expect(calls.last.arguments, containsPair('done', 600));

    await keeper.follow(TransfersState([_item('a', status: TransferStatus.completed, done: 100)]));
    expect(methods(), ['begin', 'update', 'end']);
  });

  test('photo backup alone asks for nothing, and nothing begins off screen', () async {
    await keeper.follow(TransfersState([_item('b', origin: TransferOrigin.backup)]), now: t0);
    expect(calls, isEmpty);

    onScreen = false;
    await keeper.follow(TransfersState([_item('a')]), now: t0);
    expect(calls, isEmpty);
  });

  test('the share done grows as one file finishes and the next starts', () async {
    await keeper.follow(TransfersState([_item('a', done: 50), _item('b', status: TransferStatus.queued)]), now: t0);
    await keeper.follow(
      TransfersState([_item('a', status: TransferStatus.completed, done: 100), _item('b', done: 0)]),
      now: t0.add(const Duration(seconds: 5)),
    );
    expect(calls.last.method, 'update');
    expect(calls.last.arguments, containsPair('done', 500));
    expect(calls.last.arguments, containsPair('title', 'Uploading 1 file'));
  });

  test('updates come at most once a second while the title stays', () async {
    await keeper.follow(TransfersState([_item('a', done: 10)]), now: t0);
    await keeper.follow(TransfersState([_item('a', done: 20)]), now: t0.add(const Duration(milliseconds: 300)));
    expect(methods(), ['begin']);
    await keeper.follow(TransfersState([_item('a', done: 30)]), now: t0.add(const Duration(milliseconds: 1200)));
    expect(methods(), ['begin', 'update']);
  });

  test('a task iOS ended begins again the next time there is work on screen', () async {
    await keeper.follow(TransfersState([_item('a')]), now: t0);
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('stopped')),
      (_) {},
    );
    await keeper.follow(TransfersState([_item('a', done: 50)]), now: t0.add(const Duration(seconds: 3)));
    expect(methods(), ['begin', 'begin']);
  });

  test('uploads and downloads are named apart, with the speed beside the share', () {
    final state = TransfersState([
      _item('up', done: 50, speed: 1500000),
      _item('down', kind: TransferKind.download, origin: TransferOrigin.save, done: 50),
    ]);
    final (title, subtitle, done) = IosBackgroundTransfers.describe(state, {'up', 'down'});
    expect(title, 'Uploading 1 file · Downloading 1 file');
    expect(subtitle, startsWith('50% · '));
    expect(done, 500);
  });
}
