import '../../../infrastructure/storage/preferences.dart';
import '../../network/data/mobile_data.dart';

/// Whether one photo or video may go up now.
enum BackupAllowance {
  go,

  /// Mobile data isn't allowed for it, so it waits for Wi-Fi.
  waitForWifi,

  /// It would pass the monthly mobile data limit, so it waits for Wi-Fi or
  /// the next period.
  waitForBudget,
}

/// The backup rule for one item of [bytes]: anything goes on an unmetered
/// network; on mobile data, [mode] decides by kind and then [data]'s
/// monthly limit by size. Pure, so the whole matrix is tested on its own.
BackupAllowance backupAllowance({
  required MobileDataState data,
  required BackupMobileData mode,
  required bool isVideo,
  required int bytes,
}) {
  if (!data.metered) return BackupAllowance.go;
  if (!mayUseMobileData(mode, isVideo: isVideo)) return BackupAllowance.waitForWifi;
  return data.fits(bytes) ? BackupAllowance.go : BackupAllowance.waitForBudget;
}

/// Whether [mode] lets a photo, or a video when [isVideo], use mobile data
/// at all.
bool mayUseMobileData(BackupMobileData mode, {required bool isVideo}) => switch (mode) {
  BackupMobileData.off => false,
  BackupMobileData.photos => !isVideo,
  BackupMobileData.all => true,
};

/// Whether [mode] lets files from the other watched folders on the phone
/// use mobile data. They aren't photos, so they go on it only once videos
/// may: Photos only keeps them for Wi-Fi.
bool foldersMayUseMobileData(BackupMobileData mode) => mayUseMobileData(mode, isVideo: true);

/// The rule for one file of [bytes] from another watched folder: the Mobile
/// data choice by [foldersMayUseMobileData], then the monthly limit, as for
/// what photo backup sends.
BackupAllowance folderAllowance({
  required MobileDataState data,
  required BackupMobileData mode,
  required int bytes,
}) => backupAllowance(data: data, mode: mode, isVideo: true, bytes: bytes);
