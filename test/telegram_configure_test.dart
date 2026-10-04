import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/infrastructure/telegram/secure_store.dart';
import 'package:telegrive/infrastructure/telegram/td_ownership.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

/// App support in a folder of the test's own.
class _Paths extends PathProviderPlatform {
  _Paths(this.support);

  final String support;

  @override
  Future<String?> getApplicationSupportPath() async => support;
}

/// The keystore, holding [key] or, when it can't be read, nothing.
class _Keys extends SecureStore {
  _Keys(this.key);

  String? key;
  int writes = 0;

  @override
  Future<String?> readDatabaseKey() async => key;

  @override
  Future<void> writeDatabaseKey(String key) async {
    writes++;
    this.key = key;
  }
}

/// TDLib turning down its parameters with [refusal], or taking them when
/// there is none.
class _Client extends TelegramClient {
  _Client(super.keys, {super.role, this.refusal});

  final TelegramException? refusal;
  int parametersSent = 0;

  @override
  Future<T> send<T extends td.TdObject>(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (function is td.SetTdlibParameters) {
      parametersSent++;
      final refused = refusal;
      if (refused != null && parametersSent == 1) throw refused;
    }
    return const td.Ok() as T;
  }

  /// Asks for the parameters the way TDLib does once it is loaded, and
  /// waits until they have been dealt with: TDLib took them, or
  /// [fatalError] says why not.
  Future<void> configure() async {
    final said = Completer<void>();
    void listener() {
      if (fatalError.value != null && !said.isCompleted) said.complete();
    }

    fatalError.addListener(listener);
    receive(
      const td.UpdateAuthorizationState(
        authorizationState: td.AuthorizationStateWaitTdlibParameters(),
      ).toJson(),
    );
    final until = DateTime.now().add(const Duration(seconds: 5));
    while (!said.isCompleted &&
        parametersSent < (refusal == null ? 1 : 2) &&
        DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fatalError.removeListener(listener);
  }
}

const _locked = TelegramException(
  400,
  'Can\'t lock file "td.binlog", because it is already in use; check for another program '
  'instance running',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late File kept;
  late PathProviderPlatform paths;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    support = await Directory.systemTemp.createTemp('telegrive_configure');
    kept = File('${support.path}/tdlib/db/td.binlog');
    await kept.create(recursive: true);
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(support.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = paths;
    await support.delete(recursive: true);
  });

  test('a database another TDLib still holds is kept, and the app says to try again', () async {
    final keys = _Keys('key');
    final client = _Client(keys, refusal: _locked);
    addTearDown(client.dispose);

    await client.configure();

    expect(
      client.fatalError.value,
      'Telegram is still running in the background. Try again in a moment.',
    );
    expect(await kept.exists(), isTrue);
    expect((keys.writes, keys.key), (0, 'key'));
    expect(client.parametersSent, 1);
  });

  test('the background job never makes a key it could not read', () async {
    final keys = _Keys(null);
    final client = _Client(keys, role: TdRole.worker);
    addTearDown(client.dispose);

    await client.configure();

    expect(client.fatalError.value, isNotNull);
    expect(client.parametersSent, 0);
    expect(keys.writes, 0);
    expect(await kept.exists(), isTrue);
  });

  test('the background job leaves a database TDLib turns down as it is', () async {
    final keys = _Keys('key');
    final client = _Client(
      keys,
      role: TdRole.worker,
      refusal: const TelegramException(401, 'Wrong database encryption key'),
    );
    addTearDown(client.dispose);

    await client.configure();

    expect(client.fatalError.value, isNotNull);
    expect(client.parametersSent, 1);
    expect(keys.writes, 0);
    expect(await kept.exists(), isTrue);
  });

  test('a start that fails lets go of TDLib, so trying again finds it free', () async {
    // The TDLib library is Android's, so on the host loading it fails after
    // ownership was taken.
    final client = TelegramClient(_Keys('key'));
    addTearDown(client.dispose);
    final root = Directory('${support.path}/tdlib');

    await expectLater(client.start(), throwsA(anything));
    expect(client.fatalError.value, startsWith('Could not start Telegram'));
    expect(await TdOwnership(root).isHeld(), isFalse);

    await expectLater(client.start().timeout(const Duration(seconds: 5)), throwsA(anything));
    expect(await TdOwnership(root).isHeld(), isFalse);
  });

  test('the app starts a database TDLib turns down over, with a new key', () async {
    final keys = _Keys('key');
    final client = _Client(
      keys,
      refusal: const TelegramException(401, 'Wrong database encryption key'),
    );
    addTearDown(client.dispose);

    await client.configure();

    expect(client.parametersSent, 2);
    expect(keys.writes, 1);
    expect(await kept.exists(), isFalse);
    expect(client.fatalError.value, isNull);
  });
}
