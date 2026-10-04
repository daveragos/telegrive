import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/backup/data/local_media.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/edit_outbox.dart';
import 'package:telegrive/features/drive/data/forward_origin.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/file_actions.dart';
import 'package:telegrive/features/files/presentation/file_tiles.dart';
import 'package:telegrive/features/files/presentation/files_screen.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

/// The drive as Files reads it: a set folder tree, some of it in the
/// trash, and the files in it.
class _Repository extends DriveRepository {
  _Repository(super.ref, this.folders, this.files, {this.trashed = const {}});

  final List<DriveFolder> folders;
  final List<DriveFile> files;
  final Set<String> trashed;

  @override
  Stream<FolderContents> watchFolder(String? folderId) => Stream.value(
    FolderContents(
      folders: [
        for (final folder in folders)
          if (folder.parentId == folderId && !trashed.contains(folder.id)) folder,
      ],
      files: [
        for (final file in files)
          if (file.folderId == folderId) file,
      ],
    ),
  );

  @override
  Stream<DriveFolder?> watchFolderInfo(String id) =>
      Stream.value(folders.where((f) => f.id == id).firstOrNull);

  @override
  Future<List<DriveFolder>> pathTo(String? folderId) async {
    final path = <DriveFolder>[];
    var cursor = folders.where((f) => f.id == folderId).firstOrNull;
    while (cursor != null) {
      path.insert(0, cursor);
      final parent = cursor.parentId;
      cursor = folders.where((f) => f.id == parent).firstOrNull;
    }
    return path;
  }

  @override
  Future<DriveFolder?> shownFolder(String id) async =>
      trashed.contains(id) ? null : folders.where((f) => f.id == id).firstOrNull;
}

