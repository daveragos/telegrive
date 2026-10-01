import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_tiles.dart';
import '../../files/presentation/folder_picker.dart';
import '../../photos/presentation/media_grid.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/domain/transfer_error.dart';
import '../data/chat_media.dart';

/// The files in one Telegram chat, to pick and save into a drive folder.
/// Telegram copies each one into the channel itself, so nothing is
/// downloaded or uploaded, and the copies keep the messages' dates. The
/// screen is always selecting: a tap picks a file.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({
    super.key,
    required this.chatId,
    required this.title,
    this.folderId,
    this.photos = false,
  });

  final int chatId;

  /// The chat's name.
  final String title;

  /// Where the copies go until another folder is picked; null for the root.
  final String? folderId;

  /// Opened from Photos: it starts on photos and videos, and saves them into
  /// a folder named after the chat inside 'From Telegram', which is made
  /// only when they are saved.
  final bool photos;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  late ImportFilter _filter = widget.photos ? ImportFilter.media : ImportFilter.documents;

  /// What is picked, by preview id, under every filter: a pick stays when
  /// the person looks at another kind of file.
  final _selection = MediaSelection();

  /// Every file listed so far, by preview id, so picks made under another
  /// filter can still be saved.
  final Map<String, ChatItem> _seen = {};

  final _scroll = ScrollController();

  late String? _folderId = widget.folderId;

  /// A folder to make when the files are saved, until another is picked.
  late List<String>? _newPath = widget.photos ? ['From Telegram', widget.title] : null;

  /// The kind of file Select all is reading every page of.
  ImportFilter? _loadingAll;
  bool _saving = false;

  ({int chatId, ImportFilter filter}) get _source => (chatId: widget.chatId, filter: _filter);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_checkNearEnd);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _selection.dispose();
    super.dispose();
  }

  void _checkNearEnd() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 800) _loadMore();
  }

  /// The next page, unless a failed one waits for Try again.
  void _loadMore() {
    final media = ref.read(chatMediaProvider(_source)).value;
    if (media == null || media.complete || media.pageError != null) return;
    ref.read(chatMediaProvider(_source).notifier).loadMore();
  }

  /// Keeps reading while what is listed doesn't reach past the screen: a
  /// short page, or one whose files were all left out, leaves nothing to
  /// scroll. The grid looks after itself.
  void _fill() {
    if (!mounted) return;
    final media = ref.read(chatMediaProvider(_source)).value;
    if (media == null) return;
    if (media.items.isEmpty) {
      _loadMore();
    } else if (_filter != ImportFilter.media) {
      _checkNearEnd();
    }
  }

  void _retryPage() => ref.read(chatMediaProvider(_source).notifier).loadMore();

  /// Picks every file of the kind on screen, reading the pages not yet in
  /// first, up to [ChatMedia.selectAllCap].
  Future<void> _selectAll() async {
    final source = _source;
    setState(() => _loadingAll = source.filter);
    final media = await ref.read(chatMediaProvider(source).notifier).loadAll();
    if (!mounted) return;
    setState(() => _loadingAll = null);
    if (media == null || source != _source) return;
    final items = media.items.take(ChatMedia.selectAllCap).toList();
    for (final item in items) {
      _seen[item.preview.id] = item;
    }
    _selection.replace({..._selection.ids, for (final item in items) item.preview.id});
    final capped =
        media.items.length > ChatMedia.selectAllCap || (!media.complete && media.pageError == null);
    if (capped) {
      showSnack(context, 'Selected the newest ${Formatters.number(ChatMedia.selectAllCap)}');
    }
  }

  Future<void> _pickFolder() async {
    final choice = await showFolderPicker(context, title: 'Save to', startIn: _folderId);
    if (choice == null || !mounted) return;
    setState(() {
      _folderId = choice.folderId;
      _newPath = null;
    });
  }

  /// Queues a copy of each of [picked] into the chosen folder, making it
  /// first when it is new, then leaves.
  Future<void> _save(List<ChatItem> picked, {required String into}) async {
    setState(() => _saving = true);
    final repository = ref.read(driveRepositoryProvider);
    final queue = ref.read(transferQueueProvider.notifier);
    // The snack and its View outlast this screen.
    final router = GoRouter.of(context);
    final lasting = Navigator.of(context, rootNavigator: true).context;
    final int queued;
    try {
      final folderId = switch (_newPath) {
        final path? => await repository.ensureFolderPath(path),
        null => _folderId,
      };
      queued = await queue.enqueueCopies([
        for (final item in picked)
          CopyRequest(
            chatId: widget.chatId,
            messageId: item.messageId,
            name: item.name,
            mimeType: item.mimeType,
            size: item.size,
            date: item.date,
          ),
      ], folderId: folderId);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, describeTransferError(e));
      }
      return;
    }
    if (!mounted) return;
    context.pop();
    if (!lasting.mounted) return;
    showSnack(
      lasting,
      queued == 0
          ? 'These are already being saved'
          : 'Saving ${Formatters.count(queued, 'file')} to $into',
      actionLabel: 'View',
      onAction: () => router.push('/transfers'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(chatMediaProvider(_source));
    final crumbs = ref.watch(breadcrumbsProvider(_folderId)).value;
    final state = media.value;
    if (state != null) {
      for (final item in state.items) {
        _seen[item.preview.id] = item;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _fill());
    }

    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        final picked = [for (final id in _selection.ids) ?_seen[id]];
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _selection.active ? '${Formatters.number(_selection.length)} selected' : widget.title,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (state != null && state.items.isNotEmpty)
                TextButton(
                  onPressed: _loadingAll != null || _saving ? null : _selectAll,
                  child: const Text('Select all'),
                ),
              const SizedBox(width: Space.s),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _filters(),
              if (state != null && state.totalCount > 0) _status(state),
              Expanded(child: _content(media)),
            ],
          ),
          bottomNavigationBar: _bottomBar(picked, crumbs),
        );
      },
    );
  }

  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, Space.m),
      child: Row(
        children: [
          for (final (index, filter) in ImportFilter.values.indexed) ...[
            if (index > 0) const SizedBox(width: Space.s),
            ChoiceChip(
              label: Text(filter.label),
              selected: _filter == filter,
              showCheckmark: false,
              onSelected: (_) => setState(() => _filter = filter),
            ),
          ],
        ],
      ),
    );
  }

  /// How many there are, newest first, and how many are left out and why.
  Widget _status(ChatMediaState state) {
    final count = Formatters.count(state.totalCount, _filter.noun, _filter.nouns);
    final text = _loadingAll == _filter
        ? 'Loading $count…'
        : [
            '$count, newest first',
            if (state.hiddenSaved > 0)
              '${Formatters.number(state.hiddenSaved)} already in your drive',
            if (state.hiddenProtected > 0)
              '${Formatters.number(state.hiddenProtected)} can\'t be saved',
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.s),
      child: Text(text, style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures)),
    );
  }

  Widget _content(AsyncValue<ChatMediaState> media) {
    if (media.value case final state?) return _files(state);
    if (media.hasError) {
      return EmptyState(
        title: 'This chat didn\'t load',
        message: describeTransferError(media.error),
        action: TextButton(
          onPressed: () => ref.invalidate(chatMediaProvider(_source)),
          child: const Text('Try again'),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  Widget _files(ChatMediaState state) {
    if (state.items.isEmpty) {
      if (state.pageError case final error?) {
        return EmptyState(
          title: 'This chat didn\'t load',
          message: error,
          action: TextButton(onPressed: _retryPage, child: const Text('Try again')),
        );
      }
      if (!state.complete) return const Center(child: CircularProgressIndicator());
      final others = [
        for (final filter in ImportFilter.values)
          if (filter != _filter) filter.label,
      ].join(' or ');
      final hidden = state.hiddenSaved + state.hiddenProtected;
      return EmptyState(
        title: hidden == 0 ? _filter.emptyTitle : 'Nothing new to save here',
        message: 'Try $others.',
        compact: true,
      );
    }

    if (_filter == ImportFilter.media) {
      return MediaGrid(
        files: [for (final item in state.items) item.preview],
        selection: _selection,
        alwaysSelecting: true,
        onOpen: (_) {},
        onNearEnd: _loadMore,
        header: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 0),
              child: Text(
                'Photos sent as photos are Telegram\'s compressed copies. '
                'Files sent as documents come across intact.',
                style: context.text.bodySmall,
              ),
            ),
          ),
        ],
        footer: [if (!state.complete) SliverToBoxAdapter(child: _end(state))],
      );
    }

    return ListView.builder(
      key: ValueKey(_filter),
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: Space.l),
      itemCount: state.items.length + (state.complete ? 0 : 1),
      itemBuilder: (context, i) {
        if (i == state.items.length) return _end(state);
        final item = state.items[i];
        final id = item.preview.id;
        return FileListTile(
          file: item.preview,
          subtitle: '${Formatters.bytes(item.size)} · ${Formatters.date(item.date)}',
          selecting: true,
          selected: _selection.contains(id),
          onTap: () => _selection.toggle(id),
        );
      },
    );
  }

  /// The foot of a list with more to come: a spinner while the next page
  /// loads, or why it didn't.
  Widget _end(ChatMediaState state) {
    if (state.pageError case final error?) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.s, Space.s),
        child: Row(
          children: [
            Expanded(child: Text(error, style: context.text.bodySmall)),
            TextButton(onPressed: _retryPage, child: const Text('Try again')),
          ],
        ),
      );
    }
    return const SizedBox(
      height: 44,
      child: Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  /// Where the files go, and the button that saves them. [crumbs] is the
  /// path to the chosen folder, null while it loads.
  Widget _bottomBar(List<ChatItem> picked, List<DriveFolder>? crumbs) {
    final colors = context.colors;
    final String destination;
    final String into;
    if (_newPath case final path?) {
      destination = path.join(' › ');
      into = path.last;
    } else if (crumbs == null || crumbs.isEmpty) {
      destination = _folderId == null || crumbs != null ? 'My Drive' : '';
      into = destination;
    } else {
      destination = crumbs.map((folder) => folder.name).join(' › ');
      into = crumbs.last.name;
    }
    final bytes = picked.fold<int>(0, (sum, item) => sum + item.size);

    return Material(
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.line))),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _saving ? null : _pickFolder,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.m, Space.m),
                  child: Row(
                    children: [
                      Icon(Icons.folder_outlined, color: colors.text2),
                      const SizedBox(width: Space.m),
                      Text('Save to', style: context.text.bodyMedium),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: Text(
                          destination,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall,
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: colors.text3),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.m),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: picked.isEmpty || _saving
                        ? null
                        : () => _save(picked, into: into),
                    child: Text(
                      picked.isEmpty
                          ? 'Save'
                          : 'Save ${Formatters.count(picked.length, 'file')} · '
                                '${Formatters.bytes(bytes)}',
                      style: const TextStyle(fontFeatures: tabularFigures),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
