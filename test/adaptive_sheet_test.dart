import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/platform/app_platform.dart';
import 'package:telegrive/core/widgets/adaptive_sheet.dart';

/// On a computer a sheet is a menu at the pointer or a dialog, laid out as
/// a computer's are.
void main() {
  setUp(() => AppPlatform.debugDesktop = true);
  tearDown(() => AppPlatform.debugDesktop = false);

  Widget rows(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Lease.pdf'),
      ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Rename'), onTap: () {}),
      ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Move to Trash'), onTap: () {}),
    ],
  );

  Future<BuildContext> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (screen) {
              context = screen;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('a menu has rows as close as a computer menu has them, below some room', (tester) async {
    final context = await pump(tester);
    showAdaptiveSheet<void>(context: context, builder: rows);
    await tester.pumpAndSettle();

    final row = tester.getSize(find.widgetWithText(ListTile, 'Rename'));
    expect(row.height, lessThanOrEqualTo(40));
    final card = tester.getTopLeft(find.byType(Material).last);
    expect(tester.getTopLeft(find.text('Lease.pdf')).dy - card.dy, greaterThanOrEqualTo(4));
  });

  testWidgets('a dialog leaves its first line room at the top', (tester) async {
    final context = await pump(tester);
    showAdaptiveSheet<void>(context: context, kind: SheetKind.dialog, builder: rows);
    await tester.pumpAndSettle();

    final dialog = tester.getTopLeft(find.byType(Dialog));
    expect(tester.getTopLeft(find.text('Lease.pdf')).dy - dialog.dy, greaterThanOrEqualTo(12));
  });

  testWidgets('on a phone a long sheet stops short of the top, clear of the status bar, and scrolls', (tester) async {
    AppPlatform.debugDesktop = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (screen) {
              context = screen;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SingleChildScrollView(
        child: Column(children: [for (var i = 0; i < 40; i++) ListTile(title: Text('Row $i'))]),
      ),
    );
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byType(BottomSheet));
    expect(sheet.top, greaterThanOrEqualTo(844 * (1 - sheetMaxHeight) - 0.5));
    expect(sheet.top, greaterThan(47));

    // Dragged down by its handle, it closes.
    await tester.dragFrom(Offset(sheet.center.dx, sheet.top + 12), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });
}
