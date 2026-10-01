import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format/formatters.dart';
import '../core/widgets/common.dart';
import '../features/backup/data/backup_controller.dart';
import '../features/backup/presentation/backup_prompt.dart';
import '../features/capture/data/device_capture.dart';
import '../features/drive/data/telegram_wait.dart';
import '../features/files/data/bulk_edits.dart';
import '../features/offline/data/offline_sync.dart';
import '../features/search/data/content_indexer.dart';
import '../features/share/data/recent_destinations.dart';
import '../features/share/data/share_intake.dart';
import '../features/share/presentation/share_sheet.dart';
import '../features/transfers/data/transfer_queue.dart';
import '../features/transfers/domain/transfer_wait.dart';
import '../features/trash/data/pending_deletes.dart';
import '../infrastructure/database/app_database.dart' show TransferKind, TransferOrigin;
import 'launch_action.dart';
import 'theme/tokens.dart';

/// Three places to be: Home, Files, Photos. Transfers is not a place, it is
/// something happening, so it shows as a line above the bar while it
/// happens, and so does a big change to many items. Settings sits under the
/// avatar on Home.
///
/// The shell is also the first screen of an open drive, so it asks the
/// one-time "back up your photos?" question and acts on a tapped
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
    // Asked now, so the New sheet has its answer before the first tap and
    // never grows while it is open.
    ref.read(captureSupportProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(pendingLaunchActionProvider);
      if (ref.read(shareIntakeProvider).isNotEmpty) {
        showShareSheet(context, ref);
      } else if (pending != null) {
        _carryOut(pending);
      } else {
        maybeAskToBackUp(context, ref);
      }
    });
  }

  void _carryOut(LaunchAction? action) {
    if (action == null) return;
    ref.read(pendingLaunchActionProvider.notifier).set(null);
    switch (action) {
      case LaunchAction.backup:
        _go(_photosBranch);
        ref.read(backupControllerProvider.notifier).schedule(immediate: true);
      case LaunchAction.transfers:
        // Over Home rather than in its place, so back lands on Home.
        context.push('/transfers');
    }
  }

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    ref.listen<LaunchAction?>(
      pendingLaunchActionProvider,
      (_, action) => _carryOut(action),
    );
    // Keeps pinned files and folders on the phone, and reads photos and
    // documents for search, while the drive is open.
    ref.watch(offlineSyncProvider);
    ref.watch(contentIndexerProvider);
    // Keeps the recent folders, and their targets in the system share
    // sheet, following the drive while it is open, without rebuilding the
    // shell when they change.
    ref.listen(recentDestinationsProvider, (_, _) {});
    // Files shared in from another app, whether it was open or not.
    ref.listen<List<SharedFile>>(shareIntakeProvider, (previous, next) {
      if (next.isNotEmpty && (previous == null || previous.isEmpty)) {
        showShareSheet(context, ref);
      }
    });
    // A delete for good runs after its Undo has had its time, often once
    // the screen that asked for it is gone, so a failure is said here.
    ref.listen<DeleteFailure?>(
      pendingDeletesProvider.select((s) => s.lastFailure),
      (previous, next) {
        if (next != null && next != previous) showSnack(context, next.message);
      },
    );

    final colors = context.colors;
    // Backup has its own home on the Photos tab; the strip is for things the
    // person started.
    final manualActive = ref.watch(
      transferQueueProvider.select((s) => s.activeCount - s.backupActive.length),
    );
    final backingUp = ref.watch(backupControllerProvider.select((b) => b.isWorking));
    // A bulk change wins the one line there is.
    final showBulk = _bulkLineShows(ref);
    final wide = MediaQuery.sizeOf(context).width >= 840;

    Widget icon(IconData data, int index) =>
        index == _photosBranch && backingUp ? Badge(child: Icon(data)) : Icon(data);

    final body = Column(
      children: [
        Expanded(child: shell),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          // Home already lists what is moving in its Activity group, but
          // not bulk changes.
          child: showBulk
              ? const _BulkStrip()
              : manualActive > 0 && shell.currentIndex != 0
              ? const _TransferStrip()
              : const SizedBox(width: double.infinity),
        ),
      ],
    );

    final Widget scaffold;
    if (wide) {
      scaffold = Scaffold(
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
    } else {
      scaffold = _narrow(body, icon);
    }

    // Back never closes the app by surprise: from another tab it goes Home,
    // and on Home it asks for a second press.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: scaffold,
    );
  }

  /// Running for two seconds after a first back press on Home.
  Timer? _exitWindow;

  void _back() {
    if (shell.currentIndex != 0) {
      _go(0);
      return;
    }
    if (_exitWindow?.isActive ?? false) {
      SystemNavigator.pop();
      return;
    }
    _exitWindow = Timer(const Duration(seconds: 2), () {});
    showSnack(context, 'Press back again to exit');
  }

  @override
  void dispose() {
    _exitWindow?.cancel();
    super.dispose();
  }

  Widget _narrow(Widget body, Widget Function(IconData, int) icon) {
    final colors = context.colors;
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

/// "Uploading 2 files · 41% · 8.3 MB/s" above the bar, opening Transfers,
/// or "Saving 68 files from Telegram · 12 of 80 saved" while only copies
/// from chats are being made. When everything in it is sitting out a short
/// Telegram wait, the line counts down to the next try instead, with the
/// bar gone grey; when it all waits for the network, the line says so, grey
/// too. Transfers waiting for Wi-Fi aren't in flight, so they aren't counted
/// here.
class _TransferStrip extends ConsumerWidget {
  const _TransferStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final state = ref.watch(transferQueueProvider);
    final active = state.active
        .where((t) => t.origin != TransferOrigin.backup)
        .toList();
    // Copies from chats send nothing from the phone, so they aren't counted
    // as uploads, and having no bytes to follow, on their own they are
    // counted by file.
    final copies = active.where((t) => t.origin == TransferOrigin.fromChat).length;
    final uploads = active.where((t) => t.kind == TransferKind.upload).length - copies;
    final downloads = active.length - uploads - copies;
    final onlyCopies = copies > 0 && copies == active.length;
    final copied = state.copyCount;
    final progress = onlyCopies
        ? copied.saved / copied.total
        : TransfersState.byteProgress(active);
    final speed = active.fold<double>(0, (sum, t) => sum + t.bytesPerSecond);

    final title = [
      if (uploads > 0) 'Uploading ${Formatters.count(uploads, 'file')}',
      if (downloads > 0) 'Downloading ${Formatters.count(downloads, 'file')}',
      if (copies > 0) 'Saving ${Formatters.count(copies, 'file')} from Telegram',
    ].join(', ');
    final waits = [
      for (final item in active)
        if (item.wait case WaitingForTelegram(:final until)) until,
    ];
    final resumesAt = waits.isEmpty || waits.length < active.length
        ? null
        : waits.reduce((a, b) => a.isBefore(b) ? a : b);
    final offline = active.isNotEmpty && active.every((t) => t.wait is WaitingForNetwork);
    final percent = '${(progress * 100).round()}%';

    Widget line(String detail, {required bool waiting}) => StatusLine(
      icon: uploads > 0
          ? Icons.arrow_upward_rounded
          : downloads > 0
          ? Icons.arrow_downward_rounded
          : Icons.telegram,
      color: waiting ? null : colors.accent,
      text: title,
      detail: detail,
      progress: waiting || progress > 0 ? progress : -1,
      progressColor: waiting ? colors.text3 : null,
      onTap: () => context.push('/transfers'),
    );

    return Material(
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.line))),
        child: offline
            ? StatusLine(
                icon: Icons.cloud_off_rounded,
                text: 'Waiting for network',
                detail: '$title · $percent',
                progress: progress,
                progressColor: colors.text3,
                onTap: () => context.push('/transfers'),
              )
            : resumesAt == null
            ? line(
                onlyCopies
                    ? '${Formatters.number(copied.saved)} of '
                          '${Formatters.number(copied.total)} saved'
                    : [percent, if (speed > 0) Formatters.speed(speed)].join(' · '),
                waiting: false,
              )
            : Countdown(
                until: resumesAt,
                builder: (context, left) => line(
                  'Waiting for Telegram · ${Formatters.countdown(left)}',
                  waiting: true,
                ),
              ),
      ),
    );
  }
}

