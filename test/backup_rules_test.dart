import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/backup/data/backup_rules.dart';
import 'package:telegrive/features/network/data/mobile_data.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

const _mb = 1024 * 1024;

/// 240 MB of a 250 MB limit used, on [metered] data or not.
MobileDataState _data({required bool metered, bool overridden = false}) => MobileDataState(
  metered: metered,
  limit: 250 * _mb,
  renewDay: 3,
  periodStart: DateTime(2026, 9, 3),
  periodEnd: DateTime(2026, 10, 3),
  mobileBytes: 240 * _mb,
  overridden: overridden,
);

void main() {
  group('backupAllowance', () {
    const fits = 3 * _mb;
    const tooBig = 30 * _mb;

    BackupAllowance allowance(
      MobileDataState data,
      BackupMobileData mode, {
      required bool isVideo,
      required int bytes,
    }) => backupAllowance(data: data, mode: mode, isVideo: isVideo, bytes: bytes);

    test('anything goes on an unmetered network, whatever the mode and size', () {
      for (final mode in BackupMobileData.values) {
        for (final isVideo in [false, true]) {
          for (final bytes in [fits, tooBig]) {
            expect(
              allowance(_data(metered: false), mode, isVideo: isVideo, bytes: bytes),
              BackupAllowance.go,
              reason: '$mode, video: $isVideo, $bytes bytes',
            );
          }
        }
      }
    });

    test('with mobile data off, nothing goes on it', () {
      for (final isVideo in [false, true]) {
        for (final bytes in [fits, tooBig]) {
          expect(
            allowance(_data(metered: true), BackupMobileData.off, isVideo: isVideo, bytes: bytes),
            BackupAllowance.waitForWifi,
          );
        }
      }
    });

    test('with photos only, videos wait for Wi-Fi and photos keep to the limit', () {
      final data = _data(metered: true);
      expect(
        allowance(data, BackupMobileData.photos, isVideo: true, bytes: fits),
        BackupAllowance.waitForWifi,
      );
      expect(
        allowance(data, BackupMobileData.photos, isVideo: true, bytes: tooBig),
        BackupAllowance.waitForWifi,
      );
      expect(
        allowance(data, BackupMobileData.photos, isVideo: false, bytes: fits),
        BackupAllowance.go,
      );
      expect(
        allowance(data, BackupMobileData.photos, isVideo: false, bytes: tooBig),
        BackupAllowance.waitForBudget,
      );
    });

    test('with photos and videos, both keep to the limit', () {
      final data = _data(metered: true);
      for (final isVideo in [false, true]) {
        expect(
          allowance(data, BackupMobileData.all, isVideo: isVideo, bytes: fits),
          BackupAllowance.go,
        );
        expect(
          allowance(data, BackupMobileData.all, isVideo: isVideo, bytes: tooBig),
          BackupAllowance.waitForBudget,
        );
      }
    });

    test('exactly filling the limit still fits', () {
      expect(
        allowance(_data(metered: true), BackupMobileData.all, isVideo: false, bytes: 10 * _mb),
        BackupAllowance.go,
      );
    });

    test('Use data anyway lets what the mode allows past the limit', () {
      final data = _data(metered: true, overridden: true);
      expect(
        allowance(data, BackupMobileData.all, isVideo: true, bytes: tooBig),
        BackupAllowance.go,
      );
      expect(
        allowance(data, BackupMobileData.photos, isVideo: false, bytes: tooBig),
        BackupAllowance.go,
      );
      // It doesn't change what the mode keeps for Wi-Fi.
      expect(
        allowance(data, BackupMobileData.photos, isVideo: true, bytes: fits),
        BackupAllowance.waitForWifi,
      );
      expect(
        allowance(data, BackupMobileData.off, isVideo: false, bytes: fits),
        BackupAllowance.waitForWifi,
      );
    });

    test('without a limit, size never holds anything back', () {
      final data = MobileDataState(
        metered: true,
        limit: null,
        renewDay: 1,
        periodStart: DateTime(2026, 9),
        periodEnd: DateTime(2026, 10),
        mobileBytes: 50 * 1024 * _mb,
      );
      expect(
        allowance(data, BackupMobileData.all, isVideo: true, bytes: 4 * 1024 * _mb),
        BackupAllowance.go,
      );
    });
  });

  group('folderAllowance', () {
    const fits = 3 * _mb;
    const tooBig = 30 * _mb;

    BackupAllowance allowance(MobileDataState data, BackupMobileData mode, int bytes) =>
        folderAllowance(data: data, mode: mode, bytes: bytes);

    test('files from other folders use mobile data only with photos and videos', () {
      expect(foldersMayUseMobileData(BackupMobileData.off), isFalse);
      expect(foldersMayUseMobileData(BackupMobileData.photos), isFalse);
      expect(foldersMayUseMobileData(BackupMobileData.all), isTrue);
    });

    test('anything goes on an unmetered network', () {
      for (final mode in BackupMobileData.values) {
        expect(allowance(_data(metered: false), mode, tooBig), BackupAllowance.go, reason: '$mode');
      }
    });

    test('on mobile data they wait for Wi-Fi unless photos and videos may use it', () {
      final data = _data(metered: true);
      expect(allowance(data, BackupMobileData.off, fits), BackupAllowance.waitForWifi);
      expect(allowance(data, BackupMobileData.photos, fits), BackupAllowance.waitForWifi);
      expect(allowance(data, BackupMobileData.all, fits), BackupAllowance.go);
    });

    test('they keep to the monthly limit, and Use data anyway lets them past it', () {
      expect(
        allowance(_data(metered: true), BackupMobileData.all, tooBig),
        BackupAllowance.waitForBudget,
      );
      expect(
        allowance(_data(metered: true, overridden: true), BackupMobileData.all, tooBig),
        BackupAllowance.go,
      );
    });
  });
}
