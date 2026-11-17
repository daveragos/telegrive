import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/preview_maker.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';

class _MobileData extends NetworkStatus {
  @override
  NetworkState build() => const NetworkState(online: true, metered: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    final temp = Directory.systemTemp.createTempSync('preview_maker_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => temp.path,
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProvider,
        null,
      );
      temp.deleteSync(recursive: true);
    });
  });

  ProviderContainer onMobileData() {
    final container = ProviderContainer(
      overrides: [networkStatusProvider.overrideWith(_MobileData.new)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('on mobile data, previews wait for Wi-Fi unless the person agreed', () async {
    final maker = onMobileData().read(previewMakerProvider);

    await expectLater(maker.make(const []), throwsA(isA<DriveException>()));
  });

  test('on mobile data the person agreed to, previews go ahead', () async {
    final maker = onMobileData().read(previewMakerProvider);

    final result = await maker.make(const [], onMobileData: true);

    expect(result.outcome.complete, isTrue);
    expect(result.noPicture, 0);
  });
}
