import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../core/config/app_config.dart';
import '../core/platform/app_platform.dart';
import '../core/platform/desktop_input.dart';
import '../core/widgets/common.dart';
import '../features/drive/data/drive_sync.dart';
import '../features/files/data/browse_preferences.dart';
import '../features/files/presentation/file_actions.dart';
import '../features/files/presentation/phone_folder_upload.dart';
import '../features/settings/data/settings_providers.dart';
import '../infrastructure/storage/preferences.dart';
import 'app_phase.dart';
import 'desktop_sidebar.dart';
import 'desktop_tray.dart';
import 'router.dart';

/// The Mac's menu bar, as a Mac app has it: the app's own menu with
/// Settings, File for new folders and uploads, Edit, View, Go to every
/// place the sidebar has, Window and Help, each with the keys a Mac user
/// expects. Edit's commands go to the text field being typed in, or else
/// to the page: Select All selects a folder's items, and Undo takes back
/// what a snack offers to. Nothing on Windows and Linux, whose windows
/// have no menu bar; the pages' own keys serve there.
class DesktopMenuBar extends ConsumerWidget {
  const DesktopMenuBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppPlatform.isDesktop || !Platform.isMacOS) return child;
    final open = ref.watch(appPhaseProvider) == AppPhase.ready;
    final viewMode = ref.watch(browsePreferencesProvider.select((b) => b.viewMode));
    final version = ref.watch(appVersionProvider).value ?? '';

    /// [run] over the app's pages, once a drive is open.
    VoidCallback? whenOpen(void Function(BuildContext context) run) => !open
        ? null
        : () {
            final context = rootNavigatorKey.currentState?.overlay?.context;
            if (context != null && context.mounted) run(context);
          };
    VoidCallback? place(SidebarPlace place) => whenOpen((context) {
      unawaited(DesktopTray.show());
      DesktopNavigation.go(context, ref, place);
    });
    String? folder(BuildContext context) => DesktopNavigation.openFolder(GoRouter.of(context));

    PlatformMenuItem item(String label, VoidCallback? onSelected, [MenuSerializableShortcut? shortcut]) =>
        PlatformMenuItem(label: label, onSelected: onSelected, shortcut: shortcut);
    SingleActivator keys(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, meta: true, shift: shift);
    List<PlatformMenuItem> provided(List<PlatformProvidedMenuItemType> types) => [
      for (final type in types)
        if (PlatformProvidedMenuItem.hasMenu(type)) PlatformProvidedMenuItem(type: type),
    ];

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: AppConfig.appName,
          menus: [
            PlatformMenuItemGroup(members: provided([PlatformProvidedMenuItemType.about])),
            PlatformMenuItemGroup(
              members: [item('Settings…', place(DesktopNavigation.settings), keys(LogicalKeyboardKey.comma))],
            ),
            PlatformMenuItemGroup(members: provided([PlatformProvidedMenuItemType.servicesSubmenu])),
            PlatformMenuItemGroup(
              members: provided([
                PlatformProvidedMenuItemType.hide,
                PlatformProvidedMenuItemType.hideOtherApplications,
                PlatformProvidedMenuItemType.showAllApplications,
              ]),
            ),
            PlatformMenuItemGroup(members: provided([PlatformProvidedMenuItemType.quit])),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItemGroup(
              members: [
                item(
                  'New Folder',
                  whenOpen((context) => unawaited(FileActions.createFolder(context, ref, parentId: folder(context)))),
                  keys(LogicalKeyboardKey.keyN, shift: true),
                ),
                item(
                  'Upload Files…',
                  whenOpen((context) => unawaited(FileActions.upload(context, ref, folderId: folder(context)))),
                  keys(LogicalKeyboardKey.keyO),
                ),
                item(
                  'Upload a Folder…',
                  whenOpen((context) => unawaited(PhoneFolderUpload.start(context, ref, folderId: folder(context)))),
                  keys(LogicalKeyboardKey.keyO, shift: true),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [item('Close Window', () => unawaited(windowManager.close()), keys(LogicalKeyboardKey.keyW))],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Edit',
          menus: [
            PlatformMenuItemGroup(
              members: [
                item('Undo', _undo, keys(LogicalKeyboardKey.keyZ)),
                item(
                  'Redo',
                  () => _invoke(const RedoTextIntent(SelectionChangedCause.keyboard)),
                  keys(LogicalKeyboardKey.keyZ, shift: true),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                item(
                  'Cut',
                  () => _invoke(const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard)),
                  keys(LogicalKeyboardKey.keyX),
                ),
                item('Copy', () => _invoke(CopySelectionTextIntent.copy), keys(LogicalKeyboardKey.keyC)),
                item(
                  'Paste',
                  () => _invoke(const PasteTextIntent(SelectionChangedCause.keyboard)),
                  keys(LogicalKeyboardKey.keyV),
                ),
                item(
                  'Select All',
                  () => _invoke(const SelectAllTextIntent(SelectionChangedCause.keyboard)),
                  keys(LogicalKeyboardKey.keyA),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItemGroup(
              members: [
                item(
                  viewMode == ViewMode.list ? 'Show as Grid' : 'Show as List',
                  open ? ref.read(browsePreferencesProvider.notifier).toggleViewMode : null,
                ),
                item(
                  'Refresh',
                  open ? () => ref.read(driveSyncProvider.notifier).refresh() : null,
                  keys(LogicalKeyboardKey.keyR),
                ),
              ],
            ),
            PlatformMenuItemGroup(members: provided([PlatformProvidedMenuItemType.toggleFullScreen])),
          ],
        ),
        PlatformMenu(
          label: 'Go',
          menus: [
            PlatformMenuItemGroup(
              members: [item('Back', open ? _back : null, keys(LogicalKeyboardKey.bracketLeft))],
            ),
            PlatformMenuItemGroup(
              members: [
                for (final (index, p) in DesktopNavigation.places.indexed)
                  item(p.label, place(p), keys(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + index))),
                for (final p in DesktopNavigation.morePlaces) item(p.label, place(p)),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                item(DesktopNavigation.transfers.label, place(DesktopNavigation.transfers)),
                item(
                  'Search',
                  whenOpen((context) {
                    if (!_invoke(const FindIntent())) DesktopNavigation.go(context, ref, DesktopNavigation.search);
                  }),
                  keys(LogicalKeyboardKey.keyF),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Window',
          menus: [
            PlatformMenuItemGroup(
              members: provided([
                PlatformProvidedMenuItemType.minimizeWindow,
                PlatformProvidedMenuItemType.zoomWindow,
              ]),
            ),
            PlatformMenuItemGroup(members: provided([PlatformProvidedMenuItemType.arrangeWindowsInFront])),
          ],
        ),
        PlatformMenu(
          label: 'Help',
          menus: [
            PlatformMenuItemGroup(
              members: [
                item('Telegrive Help', () => unawaited(launchUrl(AppConfig.website))),
                item('Report a Problem…', () => unawaited(launchUrl(AppConfig.problemReport(version)))),
              ],
            ),
          ],
        ),
      ],
      child: child,
    );
  }

  /// Hands [intent] to whatever has the keys, the text field being typed in
  /// or the page around it, and says whether one took it.
  static bool _invoke(Intent intent) {
    final context = primaryFocus?.context;
    if (context == null || !context.mounted) return false;
    final run = Actions.handler(context, intent);
    run?.call();
    return run != null;
  }

  /// Undo in the text being typed, or else what a snack offers to undo.
  static void _undo() {
    if (!_invoke(const UndoTextIntent(SelectionChangedCause.keyboard))) PendingUndo.undo();
  }

  /// Back from the page on top, a folder inside Files included.
  static void _back() {
    final context = primaryFocus?.context;
    final navigator = (context != null && context.mounted ? Navigator.maybeOf(context) : null) ??
        rootNavigatorKey.currentState;
    unawaited(navigator?.maybePop());
  }
}
