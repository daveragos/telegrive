import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/phone_albums/data/phone_albums.dart';
import 'package:telegrive/features/phone_albums/presentation/phone_album_upload.dart';

/// A planner over a drive holding file `kept`, with `trashed` in the trash
/// and `gone` no longer in the index.
AlbumUploadPlanner _planner({
  Map<String, String> backedUp = const {},
  Map<String, ({String fileId, bool smallCopy})> fingerprints = const {},
  Map<String, PendingAssetUpload> pending = const {},
}) => AlbumUploadPlanner(
  backedUp: backedUp,
  fingerprints: fingerprints,
  pending: pending,
  isLive: (fileId) async => fileId == 'kept',
);

void main() {
  group('AlbumUploadPlanner.before', () {
    test('a photo going up into this album already is left to that upload', () async {
      final planner = _planner(
        pending: {'a1': (transferId: 't1', inAlbum: true)},
        backedUp: {'a1': 'kept'},
      );
      expect(await planner.before('a1'), isA<AlreadyGoing>());
    });

    test('a photo going up elsewhere, by backup say, joins the album as it lands', () async {
      final planner = _planner(pending: {'a1': (transferId: 't1', inAlbum: false)});
      final fate = await planner.before('a1');
      expect(fate, isA<JoinsOnLanding>());
      expect((fate! as JoinsOnLanding).transferId, 't1');
    });

    test('a photo backup sent joins the album where it is', () async {
      final fate = await _planner(backedUp: {'a1': 'kept'}).before('a1');
      expect(fate, isA<InDrive>());
      expect((fate! as InDrive).fileId, 'kept');
    });

    test('a photo whose backed-up file is in the trash or gone is read again', () async {
      final planner = _planner(backedUp: {'a1': 'trashed', 'a2': 'gone'});
      expect(await planner.before('a1'), isNull);
      expect(await planner.before('a2'), isNull);
    });

    test('a photo the phone knows nothing of is read', () async {
      expect(await _planner().before('a1'), isNull);
    });
  });

  group('AlbumUploadPlanner.after', () {
    test('a file the drive has under the same name and size joins the album', () async {
      final planner = _planner(
        fingerprints: {'IMG_1.HEIC|2048': (fileId: 'kept', smallCopy: false)},
      );
      final fate = await planner.after('IMG_1.HEIC', 2048);
      expect(fate, isA<InDrive>());
      expect((fate as InDrive).fileId, 'kept');
    });

    test('a small copy of it counts as in the drive, as backup counts it', () async {
      final planner = _planner(
        fingerprints: {'IMG_1.HEIC|2048': (fileId: 'kept', smallCopy: true)},
      );
      expect(await planner.after('IMG_1.HEIC', 2048), isA<InDrive>());
    });

    test('another size, or a match in the trash, goes up', () async {
      final planner = _planner(
        fingerprints: {
          'IMG_1.HEIC|2048': (fileId: 'kept', smallCopy: false),
          'IMG_2.HEIC|4096': (fileId: 'trashed', smallCopy: false),
        },
      );
      expect(await planner.after('IMG_1.HEIC', 1024), isA<GoesUp>());
      expect(await planner.after('IMG_2.HEIC', 4096), isA<GoesUp>());
    });
  });

  group('albumFolderName', () {
    test('keeps the album\'s name, trimmed', () {
      expect(albumFolderName('  Wedding '), 'Wedding');
    });

    test('names an album with no name Phone album', () {
      expect(albumFolderName(''), 'Phone album');
      expect(albumFolderName('   '), 'Phone album');
    });

    test('cuts a long name to what a folder name may be', () {
      expect(albumFolderName('a' * 200).length, 128);
    });
  });

  group('PhoneAlbumUpload.summary', () {
    String? summary({
      int uploading = 0,
      int inDrive = 0,
      int joining = 0,
      int alreadyGoing = 0,
      int unreadable = 0,
      bool outOfRoom = false,
      bool waitsForWifi = false,
    }) => PhoneAlbumUpload.summary(
      album: 'Wedding',
      uploading: uploading,
      inDrive: inDrive,
      joining: joining,
      alreadyGoing: alreadyGoing,
      unreadable: unreadable,
      outOfRoom: outOfRoom,
      waitsForWifi: waitsForWifi,
    );

    test('says how many go up', () {
      expect(summary(uploading: 40), 'Uploading 40 items to "Wedding".');
      expect(
        summary(uploading: 1, waitsForWifi: true),
        'Waiting for Wi-Fi to upload 1 item to "Wedding".',
      );
    });

    test('says how many join from the drive beside those going up', () {
      expect(
        summary(uploading: 40, inDrive: 200),
        'Uploading 40 items to "Wedding". '
        '200 items already in your drive join it where they are.',
      );
    });

    test('leaves files joining from the drive alone to the album\'s own change', () {
      expect(summary(inDrive: 200), isNull);
    });

    test('says which uploads under way join it as they land', () {
      expect(
        summary(joining: 3),
        '3 items already going up join "Wedding" as they land.',
      );
      expect(
        summary(uploading: 2, joining: 3),
        'Uploading 2 items to "Wedding". 3 items already going up join it as they land.',
      );
      expect(
        summary(inDrive: 5, joining: 3),
        '3 items already going up join "Wedding" as they land.',
      );
    });

    test('says what couldn\'t be read and when the phone ran out of room', () {
      expect(
        summary(uploading: 2, unreadable: 1, outOfRoom: true),
        'Uploading 2 items to "Wedding". 1 item couldn\'t be read. '
        'The phone ran low on room, so the rest wait: upload the album again '
        'once these are up.',
      );
    });

    test('says an album already on its way is', () {
      expect(summary(alreadyGoing: 12), '"Wedding" is already on its way to your drive.');
    });

    test('says nothing when nothing happened', () {
      expect(summary(), isNull);
    });
  });
}
