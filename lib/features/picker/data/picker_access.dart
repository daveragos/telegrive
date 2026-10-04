import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_session.dart';
import '../../lock/data/app_lock.dart';
import '../../player/data/stream_server.dart';

/// Whether this phone has Android's file picker to show the drive in. The
/// screenshot harness, which runs on a computer, says yes so that Settings
/// draws the switch.
final pickerSupportedProvider = Provider<bool>((ref) => !kIsWeb && Platform.isAndroid);

/// Whether the person wants the drive in Android's file picker, which
/// Settings › This phone › Show the drive in other apps sets. It is written
/// through here rather than by invalidating preferencesProvider, which would
/// lock the app again while app lock is on.
class PickerEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(preferencesProvider).pickerEnabled;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(preferencesProvider).setPickerEnabled(on);
  }
}

final pickerEnabledProvider = NotifierProvider<PickerEnabledNotifier, bool>(
  PickerEnabledNotifier.new,
);

/// Keeps Android's file picker in step with the app. Watched from the app
/// root, so it still sees the drive close on sign-out; it does nothing off
/// Android.
///
/// The picker is a DocumentsProvider in a process of its own that reads the
/// index straight from disk, so browsing needs neither Flutter nor TDLib.
/// Android lists it only while its component is on, which is while the
/// person wants it and app lock is off: the picker can't ask for a
/// fingerprint, so a locked app keeps the drive out of other apps.
///
/// A file that isn't on the phone is read through the [StreamServer], which
/// runs only in this process. While the drive is open and the picker is on,
/// the server's port and token sit in picker/bridge.json among the app's
/// private files, and otherwise the file is gone, so the picker knows to
/// say that Telegrive needs to be open. The file is written under another
/// name and renamed into place, so the picker never reads half of one.
final pickerAccessProvider = Provider<void>((ref) {
  if (!ref.read(pickerSupportedProvider)) return;
  const channel = MethodChannel('telegrive/picker');

  bool enabled() => ref.read(pickerEnabledProvider) && !ref.read(appLockProvider).enabled;
  bool bridge() => enabled() && ref.read(driveSessionProvider) != null;

  // What Android and the bridge file were last brought to, so a change
  // that leaves both as they are sends nothing.
  bool? sentEnabled;
  bool? wroteBridge;

  Future<void> apply() async {
    if (!ref.mounted) return;
    final on = enabled();
    if (on != sentEnabled) {
      sentEnabled = on;
      try {
        await channel.invokeMethod<void>('setEnabled', on);
      } catch (e) {
        debugPrint('[Picker] Could not switch the picker: $e');
      }
    }
    if (!ref.mounted) return;
    final open = bridge();
    if (open == wroteBridge) return;
    wroteBridge = open;
    if (open) {
      await _writeBridge(ref.read(streamServerProvider));
    } else {
      await deletePickerBridge();
    }
  }

  // One change at a time and in order, so a quick off and on never lands
  // the other way round.
  var applying = Future<void>.value();
  void schedule() => applying = applying.then((_) => apply());

  ref.listen<bool>(pickerEnabledProvider, (_, _) => schedule());
  ref.listen<bool>(appLockProvider.select((lock) => lock.enabled), (_, _) => schedule());
  ref.listen<DriveSession?>(driveSessionProvider, (_, _) => schedule(), fireImmediately: true);
  ref.onDispose(() => unawaited(applying.then((_) => deletePickerBridge())));
});

Future<File> _bridgeFile() async =>
    File(p.join((await getApplicationSupportDirectory()).path, 'picker', 'bridge.json'));

Future<void> _writeBridge(StreamServer server) async {
  try {
    final (:port, :token) = await server.endpoint();
    final file = await _bridgeFile();
    await file.parent.create(recursive: true);
    final draft = File('${file.path}.tmp');
    await draft.writeAsString(jsonEncode({'port': port, 'token': token}), flush: true);
    await draft.rename(file.path);
  } catch (e) {
    debugPrint('[Picker] Could not write the bridge file: $e');
  }
}

/// Takes away the picker's way to this app's stream server, so files that
/// aren't on the phone say that Telegrive needs to be open.
Future<void> deletePickerBridge() async {
  try {
    final file = await _bridgeFile();
    if (await file.exists()) await file.delete();
  } catch (e) {
    debugPrint('[Picker] Could not delete the bridge file: $e');
  }
}
