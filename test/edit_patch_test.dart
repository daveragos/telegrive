import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/drive/domain/edit_patch.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';

void main() {
  final created = DateTime(2026, 9, 1);
  final trashed = DateTime(2026, 10, 1, 9, 30);

  FileManifest file({
    String name = 'Scan 12.pdf',
    String? folderId,
    bool starred = false,
    DateTime? trashedAt,
    List<String> albums = const [],
  }) => FileManifest(
    id: 'f1',
    name: name,
    folderId: folderId,
    mimeType: 'application/pdf',
    size: 1200,
    createdAt: created,
    modifiedAt: created,
    starred: starred,
    trashedAt: trashedAt,
    albums: albums,
  );

  group('fileDiff', () {
    test('holds only the fields that changed, with where each started', () {
      final patch = EditPatch.fileDiff(
        file(albums: ['a1']),
        file(name: 'Lease.pdf', folderId: 'work', albums: ['a2', 'a1']),
      );
      expect(patch.toJson(), {
        'n': {'b': 'Scan 12.pdf', 'w': 'Lease.pdf'},
        'f': {'b': null, 'w': 'work'},
        'al': {
          'b': ['a1'],
          'w': ['a1', 'a2'],
        },
      });
    });

    test('albums in another order are no change', () {
      expect(
        EditPatch.fileDiff(file(albums: ['a1', 'a2']), file(albums: ['a2', 'a1'])).isEmpty,
        isTrue,
      );
    });

    test('a trash is kept as the time it happened', () {
      final patch = EditPatch.fileDiff(file(), file(trashedAt: trashed));
      expect(patch.toJson(), {
        'tr': {'b': null, 'w': trashed.millisecondsSinceEpoch},
      });
    });
  });

  group('then', () {
    test('keeps the first start and the last wish', () {
      final first = EditPatch.fileDiff(file(), file(name: 'Lease.pdf'));
      final second = EditPatch.fileDiff(
        file(name: 'Lease.pdf'),
        file(name: 'Lease 2026.pdf', starred: true),
      );
      expect(first.then(second).toJson(), {
        'n': {'b': 'Scan 12.pdf', 'w': 'Lease 2026.pdf'},
        'st': {'b': false, 'w': true},
      });
    });

    test('a trash followed by a restore leaves nothing to send', () {
      final trash = EditPatch.fileDiff(file(), file(trashedAt: trashed));
      final restore = EditPatch.fileDiff(file(trashedAt: trashed), file());
      expect(trash.then(restore).isEmpty, isTrue);
    });

    test('a move back to the root keeps the root it started from', () {
      final away = EditPatch.fileDiff(file(), file(folderId: 'work'));
      final back = EditPatch.fileDiff(file(folderId: 'work'), file());
      expect(away.then(back).isEmpty, isTrue);
    });

    test('an album taken out again is no change, whatever the order', () {
      final add = EditPatch.fileDiff(file(albums: ['a1']), file(albums: ['a1', 'a2']));
      final remove = EditPatch.fileDiff(file(albums: ['a2', 'a1']), file(albums: ['a1']));
      expect(add.then(remove).isEmpty, isTrue);
    });
  });

  group('resolve', () {
    final rename = EditPatch.fileDiff(file(), file(name: 'Lease.pdf'));

    test('applies a field Telegram still has as it started', () {
      final result = rename.resolve(EditPatch.fileValues(file()));
      expect(result.apply, {'n': 'Lease.pdf'});
      expect(result.skipped, isEmpty);
    });

    test('has nothing to do for a field Telegram already has as wanted', () {
      final result = rename.resolve(EditPatch.fileValues(file(name: 'Lease.pdf')));
      expect(result.apply, isEmpty);
      expect(result.skipped, isEmpty);
    });

    test('applies a restore when Telegram\'s trash time has milliseconds the index lacks', () {
      final restore = EditPatch.fileDiff(file(trashedAt: trashed), file());
      final onChannel = trashed.add(const Duration(milliseconds: 123));
      final remote = EditPatch.fileValues(file(trashedAt: onChannel));
      expect(remote['tr'], trashed.millisecondsSinceEpoch);
      final result = restore.resolve(remote);
      expect(result.apply, {'tr': null});
      expect(result.skipped, isEmpty);
    });

    test('skips a field another device changed to something else', () {
      final result = rename.resolve(EditPatch.fileValues(file(name: 'Budget.xlsx')));
      expect(result.apply, isEmpty);
      expect(result.skipped, {'n'});
    });

    test('still applies the other fields when one is skipped', () {
      final patch = EditPatch.fileDiff(file(), file(name: 'Lease.pdf', starred: true));
      final result = patch.resolve(EditPatch.fileValues(file(name: 'Budget.xlsx')));
      expect(result.apply, {'st': true});
      expect(result.skipped, {'n'});
    });

    test('merges albums with one another device added', () {
      final add = EditPatch.fileDiff(file(albums: ['a']), file(albums: ['a', 'b']));
      final result = add.resolve(EditPatch.fileValues(file(albums: ['a', 'c'])));
      expect(result.apply, {
        'al': ['a', 'b', 'c'],
      });
      expect(result.skipped, isEmpty);
    });

    test('takes out an album even when another device added one', () {
      final remove = EditPatch.fileDiff(file(albums: ['a', 'b']), file(albums: ['a']));
      final result = remove.resolve(EditPatch.fileValues(file(albums: ['a', 'b', 'c'])));
      expect(result.apply, {
        'al': ['a', 'c'],
      });
    });

    test('a folder\'s rename and move resolve the same way', () {
      final folder = FolderManifest(
        id: 'd1',
        name: 'Tax',
        parentId: null,
        createdAt: created,
        modifiedAt: created,
      );
      final moved = EditPatch.folderDiff(
        folder,
        EditPatch.applyToFolder(folder, {'n': 'Taxes', 'p': 'docs'}),
      );
      final result = moved.resolve(EditPatch.folderValues(folder));
      expect(result.apply, {'n': 'Taxes', 'p': 'docs'});
    });
  });

  group('over', () {
    test('shows each wanted value over what Telegram holds', () {
      final patch = EditPatch.fileDiff(
        file(albums: ['a']),
        file(name: 'Lease.pdf', albums: ['a', 'b']),
      );
      final shown = patch.over(EditPatch.fileValues(file(starred: true, albums: ['a', 'c'])));
      expect(shown['n'], 'Lease.pdf');
      expect(shown['st'], isTrue);
      expect(shown['al'], ['a', 'b', 'c']);
    });
  });

  group('rebase', () {
    test('after a send, keeps only what changed since', () {
      final sent = EditPatch.fileDiff(file(), file(name: 'Lease.pdf'));
      final meanwhile = sent.then(
        EditPatch.fileDiff(file(name: 'Lease.pdf'), file(name: 'Lease.pdf', starred: true)),
      );
      expect(meanwhile.rebase(sent).toJson(), {
        'st': {'b': false, 'w': true},
      });
    });

    test('a field renamed again since starts from the name that was sent', () {
      final sent = EditPatch.fileDiff(file(), file(name: 'Lease.pdf'));
      final meanwhile = sent.then(
        EditPatch.fileDiff(file(name: 'Lease.pdf'), file(name: 'Lease 2026.pdf')),
      );
      expect(meanwhile.rebase(sent).toJson(), {
        'n': {'b': 'Lease.pdf', 'w': 'Lease 2026.pdf'},
      });
    });

    test('nothing is left of a patch that went as it was', () {
      final sent = EditPatch.fileDiff(file(), file(name: 'Lease.pdf', trashedAt: trashed));
      expect(sent.rebase(sent).isEmpty, isTrue);
    });
  });

  test('a patch survives JSON as the outbox stores it', () {
    final patch = EditPatch.fileDiff(
      file(albums: ['a1']),
      file(
        name: 'Lease.pdf',
        folderId: 'work',
        starred: true,
        trashedAt: trashed,
        albums: ['a1', 'a2'],
      ),
    );
    final stored = jsonEncode(patch.toJson());
    final back = EditPatch.fromJson(jsonDecode(stored) as Map<String, Object?>);
    expect(back.toJson(), patch.toJson());
    expect(jsonDecode(stored)['n'], {'b': 'Scan 12.pdf', 'w': 'Lease.pdf'});
  });

  test('an album rename is a name and nothing else', () {
    expect(EditPatch.albumRename('Trip', 'Lalibela 2026').toJson(), {
      'n': {'b': 'Trip', 'w': 'Lalibela 2026'},
    });
    expect(EditPatch.albumRename('Trip', 'Trip').isEmpty, isTrue);
  });

  test('applying values to a manifest restores, moves and stars', () {
    final restored = EditPatch.applyToFile(
      FileManifest(
        id: 'f1',
        name: 'Old.pdf',
        folderId: 'work',
        mimeType: 'application/pdf',
        size: 1,
        createdAt: created,
        modifiedAt: created,
        trashedAt: trashed,
        replacedBy: 'f2',
      ),
      {'tr': null, 'f': null, 'st': true},
    );
    expect(restored.trashedAt, isNull);
    expect(restored.replacedBy, isNull);
    expect(restored.folderId, isNull);
    expect(restored.starred, isTrue);
  });
}
