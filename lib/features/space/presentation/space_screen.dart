import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/file_style.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../infrastructure/database/app_database.dart' show FolderSize;
import '../../backup/data/free_up_space.dart';
import '../../backup/presentation/free_up_space_sheet.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/file_location.dart';
import '../../files/presentation/file_tiles.dart';
import '../../offline/data/offline_sync.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/phone_usage.dart';

/// Where the space goes. First the drive, which Telegram stores: its
/// biggest files, which can be moved or put in the trash from here, its
/// top-level folders and the trash. Then what Telegrive keeps on this
/// phone, in plain figures, with a Clear only where clearing loses nothing.
class SpaceScreen extends ConsumerStatefulWidget {
  const SpaceScreen({super.key, this.focusPhone = false});

  /// Opens at what this phone keeps rather than at the top.
  final bool focusPhone;

  @override
  ConsumerState<SpaceScreen> createState() => _SpaceScreenState();
}

class _SpaceScreenState extends ConsumerState<SpaceScreen> {
  /// Selected files among the largest, by id.
  final Set<String> _selected = {};
  final _phoneKey = GlobalKey();
  bool _focused = false;

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(DriveFile file) => setState(() {
    if (!_selected.remove(file.id)) _selected.add(file.id);
  });

  void _clearSelection() => setState(_selected.clear);

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(storageSummaryProvider);
    final largest = ref.watch(largestFilesProvider);
    final folders = ref.watch(folderSizesProvider);
    final files = largest.value ?? const <DriveFile>[];

    // Files that left the list, trashed or no longer among the biggest,
    // leave the selection too.
    if (largest.hasValue) _selected.retainWhere((id) => files.any((f) => f.id == id));
    // Once the drive's figures are in, nothing above this phone's grows any
    // more, so the jump lands where it should.
    if (widget.focusPhone && !_focused && summary.hasValue && largest.hasValue && folders.hasValue) {
      _focused = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final header = _phoneKey.currentContext;
        if (header != null) Scrollable.ensureVisible(header);
      });
    }

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: _selecting ? _selectionBar(files) : AppBar(title: const Text('Space')),
        // Built whole rather than as rows come into view, so it can open at
        // this phone's figures however long the lists above them are.
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: Space.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (summary.value case final summary?) _DriveTotal(summary: summary),
              const SectionHeader('Largest files'),
              _largestFiles(largest),
              if (folders.value case final rows? when rows.isNotEmpty) ...[
                const SectionHeader('By folder'),
                ListGroup(children: [for (final folder in rows) _FolderRow(folder: folder)]),
              ],
              const _TrashRow(),
              _OnThisPhone(headerKey: _phoneKey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _largestFiles(AsyncValue<List<DriveFile>> largest) {
    // Null until the folders are read; rows then say only their size.
    final byId = ref.watch(folderIndexProvider).value;
    return AsyncView<List<DriveFile>>(
      value: largest,
      loading: const Padding(
        padding: EdgeInsets.all(Space.x3),
        child: Center(child: CircularProgressIndicator()),
      ),
      data: (files) => files.isEmpty
          ? const EmptyState(
              title: 'Nothing here yet',
              message: 'Upload files and the biggest ones show up here.',
              compact: true,
            )
          : ListGroup(
              children: [
                for (final file in files)
                  FileListTile(
                    file: file,
                    subtitle: [
                      Formatters.bytes(file.size),
                      if (byId != null) locationOf(byId, file.folderId, fromRoot: true),
                    ].join(' · '),
                    selected: _selected.contains(file.id),
                    selecting: _selecting,
                    onTap: _selecting
                        ? () => _toggle(file)
                        : () => FileActions.open(context, ref, file),
                    onLongPress: () => _toggle(file),
                    onMore: () => FileActions.showFileSheet(context, ref, file),
                  ),
              ],
            ),
    );
  }

  PreferredSizeWidget _selectionBar(List<DriveFile> files) {
    final chosen = [
      for (final file in files)
        if (_selected.contains(file.id)) file,
    ];

    Future<void> then(Future<bool> action) async {
      if (await action && mounted) _clearSelection();
    }

    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
      leading: IconButton(
        onPressed: _clearSelection,
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Clear selection',
      ),
      title: Text(Formatters.number(chosen.length)),
      actions: [
        IconButton(
          onPressed: () => then(FileActions.move(context, ref, files: chosen)),
          icon: const Icon(Icons.drive_file_move_outline),
          tooltip: 'Move',
        ),
        IconButton(
          onPressed: () => then(FileActions.delete(context, ref, files: chosen)),
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: 'Move to Trash',
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// How big the drive is and how many files it holds, said once on top.
class _DriveTotal extends StatelessWidget {
  const _DriveTotal({required this.summary});

  final StorageSummary summary;

  @override
  Widget build(BuildContext context) {
    const figures = TextStyle(fontFeatures: tabularFigures);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${Formatters.bytes(summary.bytes)} in your drive',
            style: context.text.titleMedium?.merge(figures),
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${Formatters.count(summary.fileCount, 'file')} · '
            'Stored in Telegram, not on this phone.',
            style: context.text.bodyMedium?.merge(figures),
          ),
        ],
      ),
    );
  }
}

/// A top-level folder and everything below it, which opens it in Files.
/// The files in no folder open the root, where Files lists them.
class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folder});

  final FolderSize folder;

  @override
  Widget build(BuildContext context) {
    final id = folder.folderId;
    return ListTile(
      leading: id == null
          ? FileIconTile(style: FileStyle.forKind(FileKind.other))
          : const FolderIconTile(),
      title: Text(
        id == null ? 'Not in a folder' : folder.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${Formatters.count(folder.count, 'file')} · ${Formatters.bytes(folder.bytes)}',
        style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
      ),
      // Going rather than pushing, since Files is a place of its own.
      onTap: () => context.go(id == null ? '/files' : '/files/$id'),
    );
  }
}

