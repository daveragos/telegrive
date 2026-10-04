import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../drive/data/drive_repository.dart';
import '../../files/presentation/folder_picker.dart';
import '../data/phone_folders.dart';
import '../data/watched_folders.dart';

/// What the person settled on in a watched folder's sheet.
typedef _Choice = ({
  WatchFilter filter,
  bool subfolders,
  String? destinationId,
  bool includeExisting,
});

/// Adds a phone folder whose new files upload by themselves: Android's
/// folder picker first, where backing out ends it without a word, then the
/// sheet that says how many files are in it and what to send where. A
/// folder that is on the list already isn't added twice, and the access
/// to one that isn't added after all goes back to Android.
Future<void> showAddWatchedFolder(BuildContext context, WidgetRef ref) async {
  final folders = ref.read(phoneFoldersProvider);
  final controller = ref.read(watchedFoldersProvider.notifier);
  final PickedFolder? answer;
  try {
    answer = await folders.pick();
  } on PlatformException catch (e) {
    if (context.mounted) _pickFailed(context, e);
    return;
  }
  if (answer == null || !context.mounted) return;
  final picked = answer;
  final watched = ref.read(watchedFolderViewsProvider).value ?? const [];
  if (watched.any((view) => view.row.treeUri == picked.uri)) {
    showSnack(context, '${picked.name} is already on the list.');
    return;
  }
  final choice = await showModalBottomSheet<_Choice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _WatchedFolderSheet(uri: picked.uri, name: picked.name),
  );
  if (choice == null) {
    await folders.release(picked.uri);
    return;
  }
  try {
    await controller.add(
      picked,
      filter: choice.filter,
      subfolders: choice.subfolders,
      destinationId: choice.destinationId,
      includeExisting: choice.includeExisting,
    );
  } catch (e) {
    debugPrint('[Folders] ${picked.name}: $e');
    await folders.release(picked.uri);
    if (context.mounted) showSnack(context, 'Telegrive can\'t read ${picked.name}.');
  }
}

/// The settings of watched folder [view]: what it sends, its subfolders
/// and where its files go, with the way to stop uploading it.
Future<void> showWatchedFolderSheet(
  BuildContext context,
  WidgetRef ref,
  WatchedFolderView view,
) async {
  final controller = ref.read(watchedFoldersProvider.notifier);
  final choice = await showModalBottomSheet<_Choice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _WatchedFolderSheet(
      uri: view.row.treeUri,
      name: view.row.label,
      existing: view,
    ),
  );
  if (choice == null) return;
  await controller.update(
    view.row.id,
    filter: choice.filter,
    subfolders: choice.subfolders,
    destinationId: choice.destinationId,
  );
}

/// 'Choose again' on a folder Telegrive can't read: the picker
/// opens, and the folder picked takes its place.
Future<void> chooseWatchedFolderAgain(
  BuildContext context,
  WidgetRef ref,
  WatchedFolderView view,
) async {
  try {
    await ref.read(watchedFoldersProvider.notifier).reauthorize(view.row.id);
  } on PlatformException catch (e) {
    if (context.mounted) _pickFailed(context, e);
  }
}

void _pickFailed(BuildContext context, PlatformException e) => showSnack(
  context,
  e.code == 'not_persisted'
      ? 'Android didn\'t let Telegrive keep access to that folder.'
      : 'Couldn\'t open the folder picker.',
);

class _WatchedFolderSheet extends ConsumerStatefulWidget {
  const _WatchedFolderSheet({required this.uri, required this.name, this.existing});

  final String uri;
  final String name;

  /// The folder's settings as they stand; null while adding it.
  final WatchedFolderView? existing;

  @override
  ConsumerState<_WatchedFolderSheet> createState() => _WatchedFolderSheetState();
}

class _WatchedFolderSheetState extends ConsumerState<_WatchedFolderSheet> {
  static const _motion = Duration(milliseconds: 200);

  late WatchFilter _filter = widget.existing?.row.filter ?? WatchFilter.documents;
  late bool _subfolders = widget.existing?.row.subfolders ?? true;
  late String? _destinationId = widget.existing?.row.destinationId;
  late String _destination =
      widget.existing?.destinationLabel ?? '${WatchedFoldersController.rootFolder} › ${widget.name}';
  bool _includeExisting = true;

  /// Files can't hold the uploads loose, so picking it is turned down.
  bool _rootRefused = false;

  /// The folder's files, or null while they are being counted.
  List<PhoneDocument>? _files;
  bool _truncated = false;
  bool _unreadable = false;

  /// Bumped by each listing, so an answer that comes after a newer request
  /// is dropped.
  int _listing = 0;

