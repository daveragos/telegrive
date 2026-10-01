import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the New sheet can make with the phone itself. Each name is the
/// telegrive/capture method that makes it.
enum CaptureKind { scan, photo }

/// Which captures this phone can make, so the New sheet leaves out a row
/// the phone can't do rather than show it greyed.
@immutable
class CaptureSupport {
  const CaptureSupport({required this.scan, required this.photo});

  factory CaptureSupport.fromMap(Map<Object?, Object?> map) =>
      CaptureSupport(scan: map['scan'] == true, photo: map['photo'] == true);

  static const none = CaptureSupport(scan: false, photo: false);

  /// Play services is there to run the document scanner.
  final bool scan;

  /// An app on the phone takes a photo when asked.
  final bool photo;
}

/// A scan or a photo in the app's cache, alone in a folder of its own,
/// under the name the phone gave it.
@immutable
class CapturedFile {
  const CapturedFile({
    required this.path,
    required this.name,
    required this.size,
    this.pages,
    this.takenAt,
  });

  factory CapturedFile.fromMap(Map<Object?, Object?> map) {
    final takenAt = map['takenAt'] as num?;
    return CapturedFile(
      path: map['path']! as String,
      name: map['name']! as String,
      size: (map['size']! as num).toInt(),
      pages: (map['pages'] as num?)?.toInt(),
      takenAt: takenAt == null ? null : DateTime.fromMillisecondsSinceEpoch(takenAt.toInt()),
    );
  }

  final String path;
  final String name;
  final int size;

  /// How many pages a scan has; null for a photo.
  final int? pages;

  /// When a photo was taken; null for a scan.
  final DateTime? takenAt;
}

/// The document scanner and the phone's camera app, reached through the
/// telegrive/capture channel. Android only.
class DeviceCapture {
  static const _channel = MethodChannel('telegrive/capture');

  Future<CaptureSupport> support() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('support');
    return map == null ? CaptureSupport.none : CaptureSupport.fromMap(map);
  }

  /// Opens the scanner or the camera and waits for what it hands back, or
  /// null when the person backed out. A [PlatformException] says why it
  /// couldn't start: `unavailable` for a scanner that can't run, `no_camera`
  /// for a camera app that refused, or `busy` while another capture is out.
  Future<CapturedFile?> capture(CaptureKind kind) async {
    final map = await _channel.invokeMapMethod<Object?, Object?>(kind.name);
    return map == null ? null : CapturedFile.fromMap(map);
  }
}

final deviceCaptureProvider = Provider<DeviceCapture>((ref) => DeviceCapture());

/// Asked once per launch, when the shell opens, so the New sheet knows its
/// rows before the first tap and never changes height while it is open.
/// Kept alive for that reason. A phone that can't say counts as able to do
/// neither.
final captureSupportProvider = FutureProvider<CaptureSupport>((ref) async {
  if (kIsWeb || !Platform.isAndroid) return CaptureSupport.none;
  try {
    return await ref.read(deviceCaptureProvider).support();
  } catch (_) {
    return CaptureSupport.none;
  }
});
