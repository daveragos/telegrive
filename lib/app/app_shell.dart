import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format/formatters.dart';
import '../features/backup/data/backup_controller.dart';
import '../features/backup/presentation/backup_prompt.dart';
import '../features/transfers/data/transfer_queue.dart';
import '../infrastructure/database/app_database.dart' show TransferKind, TransferOrigin;
import 'launch_action.dart';

/// Bottom navigation on phones, a rail on wide screens, and a live transfer
/// strip whenever something is moving and Transfers isn't already open.
///
/// It is also the first screen of an open drive, so it asks the one-time
/// "back up your photos?" question and acts on a tapped backup notification.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const int _photosBranch = 2;
  static const int _transfersBranch = 3;

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.folder_outlined, Icons.folder_rounded, 'Files'),
    (Icons.photo_library_outlined, Icons.photo_library_rounded, 'Photos'),
    (Icons.swap_vert_rounded, Icons.swap_vert_rounded, 'Transfers'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  StatefulNavigationShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(pendingLaunchActionProvider);
      if (pending != null) {
        _carryOut(pending);
      } else {
        maybeAskToBackUp(context, ref);
      }
    });
  }

  void _carryOut(LaunchAction? action) {
    if (action != LaunchAction.backup) return;
    ref.read(pendingLaunchActionProvider.notifier).set(null);
    _go(_photosBranch);
    ref.read(backupControllerProvider.notifier).schedule(immediate: true);
  }

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    ref.listen<LaunchAction?>(
      pendingLaunchActionProvider,
      (_, action) => _carryOut(action),
    );

    // Backup has its own home on the Photos tab; the badge and strip are
    // for things the person started.
    final manualActive = ref.watch(
      transferQueueProvider.select(
        (s) => s.activeCount - s.backupActive.length,
      ),
    );
    final backingUp = ref.watch(backupControllerProvider.select((b) => b.isWorking));
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final showStrip = manualActive > 0 && shell.currentIndex != _transfersBranch;

    Widget icon(IconData data, int index) {
      if (index == _transfersBranch && manualActive > 0) {
        return Badge.count(count: manualActive, child: Icon(data));
      }
      if (index == _photosBranch && backingUp) {
        return Badge(child: Icon(data));
      }
      return Icon(data);
    }

    final body = Column(
      children: [
        Expanded(child: shell),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: showStrip
              ? _TransferStrip(onTap: () => _go(_transfersBranch))
              : const SizedBox(width: double.infinity),
        ),
      ],
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.9,
              destinations: [
                for (final (index, (outline, filled, label)) in _destinations.indexed)
                  NavigationRailDestination(
                    icon: icon(outline, index),
                    selectedIcon: icon(filled, index),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _go,
        destinations: [
          for (final (index, (outline, filled, label)) in _destinations.indexed)
            NavigationDestination(
              icon: icon(outline, index),
              selectedIcon: icon(filled, index),
              label: label,
            ),
        ],
      ),
    );
  }
}

class _TransferStrip extends ConsumerWidget {
  const _TransferStrip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(transferQueueProvider);
    final active = state.active
        .where((t) => t.origin == TransferOrigin.manual)
        .toList();
    final totalBytes = active.fold<int>(0, (sum, t) => sum + t.row.totalBytes);
    final doneBytes = active.fold<int>(0, (sum, t) => sum + t.row.doneBytes);
    final progress = totalBytes == 0 ? 0.0 : doneBytes / totalBytes;
    final uploads = active.where((t) => t.kind == TransferKind.upload).length;
    final downloads = active.length - uploads;
    final speed = active.fold<double>(0, (sum, t) => sum + t.bytesPerSecond);
    final label = [
      if (uploads > 0) 'Uploading ${Formatters.count(uploads, 'file')}',
      if (downloads > 0) 'Downloading ${Formatters.count(downloads, 'file')}',
    ].join(' · ');

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 3,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              child: Row(
                children: [
                  Icon(
                    uploads > 0 ? Icons.cloud_upload_rounded : Icons.cloud_download_rounded,
                    color: scheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    [
                      '${(progress * 100).round()}%',
                      if (speed > 0) Formatters.speed(speed),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
