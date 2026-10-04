import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/widgets/file_visuals.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/photos/presentation/media_grid.dart';
import 'package:telegrive/features/photos/presentation/media_grid_layout.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

/// [count] photos a month for the three months up to this one, newest first.
List<DriveFile> _photos({int count = 20}) {
  final now = DateTime.now();
  return [
    for (var month = 0; month < 3; month++)
      for (var i = 0; i < count; i++)
        DriveFile(
          id: 'm$month-$i',
          folderId: null,
          name: 'IMG_$month$i.jpg',
          mimeType: 'image/jpeg',
          kind: FileKind.image,
          size: 1000,
          createdAt: now,
          modifiedAt: now,
          partCount: 1,
          starred: false,
          takenAt: DateTime(now.year, now.month - month, 1),
        ),
  ];
}

void main() {
  late MediaSelection selection;
  late List<DriveFile> files;
  late List<MonthSection> months;

  setUp(() {
    selection = MediaSelection();
    files = _photos();
    months = monthSections(files);
  });

  tearDown(() => selection.dispose());

  Future<void> pumpGrid(
    WidgetTester tester, {
    bool alwaysSelecting = false,
    bool selectable = true,
    List<Widget> header = const [],
    double textScale = 1,
    Map<String, Object> preferences = const {},
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(preferences);
    final shared = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(shared)],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: MediaGrid(
              files: files,
              selection: selection,
              alwaysSelecting: alwaysSelecting,
              selectable: selectable,
              header: header,
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder header(String title) => find.widgetWithText(InkWell, title);

  Finder headerIcon(String title, IconData icon) =>
      find.descendant(of: header(title), matching: find.byIcon(icon));

  Set<String> idsOf(MonthSection month) => {for (final f in month.files) f.id};

  double scrolled(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

  /// The scrubber's month label, which is the only month title drawn
  /// through an AnimatedOpacity.
  AnimatedOpacity label(String title) =>
      find
              .ancestor(of: find.text(title), matching: find.byType(AnimatedOpacity))
              .evaluate()
              .single
              .widget
          as AnimatedOpacity;

  testWidgets('while selecting, a month header selects and clears that month', (tester) async {
    await pumpGrid(tester, alwaysSelecting: true);
    final august = months[1];
    expect(headerIcon(august.title, Icons.radio_button_unchecked_rounded), findsOneWidget);

    await tester.tap(header(august.title));
    await tester.pumpAndSettle();
    expect(selection.ids, idsOf(august));
    expect(headerIcon(august.title, Icons.check_circle_rounded), findsOneWidget);
    expect(headerIcon(months[0].title, Icons.radio_button_unchecked_rounded), findsOneWidget);

    await tester.tap(header(august.title));
    await tester.pumpAndSettle();
    expect(selection.ids, isEmpty);
    expect(headerIcon(august.title, Icons.radio_button_unchecked_rounded), findsOneWidget);
  });

  testWidgets('a month partly selected gets the rest', (tester) async {
    await pumpGrid(tester, alwaysSelecting: true);
    final first = months[0];
    await tester.tap(find.byType(FileThumbnail).at(3));
    await tester.pumpAndSettle();
    expect(selection.ids, {first.files[3].id});
    expect(headerIcon(first.title, Icons.radio_button_unchecked_rounded), findsOneWidget);

    await tester.tap(header(first.title));
    await tester.pumpAndSettle();
    expect(selection.ids, idsOf(first));
    expect(headerIcon(first.title, Icons.check_circle_rounded), findsOneWidget);

    // Taking one photo out empties the circle again.
    selection.toggle(first.files[0].id);
    await tester.pumpAndSettle();
    expect(headerIcon(first.title, Icons.radio_button_unchecked_rounded), findsOneWidget);
  });

  testWidgets('outside selection, a title has no circle and a tap selects its month', (
    tester,
  ) async {
    await pumpGrid(tester);
    for (final month in months.take(2)) {
      expect(headerIcon(month.title, Icons.radio_button_unchecked_rounded), findsNothing);
      expect(headerIcon(month.title, Icons.check_circle_rounded), findsNothing);
    }

    await tester.tap(header(months[1].title));
    await tester.pumpAndSettle();
    expect(selection.active, isTrue);
    expect(selection.ids, idsOf(months[1]));
    expect(headerIcon(months[1].title, Icons.check_circle_rounded), findsOneWidget);
    expect(headerIcon(months[0].title, Icons.radio_button_unchecked_rounded), findsOneWidget);
  });

  testWidgets('where the grid can\'t select, a title does nothing', (tester) async {
    await pumpGrid(tester, selectable: false);
    await tester.tap(header(months[1].title));
    await tester.pumpAndSettle();
    expect(selection.ids, isEmpty);
    expect(selection.active, isFalse);
  });

  testWidgets('dragging to select ticks once for each new tile', (tester) async {
    final ticks = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') ticks.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpGrid(tester);
    final tiles = find.byType(FileThumbnail);
    final first = tester.getCenter(tiles.at(0));

    final gesture = await tester.startGesture(first);
    await tester.pump(const Duration(milliseconds: 700));
    expect(ticks, hasLength(1));

    await gesture.moveTo(tester.getCenter(tiles.at(1)));
    await tester.pump();
    // Moving about inside the same tile adds nothing.
    await gesture.moveBy(const Offset(4, 4));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(tiles.at(2)));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(ticks, List.filled(3, 'HapticFeedbackType.selectionClick'));
    expect(selection.ids, {for (final f in months[0].files.take(3)) f.id});
  });

  testWidgets('dragging the handle jumps through months and lands on one', (tester) async {
    await pumpGrid(tester, alwaysSelecting: true);

    // The handle shows once the grid scrolls.
    await tester.dragFrom(const Offset(180, 400), const Offset(0, -60));
    await tester.pump();
    final before = scrolled(tester);
    expect(before, greaterThan(0));

    final gesture = await tester.startGesture(const Offset(350, 100));
    await gesture.moveTo(const Offset(350, 140));
    await tester.pump();
    await gesture.moveTo(const Offset(350, 500));
    await tester.pump(const Duration(milliseconds: 200));
    expect(scrolled(tester), greaterThan(before));
    expect(label(months.last.title).opacity, 1);

    // Back up to the middle month and let go: its header is at the top.
    await gesture.moveTo(const Offset(350, 250));
    await tester.pump();
    expect(label(months[1].title).opacity, 1);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getTopLeft(header(months[1].title)).dy, 0);
    expect(label(months[1].title).opacity, 0);
    expect(selection.ids, isEmpty);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the handle lands on the month under a header, big text and five columns', (
    tester,
  ) async {
    // Five columns make rows shorter, so it takes more photos to run past
    // the two screens that earn the handle.
    files = _photos(count: 40);
    months = monthSections(files);
    await pumpGrid(
      tester,
      alwaysSelecting: true,
      header: const [SliverToBoxAdapter(child: SizedBox(height: 88))],
      textScale: 1.5,
      preferences: {'photo_columns': 5},
    );

    await tester.dragFrom(const Offset(180, 400), const Offset(0, -60));
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(350, 100));
    await gesture.moveTo(const Offset(350, 140));
    await tester.pump();
    await gesture.moveTo(const Offset(350, 350));
    await tester.pump();
    expect(label(months[1].title).opacity, 1);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    // Five columns make the tiles a fractional size, so the header lands
    // within a hair of the top rather than on it.
    expect(tester.getTopLeft(header(months[1].title)).dy, closeTo(0, 0.01));

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a finger held on the handle never starts selecting', (tester) async {
    await pumpGrid(tester);
    await tester.dragFrom(const Offset(180, 400), const Offset(0, -60));
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(350, 300));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(const Offset(350, 360));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    expect(selection.ids, isEmpty);

    // Hidden again, the edge is the grid's: a long-press there selects.
    final press = await tester.startGesture(const Offset(350, 300));
    await tester.pump(const Duration(milliseconds: 700));
    await press.up();
    await tester.pump(const Duration(seconds: 2));
    expect(selection.ids, hasLength(1));
  });

  testWidgets('a short grid has no handle', (tester) async {
    files = _photos(count: 3);
    months = monthSections(files);
    await pumpGrid(tester);

    final gesture = await tester.startGesture(const Offset(350, 100));
    await gesture.moveTo(const Offset(350, 500));
    await tester.pump();
    expect(find.byType(AnimatedOpacity), findsNothing);
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
  });
}