/// What the router shows: the folder browser, and a screen over it that
/// offers Show in folder, as Search and the viewer do.
GoRouter _router(String location, {DriveFile? showing}) => GoRouter(
  initialLocation: location,
  routes: [
    GoRoute(
      path: '/files',
      builder: (_, state) =>
          FilesScreen(highlight: state.uri.queryParameters['highlight']),
      routes: [
        GoRoute(
          path: ':folderId',
          builder: (_, state) => FilesScreen(
            folderId: state.pathParameters['folderId'],
            highlight: state.uri.queryParameters['highlight'],
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/over',
      builder: (_, _) => Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Column(
            children: [
              TextButton(
                onPressed: () => FileActions.showInFolder(context, ref, showing!),
                child: const Text('Show in folder'),
              ),
              TextButton(
                onPressed: () => FileActions.showDetails(context, ref, showing!),
                child: const Text('Details'),
              ),
            ],
          ),
        ),
      ),
    ),
  ],
);

void main() {
  final at = DateTime(2026, 9, 23, 9);

  DriveFolder folder(String id, String? parentId) => DriveFolder(
    id: id,
    parentId: parentId,
    name: id,
    createdAt: at,
    modifiedAt: at,
  );

  DriveFile file(String name, String? folderId, {bool adopted = false}) => DriveFile(
    id: name,
    folderId: folderId,
    name: name,
    mimeType: 'application/pdf',
    kind: FileKind.document,
    size: 2100000,
    createdAt: at,
    modifiedAt: at,
    partCount: 1,
    starred: false,
    adopted: adopted,
  );

  final folders = [folder('Work', null), folder('Clients', 'Work'), folder('Old', null)];

  Future<GoRouter> pumpFiles(
    WidgetTester tester,
    String location, {
    required List<DriveFile> files,
    Set<String> trashed = const {},
    DriveFile? showing,
    Map<String, Object> prefs = const {},
    List<Override> overrides = const [],
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    final router = _router(location, showing: showing);
    addTearDown(router.dispose);
    // Details reads albums and backup records from the index.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          appDatabaseProvider.overrideWithValue(db),
          driveRepositoryProvider.overrideWith(
            (ref) => _Repository(ref, folders, files, trashed: trashed),
          ),
          offlineCopiesProvider.overrideWith((ref) => Stream.value(const {})),
          offlinePinsProvider.overrideWith((ref) => Stream.value(const {})),
          pendingItemIdsProvider.overrideWith((ref) => Stream.value(const {})),
          for (final f in files)
            for (final px in thumbBuckets)
              localThumbnailProvider((fileId: f.id, px: px)).overrideWith((ref) async => null),
          ...overrides,
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await settle(tester);
    return router;
  }

  bool tinted(WidgetTester tester, String name) =>
      tester.widget<FileListTile>(find.widgetWithText(FileListTile, name)).highlighted;

  String location(GoRouter router) => router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets('opens the folder the file is in, with its row tinted for a moment', (
    tester,
  ) async {
    final invoice = file('Invoice 0231.pdf', 'Clients');
    final router = await pumpFiles(
      tester,
      '/over',
      files: [file('Invoice 0230.pdf', 'Clients'), invoice],
      showing: invoice,
    );

    await tester.tap(find.text('Show in folder'));
    await settle(tester);
    expect(location(router), '/files/Clients?highlight=Invoice+0231.pdf');
    expect(find.text('Show in folder'), findsNothing);
    expect(tinted(tester, 'Invoice 0231.pdf'), isTrue);
    expect(tinted(tester, 'Invoice 0230.pdf'), isFalse);

    await tester.pump(const Duration(milliseconds: 1500));
    await settle(tester);
    expect(tinted(tester, 'Invoice 0231.pdf'), isFalse);
  });

  testWidgets("Details' Location row says where the file is and goes there", (
    tester,
  ) async {
    final invoice = file('Invoice 0231.pdf', 'Clients');
    final router = await pumpFiles(tester, '/over', files: [invoice], showing: invoice);

    await tester.tap(find.text('Details'));
    await settle(tester);
    await tester.tap(find.text('Files › Work › Clients'));
    await settle(tester);
    expect(location(router), '/files/Clients?highlight=Invoice+0231.pdf');
    expect(find.text('Location'), findsNothing);
    expect(tinted(tester, 'Invoice 0231.pdf'), isTrue);
    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('a file at the root opens Files', (tester) async {
    final loose = file('loose.pdf', null);
    final router = await pumpFiles(tester, '/over', files: [loose], showing: loose);
    await tester.tap(find.text('Show in folder'));
    await settle(tester);
    expect(location(router), '/files?highlight=loose.pdf');
    expect(tinted(tester, 'loose.pdf'), isTrue);
    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('a forwarded file at the root is pointed out under Forwarded', (tester) async {
    final forward = file('contract.pdf', null, adopted: true);
    final router = await pumpFiles(
      tester,
      '/over',
      files: [file('loose.pdf', null), forward],
      showing: forward,
      overrides: [
        forwardOriginProvider('contract.pdf').overrideWith(
          (ref) async => (forwarded: true, name: 'Selam Tesfaye'),
        ),
      ],
    );
    await tester.tap(find.text('Show in folder'));
    await settle(tester);
    expect(location(router), '/files?highlight=contract.pdf');
    expect(find.text('Forwarded · 1'), findsOneWidget);
    expect(tinted(tester, 'contract.pdf'), isTrue);
    expect(tinted(tester, 'loose.pdf'), isFalse);
    await tester.pump(const Duration(milliseconds: 1500));
    await settle(tester);
    expect(tinted(tester, 'contract.pdf'), isFalse);
  });

  testWidgets('a file whose folder is in the trash opens Files', (tester) async {
    final kept = file('kept.pdf', 'Old');
    final router = await pumpFiles(
      tester,
      '/over',
      files: [kept],
      trashed: {'Old'},
      showing: kept,
    );
    await tester.tap(find.text('Show in folder'));
    await settle(tester);
    expect(location(router), '/files?highlight=kept.pdf');
  });

  testWidgets('in a long list the row is brought into view', (tester) async {
    final files = [
      for (var i = 0; i < 80; i++) file('Scan ${i.toString().padLeft(2, '0')}.pdf', null),
    ];
    await pumpFiles(tester, '/files?highlight=Scan+64.pdf', files: files);
    await tester.pump(const Duration(milliseconds: 300));

    final row = find.widgetWithText(FileListTile, 'Scan 64.pdf');
    expect(row, findsOneWidget);
    final screen = tester.getRect(find.byType(FilesScreen));
    final rect = tester.getRect(row);
    expect(rect.top, greaterThanOrEqualTo(screen.top));
    expect(rect.bottom, lessThanOrEqualTo(screen.bottom));
    expect(tinted(tester, 'Scan 64.pdf'), isTrue);
    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('a row already on screen is tinted where it is', (tester) async {
    final files = [
      for (var i = 0; i < 20; i++) file('Scan ${i.toString().padLeft(2, '0')}.pdf', null),
    ];
    await pumpFiles(tester, '/files?highlight=Scan+01.pdf', files: files);
    await tester.pump(const Duration(milliseconds: 300));

    expect(tinted(tester, 'Scan 01.pdf'), isTrue);
    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, 0);
    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('in grid view the card is tinted too', (tester) async {
    await pumpFiles(
      tester,
      '/files?highlight=b.pdf',
      files: [file('a.pdf', null), file('b.pdf', null)],
      prefs: {'view_mode': 'grid'},
    );
    final card = find.widgetWithText(FileGridCard, 'b.pdf');
    expect(tester.widget<FileGridCard>(card).highlighted, isTrue);
    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('showing the same folder for another file points that one out', (
    tester,
  ) async {
    final router = await pumpFiles(
      tester,
      '/files?highlight=a.pdf',
      files: [file('a.pdf', null), file('b.pdf', null)],
    );
    expect(tinted(tester, 'a.pdf'), isTrue);

    router.go('/files?highlight=b.pdf');
    await settle(tester);
    expect(tinted(tester, 'a.pdf'), isFalse);
    expect(tinted(tester, 'b.pdf'), isTrue);
    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets("a file that isn't there leaves the folder untinted", (tester) async {
    await pumpFiles(tester, '/files?highlight=gone.pdf', files: [file('a.pdf', null)]);
    expect(tinted(tester, 'a.pdf'), isFalse);
  });

  test('only a folder Files lists is one to show', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    var message = 1;
    Future<void> add(String id, {String? parentId, DateTime? trashedAt}) =>
        db.upsertFolder(
          FoldersCompanion.insert(
            id: id,
            parentId: Value(parentId),
            name: id,
            messageId: message++,
            createdAt: at,
            modifiedAt: at,
            trashedAt: Value(trashedAt),
          ),
        );
    await add('Work');
    await add('Old', trashedAt: at);
    await add('Inside old', parentId: 'Old');

    final repository = container.read(driveRepositoryProvider);
    expect((await repository.shownFolder('Work'))?.name, 'Work');
    expect(await repository.shownFolder('Old'), isNull);
    expect(await repository.shownFolder('Inside old'), isNull);
    expect(await repository.shownFolder('missing'), isNull);
  });
}

/// A few frames: enough for the folder to arrive, the row to be tinted and
/// the list to ease into place.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
