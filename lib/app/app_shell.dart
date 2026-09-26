import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format/formatters.dart';
import '../core/widgets/common.dart';
import '../features/backup/data/backup_controller.dart';
import '../features/backup/presentation/backup_prompt.dart';
import '../features/transfers/data/transfer_queue.dart';
import '../infrastructure/database/app_database.dart' show TransferKind, TransferOrigin;
import 'launch_action.dart';
import 'theme/tokens.dart';

/// Three places to be: Home, Files, Photos. Transfers is not a place, it is
/// something happening, so it shows as a line above the bar while it
/// happens. Settings sits under the avatar on Home.
///
/// The shell is also the first screen of an open drive, so it asks the
/// one-time "back up your photos?" question and acts on a tapped backup
/// notification.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const int _photosBranch = 2;

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.folder_outlined, Icons.folder_rounded, 'Files'),
    (Icons.photo_library_outlined, Icons.photo_library_rounded, 'Photos'),
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

    final colors = context.colors;
    // Backup has its own home on the Photos tab; the strip is for things the
    // person started.
    final manualActive = ref.watch(
      transferQueueProvider.select((s) => s.activeCount - s.backupActive.length),
    );
    final backingUp = ref.watch(backupControllerProvider.select((b) => b.isWorking));
    final wide = MediaQuery.sizeOf(context).width >= 840;

    Widget icon(IconData data, int index) =>
        index == _photosBranch && backingUp ? Badge(child: Icon(data)) : Icon(data);

    final body = Column(
      children: [
        Expanded(child: shell),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          // Home already lists what is moving in its Activity group.
          child: manualActive > 0 && shell.currentIndex != 0
              ? const _TransferStrip()
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
            VerticalDivider(width: 1, color: colors.line),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.line)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final (index, (outline, filled, label)) in _destinations.indexed)
              NavigationDestination(
                icon: icon(outline, index),
                selectedIcon: icon(filled, index),
                label: label,
              ),
          ],
        ),
      ),
    );
  }
}

/// "Uploading 2 files · 41% · 8.3 MB/s" above the bar, opening Transfers.
class _TransferStrip extends ConsumerWidget {
  const _TransferStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
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

    final title = [
      if (uploads > 0) 'Uploading ${Formatters.count(uploads, 'file')}',
      if (downloads > 0) 'Downloading ${Formatters.count(downloads, 'file')}',
    ].join(', ');

    return Material(
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.line))),
        child: StatusLine(
          icon: uploads > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          color: colors.accent,
          text: title,
          detail: [
            '${(progress * 100).round()}%',
            if (speed > 0) Formatters.speed(speed),
          ].join(' · '),
          progress: progress > 0 ? progress : -1,
          onTap: () => context.push('/transfers'),
        ),
      ),
    );
  }
}
