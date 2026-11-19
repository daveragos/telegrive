import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/files/data/clipboard_files.dart';
import 'package:telegrive/features/files/presentation/drop_to_upload.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('telegrive/clipboard');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var copied = <String>[];

  setUp(() {
    copied = [];
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'files' ? copied : null);
    // desktop_drop asks its plugin when a drop target appears.
    messenger.setMockMethodCallHandler(const MethodChannel('desktop_drop'), (_) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(const MethodChannel('desktop_drop'), null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('a Mac reads the files copied, and leaves out empty paths', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    copied = ['/Users/me/a.pdf', '', '/Users/me/Photos'];
    expect(await ClipboardFiles.read(), ['/Users/me/a.pdf', '/Users/me/Photos']);
  });

  test('elsewhere the clipboard holds no files', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    copied = ['C:/a.pdf'];
    expect(await ClipboardFiles.read(), isEmpty);
  });

  Future<void> pump(WidgetTester tester, Widget page) => tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: DropToUpload(folderOf: (_) => null, child: page)),
      ),
    ),
  );

  Future<void> paste(WidgetTester tester) async {
    Actions.maybeInvoke(primaryFocus!.context!, const PasteTextIntent(SelectionChangedCause.keyboard));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Paste with nothing copied says how to paste files', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pump(tester, const Focus(autofocus: true, child: Text('page')));
    await tester.pump();

    await paste(tester);
    expect(find.textContaining('Copy files in Finder'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Paste in a text field pastes its text, not files', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    copied = ['/Users/me/a.pdf'];
    await pump(tester, const TextField(autofocus: true));
    await tester.pump();

    await paste(tester);
    expect(find.textContaining('Copy files in Finder'), findsNothing);
    expect(find.textContaining('Uploading'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
