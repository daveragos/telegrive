import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../files/presentation/folder_picker.dart';
import '../../lock/data/app_lock.dart';

/// The folders this phone last uploaded into, most recent first, with the
/// drive's root as Files. The Save to Telegrive sheet starts on the first
/// and offers the rest, and on Android up to [maxTargets] of them, never
/// the root, are targets of their own in the system share sheet, named
/// after the folder, so a share goes straight in.
///
/// The names follow the drive: they are looked up again after every sync,
/// and a folder that is gone or in the trash drops out. While app lock is
/// on, the share sheet gets none of them, so folder names stay out of
/// other apps.
class RecentDestinations extends Notifier<List<FolderChoice>> {
  static const _channel = MethodChannel('telegrive/share');

  /// How many folders are remembered.
  static const keep = 5;

  /// How many of them the system share sheet is offered.
  static const maxTargets = 4;

  /// Whether there is a system share sheet to publish to. Tests that mock
  /// the channel turn this on.
  @visibleForTesting
  static bool onAndroid = !kIsWeb && Platform.isAndroid;

  /// [ids] with [id] first, once, and no more than [keep] of them.
  static List<String> pushed(List<String> ids, String id) =>
      [id, ...ids.where((x) => x != id)].take(keep).toList();

  Preferences get _prefs => ref.read(preferencesProvider);

  /// Counts the look-ups started, so that of two running at once only the
  /// later one, which read the newer list, sets the folders.
  var _lookUps = 0;

  @override
  List<FolderChoice> build() {
    // Looked up when the drive opens, or straight away when it is open
    // already; either way once build is done, since the look-up sets the
    // state.
    ref.listen<DriveSession?>(driveSessionProvider, (_, session) {
      if (session != null) unawaited(Future(refresh));
    }, fireImmediately: true);
    ref.listen<bool>(driveSyncProvider.select((sync) => sync.running), (
      wasRunning,
      running,
    ) {
      if (wasRunning == true && !running) unawaited(refresh());
    });
    ref.listen<bool>(
      appLockProvider.select((lock) => lock.enabled),
      (_, _) => unawaited(_publish(state)),
    );
    return const [];
  }

  /// Remembers [folderId], or the root when it is null, as where the last
  /// upload went. A folder that has a target in the share sheet is told
  /// it was used, which is how Android ranks the targets.
  Future<void> note(String? folderId) async {
    await _prefs.setRecentDestinations(
      pushed(_prefs.recentDestinations, folderId ?? ''),
    );
    if (folderId != null && onAndroid) {
      try {
        await _channel.invokeMethod<void>('reportTarget', {'id': folderId});
      } catch (e) {
        debugPrint('[Share] Could not report the target: $e');
      }
    }
    await refresh();
  }

  /// Looks the folders up in the drive again: a renamed one takes its new
  /// name, and one that is gone or in the trash is forgotten. Nothing
  /// changes while no drive is open, since there is nothing to look them
  /// up in.
  Future<void> refresh() async {
    if (!ref.mounted || ref.read(driveSessionProvider) == null) return;
    final lookUp = ++_lookUps;
    final repository = ref.read(driveRepositoryProvider);
    final dropped = <String>{};
    final choices = <FolderChoice>[];
    for (final id in _prefs.recentDestinations) {
      if (id.isEmpty) {
        choices.add(const FolderChoice(null, 'Files'));
        continue;
      }
      final folder = await repository.shownFolder(id);
      if (folder == null) {
        dropped.add(id);
        continue;
      }
      choices.add(FolderChoice(folder.id, folder.name));
    }
    // The drive may have closed while the folders were looked up, or a
    // later look-up started, which has the newer list.
    if (!_current(lookUp)) return;
    if (dropped.isNotEmpty) {
      // Read again: a folder used during the look-up is already first,
      // and stays.
      await _prefs.setRecentDestinations([
        for (final id in _prefs.recentDestinations)
          if (!dropped.contains(id)) id,
      ]);
      if (!_current(lookUp)) return;
    }
    state = choices;
    await _publish(choices);
  }

  /// Whether the look-up [lookUp] is the latest and its drive still open.
  bool _current(int lookUp) =>
      ref.mounted && lookUp == _lookUps && ref.read(driveSessionProvider) != null;

  /// Forgets every folder and takes the targets out of the share sheet,
  /// for a drive leaving the phone. A look-up still under way leaves the
  /// list empty.
  Future<void> clear() async {
    _lookUps++;
    await _prefs.clearRecentDestinations();
    state = const [];
    if (onAndroid) await _setTargets(const []);
  }

  /// Offers the share sheet the first of [choices] that are folders, or
  /// nothing while app lock is on or no drive is open.
  Future<void> _publish(List<FolderChoice> choices) async {
    if (!onAndroid) return;
    final hidden =
        ref.read(appLockProvider).enabled || ref.read(driveSessionProvider) == null;
    await _setTargets([
      if (!hidden)
        for (final choice in choices.where((c) => c.folderId != null).take(maxTargets))
          {'id': choice.folderId!, 'name': choice.name},
    ]);
  }

  Future<void> _setTargets(List<Map<String, String>> targets) async {
    try {
      await _channel.invokeMethod<void>('setTargets', targets);
    } catch (e) {
      debugPrint('[Share] Could not publish the share targets: $e');
    }
  }
}

final recentDestinationsProvider =
    NotifierProvider<RecentDestinations, List<FolderChoice>>(
      RecentDestinations.new,
    );
