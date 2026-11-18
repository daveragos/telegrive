import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_platform.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import 'dav_server.dart';
import 'drive_mount.dart';

/// Where the drive stands as a disk on this computer.
@immutable
class MountState {
  const MountState({this.busy = false, this.place});

  /// Mounting or unmounting is under way.
  final bool busy;

  /// Where the drive shows while it is mounted: /Volumes/Telegrive, a drive
  /// letter, or the address a Linux file manager opens.
  final String? place;

  bool get mounted => place != null;
}

/// The drive as a disk in Finder, File Explorer or a Linux file manager:
/// [DavServer] serving it, and the system mounting that. It is mounted as
/// the drive opens when the person asked for that, and unmounted as the
/// app quits, so the system isn't left with a disk nobody answers for.
class DriveMountController extends Notifier<MountState> {
  DavServer get _server => ref.read(davServerProvider);

  @override
  MountState build() {
    if (!AppPlatform.isDesktop) return const MountState();
    ref.listen<DriveSession?>(driveSessionProvider, (previous, next) {
      if (previous == null && next != null && ref.read(preferencesProvider).mountAtStart) {
        unawaited(mount().then<void>((_) {}, onError: (Object e) => debugPrint('[Mount] At start: $e')));
      }
    }, fireImmediately: true);
    return const MountState();
  }

  /// Serves the drive and mounts it, or takes up a mount of the same
  /// address left from before, and answers where it shows.
  Future<String> mount() async {
    if (ref.read(driveSessionProvider) == null) throw const DriveException('Open your drive first.');
    state = MountState(busy: true, place: state.place);
    try {
      final address = await _server.start();
      final place = await DriveMount.mountedAt(address) ?? await DriveMount.mount(address);
      state = MountState(place: place);
      return place;
    } catch (_) {
      state = const MountState();
      rethrow;
    }
  }

  /// Unmounts the drive and stops serving it.
  Future<void> unmount() async {
    final address = _server.address;
    state = MountState(busy: true, place: state.place);
    try {
      if (address != null) await DriveMount.unmount(address);
      await _server.stop();
      state = const MountState();
    } catch (_) {
      state = MountState(place: state.place);
      rethrow;
    }
  }

  /// Unmounts the drive as the app quits, giving up after a few seconds
  /// rather than holding the quit.
  Future<void> letGo() async {
    if (!state.mounted && !_server.running) return;
    try {
      await unmount().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[Mount] Quitting: $e');
    }
  }

  /// The address the drive is served at, for VLC, Kodi or rclone, serving
  /// it if it isn't already.
  Future<Uri> address() => _server.start();
}

final driveMountProvider = NotifierProvider<DriveMountController, MountState>(DriveMountController.new);
