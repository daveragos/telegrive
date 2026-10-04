import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/database/app_database.dart' show SaveTarget, TransferRow;
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/file_tiles.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/offline_sync.dart';

/// Everything this phone keeps for use without a connection, one row per
/// file or folder kept, each saying how far along it is, with one line on
/// top for all of them and the switch that keeps them to Wi-Fi.
class OfflineScreen extends ConsumerWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(offlineOverviewProvider);
    final anything = overview.value?.pins.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available offline'),
        actions: [
          if (anything)
            PopupMenuButton<_Menu>(
              tooltip: 'More',
              onSelected: (choice) => switch (choice) {
                _Menu.removeAll => _removeAll(context, ref),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: _Menu.removeAll, child: Text('Remove all')),
              ],
            ),
        ],
      ),
      body: AsyncView(
        value: overview,
        data: (overview) => overview.pins.isEmpty
            ? const EmptyState(
                icon: Icons.offline_pin_outlined,
                title: 'Nothing kept offline yet',
                message:
                    'Choose Make available offline from a file or folder\'s menu and it '
                    'stays on this phone.',
              )
            : ListView(
                padding: const EdgeInsets.only(top: Space.s, bottom: Space.x4),
                children: [
                  ListGroup(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeOut,
                        child: _Summary(
                          key: ValueKey(_Phase.of(overview)),
                          overview: overview,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.m),
                  const ListGroup(children: [_WifiOnlySwitch()]),
                  const SectionHeader('Kept on this phone'),
                  ListGroup(
                    children: [for (final pin in overview.pins) _PinRow(pin: pin)],
                  ),
                ],
              ),
      ),
    );
  }

  static Future<void> _removeAll(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Stop keeping files offline?',
      message: 'Their copies on this phone are removed. The files stay in your drive.',
      confirmLabel: 'Remove',
    );
    if (ok) await ref.read(offlineSyncProvider.notifier).removeAll();
  }
}

enum _Menu { removeAll }

/// Which of its sentences the line on top says, so it changes with a fade
/// only when that changes, not with every byte.
enum _Phase {
  downloading,
  paused,
  needRoom,
  waiting,
  kept;

  static _Phase of(OfflineOverview overview) {
    if (overview.downloading > 0) return downloading;
    if (overview.paused > 0) return paused;
    if (overview.needRoom > 0) return needRoom;
    if (overview.waiting > 0) return waiting;
    return kept;
  }
}

bool _isOffline(TransferRow row) => row.saveTo == SaveTarget.offline;

/// One line for everything kept offline: what the phone holds, or how far
/// the copies on their way have come and what holds them.
class _Summary extends ConsumerWidget {
  const _Summary({super.key, required this.overview});

  final OfflineOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final queue = ref.read(transferQueueProvider.notifier);
    final o = overview;
    return switch (_Phase.of(o)) {
      _Phase.downloading => StatusLine(
        icon: Icons.download_rounded,
        color: colors.accent,
        text: 'Downloading ${Formatters.number(o.keptFiles)} of ${Formatters.count(o.files, 'file')}',
        detail: [
          '${Formatters.bytes(o.downloadingLeft)} left',
          if (o.speed >= 1) Formatters.speed(o.speed),
          if (o.needRoom > 0)
            '${Formatters.number(o.needRoom)} ${o.needRoom == 1 ? 'waits' : 'wait'} for room',
          if (o.waiting > 0)
            '${Formatters.number(o.waiting)} ${o.waiting == 1 ? 'waits' : 'wait'} for Wi-Fi',
        ].join(' · '),
        progress: o.progress,
        trailing: TextButton(
          onPressed: () => queue.pauseAll(_isOffline),
          child: const Text('Pause'),
        ),
      ),
      _Phase.paused => StatusLine(
        icon: Icons.pause_circle_outline_rounded,
        color: colors.text2,
        text: 'Paused',
        detail: '${Formatters.count(o.paused, 'file')} · ${Formatters.bytes(o.pausedLeft)} to go',
        trailing: TextButton(
          onPressed: () => queue.resumeAll(_isOffline),
          child: const Text('Resume'),
        ),
      ),
      _Phase.needRoom => StatusLine(
        icon: Icons.sd_card_alert_outlined,
        color: colors.text2,
        text: 'Waiting for room',
        detail:
            '${Formatters.count(o.needRoom, 'file')} · ${Formatters.bytes(o.needRoomLeft)} to go',
      ),
      _Phase.waiting => StatusLine(
        icon: Icons.wifi_off_rounded,
        color: colors.text2,
        text: 'Waiting for Wi-Fi',
        detail: '${Formatters.count(o.waiting, 'file')} · ${Formatters.bytes(o.waitingLeft)} to go',
        trailing: TextButton(
          onPressed: () => queue.useMobileData(o.waitingTransferIds),
          child: const Text('Download now'),
        ),
      ),
      _Phase.kept => StatusLine(
        icon: Icons.offline_pin_rounded,
        color: colors.success,
        text:
            '${Formatters.count(o.keptFiles, 'file')} · ${Formatters.bytes(o.keptBytes)} '
            'on this phone',
      ),
    };
  }
}

