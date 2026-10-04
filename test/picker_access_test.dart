import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/lock/data/app_lock.dart';
import 'package:telegrive/features/picker/data/picker_access.dart';
import 'package:telegrive/features/player/data/stream_server.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

const _session = DriveSession(
  userId: 1,
  chatId: -100,
  channelTitle: 'Telegrive',
  firstName: 'A',
  lastName: '',
  phoneNumber: '',
  username: null,
  isPremium: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  const picker = MethodChannel('telegrive/picker');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory support;
  late List<bool> sent;

  setUp(() {
    support = Directory.systemTemp.createTempSync('picker_access_test');
    sent = [];
    messenger.setMockMethodCallHandler(pathProvider, (call) async => support.path);
    messenger.setMockMethodCallHandler(picker, (call) async {
      if (call.method == 'setEnabled') sent.add(call.arguments as bool);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(pathProvider, null);
    messenger.setMockMethodCallHandler(picker, null);
    support.deleteSync(recursive: true);
  });

  File bridge() => File('${support.path}/picker/bridge.json');

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  Future<ProviderContainer> start(Map<String, Object> stored) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(stored);
    final shared = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        pickerSupportedProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    container.read(pickerAccessProvider);
    return container;
  }

  test('is off until the person turns it on', () async {
    final container = await start({});
    container.read(driveSessionProvider.notifier).open(_session);
    await until(() => sent.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sent, [false]);
    expect(bridge().existsSync(), isFalse);
  });

  test('turned on with the drive open, points the picker at the stream server', () async {
    final container = await start({});
    container.read(driveSessionProvider.notifier).open(_session);
    await container.read(pickerEnabledProvider.notifier).set(true);
    await until(() => bridge().existsSync());

    expect(sent.last, isTrue);
    final (:port, :token) = await container.read(streamServerProvider).endpoint();
    expect(jsonDecode(bridge().readAsStringSync()), {'port': port, 'token': token});
    expect(container.read(preferencesProvider).pickerEnabled, isTrue);

    // A closed drive has no server to point at, and the picker stays on
    // for the files already on the phone.
    container.read(driveSessionProvider.notifier).close();
    await until(() => !bridge().existsSync());
    expect(sent.last, isTrue);
  });

  test('stays off while app lock is on, and comes back as it was', () async {
    final container = await start({'picker_enabled': true, 'app_lock': true});
    container.read(driveSessionProvider.notifier).open(_session);
    await until(() => sent.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sent, [false]);
    expect(bridge().existsSync(), isFalse);

    await container.read(appLockProvider.notifier).setEnabled(false);
    await until(() => bridge().existsSync());
    expect(sent, [false, true]);
    expect(container.read(pickerEnabledProvider), isTrue);
  });
}
