import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/domain/drive_models.dart';

/// Which photos are selected, shared by a grid and its app bar.
class MediaSelection extends ChangeNotifier {
  Set<String> _ids = {};

  Set<String> get ids => Set.unmodifiable(_ids);
  bool get active => _ids.isNotEmpty;
  int get length => _ids.length;
  bool contains(String id) => _ids.contains(id);

  void toggle(String id) {
    _ids.contains(id) ? _ids.remove(id) : _ids.add(id);
    notifyListeners();
  }

  void replace(Set<String> ids) {
    if (setEquals(ids, _ids)) return;
    _ids = {...ids};
    notifyListeners();
  }

  void clear() => replace(const {});

  /// Lets go of anything not among [files], so the count and the actions
  /// only ever cover what is on screen.
  void keepOnly(List<DriveFile> files) =>
      replace(_ids.intersection({for (final f in files) f.id}));

  /// The selected ones among [files], in their order.
  List<DriveFile> pick(List<DriveFile> files) =>
      files.where((f) => _ids.contains(f.id)).toList();
}

/// Columns across the photo grid, one of a few steps; pinching moves
/// between them and the choice is remembered.
class PhotoColumns extends Notifier<int> {
  static const steps = [2, 3, 4, 5, 7];

  @override
  int build() {
    final saved = ref.watch(preferencesProvider).photoColumns;
    return steps.contains(saved) ? saved : 4;
  }

  /// +1 for smaller tiles (more across), -1 for bigger.
  void step(int direction) {
    final index = (steps.indexOf(state) + direction).clamp(0, steps.length - 1);
    if (steps[index] == state) return;
    state = steps[index];
    ref.read(preferencesProvider).setPhotoColumns(state);
  }
}

final photoColumnsProvider = NotifierProvider<PhotoColumns, int>(PhotoColumns.new);

/// Photos and videos as square tiles grouped by month. Tap to open,
/// long-press to select and keep dragging to select a run (scrolling at the
/// edges), pinch to make tiles bigger or smaller.
class MediaGrid extends ConsumerStatefulWidget {
  const MediaGrid({
    super.key,
    required this.files,
    required this.selection,
    required this.onOpen,
    this.header = const [],
    this.footer = const [],
    this.onRefresh,
    this.empty,
    this.alwaysSelecting = false,
    this.selectable = true,
    this.onNearEnd,
  });

  /// Newest first; months are taken from [DriveFile.momentAt].
  final List<DriveFile> files;
  final MediaSelection selection;
  final void Function(DriveFile file) onOpen;

  /// Slivers above the grid.
  final List<Widget> header;

  /// Slivers below the grid.
  final List<Widget> footer;
  final Future<void> Function()? onRefresh;

  /// Shown instead of the grid when there are no files.
  final Widget? empty;

  /// Taps select rather than open, as when picking photos to add.
  final bool alwaysSelecting;

  /// Whether a long-press starts selecting. Off where the screen has no
  /// bar to act on a selection, as in Search.
  final bool selectable;

  /// Called when the grid is scrolled close to its end, or left there by
  /// a build, so a list read page by page can fetch its next page.
  final VoidCallback? onNearEnd;

