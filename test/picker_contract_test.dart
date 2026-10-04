import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

/// Android's file picker reads the index from its own process with its own
/// SQL, so nothing in Dart would notice the schema moving away from it.
/// These are DriveDocumentsProvider's statements word for word; keep them
/// in step with
/// android/app/src/main/kotlin/dev/ragoose/telegrive/picker/DriveDocumentsProvider.kt,
/// which the first test reads to check that they still are.
const _provider =
    'android/app/src/main/kotlin/dev/ragoose/telegrive/picker/DriveDocumentsProvider.kt';

const _shownTotals =
    'SELECT COUNT(*), COALESCE(SUM(size), 0) FROM drive_files WHERE parts_present >= part_count AND hidden = 0';
const _foldersIn = 'SELECT id, name, modified_at FROM folders WHERE hidden = 0 AND parent_id = ?';
const _foldersAtRoot =
    'SELECT id, name, modified_at FROM folders WHERE hidden = 0 AND (parent_id IS NULL OR parent_id NOT IN (SELECT id FROM folders))';
const _filesIn =
    'SELECT id, name, mime_type, size, modified_at FROM drive_files WHERE hidden = 0 AND parts_present >= part_count AND folder_id = ?';
const _filesAtRoot =
    'SELECT id, name, mime_type, size, modified_at FROM drive_files WHERE hidden = 0 AND parts_present >= part_count AND (folder_id IS NULL OR folder_id NOT IN (SELECT id FROM folders))';
const _folderById = 'SELECT id, name, modified_at FROM folders WHERE hidden = 0 AND id = ?';
const _fileById =
    'SELECT id, name, mime_type, size, modified_at FROM drive_files WHERE hidden = 0 AND parts_present >= part_count AND id = ?';
const _searchFolders =
    r"SELECT id, name, modified_at FROM folders WHERE hidden = 0 AND name LIKE ? ESCAPE '\' ORDER BY modified_at DESC LIMIT 20";
const _searchFiles =
    r"SELECT id, name, mime_type, size, modified_at FROM drive_files WHERE hidden = 0 AND parts_present >= part_count AND name LIKE ? ESCAPE '\' ORDER BY modified_at DESC LIMIT 100";
const _folderParent = 'SELECT parent_id FROM folders WHERE hidden = 0 AND id = ?';
const _fileFolder =
    'SELECT folder_id FROM drive_files WHERE hidden = 0 AND parts_present >= part_count AND id = ?';
const _folderExists = 'SELECT 1 FROM folders WHERE id = ?';
const _localCopies =
    "SELECT file_id, path FROM offline_copies UNION ALL SELECT file_id, result_path FROM transfers WHERE kind = 'download' AND status = 'completed' AND result_path IS NOT NULL";
const _localCopiesOf = 'SELECT file_id, path FROM ($_localCopies) WHERE file_id = ?';

const _statements = {
  'SHOWN_TOTALS': _shownTotals,
  'FOLDERS_IN': _foldersIn,
  'FOLDERS_AT_ROOT': _foldersAtRoot,
  'FILES_IN': _filesIn,
  'FILES_AT_ROOT': _filesAtRoot,
  'FOLDER_BY_ID': _folderById,
  'FILE_BY_ID': _fileById,
  'SEARCH_FOLDERS': _searchFolders,
  'SEARCH_FILES': _searchFiles,
  'FOLDER_PARENT': _folderParent,
  'FILE_FOLDER': _fileFolder,
  'FOLDER_EXISTS': _folderExists,
  'LOCAL_COPIES': _localCopies,
  'LOCAL_COPIES_OF': _localCopiesOf,
};

/// The provider's string constants as SQLite gets them: a constant named
/// inside another is filled in, and Kotlin's escapes are undone.
Map<String, String> _kotlinConstants() {
  final source = File(_provider).readAsStringSync();
  final found = <String, String>{};
  for (final match in RegExp(r'const val (\w+) = "((?:[^"\\]|\\.)*)"').allMatches(source)) {
    found[match[1]!] = match[2]!
        .replaceAllMapped(RegExp(r'(?<!\\)\$(\w+)'), (m) => found[m[1]!] ?? m[0]!)
        .replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
  }
  return found;
}

