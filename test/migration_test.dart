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
    expect((await db.folderById('docs'))!.manifestExtra, isNull);
    expect(await db.select(db.fileOpens).get(), isEmpty);
  });
}
