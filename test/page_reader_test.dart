import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/search/data/page_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('telegrive/text');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  void answer(Object? Function(MethodCall call) reply) {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('a page with no words of its own, or a stray few, is a picture', () {
    expect(PageReader.isPicture(''), isTrue);
    expect(PageReader.isPicture('  \n 12 \n'), isTrue);
    expect(PageReader.isPicture('Invoice 2024-03 for freight from Djibouti'), isFalse);
  });

  test('the pages asked for are read on the phone, and their words come back', () async {
    answer((_) => 'TOTAL DUE 1,200 ETB');

    final text = await const PageReader().read('/docs/scan.pdf', [0, 2], maxChars: 500);

    expect(text, 'TOTAL DUE 1,200 ETB');
    expect(calls.single.method, 'readPdfPages');
    expect(calls.single.arguments, {
      'path': '/docs/scan.pdf',
      'pages': [0, 2],
      'maxChars': 500,
    });
  });

  test('while the recognizer is still on its way, the document waits for a later pass', () async {
    answer((_) => throw PlatformException(code: 'unavailable'));

    expect(await const PageReader().read('/docs/scan.pdf', [0], maxChars: 500), isNull);
  });

  test('a PDF the phone cannot read gives no words, so it is not tried forever', () async {
    answer((_) => throw PlatformException(code: 'failed', message: 'Password protected'));

    expect(await const PageReader().read('/docs/locked.pdf', [0], maxChars: 500), '');
  });

  test('a phone without text recognition gives no words', () async {
    messenger.setMockMethodCallHandler(channel, null);

    expect(await const PageReader().read('/docs/scan.pdf', [0], maxChars: 500), '');
  });
}