/// What the trash holds, files inside trashed folders included, opening
/// Trash. Left out while the trash is empty.
class _TrashRow extends ConsumerWidget {
  const _TrashRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final totals = ref.watch(trashTotalsProvider).value;
    if (totals == null || totals.$1 == 0) return const SizedBox.shrink();
    final (count, bytes) = totals;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxl),
      child: ListGroup(
        children: [
          ListTile(
            title: const Text('Trash'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${Formatters.count(count, 'file')} · ${Formatters.bytes(bytes)}',
                  style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.text3),
              ],
            ),
            onTap: () => context.push('/trash'),
          ),
        ],
      ),
    );
  }
}

/// What Telegrive keeps on this phone, by what it is for. Only what comes
/// back by itself can be cleared here; what is kept on purpose says where
/// to change it.
class _OnThisPhone extends ConsumerWidget {
  const _OnThisPhone({required this.headerKey});

  /// On the group's heading, which Settings opens the screen at.
  final GlobalKey headerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(phoneUsageProvider);
    final offline = ref.watch(offlineUsageProvider);
    final freeable = ref.watch(freeableProvider).value;
    final keep = ref.watch(freeUpKeepProvider);
    final busy = ref.watch(transferQueueProvider.select((s) => s.activeCount)) > 0;
    final measured = usage.value;
    final failed = usage.hasError && measured == null;

    String? figure(int Function(PhoneUsage usage) of) => measured != null
        ? Formatters.bytes(of(measured))
        : failed
        ? null
        : 'Measuring';
    String about(String sentence) => failed ? 'Couldn\'t measure this.' : sentence;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'On this phone',
          key: headerKey,
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x3, Space.gutter, Space.s),
          trailing: _Figure(figure((u) => u.total)),
        ),
        ListGroup(
          children: [
            _UsageRow(
              title: 'Opened files',
              value: figure((u) => u.openedFiles),
              subtitle: busy
                  ? 'Available when transfers finish'
                  : about(
                      measured == null
                          ? 'Recently opened files. Older ones go first.'
                          : 'Keeps up to ${Formatters.bytes(measured.budget, decimals: 0)} '
                                'of recently opened files. Older ones go first.',
                    ),
              action: TextButton(
                onPressed: busy ? null : () => _clearOpenedFiles(context, ref),
                child: const Text('Clear'),
              ),
            ),
            _UsageRow(
              title: 'Thumbnails',
              value: figure((u) => u.thumbnails),
              subtitle: about('They come back as you scroll.'),
              action: TextButton(
                onPressed: () => FileActions.guarded(
                  context,
                  () => clearThumbnails(ref),
                  success: 'Thumbnails cleared',
                ),
                child: const Text('Clear'),
              ),
            ),
            if (measured != null && measured.leftovers > 0)
              _UsageRow(
                title: 'Leftovers',
                value: figure((u) => u.leftovers),
                subtitle: 'Copies from uploads that didn\'t finish. Safe to remove.',
                action: TextButton(
                  onPressed: () => FileActions.guarded(
                    context,
                    () => clearLeftovers(ref),
                    success: 'Leftovers cleared',
                  ),
                  child: const Text('Clear'),
                ),
              ),
            _UsageRow(
              title: 'Available offline',
              value: switch (offline) {
                AsyncValue(value: (_, final bytes)?) => Formatters.bytes(bytes),
                AsyncError() => null,
                _ => 'Measuring',
              },
              subtitle: offline.hasError && !offline.hasValue
                  ? 'Couldn\'t measure this.'
                  : 'Kept on purpose. Change it from a file\'s menu.',
            ),
            if (freeable != null && !freeable.isEmpty)
              _UsageRow(
                title: 'Backed-up photos',
                value: Formatters.bytes(freeable.bytes),
                subtitle: keep == KeepWindow.nothing
                    ? 'Safely in your drive.'
                    : 'Safely in your drive. Free up keeps the last ${keep.label}.',
                action: TextButton(
                  onPressed: () => showFreeUpSpace(context, ref),
                  child: const Text('Free up'),
                ),
              ),
            _UsageRow(
              title: 'Index and search',
              value: figure((u) => u.index),
              subtitle: about('Rebuilt from Telegram if needed.'),
            ),
            _UsageRow(
              title: 'Telegram\'s records',
              value: figure((u) => u.telegramDatabase),
              subtitle: about('Messages and settings Telegram keeps for your account.'),
            ),
          ],
        ),
      ],
    );
  }

  static Future<void> _clearOpenedFiles(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Clear opened files?',
      message: 'They download again when you open them. Your files stay in Telegram.',
      confirmLabel: 'Clear',
    );
    if (!ok || !context.mounted) return;
    await FileActions.guarded(
      context,
      () => clearOpenedFiles(ref),
      success: 'Opened files cleared',
    );
  }
}

/// One kind of thing this phone keeps: how much of it there is, what it is
/// for, and the action that frees it when there is one.
class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.title,
    required this.value,
    required this.subtitle,
    this.action,
  });

  final String title;

  /// The figure, or null when it couldn't be measured.
  final String? value;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.only(
        left: Space.gutter,
        right: action == null ? Space.gutter : Space.s,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Figure(value),
          if (action != null) ...[const SizedBox(width: Space.xs), action!],
        ],
      ),
    );
  }
}

/// A size that changes in place, easing to its new width.
class _Figure extends StatelessWidget {
  const _Figure(this.value);

  final String? value;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Text(
        value ?? '',
        style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
      ),
    );
  }
}