  bool get _adding => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _list();
  }

  Future<void> _list() async {
    final listing = ++_listing;
    try {
      final result = await ref
          .read(phoneFoldersProvider)
          .list(widget.uri, recursive: _subfolders);
      if (!mounted || listing != _listing) return;
      setState(() {
        _files = result.files;
        _truncated = result.truncated;
      });
    } catch (e) {
      debugPrint('[Folders] ${widget.name}: $e');
      if (mounted && listing == _listing) setState(() => _unreadable = true);
    }
  }

  /// How many of the files the chosen filter sends, and their size.
  (int, int)? get _matching {
    final files = _files;
    if (files == null) return null;
    var count = 0;
    var bytes = 0;
    for (final doc in files) {
      if (!watchMatches(doc, _filter)) continue;
      count++;
      bytes += doc.size;
    }
    return (count, bytes);
  }

  Future<void> _changeDestination() async {
    final choice = await showFolderPicker(
      context,
      title: 'Upload to',
      actionLabel: 'Upload to',
      startIn: _destinationId,
    );
    if (choice == null || !mounted) return;
    final id = choice.folderId;
    if (id == null) {
      setState(() => _rootRefused = true);
      return;
    }
    final path = await ref.read(driveRepositoryProvider).pathTo(id);
    if (!mounted) return;
    setState(() {
      _rootRefused = false;
      _destinationId = id;
      _destination = path.isEmpty ? choice.name : path.map((f) => f.name).join(' › ');
    });
  }

  Future<void> _stop() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Stop uploading ${widget.name}?',
      message:
          'Files already uploaded stay in your drive. New files in '
          '${widget.name} won\'t be.',
      confirmLabel: 'Stop',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final controller = ref.read(watchedFoldersProvider.notifier);
    Navigator.pop(context);
    await controller.remove(widget.existing!.row.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final matching = _matching;
    final existingCount = matching?.$1 ?? 0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upload from ${widget.name}', style: context.text.titleMedium),
            const SizedBox(height: 2),
            AnimatedSize(
              duration: _motion,
              curve: Curves.easeOut,
              alignment: Alignment.topLeft,
              child: _meta(context, matching),
            ),
            const SizedBox(height: Space.l),
            Text('What to upload', style: context.text.labelMedium),
            RadioGroup<WatchFilter>(
              groupValue: _filter,
              onChanged: (value) => setState(() => _filter = value ?? _filter),
              child: Column(
                children: [
                  for (final filter in WatchFilter.values)
                    RadioListTile<WatchFilter>(
                      value: filter,
                      contentPadding: EdgeInsets.zero,
                      title: Text(filter.label),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include subfolders'),
              value: _subfolders,
              onChanged: (value) {
                setState(() {
                  _subfolders = value;
                  _files = null;
                  _unreadable = false;
                });
                _list();
              },
            ),
            const SizedBox(height: Space.s),
            Material(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(Radii.control),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                leading: Icon(Icons.folder_outlined, color: colors.text2),
                title: Text(_destination, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Drive folder'),
                trailing: const Text('Change'),
                onTap: _changeDestination,
              ),
            ),
            if (_rootRefused)
              Padding(
                padding: const EdgeInsets.only(top: Space.s),
                child: Text('Pick a folder inside Files.', style: context.text.bodySmall),
              ),
            AnimatedSize(
              duration: _motion,
              curve: Curves.easeOut,
              alignment: Alignment.topLeft,
              child: _adding && existingCount > 0
                  ? Padding(
                      padding: const EdgeInsets.only(top: Space.s),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          existingCount == 1
                              ? 'Upload the 1 file already there'
                              : 'Upload the ${Formatters.number(existingCount)} files already there',
                          style: const TextStyle(fontFeatures: tabularFigures),
                        ),
                        value: _includeExisting,
                        onChanged: (value) => setState(() => _includeExisting = value),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (!_adding) ...[
              const SizedBox(height: Space.s),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Stop uploading this folder',
                  style: context.text.bodyLarge?.copyWith(color: colors.danger),
                ),
                onTap: _stop,
              ),
            ],
            const SizedBox(height: Space.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: FilledButton(
                    onPressed: _adding && _unreadable
                        ? null
                        : () => Navigator.pop<_Choice>(context, (
                            filter: _filter,
                            subfolders: _subfolders,
                            destinationId: _destinationId,
                            includeExisting: _includeExisting,
                          )),
                    child: Text(_adding ? 'Start uploading' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The line under the title: a bar while the files are counted, then
  /// how many the filter sends and their size.
  Widget _meta(BuildContext context, (int, int)? matching) {
    if (_unreadable) {
      return Text('Telegrive can\'t read this folder.', style: context.text.bodyMedium);
    }
    if (matching == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Counting files…', style: context.text.bodyMedium),
          const SizedBox(height: Space.s),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: const LinearProgressIndicator(minHeight: 4),
          ),
        ],
      );
    }
    final (count, bytes) = matching;
    final tabular = context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [Formatters.count(count, 'file'), if (count > 0) Formatters.bytes(bytes)].join(' · '),
          style: tabular,
        ),
        if (_truncated)
          Text(
            'Only the first ${Formatters.number(PhoneFolders.listLimit)} files are checked.',
            style: context.text.bodySmall,
          ),
      ],
    );
  }
}

/// The filters in the words the sheet uses.
extension on WatchFilter {
  String get label => switch (this) {
    WatchFilter.documents => 'Documents and PDFs',
    WatchFilter.audio => 'Audio',
    WatchFilter.everything => 'Everything',
  };
}
