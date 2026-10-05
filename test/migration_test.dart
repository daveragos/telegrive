import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

import 'generated_migrations/schema.dart';

/// Upgrades checked against the schemas dumped into drift_schemas/ at each
/// version. After a bump, dump the new version and regenerate the helpers:
///
/// ```text
/// dart run drift_dev schema dump lib/infrastructure/database/app_database.dart drift_schemas/
/// dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
/// ```
void main() {
  final latest = GeneratedHelper.versions.last;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the newest dumped schema is the one the app runs', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, latest);
  });

  for (final from in GeneratedHelper.versions.where((v) => v < latest)) {
    test('version $from upgrades to exactly the version $latest schema', () async {
      final db = AppDatabase(await verifier.startAt(from));
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, latest);
    });
  }

  test('files and folders indexed at version 3 are still there', () async {
    final schema = await verifier.schemaAt(3);
    schema.rawDatabase.execute(
      'INSERT INTO folders (id, name, message_id, created_at, modified_at) '
      "VALUES ('docs', 'Docs', 1, 0, 0)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO drive_files (id, folder_id, name, mime_type, kind, size, '
      'created_at, modified_at, part_count, parts_present) '
      "VALUES ('a', 'docs', 'a.pdf', 'application/pdf', 'document', 3, 0, 0, 1, 1)",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latest);

    final file = (await db.fileById('a'))!;
    expect(file.name, 'a.pdf');
    expect(file.folderId, 'docs');
    expect(file.manifestExtra, isNull);
    expect(file.durationSeconds, isNull);
    expect(file.replacedBy, isNull);
    expect(file.adopted, isFalse);
    expect(file.originalSize, isNull);
    final folder = (await db.folderById('docs'))!;
    expect(folder.manifestExtra, isNull);
    expect(folder.starred, isFalse);
    expect(await db.select(db.fileOpens).get(), isEmpty);
    expect(await db.select(db.playPositions).get(), isEmpty);
    expect(await db.select(db.watchedFolders).get(), isEmpty);
    expect(await db.select(db.watchedFiles).get(), isEmpty);
    expect(await db.select(db.pendingEdits).get(), isEmpty);
  });

  // Versions 4 to 6 kept the keys they didn't know in manifest_extra, so a
  // star, length or replacement written by a newer phone is already in the
  // index and moves into its column, and out of the extras, at version 7.
  for (final from in GeneratedHelper.versions.where((v) => v >= 4 && v < 7)) {
    test('keys kept as extras at version $from move into their columns', () async {
      final schema = await verifier.schemaAt(from);
      schema.rawDatabase.execute(r'''
        INSERT INTO folders (id, name, message_id, created_at, modified_at, manifest_extra)
        VALUES ('inv', 'Invoices', 1, 0, 0, '{"st":1}'),
               ('work', 'Work', 2, 0, 0, '{"st":true,"c":"blue"}'),
               ('old', 'Old', 3, 0, 0, '{"st":0}'),
               ('plain', 'Plain', 4, 0, 0, NULL)
      ''');
      schema.rawDatabase.execute(r'''
        INSERT INTO drive_files (id, name, mime_type, kind, size, created_at,
                                 modified_at, part_count, parts_present, manifest_extra)
        VALUES ('v', 'clip.mp4', 'video/mp4', 'video', 9, 0, 0, 1, 1, '{"du":84,"rb":"w","lt":5}'),
               ('z', 'zero.mp4', 'video/mp4', 'video', 9, 0, 0, 1, 1, '{"du":0}'),
               ('t', 'text.mp4', 'video/mp4', 'video', 9, 0, 0, 1, 1, '{"du":"90"}'),
               ('p', 'plain.pdf', 'application/pdf', 'document', 9, 0, 0, 1, 1, NULL)
      ''');

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, latest);

      final inv = (await db.folderById('inv'))!;
      expect(inv.starred, isTrue);
      expect(inv.manifestExtra, isNull);
      final work = (await db.folderById('work'))!;
      expect(work.starred, isTrue);
      expect(jsonDecode(work.manifestExtra!), {'c': 'blue'});
      for (final id in ['old', 'plain']) {
        final folder = (await db.folderById(id))!;
        expect(folder.starred, isFalse, reason: id);
        expect(folder.manifestExtra, isNull, reason: id);
      }

      final clip = (await db.fileById('v'))!;
      expect(clip.durationSeconds, 84);
      expect(clip.replacedBy, 'w');
      expect(jsonDecode(clip.manifestExtra!), {'lt': 5});
      for (final id in ['z', 't', 'p']) {
        final file = (await db.fileById(id))!;
        expect(file.durationSeconds, isNull, reason: id);
        expect(file.replacedBy, isNull, reason: id);
        expect(file.manifestExtra, isNull, reason: id);
      }
    });
  }

  for (final from in GeneratedHelper.versions.where((v) => v < latest)) {
    test('a transfer queued at version $from is still queued, not waiting for Wi-Fi',
        () async {
      final schema = await verifier.schemaAt(from);
      schema.rawDatabase.execute(
        'INSERT INTO transfers (id, kind, status, name, mime_type, file_id, '
        'total_bytes, created_at) '
        "VALUES ('t', 'download', 'queued', 'a.pdf', 'application/pdf', 'a', 3, 0)",
      );

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, latest);

      final row = (await db.allTransfers()).single;
      expect(row.status, TransferStatus.queued);
      expect(row.origin, TransferOrigin.manual);
      expect(row.wifiOnly, isFalse);
      expect(row.durationSeconds, isNull);
      expect(row.replacesFileId, isNull);
      expect(row.sourceChatId, isNull);
      expect(row.sourceMessageId, isNull);
      await db.saveTransfer(
        row.copyWith(
          origin: TransferOrigin.fromChat,
          wifiOnly: true,
          durationSeconds: const Value(84),
          replacesFileId: const Value('old'),
          sourceChatId: const Value(777000),
          sourceMessageId: const Value(42),
        ),
      );
      final saved = (await db.allTransfers()).single;
      expect(saved.origin, TransferOrigin.fromChat);
      expect(saved.wifiOnly, isTrue);
      expect(saved.durationSeconds, 84);
      expect(saved.replacesFileId, 'old');
      expect(saved.sourceChatId, 777000);
      expect(saved.sourceMessageId, 42);
    });
  }

  // Nothing before version 8 knew which files came in without a manifest,
  // so every row arrives unadopted; the next full read sets the flag.
  for (final from in GeneratedHelper.versions.where((v) => v < latest)) {
    test('a file indexed at version $from is not adopted until a read says so',
        () async {
      final schema = await verifier.schemaAt(from);
      schema.rawDatabase.execute(
        'INSERT INTO drive_files (id, name, mime_type, kind, size, created_at, '
        'modified_at, part_count, parts_present) '
        "VALUES ('fwd', 'photo_2231.jpg', 'image/jpeg', 'image', 3, 0, 0, 1, 1)",
      );

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, latest);

      expect((await db.fileById('fwd'))!.adopted, isFalse);
      await db.updateFile('fwd', const DriveFilesCompanion(adopted: Value(true)));
      expect((await db.fileById('fwd'))!.adopted, isTrue);
    });
  }

  for (final from in GeneratedHelper.versions.where((v) => v < latest)) {
    test('backup records from version $from keep their state, with no reason yet',
        () async {
      final schema = await verifier.schemaAt(from);
      schema.rawDatabase.execute(
        'INSERT INTO backup_assets (asset_id, state, file_id, failures, '
        'updated_at) '
        "VALUES ('kept', 'done', 'a', 0, 0), ('stuck', 'failed', NULL, 3, 0)",
      );

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, latest);

      final records = await db.backupAssetMap();
      expect(records['kept']!.state, BackupAssetState.done);
      expect(records['kept']!.fileId, 'a');
      expect(records['stuck']!.state, BackupAssetState.failed);
      expect(records['stuck']!.failures, 3);
      expect(records.values.map((r) => r.reason), everyElement(isNull));

      await (db.update(db.backupAssets)
            ..where((a) => a.assetId.equals('stuck')))
          .write(
            const BackupAssetsCompanion(
              state: Value(BackupAssetState.skipped),
              reason: Value('Telegram took too long to answer.'),
            ),
          );
      final stuck = (await db.backupAssetMap())['stuck']!;
      expect(stuck.state, BackupAssetState.skipped);
      expect(stuck.reason, 'Telegram took too long to answer.');

      await (db.update(db.backupAssets)
            ..where((a) => a.assetId.equals('kept')))
          .write(
            const BackupAssetsCompanion(
              state: Value(BackupAssetState.missing),
              fileId: Value(null),
            ),
          );
      final kept = (await db.backupAssetMap())['kept']!;
      expect(kept.state, BackupAssetState.missing);
      expect(kept.fileId, isNull);

      await (db.update(db.backupAssets)
            ..where((a) => a.state.equalsValue(BackupAssetState.missing)))
          .write(const BackupAssetsCompanion(state: Value(BackupAssetState.removed)));
      expect((await db.backupAssetMap())['kept']!.state, BackupAssetState.removed);
      expect(await db.watchBackedUpCount().first, 0);
    });
  }

  // Watched folders are new at version 9 and belong to this phone, so no
  // earlier version has anything to bring across: both tables arrive empty
  // and take a rule with its ledger, defaults included.
  for (final from in GeneratedHelper.versions.where((v) => v < latest)) {
    test('version $from arrives with no watched folders and takes one', () async {
      final db = AppDatabase(await verifier.startAt(from));
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, latest);

      expect(await db.select(db.watchedFolders).get(), isEmpty);
      expect(await db.select(db.watchedFiles).get(), isEmpty);

      await db.into(db.watchedFolders).insert(
        WatchedFoldersCompanion.insert(
          id: 'bank',
          treeUri: 'content://com.android.externalstorage.documents/tree/'
              'primary%3ADownload%2FBank',
          label: 'Bank',
          filter: WatchFilter.documents,
          createdAt: DateTime(2026, 9, 28),
        ),
      );
      await db.into(db.watchedFiles).insert(
        WatchedFilesCompanion.insert(
          ruleId: 'bank',
          documentId: 'primary:Download/Bank/statement.pdf',
          size: 3,
          modifiedAt: DateTime(2026, 9, 27),
          state: WatchedFileState.pending,
          transferId: const Value('t'),
          updatedAt: DateTime(2026, 9, 28),
        ),
      );

      final rule = (await db.select(db.watchedFolders).get()).single;
      expect(rule.label, 'Bank');
      expect(rule.filter, WatchFilter.documents);
      expect(rule.subfolders, isTrue);
      expect(rule.destinationId, isNull);
      expect(rule.checkedAt, isNull);
      final entry = (await db.select(db.watchedFiles).get()).single;
      expect(entry.state, WatchedFileState.pending);
      expect(entry.transferId, 't');
      expect(entry.fileId, isNull);
      expect(entry.failures, 0);
    });
  }

  // Waiting changes are new at version 10 and belong to this phone, so
  // every earlier version arrives with none. The table takes a change with
  // its defaults, and one item can wait under each target.
  for (final from in GeneratedHelper.versions.where((v) => v < latest)) {
    test('version $from arrives with nothing waiting and takes a change', () async {
      final db = AppDatabase(await verifier.startAt(from));
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, latest);

      expect(await db.select(db.pendingEdits).get(), isEmpty);

      await db.into(db.pendingEdits).insert(
        PendingEditsCompanion.insert(
          target: EditTarget.file,
          itemId: 'scan',
          patch: '{"n":{"b":"Scan 12.pdf","w":"Lease.pdf"}}',
          createdAt: DateTime(2026, 9, 28, 8),
          updatedAt: DateTime(2026, 9, 28, 8, 5),
        ),
      );
      await db.into(db.pendingEdits).insert(
        PendingEditsCompanion.insert(
          target: EditTarget.folder,
          itemId: 'scan',
          patch: '{"tr":{"b":null,"w":1727430000000}}',
          createdAt: DateTime(2026, 9, 28, 9),
          updatedAt: DateTime(2026, 9, 28, 9),
          attempts: const Value(3),
          lastError: const Value('Telegram took too long to answer.'),
        ),
      );

      final rows = await db.select(db.pendingEdits).get();
      final rename = rows.singleWhere((r) => r.target == EditTarget.file);
      expect(rename.itemId, 'scan');
      expect(rename.attempts, 0);
      expect(rename.lastError, isNull);
      expect(rename.updatedAt, DateTime(2026, 9, 28, 8, 5));
      final trash = rows.singleWhere((r) => r.target == EditTarget.folder);
      expect(trash.attempts, 3);
      expect(trash.lastError, 'Telegram took too long to answer.');
    });
  }

  // Nothing before version 10 could tell a small copy from the photo it
  // stands in for, so every file arrives whole. Once a row says only a
  // small copy is in, its backup record stops counting as backed up, so
  // Free up space never offers the phone's original.
  for (final from in GeneratedHelper.versions.where((v) => v < latest)) {
    test('a file indexed at version $from is whole until a small copy says otherwise',
        () async {
      final schema = await verifier.schemaAt(from);
      schema.rawDatabase.execute(
        'INSERT INTO drive_files (id, name, mime_type, kind, size, created_at, '
        'modified_at, part_count, parts_present) '
        "VALUES ('shot', 'IMG_2041.HEIC', 'image/jpeg', 'image', 312000, 0, 0, 1, 1)",
      );
      schema.rawDatabase.execute(
        'INSERT INTO backup_assets (asset_id, state, file_id, failures, updated_at) '
        "VALUES ('a2041', 'done', 'shot', 0, 0)",
      );

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, latest);

      expect((await db.fileById('shot'))!.originalSize, isNull);
      expect(
        (await db.safelyBackedUp()).map((id, row) => MapEntry(id, row.size)),
        {'a2041': 312000},
      );

      await db.updateFile(
        'shot',
        const DriveFilesCompanion(originalSize: Value(6100000)),
      );
      await (db.update(db.backupAssets)
            ..where((a) => a.assetId.equals('a2041')))
          .write(
            const BackupAssetsCompanion(state: Value(BackupAssetState.smallCopy)),
          );
      final shot = (await db.fileById('shot'))!;
      expect(shot.size, 312000);
      expect(shot.originalSize, 6100000);
      expect((await db.backupAssetMap())['a2041']!.state, BackupAssetState.smallCopy);
      expect(await db.safelyBackedUp(), isEmpty);
      expect(await db.watchBackedUpCount().first, 0);
    });
  }
}