/// Only over Wi-Fi, for everything kept offline.
class _WifiOnlySwitch extends ConsumerWidget {
  const _WifiOnlySwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: const Text('Only over Wi-Fi'),
      subtitle: const Text('For everything kept offline'),
      value: ref.watch(offlineSyncProvider),
      onChanged: (on) => ref.read(offlineSyncProvider.notifier).setWifiOnly(on),
    );
  }
}

/// A file or folder kept offline, saying how much of it is on this phone,
/// or what it waits for, with Retry when copies failed.
class _PinRow extends ConsumerWidget {
  const _PinRow({required this.pin});

  final OfflinePinStatus pin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final (:text, :failed) = _describe(pin);
    final retry = failed
        ? TextButton(
            onPressed: () => ref
                .read(transferQueueProvider.notifier)
                .retryAll((row) => pin.failedTransferIds.contains(row.id)),
            child: const Text('Retry'),
          )
        : null;
    final subtitleColor = failed ? colors.danger : null;
    final folder = pin.folder;
    if (folder != null) {
      return FolderListTile(
        folder: folder,
        subtitle: text,
        subtitleColor: subtitleColor,
        trailing: retry,
        onTap: () => context.go('/files/${folder.id}'),
        onMore: () => _showSheet(context, ref),
      );
    }
    final file = pin.file!;
    return FileListTile(
      file: file,
      subtitle: text,
      subtitleColor: subtitleColor,
      trailing: retry,
      onTap: () => FileActions.open(context, ref, file),
      onMore: () => _showSheet(context, ref),
    );
  }

  /// The row's line. A folder counts its files; a file says its size.
  static ({String text, bool failed}) _describe(OfflinePinStatus pin) {
    final isFolder = pin.folder != null;
    final of = '${Formatters.number(pin.kept)} of ${Formatters.number(pin.wanted)}';
    final left = Formatters.bytes(pin.leftBytes);
    if (pin.downloading > 0) {
      return (
        text: isFolder ? 'Downloading $of · $left to go' : 'Downloading · $left to go',
        failed: false,
      );
    }
    if (pin.failedTransferIds.isNotEmpty) {
      return (
        text: isFolder
            ? 'Failed · ${Formatters.count(pin.failedTransferIds.length, 'file')}'
            : 'Failed',
        failed: true,
      );
    }
    if (pin.paused > 0) {
      return (text: isFolder ? 'Paused · $of' : 'Paused · $left to go', failed: false);
    }
    if (pin.needRoom > 0) {
      return (
        text: isFolder
            ? 'Waiting for room · ${Formatters.count(pin.needRoom, 'file')}'
            : 'Waiting for room · $left',
        failed: false,
      );
    }
    if (pin.waiting > 0) {
      return (
        text: isFolder
            ? 'Waiting for Wi-Fi · ${Formatters.count(pin.waiting, 'file')}'
            : 'Waiting for Wi-Fi · $left',
        failed: false,
      );
    }
    if (!isFolder) {
      return (
        text: pin.kept > 0
            ? 'Kept · ${Formatters.bytes(pin.keptBytes)}'
            : 'Not on this phone yet · ${Formatters.bytes(pin.bytes)}',
        failed: false,
      );
    }
    final files = pin.kept == pin.wanted
        ? Formatters.count(pin.kept, 'file')
        : '$of files';
    return (text: 'Kept · $files · ${Formatters.bytes(pin.keptBytes)}', failed: false);
  }

  Future<void> _showSheet(BuildContext context, WidgetRef ref) {
    final folder = pin.folder;
    // The row goes once it is no longer kept, so what that says comes
    // through the root navigator, which lasts.
    final lasting = Navigator.of(context, rootNavigator: true).context;
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) {
        void run(Future<void> Function() action) {
          Navigator.pop(sheetContext);
          action();
        }

        final colors = context.colors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.m),
                child: Text(
                  pin.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.offline_pin_rounded, color: colors.text2),
                title: const Text('Stop keeping offline'),
                onTap: () => run(
                  () => FileActions.setOffline(
                    lasting,
                    ref,
                    file: pin.file,
                    folder: folder,
                    keep: false,
                  ),
                ),
              ),
              if (folder != null)
                ListTile(
                  leading: Icon(Icons.folder_open_outlined, color: colors.text2),
                  title: const Text('Open folder'),
                  onTap: () => run(() async => context.go('/files/${folder.id}')),
                ),
            ],
          ),
        );
      },
    );
  }
}
