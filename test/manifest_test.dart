import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/features/drive/domain/caption_text.dart';

void main() {
  final created = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);

  FileManifest file({
    String name = 'Quarterly report.pdf',
    String? folderId = 'folder-1',
    int partCount = 1,
    int partIndex = 0,
    bool starred = false,
    int? durationSeconds,
    String? replacedBy,
    int? originalSize,
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
    durationSeconds: durationSeconds,
    replacedBy: replacedBy,
    originalSize: originalSize,
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
      expect(ManifestCodec.encodeFile(file()).text, isNot(contains('taken=')));
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

    test('a length round-trips, is left out when unknown and survives a move', () {
      final clip = file(name: 'clip.mp4', durationSeconds: 84);
      final decoded = ManifestCodec.decodeFile(ManifestCodec.encodeFile(clip).text)!;
      expect(decoded.durationSeconds, 84);
      expect(ManifestCodec.encodeFile(file()).text, isNot(contains('length=')));
      expect(ManifestCodec.decodeFile(ManifestCodec.encodeFile(file()).text)!.durationSeconds, isNull);

      final moved = decoded.copyWith(name: 'trip.mp4', clearFolder: true);
      expect(ManifestCodec.decodeFile(ManifestCodec.encodeFile(moved).text)!.durationSeconds, 84);
    });

    test('a length that is zero or not a number is no length', () {
      for (final du in ['0', '"90"', '-5', '1.5']) {
        final decoded = ManifestCodec.decodeFile('x\ntgr1:{"id":"a","n":"b","s":1,"du":$du}')!;
        expect(decoded.durationSeconds, isNull, reason: du);
        expect(decoded.extra, isEmpty, reason: du);
      }
    });

    test('a replaced file carries rb and restores clean', () {
      final replaced = file(replacedBy: 'new-id').copyWith(trashedAt: created);
      final decoded = ManifestCodec.decodeFile(ManifestCodec.encodeFile(replaced).text)!;
      expect(decoded.replacedBy, 'new-id');
      expect(decoded.trashedAt, created);

      final restored = decoded.copyWith(restore: true);
      expect(restored.replacedBy, isNull);
      expect(restored.trashedAt, isNull);
      expect(ManifestCodec.encodeFile(restored).text, isNot(contains('replacedby=')));
      expect(ManifestCodec.encodeFile(file()).text, isNot(contains('replacedby=')));
    });

    test('root files carry no folder', () {
      final decoded = ManifestCodec.decodeFile(
        ManifestCodec.encodeFile(file(folderId: null)).text,
      )!;
      expect(decoded.folderId, isNull);
    });

    test('the name is bold, and the details are folded under a spoiler', () {
      final encoded = ManifestCodec.encodeFile(file(), folderName: 'Invoices');

      expect(encoded.text.split('\n'), [
        'Quarterly report.pdf',
        '#Invoices',
        'Telegrive details',
        startsWith('${ManifestCodec.fileKind};'),
      ]);
      expect(encoded.styled(CaptionStyle.bold), 'Quarterly report.pdf');
      final details = encoded.styled(CaptionStyle.spoiler)!;
      expect(details, startsWith('${ManifestCodec.fileKind};'));
      expect(encoded.text, endsWith(details));
      expect(
        encoded.styled(CaptionStyle.expandableQuote),
        'Telegrive details\n$details',
      );
      expect(encoded.styles.map((range) => range.offset), orderedEquals([0, 31, 49]));
    });

    test('the details line spells its fields out', () {
      final encoded = ManifestCodec.encodeFile(file(partCount: 3, partIndex: 1, starred: true));
      expect(
        encoded.styled(CaptionStyle.spoiler),
        'tgfile2;id=file-1;name=Quarterly report.pdf;folder=folder-1;'
        'type=application/pdf;size=123456;parts=3;part=2;star=1;'
        'added=1700000000000;changed=1700000000000',
      );
    });

    test('tags and notes say where a file is and what it is', () {
      final split = ManifestCodec.encodeFile(
        file(partCount: 3, partIndex: 1, starred: true).copyWith(trashedAt: created),
        folderName: 'Tax returns 2026',
      );
      expect(split.text.split('\n').take(3), [
        'Quarterly report.pdf',
        '#Tax_returns_2026 #starred #trash',
        'Part 2 of 3',
      ]);

      final root = ManifestCodec.encodeFile(file(folderId: null), folderName: 'ignored');
      expect(root.text.split('\n')[1], 'Telegrive details');
    });

    test('a folder says what it is called and where it sits', () {
      final folder = FolderManifest(
        id: 'folder-2',
        name: 'Invoices',
        parentId: 'folder-1',
        createdAt: created,
        modifiedAt: created,
        starred: true,
      );
      final encoded = ManifestCodec.encodeFolder(folder, parentName: 'Work');
      expect(encoded.text.split('\n').take(2), ['📁 Invoices', '#Invoices #starred · in #Work']);
      expect(encoded.styled(CaptionStyle.bold), '📁 Invoices');
      expect(
        encoded.styled(CaptionStyle.spoiler),
        'tgfolder2;id=folder-2;name=Invoices;parent=folder-1;star=1;'
        'added=1700000000000;changed=1700000000000',
      );
    });

    test('values that would break the line or turn into links are escaped', () {
      const name = 'Q3; 100% #final @ \$5\u202e.pdf';
      final encoded = ManifestCodec.encodeFile(file(name: name));
      expect(
        encoded.styled(CaptionStyle.spoiler),
        contains(';name=Q3%3B 100%25 %23final %40 %245%E2%80%AE.pdf;'),
      );
      expect(ManifestCodec.decodeFile(encoded.text)!.name, name);
    });

    test('a broken escape makes no manifest of the line', () {
      expect(ManifestCodec.decodeFile('tgfile2;id=a;name=b%2;size=1'), isNull);
      expect(ManifestCodec.decodeFile('tgfile2;id=a;name=b%ZZ;size=1'), isNull);
      expect(ManifestCodec.decodeFile('tgfile2;id=a;name=b;size=1')!.name, 'b');
    });

    test('a field written twice keeps its last value', () {
      expect(ManifestCodec.decodeFile('tgfile2;id=a;name=b;name=c;size=1')!.name, 'c');
    });

    test('the last details line is the one read', () {
      final caption = 'tgfile2;id=a;name=first;size=1\nTelegrive details\ntgfile2;id=a;name=second;size=1';
      expect(ManifestCodec.decodeFile(caption)!.name, 'second');
    });

    test('albums keep their ids and order', () {
      final encoded = ManifestCodec.encodeFile(file().copyWith(albums: ['b9', 'a0']));
      expect(encoded.text, contains(';albums=b9,a0;'));
      expect(ManifestCodec.decodeFile(encoded.text)!.albums, ['b9', 'a0']);
    });

    test('long names and long folder names still fit the caption limit', () {
      final encoded = ManifestCodec.encodeFile(
        file(name: '${'#' * 250}.txt', partCount: 2, partIndex: 1),
        folderName: 'f' * 128,
      );
      expect(encoded.text.length, lessThanOrEqualTo(CaptionLayout.limit));
      expect(ManifestCodec.decodeFile(encoded.text)!.name, '${'#' * 250}.txt');
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
      expect(ManifestCodec.decodeFile('tgfile2;id=x;name=y'), isNull, reason: 'missing size');
      expect(ManifestCodec.decodeFile('tgfile2;id=x;name=y;size=big'), isNull);
      expect(ManifestCodec.decodeFile('see tgfile2;id=x;name=y;size=1'), isNull);
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

  test('captions in the older layout still decode', () {
    final file = ManifestCodec.decodeFile('a.txt\ngr1:{"id":"old","n":"a.txt","s":3}');
    final folder = ManifestCodec.decodeFolder('📁 Old\ngrf1:{"id":"f","n":"Old"}');
    expect(file?.id, 'old');
    expect(folder?.name, 'Old');
    expect(ManifestCodec.decodeFile('a.txt\ntgr1:{"id":"new","n":"a.txt","s":3}')?.id, 'new');
    expect(ManifestCodec.decodeAlbum('🖼 Trip\ntgra1:{"id":"t","n":"Trip"}')?.name, 'Trip');
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

    test('a starred folder round-trips, and the key is left out otherwise', () {
      FolderManifest folder({bool starred = false}) => FolderManifest(
        id: 'folder-2',
        name: 'Invoices',
        parentId: null,
        createdAt: created,
        modifiedAt: created,
        starred: starred,
      );
      final starredText = ManifestCodec.encodeFolder(folder(starred: true)).text;
      expect(ManifestCodec.decodeFolder(starredText)!.starred, isTrue);

      final plainText = ManifestCodec.encodeFolder(folder()).text;
      expect(plainText, isNot(contains('star=')));
      expect(ManifestCodec.decodeFolder(plainText)!.starred, isFalse);

      final old = ManifestCodec.decodeFolder('📁 Old\ngrf1:{"id":"f","n":"Old"}')!;
      expect(old.starred, isFalse);
      expect(old.extra, isEmpty);
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
        'clip.mp4\ntgr1:{"id":"v","n":"clip.mp4","s":9,"xv":123456,"x":{"a":[1,"b"]}}',
      )!;
      expect(decoded.extra, {'xv': 123456, 'x': {'a': [1, 'b']}});

      final renamed = decoded.copyWith(name: 'trip.mp4', clearFolder: true);
      final again = ManifestCodec.decodeFile(ManifestCodec.encodeFile(renamed).text)!;
      expect(again.name, 'trip.mp4');
      expect(again.extra, {'xv': 123456, 'x': {'a': [1, 'b']}});
    });

    test('an unknown field goes back onto the line exactly as it came', () {
      const line = 'tgfile2;xq=blue;xn=12;xs="12";xj={"a":[1,"b"]};xe=%23x;id=v;name=a;size=9';
      final decoded = ManifestCodec.decodeFile(line)!;
      expect(decoded.extra, {'xq': 'blue', 'xn': 12, 'xs': '"12"', 'xj': {'a': [1, 'b']}, 'xe': '#x'});
      expect(
        ManifestCodec.encodeFile(decoded).styled(CaptionStyle.spoiler),
        startsWith('tgfile2;xq=blue;xn=12;xs="12";xj={"a":[1,"b"]};xe=%23x;id=v;'),
      );
    });

    test('an unknown field never stands in for a known key', () {
      final decoded = ManifestCodec.decodeFile('tgfile2;id=v;name=a;size=9;s=big;n=other')!;
      expect(decoded.name, 'a');
      expect(decoded.size, 9);
      expect(decoded.extra, isEmpty);
    });

    test('an unknown folder key survives decode and encode', () {
      final decoded = ManifestCodec.decodeFolder(
        '📁 Invoices\ntgrf1:{"id":"f","n":"Invoices","c":"blue"}',
      )!;
      expect(decoded.extra, {'c': 'blue'});
      final text = ManifestCodec.encodeFolder(decoded).text;
      expect(ManifestCodec.decodeFolder(text)!.extra, {'c': 'blue'});
    });

    // Every new manifest field must be set on the manifests this test checks,
    // or a key missing from _keys goes unnoticed.
    test('keys this version knows never land in extra', () {
      final everything = file(
        partCount: 3,
        partIndex: 2,
        starred: true,
        durationSeconds: 84,
        replacedBy: 'new-id',
        originalSize: 6100000,
      ).copyWith(trashedAt: created, albums: ['a1b2c3']);
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
        starred: true,
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
        durationSeconds: 90,
        replacedBy: 'new-id',
        extra: const {
          'n': 'Before.pdf', 'f': 'old', 'st': 0, 'tr': 5, 'du': 84, 'rb': 'old-id',
        },
      ).toJson();
      expect(json['n'], 'Now.pdf');
      expect(json['f'], 'docs');
      expect(json['st'], 1);
      expect(json['tr'], created.millisecondsSinceEpoch);
      expect(json['du'], 90);
      expect(json['rb'], 'new-id');

      final folder = FolderManifest(
        id: 'f',
        name: 'Now',
        parentId: 'work',
        createdAt: created,
        modifiedAt: created,
        starred: true,
        extra: const {'n': 'Before', 'p': 'old', 'st': 0},
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
      final stored = ManifestCodec.encodeExtra(const {'xv': 123456, 'c': 'blue'});
      expect(ManifestCodec.decodeExtra(stored), {'xv': 123456, 'c': 'blue'});
      expect(ManifestCodec.decodeExtra(null), isEmpty);
      expect(ManifestCodec.decodeExtra('not json'), isEmpty);
      expect(ManifestCodec.decodeExtra('[1]'), isEmpty);
    });
  });

  group('small copies', () {
    FileManifest smallCopy() => FileManifest(
      id: 'p',
      name: 'IMG_1.HEIC',
      folderId: 'camera',
      mimeType: 'image/jpeg',
      size: 312000,
      createdAt: created,
      modifiedAt: created,
      takenAt: created,
      originalSize: 6100000,
    );

    test('the original\'s size round-trips as lt, beside the copy\'s own', () {
      final encoded = ManifestCodec.encodeFile(smallCopy());
      expect(encoded.text, contains(';original=6100000;'));
      final decoded = ManifestCodec.decodeFile(encoded.text)!;
      expect(decoded.originalSize, 6100000);
      expect(decoded.size, 312000);
      expect(decoded.mimeType, 'image/jpeg');
      expect(decoded.name, 'IMG_1.HEIC');
      expect(decoded.extra, isEmpty);
    });

    test('a note says it is a small copy', () {
      final encoded = ManifestCodec.encodeFile(smallCopy(), folderName: 'Camera');
      expect(encoded.text.split('\n').take(3), [
        'IMG_1.HEIC',
        '#Camera',
        'Small copy, the original follows',
      ]);
    });

    test('copyWith keeps the original\'s size, and clearOriginalSize drops it', () {
      final starred = smallCopy().copyWith(starred: true, name: 'Lalibela.HEIC');
      expect(starred.originalSize, 6100000);
      expect(ManifestCodec.decodeFile(ManifestCodec.encodeFile(starred).text)!.originalSize, 6100000);

      final whole = smallCopy().copyWith(clearOriginalSize: true);
      expect(whole.originalSize, isNull);
      final encoded = ManifestCodec.encodeFile(whole);
      expect(encoded.text.split('\n').first, 'IMG_1.HEIC');
      expect(encoded.text, isNot(contains('original=')));
    });

    test('a caption without lt is no small copy', () {
      final decoded = ManifestCodec.decodeFile(ManifestCodec.encodeFile(file()).text)!;
      expect(decoded.originalSize, isNull);
      expect(
        ManifestCodec.decodeFile('a.jpg\ntgr1:{"id":"a","n":"a.jpg","s":9,"lt":"big"}')!.originalSize,
        isNull,
      );
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
