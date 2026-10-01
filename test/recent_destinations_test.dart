import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/lock/data/app_lock.dart';
import 'package:telegrive/features/share/data/recent_destinations.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

import 'support/fake_telegram.dart';

/// A sync that runs only when a test says so.
class _Sync extends DriveSync {
  @override
  SyncState build() => const SyncState();

  void running(bool running) => state = SyncState(running: running);
}

/// App lock, on or off as a test says.
class _Lock extends AppLock {
  _Lock(this.enabled);

  final bool enabled;

  @override
  AppLockState build() => AppLockState(enabled: enabled);

  void set(bool enabled) => state = AppLockState(enabled: enabled);
}

/// The drive, where looking up a folder that has a gate in [gates] waits
/// for it, once.
class _GatedRepository extends DriveRepository {
  _GatedRepository(super.ref, this.gates);

  final Map<String, Completer<void>> gates;

  @override
  Future<DriveFolder?> shownFolder(String id) async {
    await gates.remove(id)?.future;
    return super.shownFolder(id);
  }
}

/// A folder in the drive, in the trash when [trashed].
FoldersCompanion _folder(String id, String name, {bool trashed = false}) =>
    FoldersCompanion.insert(
      id: id,
      name: name,
      messageId: id.hashCode,
      createdAt: DateTime(2026, 9, 1),
      modifiedAt: DateTime(2026, 9, 1),
      trashedAt: Value(trashed ? DateTime(2026, 9, 20) : null),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const share = MethodChannel('telegrive/share');

  group('pushed', () {
    test('moves a folder to the front without keeping its old place', () {
      expect(RecentDestinations.pushed(['a', 'b', 'c'], 'b'), ['b', 'a', 'c']);
      expect(RecentDestinations.pushed(['a', 'b'], 'a'), ['a', 'b']);
      expect(RecentDestinations.pushed([], 'a'), ['a']);
    });

    test('keeps the five most recent', () {
      expect(
        RecentDestinations.pushed(['a', 'b', 'c', 'd', 'e'], 'f'),
        ['f', 'a', 'b', 'c', 'd'],
      );
    });

    test('keeps the root as an empty id, like any folder', () {
      expect(RecentDestinations.pushed(['a', '', 'b'], ''), ['', 'a', 'b']);
      expect(RecentDestinations.pushed(['', 'a'], 'b'), ['b', '', 'a']);
    });
  });

  late AppDatabase db;
  late SharedPreferences shared;
  late List<MethodCall> calls;
  late Map<String, Completer<void>> gates;

  /// A container with the drive open (unless [open] is off), app lock as
  /// [locked] says, and [recent] remembered.
  Future<ProviderContainer> start({
    List<String> recent = const [],
    bool locked = false,
    bool open = true,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'recent_destinations': recent});
    shared = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        driveRepositoryProvider.overrideWith((ref) => _GatedRepository(ref, gates)),
        if (open) driveSessionProvider.overrideWith(TestSession.new),
        driveSyncProvider.overrideWith(_Sync.new),
        appLockProvider.overrideWith(() => _Lock(locked)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await db.upsertFolder(_folder('receipts', 'Receipts'));
    await db.upsertFolder(_folder('invoices', 'Invoices'));
    await db.upsertFolder(_folder('taxes', 'Taxes'));
    await db.upsertFolder(_folder('trips', 'Trips'));
    await db.upsertFolder(_folder('old', 'Old', trashed: true));
    // Started the way the shell keeps it, and given its first look-up.
    container.listen(recentDestinationsProvider, (_, _) {});
    await _settle();
    return container;
  }

  setUp(() {
    calls = [];
    gates = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(share, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(share, null);
    RecentDestinations.onAndroid = false;
  });

  List<String> names(ProviderContainer container) =>
      [for (final choice in container.read(recentDestinationsProvider)) choice.name];

  /// What the share sheet was last offered, as id and name pairs.
  List<Map<Object?, Object?>> lastTargets() => [
    for (final target
        in calls.lastWhere((call) => call.method == 'setTargets').arguments as List)
      target as Map<Object?, Object?>,
  ];

  group('the list', () {
    test('forgets a folder that is gone or in the trash, and calls the root '
        'Files', () async {
      final container = await start(
        recent: ['missing', 'receipts', 'old', '', 'invoices'],
      );

      expect(names(container), ['Receipts', 'Files', 'Invoices']);
      expect(
        container.read(recentDestinationsProvider).map((c) => c.folderId),
        ['receipts', null, 'invoices'],
      );
      expect(shared.getStringList('recent_destinations'), ['receipts', '', 'invoices']);
    });

    test('takes a new name after a sync', () async {
      final container = await start(recent: ['receipts']);
      await db.upsertFolder(_folder('receipts', 'Receipts 2026'));
      expect(names(container), ['Receipts']);

      final sync = container.read(driveSyncProvider.notifier) as _Sync;
      sync.running(true);
      sync.running(false);
      await _settle();

      expect(names(container), ['Receipts 2026']);
    });

    test('puts the folder just used first', () async {
      final container = await start(recent: ['receipts', '']);

      await container.read(recentDestinationsProvider.notifier).note('invoices');
      expect(names(container), ['Invoices', 'Receipts', 'Files']);

      await container.read(recentDestinationsProvider.notifier).note(null);
      expect(names(container), ['Files', 'Invoices', 'Receipts']);
      expect(shared.getStringList('recent_destinations'), ['', 'invoices', 'receipts']);
    });

    test('a look-up overtaken by a later one leaves the list to it', () async {
      final container = await start(recent: ['receipts']);
      final notifier = container.read(recentDestinationsProvider.notifier);
      await shared.setStringList('recent_destinations', ['old', 'receipts']);
      final gate = gates['receipts'] = Completer<void>();

      final older = notifier.refresh();
      await notifier.note('invoices');
      gate.complete();
      await older;

      expect(names(container), ['Invoices', 'Receipts']);
      expect(shared.getStringList('recent_destinations'), ['invoices', 'receipts']);
    });

    test('forgetting a folder keeps one used while it was looked up', () async {
      final container = await start(recent: ['receipts']);
      final notifier = container.read(recentDestinationsProvider.notifier);
      await shared.setStringList('recent_destinations', ['old', 'receipts']);
      final gate = gates['receipts'] = Completer<void>();

      final lookUp = notifier.refresh();
      await shared.setStringList('recent_destinations', ['invoices', 'old', 'receipts']);
      gate.complete();
      await lookUp;

      expect(shared.getStringList('recent_destinations'), ['invoices', 'receipts']);
    });

    test('changes nothing while no drive is open', () async {
      final container = await start(recent: ['missing', 'receipts'], open: false);

      await container.read(recentDestinationsProvider.notifier).refresh();

      expect(names(container), isEmpty);
      expect(shared.getStringList('recent_destinations'), ['missing', 'receipts']);
    });

    test('clear forgets every folder', () async {
      final container = await start(recent: ['receipts', '']);

      await container.read(recentDestinationsProvider.notifier).clear();

      expect(container.read(recentDestinationsProvider), isEmpty);
      expect(shared.containsKey('recent_destinations'), isFalse);
    });
  });

  group('targets in the share sheet', () {
    setUp(() => RecentDestinations.onAndroid = true);

    test('are the first four folders, never the root', () async {
      await start(recent: ['receipts', '', 'invoices', 'taxes', 'trips']);

      expect(lastTargets(), [
        {'id': 'receipts', 'name': 'Receipts'},
        {'id': 'invoices', 'name': 'Invoices'},
        {'id': 'taxes', 'name': 'Taxes'},
        {'id': 'trips', 'name': 'Trips'},
      ]);
    });

    test('are none while app lock is on, and come back when it goes off', () async {
      final container = await start(recent: ['receipts', 'invoices'], locked: true);
      expect(calls.where((call) => call.method == 'setTargets'), isNotEmpty);
      expect(lastTargets(), isEmpty);

      (container.read(appLockProvider.notifier) as _Lock).set(false);
      await _settle();
      expect(lastTargets(), hasLength(2));

      (container.read(appLockProvider.notifier) as _Lock).set(true);
      await _settle();
      expect(lastTargets(), isEmpty);
    });

    test('hear that a folder was used, and the root never', () async {
      final container = await start();

      await container.read(recentDestinationsProvider.notifier).note('receipts');
      await container.read(recentDestinationsProvider.notifier).note(null);

      expect(
        [
          for (final call in calls)
            if (call.method == 'reportTarget') call.arguments,
        ],
        [
          {'id': 'receipts'},
        ],
      );
    });

    test('all go when the list is cleared', () async {
      final container = await start(recent: ['receipts']);
      expect(lastTargets(), hasLength(1));

      await container.read(recentDestinationsProvider.notifier).clear();

      expect(lastTargets(), isEmpty);
    });
  });

  group('shownFolder', () {
    test('is null for a folder that is gone, trashed or inside a trashed '
        'one', () async {
      final container = await start();
      await db.upsertFolder(
        _folder('inner', 'Inner').copyWith(parentId: const Value('old')),
      );
      final repository = container.read(driveRepositoryProvider);

      expect(await repository.shownFolder('missing'), isNull);
      expect(await repository.shownFolder('old'), isNull);
      expect(await repository.shownFolder('inner'), isNull);
      expect((await repository.shownFolder('receipts'))?.name, 'Receipts');
    });
  });
}

/// Lets the look-ups the list starts on its own finish.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
