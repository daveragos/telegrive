import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:telegrive/app/desktop_sidebar.dart';

void main() {
  testWidgets('a page pushed over the shell is where the app is, not the tab below it', (tester) async {
    final router = GoRouter(
      initialLocation: '/photos',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => shell,
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const Text('Home'))]),
            StatefulShellBranch(routes: [GoRoute(path: '/photos', builder: (_, _) => const Text('Photos'))]),
          ],
        ),
        GoRoute(path: '/recent', builder: (_, _) => const Text('Recent')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(DesktopNavigation.location(router), '/photos');

    unawaited(router.push('/recent'));
    await tester.pumpAndSettle();
    expect(find.text('Recent'), findsOneWidget);
    expect(DesktopNavigation.location(router), '/recent');

    router.pop();
    await tester.pumpAndSettle();
    expect(DesktopNavigation.location(router), '/photos');
  });
}
