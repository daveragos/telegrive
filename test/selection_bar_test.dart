import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/app/theme/tokens.dart';
import 'package:telegrive/core/widgets/selection_bar.dart';

enum _More { star, selectAll }

void main() {
  late List<Object> fired;

  setUp(() => fired = []);

  /// The bar at the foot of a screen [width] wide, with Download disabled
  /// as before anything is picked.
  Future<void> pumpBar(WidgetTester tester, {double width = 360, Widget? status}) async {
    tester.view.physicalSize = Size(width, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bar = SelectionActionBar(
      actions: [
        const SelectionAction(icon: Icons.download_rounded, label: 'Download'),
        SelectionAction(icon: Icons.send_outlined, label: 'Send', onTap: () => fired.add('Send')),
        SelectionAction(
          icon: Icons.drive_file_move_outline,
          label: 'Move',
          onTap: () => fired.add('Move'),
        ),
        SelectionAction(
          icon: Icons.delete_outline_rounded,
          label: 'Trash',
          onTap: () => fired.add('Trash'),
        ),
      ],
      more: const [
        PopupMenuItem(value: _More.star, child: Text('Add to Starred')),
        PopupMenuItem(value: _More.selectAll, child: Text('Select all')),
      ],
      onMore: fired.add,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SelectionBarStatus(
          line: status,
          child: Scaffold(body: const SizedBox.expand(), bottomNavigationBar: bar),
        ),
      ),
    );
  }

  Finder inBar(Finder finder) =>
      find.descendant(of: find.byType(SelectionActionBar), matching: finder);

  testWidgets('shows four actions and More, each with its name', (tester) async {
    await pumpBar(tester);
    for (final label in ['Download', 'Send', 'Move', 'Trash', 'More']) {
      expect(inBar(find.text(label)), findsOneWidget);
    }
    expect(inBar(find.byIcon(Icons.more_horiz_rounded)), findsOneWidget);
  });

  testWidgets('a disabled action is greyed out and does nothing', (tester) async {
    await pumpBar(tester);
    final colors = AppTheme.light().extension<AppColors>()!;
    expect(tester.widget<Text>(find.text('Download')).style?.color, colors.text3);
    expect(tester.widget<Text>(find.text('Move')).style?.color, colors.text2);

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(fired, isEmpty);
  });

  testWidgets('tapping an action runs it', (tester) async {
    await pumpBar(tester);
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    expect(fired, ['Move']);
  });

  testWidgets('More opens its entries just above the bar and hands back the one picked', (
    tester,
  ) async {
    await pumpBar(tester);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Add to Starred'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Select all')).dy,
      lessThan(tester.getTopLeft(find.byType(SelectionActionBar)).dy),
    );

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(fired, [_More.selectAll]);
  });

  testWidgets('on a narrow phone each name sits under its icon', (tester) async {
    await pumpBar(tester);
    expect(find.byKey(SelectionActionBar.wideKey), findsNothing);
    final icon = tester.getRect(inBar(find.byIcon(Icons.drive_file_move_outline)));
    final label = tester.getRect(find.text('Move'));
    expect(label.top, greaterThanOrEqualTo(icon.bottom));
    expect(label.center.dx, closeTo(icon.center.dx, 1));
  });

  testWidgets('on a wide window the names sit beside their icons, from the left', (
    tester,
  ) async {
    await pumpBar(tester, width: 900);
    expect(find.byKey(SelectionActionBar.wideKey), findsOneWidget);
    final icon = tester.getRect(inBar(find.byIcon(Icons.drive_file_move_outline)));
    final label = tester.getRect(find.text('Move'));
    expect(label.left, greaterThan(icon.right));
    expect(label.center.dy, closeTo(icon.center.dy, 1));
    expect(tester.getTopLeft(inBar(find.byIcon(Icons.download_rounded))).dx, Space.gutter);
  });

  testWidgets('a status line handed down rides on top of the actions', (tester) async {
    await pumpBar(tester, status: const Text('Moving 500 items'));
    await tester.pumpAndSettle();
    expect(inBar(find.text('Moving 500 items')), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Moving 500 items')).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text('Move')).dy),
    );
  });

  group('the selection app bar', () {
    Future<void> pumpAppBar(
      WidgetTester tester, {
      required int count,
      required int bytes,
      String? noun,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              appBar: noun == null
                  ? selectionAppBar(context, count: count, bytes: bytes, onClear: () {})
                  : selectionAppBar(
                      context,
                      count: count,
                      bytes: bytes,
                      onClear: () {},
                      noun: noun,
                    ),
            ),
          ),
        ),
      );
    }

    testWidgets('says how many are selected and what their files weigh', (tester) async {
      await pumpAppBar(tester, count: 2, bytes: (6.4 * 1024 * 1024).round());
      expect(find.text('2 selected · 6.4 MB'), findsOneWidget);
      expect(find.byTooltip('Clear selection'), findsOneWidget);
    });

    testWidgets('folders alone weigh nothing, so only the count shows', (tester) async {
      await pumpAppBar(tester, count: 2, bytes: 0);
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('before anything is picked it asks for some', (tester) async {
      await pumpAppBar(tester, count: 0, bytes: 0);
      expect(find.text('Select items'), findsOneWidget);
      await pumpAppBar(tester, count: 0, bytes: 0, noun: 'photos');
      expect(find.text('Select photos'), findsOneWidget);
    });
  });
}
