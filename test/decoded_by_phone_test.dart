import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telegrive/features/viewer/presentation/decoded_by_phone.dart';
import 'package:telegrive/infrastructure/media/media_probe.dart';

void main() {
  const media = MethodChannel('telegrive/media');
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory dir;
  late List<MethodCall> asked;
  String? answer;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('telegrive_decoded');
    asked = [];
    answer = null;
    MediaProbe.asks = true;
    messenger.setMockMethodCallHandler(pathProvider, (call) async => dir.path);
    messenger.setMockMethodCallHandler(media, (call) async {
      asked.add(call);
      return answer;
    });
  });

  tearDown(() async {
    MediaProbe.asks = false;
    messenger.setMockMethodCallHandler(pathProvider, null);
    messenger.setMockMethodCallHandler(media, null);
    await dir.delete(recursive: true);
  });

  Future<void> show(WidgetTester tester, String source) async {
    // Built on real time, since the folder is made on the disk.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: DecodedByPhone(source: source, side: 2160, fallback: const Text('Can\'t be shown')),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  testWidgets('the phone is asked for a screen-sized picture into the previews folder', (tester) async {
    answer = '/made.jpg';
    await show(tester, '/data/cache/IMG_1.dng');

    final call = asked.single;
    expect(call.method, 'picture');
    expect(call.arguments['path'], '/data/cache/IMG_1.dng');
    expect(call.arguments['side'], 2160);
    expect(p.dirname(call.arguments['out'] as String), p.join(dir.path, 'previews', 'viewer'));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as FileImage).file.path, '/made.jpg');
    expect(find.text('Can\'t be shown'), findsNothing);
  });

  testWidgets('a photo the phone can\'t read either says so', (tester) async {
    await show(tester, '/data/cache/broken.cr2');

    expect(asked, hasLength(1));
    expect(find.byType(Image), findsNothing);
    expect(find.text('Can\'t be shown'), findsOneWidget);
  });
}
