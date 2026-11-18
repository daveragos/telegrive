import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/platform/app_platform.dart';
import '../../../core/platform/file_manager.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../data/drive_mount.dart';
import '../data/drive_mount_controller.dart';

/// The biggest file Windows lets through the drive letter, or null off
/// Windows or when it can't be read.
final _windowsLimitProvider = FutureProvider.autoDispose<int?>(
  (_) async => Platform.isWindows && AppPlatform.isDesktop ? DriveMount.windowsFileLimit() : null,
);

/// Settings' rows for the drive as a disk in Finder, File Explorer or a
/// Linux file manager: showing it, opening it, showing it at every start,
/// and its address for other apps. Windows also has the way past its
/// 50 MB limit.
class DriveMountSection extends ConsumerWidget {
  const DriveMountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final mount = ref.watch(driveMountProvider);
    final controller = ref.read(driveMountProvider.notifier);
    final prefs = ref.watch(preferencesProvider);
    final limit = ref.watch(_windowsLimitProvider).value;
    final where = AppPlatform.fileManager;

    Future<void> toggle(bool on) async {
      try {
        if (on) {
          await controller.mount();
        } else {
          await controller.unmount();
        }
      } catch (e) {
        debugPrint('[Mount] $e');
        if (context.mounted) {
          showSnack(
            context,
            on ? 'Couldn\'t show the drive in $where: ${_reason(e)}' : 'Couldn\'t take the drive out of $where: ${_reason(e)}',
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Drive in $where'),
        ListGroup(
          children: [
            SwitchListTile(
              title: Text('Show the drive in $where'),
              subtitle: Text(switch (mount) {
                MountState(busy: true) => 'One moment…',
                MountState(:final place?) => '${_describe(place)}, while Telegrive runs.',
                _ => 'As a disk to open, save into and drag files to, while Telegrive runs.',
              }),
              value: mount.mounted,
              onChanged: mount.busy ? null : toggle,
            ),
            if (mount.place case final place?)
              ListTile(
                title: Text('Open in $where'),
                trailing: Icon(Icons.folder_open_outlined, color: colors.text3),
                onTap: () => FileManager.open(Platform.isWindows ? '$place\\' : place),
              ),
            SwitchListTile(
              title: const Text('Show it whenever Telegrive starts'),
              value: prefs.mountAtStart,
              onChanged: (on) async {
                await prefs.setMountAtStart(on);
                ref.invalidate(preferencesProvider);
              },
            ),
            ListTile(
              title: const Text('Copy address'),
              subtitle: const Text('For VLC, Kodi or rclone on this computer'),
              trailing: Icon(Icons.copy_rounded, size: 20, color: colors.text3),
              onTap: () async {
                final address = await controller.address();
                await Clipboard.setData(ClipboardData(text: address.toString()));
                if (context.mounted) showSnack(context, 'Address copied');
              },
            ),
            if (limit != null && limit < DriveMount.windowsMaxLimit)
              ListTile(
                title: const Text('Allow files up to 4 GB'),
                subtitle: const Text(
                  'Windows lets files of 50 MB at most through a drive letter. Changing that asks for your permission.',
                ),
                onTap: () async {
                  try {
                    await DriveMount.raiseWindowsFileLimit();
                  } catch (e) {
                    debugPrint('[Mount] $e');
                    if (context.mounted) showSnack(context, 'Windows didn\'t change the limit.');
                  }
                  ref.invalidate(_windowsLimitProvider);
                },
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 0),
          child: Text(
            '$where downloads a file before opening it, so a big video plays sooner in '
            'Telegrive, or from the address in VLC. What you save or drop in uploads like '
            'any other file, and what you delete goes to Trash.',
            style: context.text.bodySmall,
          ),
        ),
      ],
    );
  }

  /// Where the disk shows, in words.
  static String _describe(String place) {
    if (Platform.isWindows) return 'As drive $place';
    if (Platform.isMacOS) return 'At $place';
    return 'Under Other Locations';
  }

  static String _reason(Object e) => switch (e) {
    ProcessException(:final message) when message.isNotEmpty => message,
    FileSystemException(:final message) => message,
    _ => '$e',
  };
}
