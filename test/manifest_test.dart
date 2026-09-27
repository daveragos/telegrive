import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';

void main() {
  final created = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);

  FileManifest file({
    String name = 'Quarterly report.pdf',
    String? folderId = 'folder-1',
    int partCount = 1,
    int partIndex = 0,
    bool starred = false,
  }) => FileManifest(
    id: 'file-1',
    name: name,
    folderId: folderId,
    mimeType: 'application/pdf',
    size: 123456,
    createdAt: created,
    modifiedAt: created,
    partCount: partCount,
    partIndex: partIndex,
    starred: starred,
  );

  group('file captions', () {
    test('round-trip every field', () {
      final original = file(partCount: 3, partIndex: 2, starred: true);
      final decoded = ManifestCodec.decodeFile(ManifestCodec.encodeFile(original).text)!;

      expect(decoded.id, original.id);
      expect(decoded.name, original.name);
      expect(decoded.folderId, original.folderId);
      expect(decoded.mimeType, original.mimeType);
      expect(decoded.size, original.size);
      expect(decoded.createdAt, original.createdAt);
      expect(decoded.partCount, 3);
      expect(decoded.partIndex, 2);
      expect(decoded.starred, isTrue);
    });

    test('capture time round-trips and is omitted when unknown', () {
      final taken = DateTime.fromMillisecondsSinceEpoch(1_690_000_000_000);
      final withTime = FileManifest(
        id: 'p',
        name: 'IMG_1.jpg',
        folderId: null,
        mimeType: 'image/jpeg',
        size: 10,
        createdAt: created,
        modifiedAt: created,
        takenAt: taken,
      );
      expect(ManifestCodec.decodeFile(ManifestCodec.encodeFile(withTime).text)!.takenAt, taken);
      expect(ManifestCodec.encodeFile(file()).text, isNot(contains('"tk"')));
      expect(ManifestCodec.decodeFile(ManifestCodec.encodeFile(file()).text)!.takenAt, isNull);
    });

    test('renames and moves keep the capture time', () {
      final taken = DateTime.fromMillisecondsSinceEpoch(1_690_000_000_000);
      final original = FileManifest(
        id: 'p',
        name: 'IMG_1.jpg',
        folderId: 'a',
        mimeType: 'image/jpeg',
        size: 10,
        createdAt: created,
        modifiedAt: created,
        takenAt: taken,
      );
      expect(original.copyWith(name: 'x.jpg', clearFolder: true).takenAt, taken);
    });

    test('root files carry no folder', () {
      final decoded = ManifestCodec.decodeFile(
        ManifestCodec.encodeFile(file(folderId: null)).text,
      )!;
      expect(decoded.folderId, isNull);
    });

    test('first line is the human-readable name, the rest is spoilered', () {
      final encoded = ManifestCodec.encodeFile(file());
      final lines = encoded.text.split('\n');

      expect(lines.first, 'Quarterly report.pdf');
      expect(
        encoded.text.substring(
          encoded.spoilerOffset,
          encoded.spoilerOffset + encoded.spoilerLength,
        ),
        startsWith(ManifestCodec.filePrefix),
      );
      expect(encoded.spoilerOffset + encoded.spoilerLength, encoded.text.length);
    });

    test('names with newlines and emoji survive', () {
      const tricky = 'Trip 🏔️\nday 1.mov';
      final encoded = ManifestCodec.encodeFile(file(name: tricky));
      expect(encoded.text.split('\n').first, 'Trip 🏔️ day 1.mov');
      expect(ManifestCodec.decodeFile(encoded.text)!.name, tricky);
    });

    test('very long names are shortened on the display line only', () {
      final long = '${'a' * 300}.txt';
      final encoded = ManifestCodec.encodeFile(file(name: long));
      expect(encoded.text.split('\n').first.length, lessThanOrEqualTo(96));
      expect(ManifestCodec.decodeFile(encoded.text)!.name, long);
      expect(encoded.text.length, lessThan(1024), reason: 'caption limit');
    });

    test('ordinary captions are not manifests', () {
      expect(ManifestCodec.decodeFile(''), isNull);
      expect(ManifestCodec.decodeFile('holiday photos'), isNull);
      expect(ManifestCodec.decodeFile('tgr1:{not json}'), isNull);
      expect(ManifestCodec.decodeFile('tgr1:{"id":"x"}'), isNull, reason: 'missing fields');
    });

    test('an out-of-range part index is rejected', () {
      expect(
        ManifestCodec.decodeFile(
          'x\ntgr1:{"id":"a","n":"b","s":1,"pc":2,"pi":2}',
        ),
        isNull,
      );
    });
  });

  test('captions from before the rename still decode', () {
    final file = ManifestCodec.decodeFile('a.txt\ngr1:{"id":"old","n":"a.txt","s":3}');
    final folder = ManifestCodec.decodeFolder('📁 Old\ngrf1:{"id":"f","n":"Old"}');
    expect(file?.id, 'old');
    expect(folder?.name, 'Old');
  });

  group('folder messages', () {
    test('round-trip', () {
      final folder = FolderManifest(
        id: 'folder-2',
        name: 'Invoices',
        parentId: 'folder-1',
        createdAt: created,
        modifiedAt: created,
      );
      final encoded = ManifestCodec.encodeFolder(folder);
      final decoded = ManifestCodec.decodeFolder(encoded.text)!;

      expect(encoded.text, startsWith('📁 Invoices\n'));
      expect(decoded.id, 'folder-2');
      expect(decoded.name, 'Invoices');
      expect(decoded.parentId, 'folder-1');
    });

    test('file and folder formats never mistake each other', () {
      final fileText = ManifestCodec.encodeFile(file()).text;
      final folderText = ManifestCodec.encodeFolder(
        FolderManifest(
          id: 'f',
          name: 'n',
          parentId: null,
          createdAt: created,
          modifiedAt: created,
        ),
      ).text;
      expect(ManifestCodec.decodeFolder(fileText), isNull);
      expect(ManifestCodec.decodeFile(folderText), isNull);
    });
  });

  group('keys from newer versions', () {
    test('an unknown file key survives decode, copyWith and encode', () {
      final decoded = ManifestCodec.decodeFile(
        'clip.mp4\ntgr1:{"id":"v","n":"clip.mp4","s":9,"du":84,"x":{"a":[1,"b"]}}',
      )!;
      expect(decoded.extra, {'du': 84, 'x': {'a': [1, 'b']}});

      final renamed = decoded.copyWith(name: 'trip.mp4', clearFolder: true);
      final again = ManifestCodec.decodeFile(ManifestCodec.encodeFile(renamed).text)!;
      expect(again.name, 'trip.mp4');
      expect(again.extra, {'du': 84, 'x': {'a': [1, 'b']}});
    });

    test('an unknown folder key survives decode and encode', () {
      final decoded = ManifestCodec.decodeFolder(
        '📁 Invoices\ntgrf1:{"id":"f","n":"Invoices","st":1}',
      )!;
      expect(decoded.extra, {'st': 1});
      final text = ManifestCodec.encodeFolder(decoded).text;
      expect(ManifestCodec.decodeFolder(text)!.extra, {'st': 1});
    });

    // Every new manifest field must be set on the manifests this test checks,
    // or a key missing from _keys goes unnoticed.
    test('keys this version knows never land in extra', () {
      final everything = file(partCount: 3, partIndex: 2, starred: true).copyWith(
        trashedAt: created,
        albums: ['a1b2c3'],
      );
      final withTime = FileManifest(
        id: 'p',
        name: 'IMG_1.jpg',
        folderId: 'a',
        mimeType: 'image/jpeg',
        size: 10,
        createdAt: created,
        modifiedAt: created,
        takenAt: created,
      );
      for (final manifest in [everything, withTime]) {
        final text = ManifestCodec.encodeFile(manifest).text;
        expect(ManifestCodec.decodeFile(text)!.extra, isEmpty);
      }
      final folder = FolderManifest(
        id: 'f',
        name: 'A',
        parentId: 'r',
        createdAt: created,
        modifiedAt: created,
        trashedAt: created,
      );
      final text = ManifestCodec.encodeFolder(folder).text;
      expect(ManifestCodec.decodeFolder(text)!.extra, isEmpty);
    });

    test('a known key wins over an extra of the same name', () {
      final json = FileManifest(
        id: 'file-1',
        name: 'Now.pdf',
        folderId: 'docs',
        mimeType: 'application/pdf',
        size: 10,
        createdAt: created,
        modifiedAt: created,
        starred: true,
        trashedAt: created,
        extra: const {'n': 'Before.pdf', 'f': 'old', 'st': 0, 'tr': 5, 'du': 84},
      ).toJson();
      expect(json['n'], 'Now.pdf');
      expect(json['f'], 'docs');
      expect(json['st'], 1);
      expect(json['tr'], created.millisecondsSinceEpoch);
      expect(json['du'], 84);

      final folder = FolderManifest(
        id: 'f',
        name: 'Now',
        parentId: 'work',
        createdAt: created,
        modifiedAt: created,
        extra: const {'n': 'Before', 'p': 'old', 'st': 1},
      ).toJson();
      expect(folder['n'], 'Now');
      expect(folder['p'], 'work');
      expect(folder['st'], 1);
    });

    test('an extra the manifest does not set still comes back out', () {
      // An older version indexed the key before it knew it, and this
      // version's own field for it was never filled in.
      final json = FileManifest(
        id: 'file-1',
        name: 'IMG_1.jpg',
        folderId: null,
        mimeType: 'image/jpeg',
        size: 10,
        createdAt: created,
        modifiedAt: created,
        extra: const {'tk': 1_690_000_000_000},
      ).toJson();
      expect(json['tk'], 1_690_000_000_000);
    });

    test('the index keeps extras as JSON, and none as null', () {
      expect(ManifestCodec.encodeExtra(const {}), isNull);
      final stored = ManifestCodec.encodeExtra(const {'du': 84, 'rb': 'new'});
      expect(ManifestCodec.decodeExtra(stored), {'du': 84, 'rb': 'new'});
      expect(ManifestCodec.decodeExtra(null), isEmpty);
      expect(ManifestCodec.decodeExtra('not json'), isEmpty);
      expect(ManifestCodec.decodeExtra('[1]'), isEmpty);
    });
  });

  group('split policy', () {
    const mib = 1024 * 1024;

    test('files within the limit stay whole', () {
      expect(SplitPolicy.partCountFor(10 * mib, limit: SplitPolicy.regularLimit), 1);
      expect(
        SplitPolicy.partCountFor(SplitPolicy.regularLimit, limit: SplitPolicy.regularLimit),
        1,
      );
    });

    test('the regular limit is 2000 MiB, not 2 GiB', () {
      expect(SplitPolicy.regularLimit, 2000 * mib);
      expect(SplitPolicy.premiumLimit, 4000 * mib);
    });

    test('larger files split into 512 MiB parts that add back up', () {
      const size = 5 * 1024 * mib + 7; // 5 GiB and change
      final parts = SplitPolicy.partCountFor(size, limit: SplitPolicy.regularLimit);
      expect(parts, 11);

      var total = 0;
      for (var i = 0; i < parts; i++) {
        expect(SplitPolicy.offsetOf(i), total);
        total += SplitPolicy.sizeOf(i, size);
      }
      expect(total, size);
      expect(SplitPolicy.sizeOf(parts - 1, size), 7);
    });

    test('premium raises the threshold', () {
      const size = 3000 * mib;
      expect(SplitPolicy.partCountFor(size, limit: SplitPolicy.regularLimit), greaterThan(1));
      expect(SplitPolicy.partCountFor(size, limit: SplitPolicy.premiumLimit), 1);
    });

    test('part names sort in order', () {
      expect(SplitPolicy.partName('movie.mkv', 0), 'movie.mkv.001');
      expect(SplitPolicy.partName('movie.mkv', 10), 'movie.mkv.011');
    });
  });

  group('trash and albums', () {
    test('a file keeps its trash time and albums, and restores clean', () {
      final trashed = file().copyWith(
        trashedAt: DateTime.fromMillisecondsSinceEpoch(1_700_000_500_000),
        albums: ['a1b2c3', 'd4e5f6'],
      );
      final decoded = ManifestCodec.decodeFile(ManifestCodec.encodeFile(trashed).text)!;
      expect(decoded.trashedAt, trashed.trashedAt);
      expect(decoded.albums, ['a1b2c3', 'd4e5f6']);

      final restored = decoded.copyWith(restore: true);
      final again = ManifestCodec.decodeFile(ManifestCodec.encodeFile(restored).text)!;
      expect(again.trashedAt, isNull);
      expect(again.albums, ['a1b2c3', 'd4e5f6']);
    });

    test('a folder keeps its trash time', () {
      final folder = FolderManifest(
        id: 'folder-1',
        name: 'Taxes',
        parentId: null,
        createdAt: created,
        modifiedAt: created,
        trashedAt: created,
      );
      final text = ManifestCodec.encodeFolder(folder).text;
      expect(ManifestCodec.decodeFolder(text)!.trashedAt, created);
    });

    test('albums are their own message kind', () {
      final album = AlbumManifest(
        id: 'a1b2c3',
        name: 'Lalibela 2026',
        createdAt: created,
        modifiedAt: created,
      );
      final text = ManifestCodec.encodeAlbum(album).text;
      expect(text.split('\n').first, '🖼 Lalibela 2026');
      expect(ManifestCodec.decodeAlbum(text)!.name, 'Lalibela 2026');
      expect(ManifestCodec.decodeFolder(text), isNull);
      expect(ManifestCodec.decodeAlbum(ManifestCodec.encodeFolder(
        FolderManifest(id: 'f', name: 'x', parentId: null, createdAt: created, modifiedAt: created),
      ).text), isNull);
    });
  });
}