/// Whether the bulk line shows: a change to more than a handful of items
/// takes a while, and any change Telegram holds up says so.
bool _bulkLineShows(WidgetRef ref) {
  final big = ref.watch(bulkEditsProvider.select((b) => b != null && b.total > 20));
  final waiting = ref.watch(telegramWaitProvider.select((until) => until != null));
  return big || waiting;
}

/// Keeps track of the dialogs, sheets and menus open on the navigator it
/// observes, for [BulkStripOverShell], which sits outside that navigator.
class PopupRoutes extends NavigatorObserver with ChangeNotifier {
  final List<PopupRoute<Object?>> _open = [];

  /// The popup on top, or null when none is open. A navigator that goes
  /// away takes its popups with it without saying so, hence the check.
  PopupRoute<Object?>? get top => _open.where((route) => route.isActive).lastOrNull;

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) => _opened(route);

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) => _closed(route);

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) => _closed(route);

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    _closed(oldRoute);
    _opened(newRoute);
  }

  void _opened(Route<Object?>? route) {
    if (route is! PopupRoute<Object?>) return;
    _open.add(route);
    notifyListeners();
  }

  void _closed(Route<Object?>? route) {
    if (route is PopupRoute<Object?> && _open.remove(route)) notifyListeners();
  }
}

