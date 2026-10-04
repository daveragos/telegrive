import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/previews.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/photos/data/photos_visibility.dart';
import 'package:telegrive/features/viewer/presentation/image_viewer_screen.dart';
import 'package:telegrive/features/viewer/presentation/vertical_swipe.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

DriveFile _photo(String id, int day) => DriveFile(
  id: id,
  folderId: 'camera',
  name: '$id.jpg',
  mimeType: 'image/jpeg',
  kind: FileKind.image,
  size: 1200000,
  createdAt: DateTime(2026, 9, day, 10, 12),
  modifiedAt: DateTime(2026, 9, day, 10, 12),
  partCount: 1,
  starred: false,
  takenAt: DateTime(2026, 9, day, 8),
);

final _photos = [_photo('a', 26), _photo('b', 25), _photo('c', 24)];

/// Which of the photos are in the trash.
class _Trashed extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void update(Set<String> ids) => state = ids;
}

final _trashedProvider = NotifierProvider<_Trashed, Set<String>>(_Trashed.new);

/// A drive whose Photo backup › Camera folder holds the three photos, and
/// whose trash and restore only flip which of them the timeline shows.
class _Repository extends DriveRepository {
  _Repository(this.ref) : super(ref);

  final Ref ref;

  @override
  Future<void> trash({
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
  }) async {
    final trashed = ref.read(_trashedProvider);
    ref.read(_trashedProvider.notifier).update({...trashed, ...files.map((f) => f.id)});
  }

  @override
  Future<void> restore({
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
  }) async {
    final back = files.map((f) => f.id).toSet();
    ref.read(_trashedProvider.notifier).update(ref.read(_trashedProvider).difference(back));
  }

  @override
  Future<DriveFile?> fileById(String id) async => _photos.where((f) => f.id == id).firstOrNull;

  @override
  Future<List<DriveFolder>> pathTo(String? folderId) async => [
    for (final (id, name, parent) in [
      ('backup', 'Photo backup', null),
      ('camera', 'Camera', 'backup'),
    ])
      DriveFolder(
        id: id,
        parentId: parent,
        name: name,
        createdAt: DateTime(2026),
        modifiedAt: DateTime(2026),
      ),
  ];
}

