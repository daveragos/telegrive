import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format/formatters.dart';
import '../core/widgets/brand_mark.dart';
import '../core/widgets/selection_bar.dart';
import '../features/files/presentation/drop_to_upload.dart';
import '../features/files/presentation/file_actions.dart';
import '../features/transfers/data/transfer_queue.dart';
import '../infrastructure/database/app_database.dart' show TransferOrigin;
import 'router.dart';
import 'theme/tokens.dart';

/// A place the sidebar opens: one of the shell's three tabs, or a page a
/// phone reaches from Home or Settings.
@immutable
class SidebarPlace {
  const SidebarPlace(this.label, this.icon, this.selectedIcon, this.path, {this.branch});

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Where it is, and what it is current for: a page under it counts.
  final String path;

  /// The shell's tab it is, for Home, Files and Photos.
  final int? branch;

  bool isCurrentAt(String location) => location == path || location.startsWith('$path/');
}

/// How the sidebar moves between places without piling pages up: a tab is
/// switched to in the shell underneath, and another page opens alone over
/// it, so Back from it is always the shell.
abstract final class DesktopNavigation {
  /// The shell's tabs, set by the shell as it builds.
  static StatefulNavigationShell? shell;

  static const places = [
    SidebarPlace('Home', Icons.home_outlined, Icons.home_rounded, '/home', branch: 0),
    SidebarPlace('Files', Icons.folder_outlined, Icons.folder_rounded, '/files', branch: 1),
    SidebarPlace('Photos', Icons.photo_library_outlined, Icons.photo_library_rounded, '/photos', branch: 2),
  ];

  static const morePlaces = [
    SidebarPlace('Starred', Icons.star_outline_rounded, Icons.star_rounded, '/starred'),
    SidebarPlace('Recent', Icons.schedule_outlined, Icons.schedule_rounded, '/recent'),
    SidebarPlace('Albums', Icons.photo_album_outlined, Icons.photo_album_rounded, '/albums'),
    SidebarPlace('Available offline', Icons.offline_pin_outlined, Icons.offline_pin_rounded, '/offline'),
    SidebarPlace('Folder sync', Icons.drive_folder_upload_outlined, Icons.drive_folder_upload_rounded, '/backup'),
    SidebarPlace('Trash', Icons.delete_outline_rounded, Icons.delete_rounded, '/trash'),
  ];

  static const transfers =
      SidebarPlace('Transfers', Icons.swap_vert_rounded, Icons.swap_vert_rounded, '/transfers');
  static const settings =
      SidebarPlace('Settings', Icons.settings_outlined, Icons.settings_rounded, '/settings');

  /// Where the app is now: the page on top, which for one pushed over the
  /// shell is the last match, while the matches' own address stays the
  /// shell's.
  static String location(GoRouter router) {
    final configuration = router.routerDelegate.currentConfiguration;
    if (configuration.isEmpty) return configuration.uri.path;
    return router.state.uri.path;
  }

  /// Opens [place]. A tab tapped again while it is showing goes back to its
  /// start, as on a phone.
  static void go(BuildContext context, WidgetRef ref, SidebarPlace place) {
    final router = GoRouter.of(context);
    final root = rootNavigatorKey.currentState;
    if (root == null) return;
    ref.read(selectionActiveProvider.notifier).set(false);
    final onShell = !root.canPop();
    if (place.branch case final branch?) {
      final shell = DesktopNavigation.shell;
      root.popUntil((route) => route.isFirst);
      shell?.goBranch(branch, initialLocation: onShell && branch == shell.currentIndex);
      return;
    }
    if (place.isCurrentAt(location(router)) && location(router) == place.path) return;
    root.popUntil((route) => route.isFirst);
    router.push(place.path);
  }

  /// The folder New adds to: the one open in Files or in Private, or the
  /// top of the drive.
  static String? openFolder(GoRouter router) {
    final segments = Uri.parse(location(router)).pathSegments;
    if (segments.length == 2 && (segments.first == 'files' || segments.first == 'private')) {
      return segments[1];
    }
    return null;
  }
}

/// The app's left column on a computer: New, search, the three places a
/// phone has in its bottom bar, and the pages a phone reaches from Home and
/// Settings, each one click away. It sits beside every page but the
/// viewer, the player and document previews, which take the window.
class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({super.key});

  static const double width = 232;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final router = GoRouter.of(context);
    final moving = ref.watch(
      transferQueueProvider.select(
        (s) => s.active.where((t) => t.origin != TransferOrigin.backup).length,
      ),
    );
    return SizedBox(
      width: width,
      child: Material(
        color: colors.surface,
        child: ListenableBuilder(
          listenable: router.routerDelegate,
          builder: (context, _) {
            final here = DesktopNavigation.location(router);
            Widget row(SidebarPlace place, {int count = 0}) => _SidebarRow(
              place: place,
              selected: place.isCurrentAt(here),
              count: count,
              onTap: () => DesktopNavigation.go(context, ref, place),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m),
                  child: Row(
                    children: [
                      const BrandMark(size: 24),
                      const SizedBox(width: Space.s),
                      Text('Telegrive', style: context.text.titleMedium),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.m),
                  child: FilledButton.icon(
                    onPressed: () => FileActions.showCreateSheet(
                      context,
                      ref,
                      folderId: DesktopNavigation.openFolder(router),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New'),
                  ),
                ),
                const SizedBox(height: Space.s),
                _SidebarRow(
                  place: const SidebarPlace('Search', Icons.search_rounded, Icons.search_rounded, '/search'),
                  selected: here.startsWith('/search'),
                  onTap: () => DesktopNavigation.go(
                    context,
                    ref,
                    const SidebarPlace('Search', Icons.search_rounded, Icons.search_rounded, '/search'),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: Space.s),
                    children: [
                      for (final place in DesktopNavigation.places) row(place),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
                        child: Divider(height: 1, color: colors.line),
                      ),
                      for (final place in DesktopNavigation.morePlaces) row(place),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.line),
                const SizedBox(height: Space.xs),
                row(DesktopNavigation.transfers, count: moving),
                row(DesktopNavigation.settings),
                const SizedBox(height: Space.s),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({required this.place, required this.selected, required this.onTap, this.count = 0});

  final SidebarPlace place;
  final bool selected;
  final VoidCallback onTap;

  /// Shown at the end of the row while above nothing: transfers in flight.
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.accent : colors.text2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 1),
      child: Material(
        color: selected ? colors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.control),
          onTap: onTap,
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                const SizedBox(width: Space.m),
                Icon(selected ? place.selectedIcon : place.icon, size: 20, color: foreground),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    place.label,
                    style: context.text.bodyMedium?.copyWith(
                      color: selected ? colors.text : colors.text2,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count > 0)
                  Text(
                    Formatters.number(count),
                    style: context.text.labelSmall?.copyWith(
                      color: colors.text3,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                const SizedBox(width: Space.m),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A page with the sidebar beside it, on a computer, taking files dropped
/// from the system.
class DesktopFrame extends StatelessWidget {
  const DesktopFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const DesktopSidebar(),
        VerticalDivider(width: 1, thickness: 1, color: context.colors.line),
        Expanded(
          // Files dropped from the system go into the folder open, or the
          // top of the drive.
          child: DropToUpload(folderOf: DesktopNavigation.openFolder, child: child),
        ),
      ],
    );
  }
}
