import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/widgets/file_visuals.dart';
import 'package:telegrive/features/drive/data/previews.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

/// A one-pixel PNG, standing in for Telegram's inline preview.
const _preview = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMQUDAAAACkAGE0Zn1yAAAAAElFTkSuQmCC';

void main() {
  late AppDatabase db;

  /// Whether the tile is in the tree, so a test can scroll it away while
  /// the providers stay.
  late ValueNotifier<bool> onScreen;
  final bytes = base64Decode(_preview);

  setUp(() async {
    onScreen = ValueNotifier(true);
    db = AppDatabase(NativeDatabase.memory());
    final at = DateTime(2026, 10, 4);
    await db.upsertFilePart(
      DriveFilesCompanion.insert(
        id: 'photo',
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        kind: FileKind.image,
        size: 100,
        createdAt: at,
        modifiedAt: at,
        minithumbnail: const Value(_preview),
      ),
      FilePartsCompanion.insert(fileId: 'photo', partIndex: 0, messageId: 1, tdFileId: 2, size: 100),
    );
  });

  tearDown(() async {
    onScreen.dispose();
    await db.close();
  });

  /// A photo that has an inline preview: as the Photos timeline reads it,
  /// without the preview itself, unless [withPreview].
  DriveFile photo({bool withPreview = false}) => DriveFile(
    id: 'photo',
    folderId: null,
    name: 'photo.jpg',
    mimeType: 'image/jpeg',
    kind: FileKind.image,
    size: 100,
    createdAt: DateTime(2026, 10, 4),
    modifiedAt: DateTime(2026, 10, 4),
    partCount: 1,
    starred: false,
    minithumbnail: withPreview ? bytes : null,
    hasMinithumbnail: true,
  );

  Future<ProviderContainer> pumpTile(
    WidgetTester tester,
    DriveFile file, {
    Map<String, Object> prefs = const {},
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: onScreen,
              builder: (_, shown, _) =>
                  shown ? FileThumbnail(file: file, size: 44) : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(FileThumbnail)));
    // The database answers outside the test's fake clock.
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
    return container;
  }

  /// The inline preview's picture, if one is drawn.
  Image? drawn(WidgetTester tester) {
    final images = tester.widgetList<Image>(find.byType(Image));
    return images.isEmpty ? null : images.single;
  }

  testWidgets('a tile read without its preview reads it for itself, blurred', (tester) async {
    await pumpTile(tester, photo());

    final image = drawn(tester)!;
    expect(image.image, isA<MemoryImage>().having((m) => m.bytes, 'bytes', bytes));
    expect(find.byType(ImageFiltered), findsOneWidget);
  });

  testWidgets('while saving memory that preview is drawn plain', (tester) async {
    await pumpTile(tester, photo(), prefs: {'save_memory': true});

    final image = drawn(tester)!;
    expect(image.image, isA<MemoryImage>().having((m) => m.bytes, 'bytes', bytes));
    expect(image.filterQuality, FilterQuality.low);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('a tile that came with its preview reads nothing', (tester) async {
    final container = await pumpTile(tester, photo(withPreview: true));

    expect(drawn(tester), isNotNull);
    expect(container.exists(minithumbnailProvider('photo')), isFalse);
  });

  testWidgets('a preview read for a tile is kept for 30 seconds after the tile goes', (
    tester,
  ) async {
    final container = await pumpTile(tester, photo());
    expect(container.exists(minithumbnailProvider('photo')), isTrue);

    onScreen.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 29));
    expect(container.exists(minithumbnailProvider('photo')), isTrue);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(container.exists(minithumbnailProvider('photo')), isFalse);
  });
}
