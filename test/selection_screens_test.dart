import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/widgets/selection_bar.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/edit_outbox.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/file_list_screen.dart';
import 'package:telegrive/features/files/presentation/file_location.dart';
import 'package:telegrive/features/files/presentation/files_screen.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/infrastructure/database/app_database.dart'
    show FolderSize;
import 'package:telegrive/infrastructure/storage/preferences.dart';

/// A drive with one folder, Work, and the files given. Starring is recorded
/// in [starred] rather than sent anywhere.
class _Repository extends DriveRepository {
  _Repository(super.ref, this.files, {bool workStarred = false})
    : work = _folder('Work', starred: workStarred);

  final List<DriveFile> files;
  final DriveFolder work;

  /// Each setStarred call as 'ids:on' or 'ids:off', in order.
  final List<String> starred = [];

  void _record(Iterable<String> ids, bool on) =>
      starred.add('${ids.join(',')}:${on ? 'on' : 'off'}');

  @override
  Stream<FolderContents> watchFolder(String? folderId) => Stream.value(
    FolderContents(
      folders: [if (folderId == null) work],
      files: [
        for (final file in files)
          if (file.folderId == folderId) file,
      ],
    ),
  );

  @override
  Stream<DriveFolder?> watchFolderInfo(String id) =>
      Stream.value(id == 'Work' ? work : null);

  @override
  Future<List<DriveFolder>> pathTo(String? folderId) async => [
    if (folderId == 'Work') work,
  ];

  @override
  Future<void> setStarred(
    List<DriveFile> files, {
    required bool starred,
  }) async => _record(files.map((f) => f.id), starred);

  @override
  Future<void> setFolderStarred(
    List<DriveFolder> folders, {
    required bool starred,
  }) async => _record(folders.map((f) => f.id), starred);
}

DriveFolder _folder(String name, {bool starred = false}) => DriveFolder(
  id: name,
  parentId: null,
  name: name,
  createdAt: DateTime(2026, 9),
  modifiedAt: DateTime(2026, 9),
  starred: starred,
);

DriveFile _file(String name, {String? folderId, bool starred = false}) =>
    DriveFile(
      id: name,
      folderId: folderId,
      name: name,
      mimeType: 'application/pdf',
      kind: FileKind.document,
      size: 2 * 1024 * 1024,
      createdAt: DateTime(2026, 9, 23),
      modifiedAt: DateTime(2026, 9, 23),
      partCount: 1,
      starred: starred,
    );