  @override
  ConsumerState<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends ConsumerState<MediaGrid> {
  final _scroll = ScrollController();

  // Drag to select.
  int? _anchor;
  Set<String> _before = const {};
  bool _adding = true;
  Offset? _pointer;
  Timer? _autoScroll;
  double _autoSpeed = 0;

  // Pinch to zoom.
  final Map<int, Offset> _touches = {};
  double? _pinchFrom;

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_changed);
    _scroll.addListener(_checkNearEnd);
  }

  @override
  void didUpdateWidget(MediaGrid old) {
    super.didUpdateWidget(old);
    if (old.selection != widget.selection) {
      old.selection.removeListener(_changed);
      widget.selection.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_changed);
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _checkNearEnd() {
    final onNearEnd = widget.onNearEnd;
    if (onNearEnd == null || !mounted || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 800) onNearEnd();
  }

  bool get _selecting => widget.alwaysSelecting || widget.selection.active;

  // ---------------------------------------------------------------------------
  // Drag to select

  int? _indexAt(Offset global) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, global, View.of(context).viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is _TileIndex) {
        return (target.metaData as _TileIndex).index;
      }
    }
    return null;
  }

  void _dragStart(LongPressStartDetails details) {
    if (!widget.selectable) return;
    final index = _indexAt(details.globalPosition);
    if (index == null) return;
    HapticFeedback.selectionClick();
    _anchor = index;
    _before = widget.selection.ids;
    _adding = !widget.selection.contains(widget.files[index].id);
    _pointer = details.globalPosition;
    _selectRunTo(index);
  }

  void _dragUpdate(LongPressMoveUpdateDetails details) {
    if (_anchor == null) return;
    _pointer = details.globalPosition;
    final index = _indexAt(details.globalPosition);
    if (index != null) _selectRunTo(index);
    _scrollNearEdges(details.globalPosition);
  }

  void _dragEnd([LongPressEndDetails? _]) {
    _anchor = null;
    _pointer = null;
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  void _selectRunTo(int index) {
    final from = math.min(_anchor!, index);
    final to = math.max(_anchor!, index);
    final run = widget.files.sublist(from, to + 1).map((f) => f.id);
    final next = {..._before};
    _adding ? next.addAll(run) : next.removeAll(run);
    widget.selection.replace(next);
  }

  void _scrollNearEdges(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    const edge = 80.0;
    final y = box.globalToLocal(global).dy;
    final height = box.size.height;
    _autoSpeed = y < edge
        ? -(edge - y) / edge * 20
        : y > height - edge
        ? (y - (height - edge)) / edge * 20
        : 0;
    if (_autoSpeed == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final target = (position.pixels + _autoSpeed).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target == position.pixels) return;
      _scroll.jumpTo(target);
      final pointer = _pointer;
      if (pointer != null) {
        final index = _indexAt(pointer);
        if (index != null) _selectRunTo(index);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Pinch to zoom

  double _spread() {
    final points = _touches.values.take(2).toList();
    return (points[0] - points[1]).distance;
  }

  void _touchDown(PointerDownEvent event) {
    _touches[event.pointer] = event.position;
    if (_touches.length == 2) setState(() => _pinchFrom = _spread());
  }

  void _touchMove(PointerMoveEvent event) {
    if (!_touches.containsKey(event.pointer)) return;
    _touches[event.pointer] = event.position;
    final from = _pinchFrom;
    if (from == null || _touches.length < 2 || from == 0) return;
    final ratio = _spread() / from;
    if (ratio > 1.3 || ratio < 0.77) {
      ref.read(photoColumnsProvider.notifier).step(ratio > 1 ? -1 : 1);
      _pinchFrom = _spread();
    }
  }

  void _touchUp(PointerEvent event) {
    _touches.remove(event.pointer);
    if (_touches.length < 2 && _pinchFrom != null) setState(() => _pinchFrom = null);
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final columns = ref.watch(photoColumnsProvider);
    final slivers = <Widget>[...widget.header];
    // A page that doesn't fill the screen leaves nothing to scroll.
    if (widget.onNearEnd != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkNearEnd());
    }

    if (widget.files.isEmpty && widget.empty != null) {
      slivers.add(SliverFillRemaining(hasScrollBody: false, child: widget.empty));
    } else {
      var offset = 0;
      for (final section in _byMonth(widget.files)) {
        final start = offset;
        slivers
          ..add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxl, Space.gutter, Space.s),
                child: Text(section.title, style: context.text.titleSmall),
              ),
            ),
          )
          ..add(
            SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: section.files.length,
              itemBuilder: (context, i) {
                final file = section.files[i];
                return MetaData(
                  metaData: _TileIndex(start + i),
                  behavior: HitTestBehavior.opaque,
                  child: _MediaTile(
                    file: file,
                    selecting: _selecting,
                    selected: widget.selection.contains(file.id),
                    onTap: () => _selecting
                        ? widget.selection.toggle(file.id)
                        : widget.onOpen(file),
                  ),
                );
              },
            ),
          );
        offset += section.files.length;
      }
    }
    slivers
      ..addAll(widget.footer)
      ..add(const SliverToBoxAdapter(child: SizedBox(height: Space.x3)));

    Widget scroll = CustomScrollView(
      controller: _scroll,
      physics: _pinchFrom != null
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
    if (widget.onRefresh case final refresh?) {
      scroll = RefreshIndicator(onRefresh: refresh, child: scroll);
    }
    return Listener(
      onPointerDown: _touchDown,
      onPointerMove: _touchMove,
      onPointerUp: _touchUp,
      onPointerCancel: _touchUp,
      child: GestureDetector(
        onLongPressStart: _dragStart,
        onLongPressMoveUpdate: _dragUpdate,
        onLongPressEnd: _dragEnd,
        onLongPressCancel: _dragEnd,
        child: scroll,
      ),
    );
  }

  static List<({String title, List<DriveFile> files})> _byMonth(List<DriveFile> files) {
    final now = DateTime.now();
    final sections = <({String title, List<DriveFile> files})>[];
    for (final file in files) {
      final moment = file.momentAt;
      final title = moment.year == now.year && moment.month == now.month
          ? 'This month'
          : moment.year == now.year
          ? DateFormat.MMMM().format(moment)
          : DateFormat.yMMMM().format(moment);
      if (sections.isEmpty || sections.last.title != title) {
        sections.add((title: title, files: []));
      }
      sections.last.files.add(file);
    }
    return sections;
  }
}

/// Marks a tile for drag selection's hit test.
class _TileIndex {
  const _TileIndex(this.index);

  final int index;
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.file,
    required this.selecting,
    required this.selected,
    required this.onTap,
  });

  final DriveFile file;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const shadow = [Shadow(blurRadius: 4, color: Colors.black54)];
    return GestureDetector(
      onTap: onTap,
      child: ColoredBox(
        color: selected ? colors.accentSoft : Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedPadding(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              padding: EdgeInsets.all(selected ? 10 : 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(selected ? Radii.thumb : 0),
                child: FileThumbnail(file: file, expand: true, radius: 0, size: 40),
              ),
            ),
            if (file.starred && !selecting)
              const Positioned(
                right: 4,
                top: 4,
                child: Icon(Icons.star_rounded, size: 16, color: Colors.white, shadows: shadow),
              ),
            if (selecting)
              Positioned(
                left: 6,
                top: 6,
                child: selected
                    ? Icon(Icons.check_circle_rounded, size: 22, color: colors.accent)
                    : const Icon(
                        Icons.radio_button_unchecked_rounded,
                        size: 22,
                        color: Colors.white,
                        shadows: shadow,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
