import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/widgets/file_visuals.dart';
import 'package:telegrive/core/widgets/selection_bar.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/photos/data/photos_visibility.dart';
import 'package:telegrive/features/photos/presentation/photos_screen.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

class _Backup extends BackupController {
  @override
  BackupState build() => const BackupState(phase: BackupPhase.upToDate);
}

class _Queue extends TransferQueue {
  @override
  TransfersState build() => TransfersState.empty;
}

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
    starred: false,
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

  group('oneTilePerPhoto', () {
    DriveFile file(String name, FileKind kind, {String folderId = 'y2025'}) => DriveFile(
      id: '$folderId/$name',
      folderId: folderId,
      name: name,
      mimeType: kind == FileKind.video ? 'video/mp4' : 'image/jpeg',
      kind: kind,
      size: 100,
      createdAt: now,
      modifiedAt: now,
      partCount: 1,
      starred: false,
    );
    List<String> names(List<DriveFile> files) => [for (final f in files) f.name];

    test('a Live Photo shows as its photo, not also its video', () {
      final media = [
        file('IMG_0094.HEIC', FileKind.image),
        file('IMG_0094.MP4', FileKind.video),
        file('20251008_175705.jpg', FileKind.image),
        file('20251008_175705.MP4', FileKind.video),
        file('VID_20251009_100000.mp4', FileKind.video),
      ];
      expect(names(oneTilePerPhoto(media)), ['IMG_0094.HEIC', '20251008_175705.jpg', 'VID_20251009_100000.mp4']);
    });

    test('an edited photo shows in place of its original', () {
      final media = [
        file('Screenshot_Maps.jpg', FileKind.image),
        file('Screenshot_Maps-edited.jpg', FileKind.image),
        file('IMG_2-bearbeitet.jpg', FileKind.image),
        file('IMG_2.jpg', FileKind.image),
      ];
      expect(names(oneTilePerPhoto(media)), ['Screenshot_Maps-edited.jpg', 'IMG_2-bearbeitet.jpg']);
    });

    test('only files in the same folder are paired', () {
      final media = [
        file('IMG_1.jpg', FileKind.image, folderId: 'camera'),
        file('IMG_1.mp4', FileKind.video, folderId: 'download'),
        file('IMG_3.jpg', FileKind.image, folderId: 'camera'),
        file('IMG_3-edited.jpg', FileKind.image, folderId: 'edits'),
      ];
      expect(oneTilePerPhoto(media), hasLength(4));
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

  /// Whether the Photos tab is in the tree. Taking it out leaves the scope,
  /// and the container in it, as the app's container outlives its shell.
  late ValueNotifier<bool> shown;

  setUp(() => shown = ValueNotifier(true));
  tearDown(() => shown.dispose());

  Future<ProviderContainer> pumpPhotos(WidgetTester tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          backupControllerProvider.overrideWith(_Backup.new),
          transferQueueProvider.overrideWith(_Queue.new),
          mediaTimelineProvider.overrideWith(
            (ref) => Stream.value([photo('camera'), photo('screenshot', folderId: 'scr')]),
          ),
          hiddenBackupFoldersProvider.overrideWith((ref) => Stream.value({'scr': 'Screenshots'})),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ValueListenableBuilder(
            valueListenable: shown,
            builder: (_, shown, _) => shown ? const PhotosScreen() : const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(PhotosScreen)));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> selectPhotos(WidgetTester tester) async {
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byTooltip('More')));
    await settle(tester);
    await tester.tap(find.text('Select photos'));
    await settle(tester);
  }

  testWidgets('Hide lets go of the selected photos it takes off screen', (tester) async {
    await pumpPhotos(tester);

    Finder tile(String id) =>
        find.byWidgetPredicate((w) => w is FileThumbnail && w.file.id == id);
    Finder selected(String title) =>
        find.descendant(of: find.byType(AppBar), matching: find.text(title));

    await tester.tap(find.widgetWithText(TextButton, 'Show'));
    await tester.pump();
    await tester.longPress(tile('camera'));
    await tester.pump();
    await tester.tap(tile('screenshot'));
    await tester.pump();
    expect(selected('2 selected · 200 B'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Hide'));
    await tester.pump();
    expect(tile('screenshot'), findsNothing);
    expect(selected('1 selected · 100 B'), findsOneWidget);
  });

  testWidgets('Select photos tells the shell to give up its bar, and ending it takes it back', (
    tester,
  ) async {
    final container = await pumpPhotos(tester);
    expect(container.read(selectionActiveProvider), isFalse);

    await selectPhotos(tester);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Select photos')),
      findsOneWidget,
    );
    expect(find.byType(SelectionActionBar), findsOneWidget);
    expect(container.read(selectionActiveProvider), isTrue);

    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pump();
    expect(find.byType(SelectionActionBar), findsNothing);
    expect(container.read(selectionActiveProvider), isFalse);
  });

  testWidgets('a tab taken down while selecting leaves the next shell its bar', (tester) async {
    final container = await pumpPhotos(tester);
    await selectPhotos(tester);
    expect(container.read(selectionActiveProvider), isTrue);

    shown.value = false;
    await tester.pump();
    await tester.pump();
    expect(container.read(selectionActiveProvider), isFalse);
  });
}
