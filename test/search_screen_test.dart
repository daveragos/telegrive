import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/format/formatters.dart';
import 'package:telegrive/features/backup/data/local_media.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/file_tiles.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/features/photos/presentation/media_grid.dart';
import 'package:telegrive/features/search/presentation/search_screen.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

typedef _Search = ({
  String query,
  Set<FileKind>? kinds,
  (DateTime, DateTime)? range,
  Iterable<String>? folderIds,
  String? literal,
  bool byMoment,
});

/// The drive as Search reads it: a fixed folder tree and files, with each
/// search it is asked for kept so a test can check what the screen asked.
class _Repository extends DriveRepository {
  _Repository(super.ref, this.folders, this.files, this.folderIndex);

  final List<DriveFolder> folders;
  final List<DriveFile> files;
  final Stream<List<DriveFolder>>? folderIndex;
  final searches = <_Search>[];

  @override
  Stream<List<DriveFile>> watchSearch(
    String query, {
    Set<FileKind>? kinds,
    (DateTime, DateTime)? range,
    Iterable<String>? folderIds,
    String? literal,
    bool byMoment = false,
  }) {
    searches.add((
      query: query,
      kinds: kinds,
      range: range,
      folderIds: folderIds,
      literal: literal,
      byMoment: byMoment,
    ));
    return Stream.value([
      for (final file in files)
        if ((kinds == null || kinds.contains(file.kind)) &&
            (folderIds == null || folderIds.contains(file.folderId)))
          file,
    ]);
  }

  @override
  Stream<List<DriveFolder>> watchFolderSearch(String query, {Iterable<String>? within}) =>
      Stream.value([
        for (final folder in folders)
          if (folder.name.toLowerCase().contains(query.toLowerCase()) &&
              (within == null || within.contains(folder.id)))
            folder,
      ]);

  @override
  Future<Set<String>> descendantFolderIds(String rootId) async {
    final ids = {rootId};
    var grew = true;
    while (grew) {
      grew = false;
      for (final folder in folders) {
        if (ids.contains(folder.parentId) && ids.add(folder.id)) grew = true;
      }
    }
    return ids;
  }

  @override
  Stream<List<DriveFolder>> watchAllFolders() => folderIndex ?? Stream.value(folders);

  @override
  Stream<DriveFolder?> watchFolderInfo(String id) =>
      Stream.value(folders.where((f) => f.id == id).firstOrNull);
}

