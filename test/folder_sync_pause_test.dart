import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/backup/data/phone_folders.dart';
import 'package:telegrive/features/backup/data/watched_folders.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

import 'support/fake_telegram.dart';

/// A queue holding [_items] that pauses and resumes them in place.
class _Queue extends TransferQueue {
  _Queue(this._items);

  final List<TransferItem> _items;

  @override
  TransfersState build() => TransfersState(_items);

  void _move(bool Function(TransferRow row) which, bool Function(TransferStatus s) from, TransferStatus to) {
    state = TransfersState([
      for (final item in state.items)
        if (which(item.row) && from(item.status)) TransferItem(item.row.copyWith(status: to)) else item,
    ]);
  }

  @override
  Future<void> pauseAll(bool Function(TransferRow row) which) async =>
      _move(which, (s) => s.isActive, TransferStatus.paused);

  @override
  Future<void> resumeAll(bool Function(TransferRow row) which) async =>
      _move(which, (s) => s == TransferStatus.paused, TransferStatus.queued);
}

/// The folders' controller with its checks counted rather than run.
class _Folders extends WatchedFoldersController {
  int scheduled = 0;

  @override
  void schedule({bool immediate = false}) => scheduled++;
}

TransferItem _upload(String id) => TransferItem(
  TransferRow(
    id: id,
    kind: TransferKind.upload,
    status: TransferStatus.running,
    name: '$id.pdf',
    mimeType: 'application/pdf',
    fileId: id,
    ownsSource: false,
    wifiOnly: false,
    totalBytes: 10,
    doneBytes: 4,
    partCount: 1,
    completedParts: 0,
    createdAt: DateTime(2026, 11, 18),
    origin: TransferOrigin.manual,
  ),
);

void main() {
  late AppDatabase db;

  Future<ProviderContainer> open({Map<String, Object> prefs = const {}}) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    final now = DateTime(2026, 11, 18, 9);
    await db.saveWatchedFolder(
      WatchedFoldersCompanion.insert(
        id: 'invoices',
        treeUri: '/Users/sam/Documents/Invoices',
        label: 'Invoices',
        filter: WatchFilter.everything,
        subfolders: const Value(true),
        createdAt: now,
      ),
    );
    await db.saveWatchedFiles([
      WatchedFilesCompanion.insert(
        ruleId: 'invoices',
        documentId: 'Invoice-1118.pdf',
        size: 10,
        modifiedAt: now,
        state: WatchedFileState.pending,
        transferId: const Value('from-folder'),
        updatedAt: now,
      ),
    ]);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        driveSessionProvider.overrideWith(TestSession.new),
        transferQueueProvider.overrideWith(() => _Queue([_upload('from-folder'), _upload('mine')])),
        watchedFoldersProvider.overrideWith(_Folders.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    return container;
  }

  test('pausing folder sync holds what it queued, leaves yours, and is saved', () async {
    final container = await open();
    final folders = container.read(watchedFoldersProvider.notifier);

    await folders.pause();

    expect(container.read(watchedFoldersProvider).paused, isTrue);
    final queue = container.read(transferQueueProvider);
    expect(queue.byId('from-folder')!.status, TransferStatus.paused);
    expect(queue.byId('mine')!.status, TransferStatus.running);
    expect(container.read(preferencesProvider).foldersPaused, isTrue);
  });

  test('resuming lets what it held go and checks the folders', () async {
    final container = await open();
    final folders = container.read(watchedFoldersProvider.notifier) as _Folders;
    await folders.pause();

    await folders.resume();

    expect(container.read(watchedFoldersProvider).paused, isFalse);
    expect(container.read(transferQueueProvider).byId('from-folder')!.status, TransferStatus.queued);
    expect(container.read(preferencesProvider).foldersPaused, isFalse);
    expect(folders.scheduled, 1);
  });

  test('a pause outlasts a restart, and nothing is checked during it', () async {
    final container = await open(prefs: {'folders_paused': true});
    PhoneFolders.supported = true;
    addTearDown(() => PhoneFolders.supported = false);

    expect(container.read(watchedFoldersProvider).paused, isTrue);
    await container.read(watchedFoldersProvider.notifier).run();

    expect(container.read(watchedFoldersProvider).rules, isEmpty);
  });
}
