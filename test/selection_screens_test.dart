import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/widgets/selection_bar.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/file_list_screen.dart';
import 'package:telegrive/features/files/presentation/file_location.dart';
import 'package:telegrive/features/files/presentation/files_screen.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

/// A drive with one folder, Work, and the files given.
class _Repository extends DriveRepository {
  _Repository(super.ref, this.files);

  final List<DriveFile> files;

  static final _work = DriveFolder(
    id: 'Work',
    parentId: null,
    name: 'Work',
    createdAt: DateTime(2026, 9),
    modifiedAt: DateTime(2026, 9),
  );

  @override
  Stream<FolderContents> watchFolder(String? folderId) => Stream.value(
    FolderContents(
      folders: [if (folderId == null) _work],
      files: [
        for (final file in files)
          if (file.folderId == folderId) file,
      ],
    ),
  );

  @override
  Stream<DriveFolder?> watchFolderInfo(String id) => Stream.value(id == 'Work' ? _work : null);

  @override
  Future<List<DriveFolder>> pathTo(String? folderId) async => [if (folderId == 'Work') _work];
}

DriveFile _file(String name, {String? folderId, bool starred = false}) => DriveFile(
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

  Future<void> pumpApp(WidgetTester tester, Widget app, {List<DriveFile> files = const []}) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        driveRepositoryProvider.overrideWith((ref) => _Repository(ref, files)),
        offlineCopiesProvider.overrideWith((ref) => Stream.value(const {})),
        offlinePinsProvider.overrideWith((ref) => Stream.value(const {})),
        starredFilesProvider.overrideWith(
          (ref) => Stream.value(files.where((f) => f.starred).toList()),
        ),
        folderIndexProvider.overrideWith((ref) => Stream.value(const {})),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: app));
    await settle(tester);
  }

  Future<GoRouter> pumpFiles(WidgetTester tester, String location, List<DriveFile> files) async {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/files',
          builder: (_, _) => const FilesScreen(),
          routes: [
            GoRoute(
              path: ':folderId',
              builder: (_, state) => FilesScreen(folderId: state.pathParameters['folderId']),
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
    );
    return router;
  }

  Finder inBar(String label) =>
      find.descendant(of: find.byType(SelectionActionBar), matching: find.text(label));

  bool enabled(WidgetTester tester, String label) =>
      tester.widget<InkWell>(find.ancestor(of: inBar(label), matching: find.byType(InkWell))).onTap !=
      null;

  bool selecting() => container.read(selectionActiveProvider);

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  testWidgets('long-pressing a file puts named actions at the foot and the size on top', (
    tester,
  ) async {
    await pumpFiles(tester, '/files', [_file('a.pdf'), _file('b.pdf')]);
    expect(find.byType(SelectionActionBar), findsNothing);

    await tester.longPress(find.text('a.pdf'));
    await settle(tester);
    for (final label in ['Download', 'Send', 'Move', 'Trash', 'More']) {
      expect(inBar(label), findsOneWidget);
    }
    expect(find.text('1 selected · 2.0 MB'), findsOneWidget);
    expect(find.text('New'), findsNothing);
    expect(selecting(), isTrue);

    await tester.tap(find.text('b.pdf'));
    await settle(tester);
    expect(find.text('2 selected · 4.0 MB'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear selection'));
    await settle(tester);
    expect(find.byType(SelectionActionBar), findsNothing);
    expect(selecting(), isFalse);
  });

  testWidgets('Select starts with nothing picked and the actions off; back ends it', (
    tester,
  ) async {
    await pumpFiles(tester, '/files', [_file('a.pdf')]);
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byTooltip('More')));
    await settle(tester);
    expect(find.text('Trash'), findsOneWidget, reason: 'the root offers Trash too');
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
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Files')), findsOneWidget);
    expect(selecting(), isFalse);
  });

  testWidgets('a folder alone has a count but no size', (tester) async {
    await pumpFiles(tester, '/files', [_file('a.pdf')]);
    await tester.longPress(find.text('Work'));
    await settle(tester);
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('leaving a folder by its breadcrumbs while selecting gives the bar back', (
    tester,
  ) async {
    await pumpFiles(tester, '/files/Work', [_file('report.pdf', folderId: 'Work')]);
    await tester.longPress(find.text('report.pdf'));
    await settle(tester);
    expect(selecting(), isTrue);

    await tester.tap(find.text('Files'));
    await settle(tester);
    expect(find.text('report.pdf'), findsNothing);
    expect(selecting(), isFalse);
  });

  testWidgets('Starred selects with Select or a long-press and acts on them together', (
    tester,
  ) async {
    await pumpApp(
      tester,
      MaterialApp(theme: AppTheme.light(), home: const FileListScreen.starred()),
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
  });
}