void main() {
  late AppDatabase db;
  final modified = DateTime(2026, 9, 25, 14, 30, 15);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> folder(String id, {String? parentId, DateTime? trashedAt}) => db.upsertFolder(
    FoldersCompanion.insert(
      id: id,
      parentId: Value(parentId),
      name: id,
      messageId: id.hashCode & 0xffffff,
      createdAt: modified,
      modifiedAt: modified,
      trashedAt: Value(trashedAt),
    ),
  );

  var messageId = 100;
  Future<void> file(
    String id, {
    String? name,
    String? folderId,
    DateTime? trashedAt,
    int partCount = 1,
    int size = 1000,
  }) => db.upsertFilePart(
    DriveFilesCompanion.insert(
      id: id,
      folderId: Value(folderId),
      name: name ?? '$id.pdf',
      mimeType: 'application/pdf',
      kind: FileKind.document,
      size: size,
      createdAt: modified,
      modifiedAt: modified,
      partCount: Value(partCount),
      trashedAt: Value(trashedAt),
    ),
    FilePartsCompanion.insert(
      fileId: id,
      partIndex: 0,
      messageId: messageId++,
      tdFileId: messageId,
      size: size ~/ partCount,
    ),
  );

  /// Documents, with a subfolder and a folder in the trash holding one more
  /// folder and a file; a shown file, one in the trash and a split file
  /// with one of two parts. At the root, a file in no folder, and a file
  /// and a folder whose folder is gone.
  Future<void> seed() async {
    await folder('docs');
    await folder('scans', parentId: 'docs');
    await folder('old', parentId: 'docs', trashedAt: modified);
    await folder('inside', parentId: 'old');
    await folder('stray', parentId: 'gone');
    await file('passport', name: 'Passport scan.pdf', folderId: 'docs', size: 3000);
    await file('trashed', folderId: 'docs', trashedAt: modified);
    await file('half', folderId: 'docs', partCount: 2);
    await file('buried', folderId: 'inside');
    await file('loose', name: 'Notes.txt', size: 200);
    await file('orphan', folderId: 'gone', size: 400);
  }

  Future<List<Map<String, Object?>>> rows(String sql, [List<String> args = const []]) async => [
    for (final row
        in await db
            .customSelect(sql, variables: [for (final arg in args) Variable.withString(arg)])
            .get())
      row.data,
  ];

  Future<Set<Object?>> ids(String sql, [List<String> args = const []]) async => {
    for (final row in await rows(sql, args)) row.values.first,
  };

  test('the SQL here is the provider\'s', () {
    final kotlin = _kotlinConstants();
    for (final MapEntry(key: name, value: sql) in _statements.entries) {
      expect(kotlin[name], sql, reason: '$name differs from $_provider');
    }
  });

  test('a folder lists what it shows, not what is in the trash or half there', () async {
    await seed();
    expect(await ids(_foldersIn, ['docs']), {'scans'});
    expect(await ids(_filesIn, ['docs']), {'passport'});
    // A folder in the trash, and everything in it, shows nowhere.
    expect(await ids(_foldersIn, ['old']), isEmpty);
    expect(await ids(_filesIn, ['inside']), isEmpty);
    final passport = (await rows(_filesIn, ['docs'])).single;
    expect(passport, {
      'id': 'passport',
      'name': 'Passport scan.pdf',
      'mime_type': 'application/pdf',
      'size': 3000,
      'modified_at': passport['modified_at'],
    });
  });

  test('the root holds what is in no folder and what lost its folder', () async {
    await seed();
    expect(await ids(_foldersAtRoot), {'docs', 'stray'});
    expect(await ids(_filesAtRoot), {'loose', 'orphan'});
  });

  test('dates are Unix seconds', () async {
    await seed();
    final seconds = modified.millisecondsSinceEpoch ~/ 1000;
    expect((await rows(_filesIn, ['docs'])).single['modified_at'], seconds);
    expect((await rows(_folderById, ['docs'])).single['modified_at'], seconds);
  });

  test('the root\'s total is what Home counts', () async {
    await seed();
    final totals = await db.watchTotals().first;
    final row = (await rows(_shownTotals)).single.values.toList();
    expect(row, [
      totals.fold<int>(0, (sum, t) => sum + t.count),
      totals.fold<int>(0, (sum, t) => sum + t.bytes),
    ]);
    expect(row, [3, 3600]);
  });

  test('copies on the phone come from offline copies and finished downloads', () async {
    await seed();
    await db.saveOfflineCopy('passport', '/files/offline/passport/Passport scan.pdf', 3000);
    TransferRow download(
      String id,
      String fileId,
      TransferStatus status, {
      TransferKind kind = TransferKind.download,
    }) => TransferRow(
      id: id,
      kind: kind,
      status: status,
      name: '$fileId.pdf',
      mimeType: 'application/pdf',
      fileId: fileId,
      ownsSource: false,
      resultPath: '/cache/$id/$fileId.pdf',
      wifiOnly: false,
      totalBytes: 1,
      doneBytes: 1,
      partCount: 1,
      completedParts: 1,
      createdAt: modified,
      origin: TransferOrigin.manual,
    );
    await db.saveTransfers([
      download('t1', 'loose', TransferStatus.completed),
      download('t2', 'orphan', TransferStatus.running),
      download('t3', 'half', TransferStatus.completed, kind: TransferKind.upload),
    ]);

    final copies = {for (final row in await rows(_localCopies)) (row['file_id'], row['path'])};
    expect(copies, {
      ('passport', '/files/offline/passport/Passport scan.pdf'),
      ('loose', '/cache/t1/loose.pdf'),
    });
    expect(await rows(_localCopiesOf, ['loose']), [
      {'file_id': 'loose', 'path': '/cache/t1/loose.pdf'},
    ]);
  });

  test(
    'search finds shown files and folders by name, with LIKE\'s characters taken literally',
    () async {
      await seed();
      await file('sale', name: '50% off.pdf');
      await file('plain', name: '500 off.pdf');
      // How the provider turns what was typed into a pattern.
      String pattern(String typed) =>
          '%${typed.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

      expect(await ids(_searchFiles, [pattern('passport')]), {'passport'});
      expect(await ids(_searchFiles, [pattern('.pdf')]), isNot(contains('trashed')));
      expect(await ids(_searchFiles, [pattern('50%')]), {'sale'});
      expect(await ids(_searchFolders, [pattern('SCAN')]), {'scans'});
      expect(await ids(_searchFolders, [pattern('inside')]), isEmpty);
    },
  );

  test('one document, and the way up the tree', () async {
    await seed();
    expect(await ids(_fileById, ['passport']), {'passport'});
    expect(await ids(_fileById, ['half']), isEmpty);
    expect(await ids(_folderById, ['old']), isEmpty);
    expect(await ids(_fileFolder, ['passport']), {'docs'});
    expect(await ids(_folderParent, ['scans']), {'docs'});
    expect(await ids(_folderParent, ['docs']), {null});
    expect(await ids(_fileFolder, ['orphan']), {'gone'});
    expect(await ids(_folderExists, ['docs']), {1});
    expect(await ids(_folderExists, ['gone']), isEmpty);
  });

  test('every column the provider reads is in the schema', () async {
    Future<Set<String>> columns(String table) async => {
      for (final row in await rows('PRAGMA table_info($table)')) row['name']! as String,
    };
    expect(
      await columns('drive_files'),
      containsAll([
        'id',
        'name',
        'mime_type',
        'size',
        'modified_at',
        'folder_id',
        'hidden',
        'parts_present',
        'part_count',
      ]),
    );
    expect(
      await columns('folders'),
      containsAll(['id', 'name', 'modified_at', 'parent_id', 'hidden']),
    );
    expect(await columns('offline_copies'), containsAll(['file_id', 'path']));
    expect(await columns('transfers'), containsAll(['file_id', 'result_path', 'kind', 'status']));
  });
}
