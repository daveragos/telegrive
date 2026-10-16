import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

import 'generated_migrations/schema.dart';

/// The app's schema checked against the ones dumped into test/drift_schemas/
/// for each released version, and the takeover of a database a build from
/// before the first release left. After a bump, dump the new version and
/// regenerate the helpers:
///
/// ```text
/// dart run drift_dev schema dump lib/infrastructure/database/app_database.dart test/drift_schemas/
/// dart run drift_dev schema generate test/drift_schemas/ test/generated_migrations/
/// ```
void main() {
  final latest = GeneratedHelper.versions.last;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  const strict = ValidationOptions(validateDropped: true);

  test('the newest dumped schema is the one the app runs', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, latest);
  });

  test('a new database is exactly the dumped schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latest, options: strict);
  });

  // Builds before the first release counted their schema up to 14, which is
  // version 1's tables as they are. Each test below gives version 1's tables
  // the shape an earlier one had.

  /// A database as a build from before the first release left it: version
  /// 1's tables, changed by [then], under schema [version], with a folder,
  /// a file and what search read from it.
  Future<AppDatabase> preRelease(int version, {List<String> then = const []}) async {
    final schema = await verifier.schemaAt(1);
    final raw = schema.rawDatabase;
    raw.execute(
      'INSERT INTO folders (id, name, message_id, created_at, modified_at) '
      "VALUES ('docs', 'Docs', 1, 0, 0)",
    );
    raw.execute(
      'INSERT INTO drive_files (id, folder_id, name, mime_type, kind, size, '
      'created_at, modified_at, part_count, parts_present) '
      "VALUES ('lease', 'docs', 'Lease.pdf', 'application/pdf', 'document', 3, 0, 0, 1, 1), "
      "('scan', 'docs', 'Scan.pdf', 'application/pdf', 'document', 3, 0, 0, 1, 1)",
    );
    raw.execute(
      'INSERT INTO file_contents (file_id, content, version, indexed_at) '
      "VALUES ('lease', 'rent due on the first', 3, 0), ('scan', 'unread', 2, 0)",
    );
    for (final statement in then) {
      raw.execute(statement);
    }
    raw.execute('PRAGMA user_version = $version');
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    return db;
  }

  Future<int> userVersion(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version');

  Future<void> expectKept(AppDatabase db) async {
    expect((await db.folderById('docs'))!.name, 'Docs');
    expect((await db.fileById('lease'))!.folderId, 'docs');
    // The last reader before the release is version 1's; an older one's
    // text is read again.
    expect(await db.indexedFileIds(1), {'lease'});
    expect(await db.indexedFileIds(2), isEmpty);
  }

  test('a database from the last build before the release is taken over as it is', () async {
    final db = await preRelease(14);
    await verifier.migrateAndValidate(db, latest, options: strict);

    expect(await userVersion(db), 1);
    await expectKept(db);
  });

  test('a version 13 database gains the import columns and keeps the rest', () async {
    final db = await preRelease(
      13,
      then: [
        'ALTER TABLE takeout_parts DROP COLUMN deleted_at',
        'ALTER TABLE takeout_items DROP COLUMN albums',
        'ALTER TABLE takeout_items DROP COLUMN starred',
      ],
    );
    await verifier.migrateAndValidate(db, latest, options: strict);

    expect(await userVersion(db), 1);
    await expectKept(db);
  });

  /// What version 12, and 10 before it, lacked of the import.
  const beforeImport = [
    'DROP TABLE takeout_items',
    'DROP TABLE takeout_details',
    'DROP TABLE takeout_entries',
    'DROP TABLE takeout_parts',
    'ALTER TABLE transfers DROP COLUMN album_ids',
    'ALTER TABLE transfers DROP COLUMN starred',
  ];

  for (final from in [12, 10]) {
    test('a version $from database gains the import and keeps the rest', () async {
      final db = await preRelease(from, then: beforeImport);
      await verifier.migrateAndValidate(db, latest, options: strict);

      expect(await userVersion(db), 1);
      await expectKept(db);
    });
  }

  test('a version 11 database also loses the caption layout column', () async {
    final db = await preRelease(
      11,
      then: [
        ...beforeImport,
        for (final table in ['file_parts', 'folders', 'albums'])
          'ALTER TABLE $table ADD COLUMN caption_layout INTEGER',
      ],
    );
    await verifier.migrateAndValidate(db, latest, options: strict);

    expect(await userVersion(db), 1);
    await expectKept(db);
  });

  test('an older database starts over, for the channel to fill again', () async {
    final db = await preRelease(
      9,
      then: ['CREATE TABLE gone (id TEXT)'],
    );
    await verifier.migrateAndValidate(db, latest, options: strict);

    expect(await userVersion(db), 1);
    expect(await db.folderById('docs'), isNull);
    expect(await db.fileById('lease'), isNull);
    expect(await db.indexedFileIds(1), isEmpty);
  });
}
