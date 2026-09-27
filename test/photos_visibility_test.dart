import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/photos/data/photos_visibility.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

void main() {
  final now = DateTime(2026, 9, 27);

  FolderRow folder(String id, String name, {String? parentId}) => FolderRow(
    id: id,
    parentId: parentId,
    name: name,
    messageId: id.hashCode,
    createdAt: now,
    modifiedAt: now,
    hidden: false,
  );

  DriveFile photo(String id, {String? folderId, bool starred = false}) => DriveFile(
    id: id,
    folderId: folderId,
    name: '$id.jpg',
    mimeType: 'image/jpeg',
    kind: FileKind.image,
    size: 100,
    createdAt: now,
    modifiedAt: now,
    partCount: 1,
    starred: starred,
  );

  group('hiddenBackupFolders', () {
    test('finds the named folders directly under Photo backup, whatever the case', () {
      final folders = [
        folder('pb', 'photo Backup'),
        folder('scr', 'screenshots', parentId: 'pb'),
        folder('cam', 'Camera', parentId: 'pb'),
        folder('wa', 'WhatsApp Images', parentId: 'pb'),
      ];
      expect(
        hiddenBackupFolders(folders, {'Screenshots', 'WHATSAPP IMAGES'}, 'Photo backup'),
        {'scr': 'screenshots', 'wa': 'WhatsApp Images'},
      );
    });

    test('matches under every top-level Photo backup', () {
      final folders = [
        folder('pb1', 'Photo backup'),
        folder('scr1', 'Screenshots', parentId: 'pb1'),
        folder('pb2', 'Photo backup'),
        folder('scr2', 'Screenshots', parentId: 'pb2'),
      ];
      expect(
        hiddenBackupFolders(folders, {'Screenshots'}, 'Photo backup'),
        {'scr1': 'Screenshots', 'scr2': 'Screenshots'},
      );
    });

    test('leaves alone same-named folders elsewhere or deeper down', () {
      final folders = [
        folder('pb', 'Photo backup'),
        folder('cam', 'Camera', parentId: 'pb'),
        folder('deep', 'Screenshots', parentId: 'cam'),
        folder('mine', 'Screenshots'),
        folder('work', 'Work'),
        folder('nested-pb', 'Photo backup', parentId: 'work'),
        folder('nested-scr', 'Screenshots', parentId: 'nested-pb'),
      ];
      expect(hiddenBackupFolders(folders, {'Screenshots'}, 'Photo backup'), isEmpty);
    });
  });

  group('filterTimeline', () {
    final media = [
      photo('a', folderId: 'cam'),
      photo('b', folderId: 'scr'),
      photo('c'),
      photo('d', folderId: 'scr'),
    ];

    test('drops files in hidden folders and keeps files at the root', () {
      expect(filterTimeline(media, {'scr'}, reveal: false).map((f) => f.id), ['a', 'c']);
    });

    test('keeps everything while revealed', () {
      expect(filterTimeline(media, {'scr'}, reveal: true).map((f) => f.id), ['a', 'b', 'c', 'd']);
    });
  });

  group('keptOutSentence', () {
    test('names one or two folders and counts the rest', () {
      expect(keptOutSentence(['Screenshots'], revealed: false), 'Screenshots is kept out of this view');
      expect(
        keptOutSentence(['Screenshots', 'WhatsApp Images'], revealed: false),
        'Screenshots and WhatsApp Images are kept out of this view',
      );
      expect(
        keptOutSentence(['Screenshots', 'Telegram', 'WhatsApp Images'], revealed: false),
        'Screenshots and 2 other folders are kept out of this view',
      );
    });

    test('says what is showing once revealed', () {
      expect(keptOutSentence(['Screenshots'], revealed: true), 'Showing Screenshots');
      expect(
        keptOutSentence(['Screenshots', 'WhatsApp Images'], revealed: true),
        'Showing Screenshots and 1 other folder',
      );
      expect(
        keptOutSentence(['Screenshots', 'Telegram', 'WhatsApp Images'], revealed: true),
        'Showing Screenshots and 2 other folders',
      );
    });
  });

  group('photosHiddenFolders', () {
    Future<Preferences> prefs(Map<String, Object> stored) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(stored);
      return Preferences(await SharedPreferences.getInstance());
    }

    test('starts with Screenshots and the chat folders', () async {
      expect((await prefs({})).photosHiddenFolders, Preferences.defaultPhotosHiddenFolders);
      expect(Preferences.defaultPhotosHiddenFolders, contains('Screenshots'));
    });

    test('an empty choice keeps nothing out', () async {
      expect((await prefs({'photos_hidden_folders': <String>[]})).photosHiddenFolders, isEmpty);
    });

    test('keeps what was chosen', () async {
      final stored = await prefs({});
      await stored.setPhotosHiddenFolders({'Telegram', 'Screenshots'});
      expect(stored.photosHiddenFolders, {'Screenshots', 'Telegram'});
    });
  });

  group('the Photos view', () {
    late StreamController<Map<String, String>> hidden;
    late ProviderContainer container;

    setUp(() {
      hidden = StreamController<Map<String, String>>();
      container = ProviderContainer(
        overrides: [
          mediaTimelineProvider.overrideWith(
            (ref) => Stream.value([
              photo('a', folderId: 'cam', starred: true),
              photo('b', folderId: 'scr1', starred: true),
              photo('c', folderId: 'scr2'),
              photo('d', folderId: 'wa'),
              photo('e'),
            ]),
          ),
          hiddenBackupFoldersProvider.overrideWith((ref) => hidden.stream),
        ],
      );
      container.listen(photosTimelineProvider, (_, _) {});
      container.listen(keptOutSummaryProvider, (_, _) {});
    });

    tearDown(() async {
      container.dispose();
      await hidden.close();
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('waits for the folders before showing anything', () async {
      await settle();
      expect(container.read(photosTimelineProvider).isLoading, isTrue);

      hidden.add({'scr1': 'Screenshots', 'scr2': 'Screenshots', 'wa': 'WhatsApp Images'});
      await settle();
      expect(container.read(photosTimelineProvider).value!.map((f) => f.id), ['a', 'e']);
    });

    test('counts what is kept out and names each folder once', () async {
      hidden.add({'scr1': 'Screenshots', 'scr2': 'Screenshots', 'wa': 'WhatsApp Images'});
      await settle();
      final summary = container.read(keptOutSummaryProvider);
      expect(summary.count, 3);
      expect(summary.names, ['Screenshots', 'WhatsApp Images']);
    });

    test('Show brings kept-out files back and the summary stays', () async {
      hidden.add({'wa': 'WhatsApp Images'});
      await settle();
      container.read(revealHiddenProvider.notifier).toggle();
      await settle();
      expect(container.read(photosTimelineProvider).value, hasLength(5));
      expect(container.read(keptOutSummaryProvider).count, 1);
    });

    test('nothing kept out when no folder has files in it', () async {
      hidden.add({'other': 'Telegram'});
      await settle();
      expect(container.read(photosTimelineProvider).value, hasLength(5));
      expect(container.read(keptOutSummaryProvider).count, 0);
    });
  });
}
