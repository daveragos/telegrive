import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../photos/presentation/media_grid.dart';
import '../data/free_up_space.dart';

/// The photos and videos Free up space would delete with the window it
/// keeps, to look through before deciding. Nothing here can be selected;
/// a tap opens the photo on its own. Tiles show the phone's own copies,
/// so the grid fills at once, offline too.
class FreeUpPreviewScreen extends ConsumerStatefulWidget {
  const FreeUpPreviewScreen({super.key});

  @override
  ConsumerState<FreeUpPreviewScreen> createState() => _FreeUpPreviewScreenState();
}

class _FreeUpPreviewScreenState extends ConsumerState<FreeUpPreviewScreen> {
  /// The grid shares a selection with its screen; this one stays empty.
  final _selection = MediaSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidates = ref.watch(freeUpCandidatesProvider);
    final now = DateTime.now();
    final cutoff = ref.watch(freeUpKeepProvider).cutoff(now);
    final before = cutoff == null ? null : Formatters.date(cutoff, now: now);

    return Scaffold(
      appBar: AppBar(title: Text(before == null ? 'Everything backed up' : 'Before $before')),
      body: AsyncView(
        value: candidates,
        data: (freeable) => MediaGrid(
          files: freeable.files,
          selection: _selection,
          selectable: false,
          onOpen: (file) => context.push('/viewer/${file.id}'),
          header: [
            if (!freeable.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 0),
                  child: Text(
                    '${Formatters.count(freeable.count, 'item')} · '
                    '${Formatters.bytes(freeable.bytes)}',
                    style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                  ),
                ),
              ),
          ],
          empty: EmptyState(
            title: before == null ? 'Nothing to free up' : 'Nothing from before $before',
            compact: true,
          ),
        ),
      ),
    );
  }
}