/// Screens opened over the shell, such as an album or the Trash, have no
/// bar for the bulk line to sit above, so it sits at their foot instead: a
/// change started there still shows how far it got, and can be stopped.
/// Wraps everything [router] shows; on the shell itself it stays out of the
/// way, since the shell has its own line.
///
/// Being outside the navigator, the line is out of reach of a dialog's or
/// sheet's barrier, so while one is open the line gets the same barrier
/// over it: dimmed like the screen, and a tap there does what a tap on the
/// barrier does, rather than stop the change behind the dialog's back.
class BulkStripOverShell extends ConsumerStatefulWidget {
  const BulkStripOverShell({
    super.key,
    required this.router,
    required this.popups,
    required this.child,
  });

  final GoRouter router;

  /// The popups open on [router]'s navigator, which must have it among its
  /// observers.
  final PopupRoutes popups;
  final Widget child;

  @override
  ConsumerState<BulkStripOverShell> createState() => _BulkStripOverShellState();
}

class _BulkStripOverShellState extends ConsumerState<BulkStripOverShell> {
  bool _overShell = false;

  /// The popup whose barrier covers the line: the one on top, or, while it
  /// closes, the one that was.
  PopupRoute<Object?>? _popup;

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onRoute);
    widget.popups.addListener(_onPopups);
  }

  @override
  void didUpdateWidget(BulkStripOverShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_onRoute);
      widget.router.routerDelegate.addListener(_onRoute);
    }
    if (oldWidget.popups != widget.popups) {
      oldWidget.popups.removeListener(_onPopups);
      widget.popups.addListener(_onPopups);
      _onPopups();
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRoute);
    widget.popups.removeListener(_onPopups);
    super.dispose();
  }

  void _onRoute() => _afterFrame(() {
    final matches = widget.router.routerDelegate.currentConfiguration.matches;
    final overShell = matches.lastOrNull is! ShellRouteMatch;
    if (overShell != _overShell) setState(() => _overShell = overShell);
  });

  void _onPopups() => _afterFrame(() {
    final popup = widget.popups.top;
    final closing = _popup;
    // A popup's barrier fades out over the screen as it closes, so the
    // line keeps its own until then rather than brighten ahead of the rest.
    if (popup == null && closing != null && !(closing.animation?.isDismissed ?? true)) {
      unawaited(
        closing.completed.whenComplete(
          () => _afterFrame(() {
            if (_popup == closing) setState(() => _popup = widget.popups.top);
          }),
        ),
      );
      return;
    }
    if (popup != _popup) setState(() => _popup = popup);
  });

  /// The router changes pages, and with them can drop popups, while the
  /// screens below this are building, so the line follows once that frame
  /// is done.
  void _afterFrame(VoidCallback update) {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) update();
      })
      ..ensureVisualUpdate();
  }

  /// [popup]'s barrier, as the navigator draws it over the screen. Its own
  /// dismissal would look for a navigator above the line and find none, so
  /// it closes [popup] directly, and only while [popup] is still on top.
  static Widget _barrier(PopupRoute<Object?> popup) {
    final color = popup.barrierColor ?? Colors.transparent;
    return AnimatedModalBarrier(
      color: (popup.animation ?? kAlwaysCompleteAnimation).drive(
        ColorTween(
          begin: color.withValues(alpha: 0),
          end: color,
        ).chain(CurveTween(curve: popup.barrierCurve)),
      ),
      dismissible: popup.barrierDismissible,
      semanticsLabel: popup.barrierLabel,
      barrierSemanticsDismissible: popup.semanticsDismissible,
      onDismiss: () {
        if (popup.isCurrent) popup.navigator?.maybePop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _overShell && _bulkLineShows(ref);
    final popup = _popup;
    return Column(
      children: [
        Expanded(
          // The line takes the bottom inset, as a bottom bar would.
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: visible,
            child: widget.child,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: visible
              ? Semantics(
                  // The barrier hides from screen readers whatever is painted
                  // before it, up to the nearest container. Without one here
                  // that takes in the dialog or sheet it sits under.
                  container: true,
                  child: Stack(
                    children: [
                      ColoredBox(
                        color: context.colors.surface,
                        child: const SafeArea(top: false, child: _BulkStrip()),
                      ),
                      if (popup != null) Positioned.fill(child: _barrier(popup)),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// "Moving 500 items · 212 of 500 done" above the bar, or at the foot of a
/// screen opened over it, with Stop. While Telegram holds the change up, the
/// line counts down to when it carries on, with the bar gone grey.
class _BulkStrip extends ConsumerWidget {
  const _BulkStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final bulk = ref.watch(bulkEditsProvider);
    final until = ref.watch(telegramWaitProvider);
    final edits = ref.read(bulkEditsProvider.notifier);

    Widget line(String detail, {required bool waiting}) => StatusLine(
      icon: bulk?.icon ?? Icons.hourglass_empty_rounded,
      color: waiting ? null : colors.accent,
      text: bulk?.label ?? 'Telegram asked us to wait',
      detail: detail,
      progress: bulk == null ? null : bulk.done / bulk.total,
      progressColor: waiting ? colors.text3 : null,
      trailing: TextButton(
        onPressed: (bulk?.stopping ?? false) ? null : edits.stop,
        child: const Text('Stop'),
      ),
    );

    return Material(
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.line))),
        child: until == null
            ? line(
                '${Formatters.number(bulk?.done ?? 0)} of '
                '${Formatters.number(bulk?.total ?? 0)} done',
                waiting: false,
              )
            : Countdown(
                until: until,
                builder: (context, left) => line(
                  bulk == null
                      ? 'Resuming in ${Formatters.countdown(left)}'
                      : 'Telegram asked us to wait · resuming in ${Formatters.countdown(left)}',
                  waiting: true,
                ),
              ),
      ),
    );
  }
}