void main() {
  final at = DateTime(2026, 3, 14, 9);

  DriveFolder folder(String id, String? parentId) => DriveFolder(
    id: id,
    parentId: parentId,
    name: id,
    createdAt: at,
    modifiedAt: at,
  );

  DriveFile file(String name, String? folderId, {FileKind kind = FileKind.document}) =>
      DriveFile(
        id: name,
        folderId: folderId,
        name: name,
        mimeType: 'application/pdf',
        kind: kind,
        size: 1200,
        createdAt: at,
        modifiedAt: at,
        partCount: 1,
        starred: false,
      );

  final folders = [
    folder('Work', null),
    folder('Invoices', 'Work'),
    folder('Paid', 'Invoices'),
    folder('2024', 'Work'),
  ];

  late _Repository repository;

  Future<void> pumpSearch(
    WidgetTester tester,
    SearchScreen screen, {
    List<DriveFile> files = const [],
    Stream<List<DriveFolder>>? folderIndex,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          driveRepositoryProvider.overrideWith(
            (ref) => repository = _Repository(ref, folders, files, folderIndex),
          ),
          offlineCopiesProvider.overrideWith((ref) => Stream.value(const {})),
          offlinePinsProvider.overrideWith((ref) => Stream.value(const {})),
          for (final f in files)
            localThumbnailProvider(f.id).overrideWith((ref) async => null),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: screen),
      ),
    );
    await settle(tester);
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    // Past the typing pause, then the results.
    await tester.pump(const Duration(milliseconds: 200));
    await settle(tester);
  }

  final meta = '${Formatters.bytes(1200)} · ${Formatters.date(at)}';

  testWidgets('from a folder it starts there, and the chip widens it', (tester) async {
    await pumpSearch(
      tester,
      const SearchScreen(initialFolderId: 'Invoices'),
      files: [
        file('march invoice.pdf', 'Invoices'),
        file('paid invoice.pdf', 'Paid'),
        file('work invoice.pdf', 'Work'),
        file('loose invoice.pdf', null),
      ],
    );
    final chip = find.widgetWithText(FilterChip, 'In Invoices');
    expect(tester.widget<FilterChip>(chip).selected, isTrue);
    expect(find.text('Search in Invoices'), findsWidgets);

    await type(tester, 'invoice');
    expect(repository.searches.last.folderIds, {'Invoices', 'Paid'});
    // The folder searched in isn't one of its own results.
    expect(find.byType(FolderListTile), findsNothing);
    // Directly in the folder searched, the place goes without saying.
    expect(find.text(meta), findsOneWidget);
    expect(find.text('$meta · Work › Invoices › Paid'), findsOneWidget);
    expect(find.text('work invoice.pdf'), findsNothing);

    await tester.tap(chip);
    await settle(tester);
    expect(repository.searches.last.folderIds, isNull);
    expect(find.text('Search files and folders'), findsOneWidget);
    expect(find.widgetWithText(FolderListTile, 'Invoices'), findsOneWidget);
    expect(find.text('$meta · Work › Invoices'), findsOneWidget);
    expect(find.text('$meta · Work'), findsOneWidget);
    expect(find.text('$meta · Files'), findsOneWidget);
  });

  testWidgets('words and a date narrow together', (tester) async {
    await pumpSearch(tester, const SearchScreen());
    expect(find.byType(FilterChip), findsNWidgets(FileKind.values.length));

    await type(tester, 'invoice march 2024');
    expect(find.text('"invoice" from March 2024'), findsOneWidget);
    final search = repository.searches.last;
    expect(search.query, 'invoice');
    expect(search.literal, 'invoice march 2024');
    expect(search.range!.$1, DateTime(2024, 3));

    await type(tester, 'march 2024');
    expect(find.text('Everything from March 2024'), findsOneWidget);

    await type(tester, 'report may');
    expect(find.byIcon(Icons.event_outlined), findsNothing);
    expect(repository.searches.last.query, 'report may');

    await type(tester, 'total 1,250');
    expect(repository.searches.last.query, 'total 1,250');
  });

  testWidgets('a query that is only a date still finds folders named so', (tester) async {
    await pumpSearch(tester, const SearchScreen());

    await type(tester, '2024');
    expect(find.text('Everything from 2024'), findsOneWidget);
    expect(find.widgetWithText(FolderListTile, '2024'), findsOneWidget);
    expect(find.widgetWithText(FolderListTile, 'Work'), findsNothing);
  });

  testWidgets('rows name their folder once the folders are read', (tester) async {
    final index = StreamController<List<DriveFolder>>();
    addTearDown(index.close);
    await pumpSearch(
      tester,
      const SearchScreen(),
      files: [file('paid invoice.pdf', 'Paid')],
      folderIndex: index.stream,
    );

    await type(tester, 'invoice');
    expect(find.text(meta), findsOneWidget);

    index.add(folders);
    await settle(tester);
    expect(find.text('$meta · Work › Invoices › Paid'), findsOneWidget);
  });

  testWidgets('from Photos it finds videos too and shows the grid', (tester) async {
    await pumpSearch(
      tester,
      const SearchScreen(media: true),
      files: [
        file('trek.jpg', null, kind: FileKind.image),
        file('trek.mp4', null, kind: FileKind.video),
        file('trek.pdf', null),
      ],
    );
    expect(find.text('Search photos and videos'), findsWidgets);
    expect(find.byType(FilterChip), findsNWidgets(2));
    expect(find.widgetWithText(FilterChip, 'Images'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Videos'), findsOneWidget);

    await type(tester, 'trek');
    expect(repository.searches.last.kinds, {FileKind.image, FileKind.video});
    expect(repository.searches.last.byMoment, isTrue);
    expect(find.byType(MediaGrid), findsOneWidget);
    expect(find.text('Photos and videos · 2'), findsOneWidget);
    expect(find.text('Folders'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Videos'));
    await settle(tester);
    expect(find.text('Videos · 1'), findsOneWidget);
  });
}

/// A few frames, enough for a search's providers to deliver; the text
/// field's blinking cursor keeps pumpAndSettle from ever settling.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