void main() {
  late AppDatabase db;
  late GoRouter router;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester, String location) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    router = GoRouter(
      initialLocation: '/photos',
      routes: [
        GoRoute(
          path: '/photos',
          builder: (_, _) => const Scaffold(body: Center(child: Text('Photos'))),
        ),
        GoRoute(
          path: '/viewer/:fileId',
          builder: (_, state) => ImageViewerScreen(
            fileId: state.pathParameters['fileId']!,
            source: state.uri.queryParameters['from'],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          appDatabaseProvider.overrideWithValue(db),
          driveRepositoryProvider.overrideWith(_Repository.new),
          photosTimelineProvider.overrideWith((ref) {
            final trashed = ref.watch(_trashedProvider);
            return AsyncData([
              for (final photo in _photos)
                if (!trashed.contains(photo.id)) photo,
            ]);
          }),
          for (final photo in _photos) ...[
            fileInfoProvider(photo.id).overrideWith((ref) => Stream.value(photo)),
            // Still coming down from Telegram, which the gestures work over.
            filePreviewProvider(photo.id).overrideWith(
              (ref) => Stream.value(const PreviewProgress(received: 0, total: 1200000)),
            ),
          ],
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await settle(tester);
    router.push(location);
    await settle(tester);
  }

  Finder bar(String text) => find.descendant(of: find.byType(AppBar), matching: find.text(text));

  Finder subtitle(String ending) => find.descendant(
    of: find.byType(AppBar),
    matching: find.textContaining(RegExp('· $ending\$')),
  );

  /// The page on screen, which the vertical gestures act on.
  Finder page() => find.byType(VerticalSwipe).hitTestable().first;

  testWidgets('opened from the timeline the bar counts; opened on one file it does not', (
    tester,
  ) async {
    await open(tester, '/viewer/b?from=photos');
    expect(bar('b.jpg'), findsOneWidget);
    expect(subtitle('2 of 3'), findsOneWidget);

    router.pop();
    await settle(tester);
    router.push('/viewer/b');
    await settle(tester);
    expect(bar('b.jpg'), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.textContaining(' of ')), findsNothing);
  });

  testWidgets('the size shows only where no count takes its room', (tester) async {
    final size = find.descendant(of: find.byType(AppBar), matching: find.textContaining('MB'));
    await open(tester, '/viewer/b?from=photos');
    expect(size, findsNothing);

    router.pop();
    await settle(tester);
    router.push('/viewer/b');
    await settle(tester);
    expect(size, findsOneWidget);
  });

  testWidgets('the back arrow and every action are white on the dark bar', (tester) async {
    await open(tester, '/viewer/b?from=photos');
    final icons = [
      find.byType(BackButtonIcon),
      for (final tip in ['Star', 'Share', 'Move to Trash', 'More'])
        find.descendant(of: find.byTooltip(tip), matching: find.byType(Icon)),
    ];
    for (final icon in icons) {
      expect(IconTheme.of(tester.element(icon)).color, Colors.white);
    }
  });

  testWidgets('the bar holds Star, Share, Move to Trash and More, in that order', (
    tester,
  ) async {
    await open(tester, '/viewer/b?from=photos');
    final xs = [
      for (final tip in ['Star', 'Share', 'Move to Trash', 'More'])
        tester.getCenter(find.byTooltip(tip)).dx,
    ];
    expect(xs, orderedEquals([...xs]..sort()));
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)), findsNWidgets(5));
  });

  testWidgets('trash shows the next photo, and Undo puts it back in its place', (tester) async {
    await open(tester, '/viewer/b?from=photos');
    await tester.tap(find.byTooltip('Move to Trash'));
    await settle(tester);
    expect(find.text('Moved "b.jpg" to Trash'), findsOneWidget);
    expect(bar('c.jpg'), findsOneWidget);
    expect(subtitle('2 of 2'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(bar('c.jpg'), findsOneWidget);
    expect(subtitle('3 of 3'), findsOneWidget);

    await tester.drag(page(), const Offset(500, 0));
    await settle(tester);
    expect(bar('b.jpg'), findsOneWidget);
    expect(subtitle('2 of 3'), findsOneWidget);
  });

  testWidgets('trashing the last photo closes the viewer and the snack stays', (tester) async {
    await open(tester, '/viewer/b');
    await tester.tap(find.byTooltip('Move to Trash'));
    await settle(tester);
    expect(find.byType(ImageViewerScreen), findsNothing);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Moved "b.jpg" to Trash'), findsOneWidget);
  });

  testWidgets('a flick down closes the viewer, and the bar hides while dragging', (
    tester,
  ) async {
    await open(tester, '/viewer/b?from=photos');
    final gesture = await tester.startGesture(tester.getCenter(page()));
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 60));
    await settle(tester);
    expect(
      tester.widget<IgnorePointer>(
        find.ancestor(of: find.byType(AppBar), matching: find.byType(IgnorePointer)).first,
      ).ignoring,
      isTrue,
    );
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    await settle(tester);
    expect(find.byType(ImageViewerScreen), findsNothing);
    expect(find.text('Photos'), findsOneWidget);
  });

  testWidgets('a short drag down leaves the viewer open with its bar back', (tester) async {
    await open(tester, '/viewer/b?from=photos');
    await tester.drag(page(), const Offset(0, 80));
    await settle(tester);
    expect(find.byType(ImageViewerScreen), findsOneWidget);
    expect(
      tester.widget<IgnorePointer>(
        find.ancestor(of: find.byType(AppBar), matching: find.byType(IgnorePointer)).first,
      ).ignoring,
      isFalse,
    );
  });

  testWidgets('a flick up opens Details with what the drive knows about the photo', (
    tester,
  ) async {
    await open(tester, '/viewer/b?from=photos');
    for (final (id, name, messageId) in [('t', 'Trip', 50), ('f', 'Family', 51)]) {
      await db.upsertAlbum(
        AlbumsCompanion.insert(
          id: id,
          name: name,
          messageId: messageId,
          createdAt: DateTime(2026),
          modifiedAt: DateTime(2026),
        ),
      );
    }
    await db.setFileAlbums('b', ['t', 'f']);
    await db.markAssetBackedUp('asset-b', 'b');

    await tester.drag(page(), const Offset(0, -100));
    await settle(tester);
    expect(find.text('Taken'), findsOneWidget);
    expect(find.text('Files › Photo backup › Camera'), findsOneWidget);
    expect(find.text('Family, Trip'), findsOneWidget);
    expect(find.text('This phone · Camera'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Show in Telegram'), findsOneWidget);
    expect(find.byType(ImageViewerScreen), findsOneWidget);
  });

  testWidgets('zoomed in, a vertical drag pans and nothing closes', (tester) async {
    await open(tester, '/viewer/b?from=photos');
    Future<void> doubleTap() async {
      await tester.tap(page());
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(page());
      await settle(tester);
    }

    await doubleTap();
    await tester.drag(page(), const Offset(0, 200));
    await settle(tester);
    expect(find.byType(ImageViewerScreen), findsOneWidget);

    await doubleTap();
    await tester.drag(page(), const Offset(0, 200));
    await settle(tester);
    expect(find.byType(ImageViewerScreen), findsNothing);
  });
}