void main() {
  late ProviderContainer container;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpApp(
    WidgetTester tester,
    Widget app, {
    List<DriveFile> files = const [],
    List<DriveFolder> starredFolders = const [],
    bool workStarred = false,
    bool counted = true,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        driveRepositoryProvider.overrideWith(
          (ref) => _Repository(ref, files, workStarred: workStarred),
        ),
        offlineCopiesProvider.overrideWith((ref) => Stream.value(const {})),
        offlinePinsProvider.overrideWith((ref) => Stream.value(const {})),
        pendingItemIdsProvider.overrideWith((ref) => Stream.value(const {})),
        starredFilesProvider.overrideWith(
          (ref) => Stream.value(files.where((f) => f.starred).toList()),
        ),
        starredFoldersProvider.overrideWith(
          (ref) => Stream.value(starredFolders),
        ),
        starredFolderSizesProvider.overrideWith(
          (ref) => counted
              ? Stream.value({
                  for (final folder in starredFolders)
                    folder.id: FolderSize(
                      folder.id,
                      folder.name,
                      12,
                      340 * 1024 * 1024,
                    ),
                })
              : const Stream.empty(),
        ),
        folderIndexProvider.overrideWith((ref) => Stream.value(const {})),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: app),
    );
    await settle(tester);
  }

  Future<GoRouter> pumpFiles(
    WidgetTester tester,
    String location,
    List<DriveFile> files, {
    bool workStarred = false,
  }) async {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/files',
          builder: (_, _) => const FilesScreen(),
          routes: [
            GoRoute(
              path: ':folderId',
              builder: (_, state) =>
                  FilesScreen(folderId: state.pathParameters['folderId']),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpApp(
      tester,
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      files: files,
      workStarred: workStarred,
    );
    return router;
  }

  _Repository repository() =>
      container.read(driveRepositoryProvider) as _Repository;

  Finder inBar(String label) => find.descendant(
    of: find.byType(SelectionActionBar),
    matching: find.text(label),
  );

  bool enabled(WidgetTester tester, String label) =>
      tester
          .widget<InkWell>(
            find.ancestor(of: inBar(label), matching: find.byType(InkWell)),
          )
          .onTap !=
      null;

  bool selecting() => container.read(selectionActiveProvider);

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  testWidgets(
    'long-pressing a file puts named actions at the foot and the size on top',
    (tester) async {
      await pumpFiles(tester, '/files', [_file('a.pdf'), _file('b.pdf')]);
      expect(find.byType(SelectionActionBar), findsNothing);

      await tester.longPress(find.text('a.pdf'));
      await settle(tester);
      for (final label in ['Download', 'Send', 'Move', 'Trash', 'More']) {
        expect(inBar(label), findsOneWidget);
      }
      expect(find.text('1 selected · 2.0 MB'), findsOneWidget);
      expect(find.byTooltip('New'), findsNothing);
      expect(selecting(), isTrue);

      await tester.tap(find.text('b.pdf'));
      await settle(tester);
      expect(find.text('2 selected · 4.0 MB'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear selection'));
      await settle(tester);
      expect(find.byType(SelectionActionBar), findsNothing);
      expect(selecting(), isFalse);
    },
  );

  testWidgets(
    'Select starts with nothing picked and the actions off; back ends it',
    (tester) async {
      await pumpFiles(tester, '/files', [_file('a.pdf')]);
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip('More'),
        ),
      );
      await settle(tester);
      expect(
        find.text('Trash'),
        findsOneWidget,
        reason: 'the root offers Trash too',
      );
      await tester.tap(find.text('Select'));
      await settle(tester);

      expect(find.text('Select items'), findsOneWidget);
      expect(selecting(), isTrue);
      for (final label in ['Download', 'Send', 'Move', 'Trash']) {
        expect(enabled(tester, label), isFalse, reason: label);
      }

      await tester.tap(find.text('a.pdf'));
      await settle(tester);
      expect(find.text('1 selected · 2.0 MB'), findsOneWidget);
      expect(enabled(tester, 'Move'), isTrue);

      await back(tester);
      expect(find.byType(SelectionActionBar), findsNothing);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Files')),
        findsOneWidget,
      );
      expect(selecting(), isFalse);
    },
  );

  testWidgets('a folder alone has a count but no size, and can be starred', (
    tester,
  ) async {
    await pumpFiles(tester, '/files', [_file('a.pdf')]);
    await tester.longPress(find.text('Work'));
    await settle(tester);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(inBar('More'));
    await settle(tester);
    expect(find.text('Add to Starred'), findsOneWidget);

    await tester.tap(find.text('Add to Starred'));
    await settle(tester);
    expect(repository().starred, ['Work:on']);
    expect(find.text('Added to Starred'), findsOneWidget);
    expect(find.byType(SelectionActionBar), findsNothing);
  });

  testWidgets('a starred folder offers Remove from Starred, and removes it', (
    tester,
  ) async {
    await pumpFiles(tester, '/files', [_file('a.pdf')], workStarred: true);
    await tester.longPress(find.text('Work'));
    await settle(tester);

    await tester.tap(inBar('More'));
    await settle(tester);
    expect(find.text('Remove from Starred'), findsOneWidget);
    expect(find.text('Add to Starred'), findsNothing);

    await tester.tap(find.text('Remove from Starred'));
    await settle(tester);
    expect(repository().starred, ['Work:off']);
    expect(find.text('Removed from Starred'), findsOneWidget);
  });

  testWidgets(
    'a starred folder with an unstarred file still offers Add to Starred',
    (tester) async {
      await pumpFiles(tester, '/files', [_file('a.pdf')], workStarred: true);
      await tester.longPress(find.text('Work'));
      await settle(tester);
      await tester.tap(find.text('a.pdf'));
      await settle(tester);
      expect(find.text('2 selected · 2.0 MB'), findsOneWidget);

      await tester.tap(inBar('More'));
      await settle(tester);
      expect(find.text('Add to Starred'), findsOneWidget);

      await tester.tap(find.text('Add to Starred'));
      await settle(tester);
      expect(repository().starred, ['a.pdf:on', 'Work:on']);
    },
  );

  testWidgets(
    'Starred lists the starred folders first, each with what it holds',
    (tester) async {
      final work = _folder('Work', starred: true);
      await pumpApp(
        tester,
        MaterialApp(
          theme: AppTheme.light(),
          home: const FileListScreen.starred(),
        ),
        files: [_file('a.pdf', starred: true)],
        starredFolders: [work],
      );

      expect(find.text('1 folder · 1 file · 2.0 MB'), findsOneWidget);
      expect(find.text('Folders'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('12 items · 340 MB'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Work')).dy,
        lessThan(tester.getTopLeft(find.text('a.pdf')).dy),
      );
    },
  );

  testWidgets(
    'Starred with folders alone counts just them, and leaves them be while '
    'selecting',
    (tester) async {
      await pumpApp(
        tester,
        MaterialApp(
          theme: AppTheme.light(),
          home: const FileListScreen.starred(),
        ),
        starredFolders: [_folder('Work', starred: true)],
        counted: false,
      );
      expect(find.text('1 folder'), findsOneWidget);
      expect(find.text('Folders'), findsNothing);
      expect(
        find.textContaining('Folder · '),
        findsOneWidget,
        reason: 'not counted yet, so the row keeps its plain line',
      );
      expect(find.text('Empty folder'), findsNothing);

      // Without a router, opening the folder would throw; the row sits
      // still instead.
      await tester.tap(find.byTooltip('Select'));
      await settle(tester);
      await tester.tap(find.text('Work'));
      await settle(tester);
      expect(find.text('Select items'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Starred with nothing starred says so, folders included', (
    tester,
  ) async {
    await pumpApp(
      tester,
      MaterialApp(
        theme: AppTheme.light(),
        home: const FileListScreen.starred(),
      ),
    );
    expect(find.text('Nothing starred yet'), findsOneWidget);
    expect(find.textContaining('files and folders'), findsOneWidget);
  });

  testWidgets(
    'leaving a folder by its breadcrumbs while selecting gives the bar back',
    (tester) async {
      await pumpFiles(tester, '/files/Work', [
        _file('report.pdf', folderId: 'Work'),
      ]);
      await tester.longPress(find.text('report.pdf'));
      await settle(tester);
      expect(selecting(), isTrue);

      await tester.tap(find.text('Files'));
      await settle(tester);
      expect(find.text('report.pdf'), findsNothing);
      expect(selecting(), isFalse);
    },
  );

  testWidgets(
    'Starred selects with Select or a long-press and acts on them together',
    (tester) async {
      await pumpApp(
        tester,
        MaterialApp(
          theme: AppTheme.light(),
          home: const FileListScreen.starred(),
        ),
        files: [
          _file('a.pdf', starred: true),
          _file('b.pdf', starred: true),
          _file('c.pdf', starred: true),
        ],
      );

      await tester.tap(find.byTooltip('Select'));
      await settle(tester);
      expect(find.text('Select items'), findsOneWidget);
      expect(enabled(tester, 'Trash'), isFalse);

      await tester.tap(find.text('a.pdf'));
      await settle(tester);
      expect(find.text('1 selected · 2.0 MB'), findsOneWidget);
      await back(tester);
      expect(find.text('Starred'), findsOneWidget);

      await tester.longPress(find.text('b.pdf'));
      await settle(tester);
      expect(find.text('1 selected · 2.0 MB'), findsOneWidget);
      for (final label in ['Download', 'Send', 'Move', 'Trash']) {
        expect(enabled(tester, label), isTrue, reason: label);
      }

      await tester.tap(inBar('More'));
      await settle(tester);
      expect(find.text('Remove from Starred'), findsOneWidget);
      await tester.tap(find.text('Select all'));
      await settle(tester);
      expect(find.text('3 selected · 6.0 MB'), findsOneWidget);

      // With everything picked, the menu offers the way back.
      await tester.tap(inBar('More'));
      await settle(tester);
      expect(find.text('Select all'), findsNothing);
      await tester.tap(find.text('Deselect all'));
      await settle(tester);
      expect(find.text('Starred'), findsOneWidget);
      expect(find.textContaining('selected'), findsNothing);
    },
  );
}
