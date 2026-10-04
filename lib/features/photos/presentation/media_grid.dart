import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/domain/drive_models.dart';
import 'media_grid_layout.dart';

/// Which photos are selected, shared by a grid and its app bar.
class MediaSelection extends ChangeNotifier {
  Set<String> _ids = {};

  /// Selecting was started from a menu, before any photo was picked.
  bool _forced = false;

  Set<String> get ids => Set.unmodifiable(_ids);
  bool get active => _forced || _ids.isNotEmpty;
  int get length => _ids.length;
  bool contains(String id) => _ids.contains(id);

  /// Starts selecting with nothing picked yet, as Select photos does.
  void begin() {
    if (_forced) return;
    _forced = true;
    notifyListeners();
  }

  void toggle(String id) {
    _ids.contains(id) ? _ids.remove(id) : _ids.add(id);
    notifyListeners();
  }

  void replace(Set<String> ids) {
    if (setEquals(ids, _ids)) return;
    _ids = {...ids};
    notifyListeners();
  }

  void clear() {
    if (!active) return;
    _forced = false;
    _ids = {};
    notifyListeners();
  }

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
/// edges), pinch to make tiles bigger or smaller. A long grid has a handle
/// at its right edge that jumps between months, and a month's title selects
/// or clears all of it, starting a selection when there is none.
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

  /// The months and each photo's place within its month, worked out again
  /// only when the grid is handed a new list of files, so selecting, and
  /// dragging to select, never cuts 20,000 photos into months again.
  late List<MonthSection> _sections;
  late Map<String, int> _indexInSection;

  /// How far the slivers above the first month reach, as laid out.
  double _leading = 0;

  // Drag to select.
  int? _anchor;

  /// The tile the drag last reached, so each new one ticks once.
  int? _lastIndex;
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
    _layOutMonths();
    widget.selection.addListener(_changed);
    _scroll.addListener(_checkNearEnd);
  }

  @override
  void didUpdateWidget(MediaGrid old) {
    super.didUpdateWidget(old);
    if (!identical(old.files, widget.files)) _layOutMonths();
    if (old.selection != widget.selection) {
      old.selection.removeListener(_changed);
      widget.selection.addListener(_changed);
    }
  }

  void _layOutMonths() {
    _sections = monthSections(widget.files);
    _indexInSection = {
      for (final section in _sections)
        for (final (index, file) in section.files.indexed) file.id: index,
    };
  }

  /// Where the tile keyed [key] sits in [section] of the latest list, so a
  /// tile keeps its element, and the picture it has loaded, when photos
  /// arrive ahead of it. Null for one that isn't in this month.
  int? _tileIndex(MonthSection section, Key key) {
    if (key is! ValueKey<String>) return null;
    final index = _indexInSection[key.value];
    if (index == null || index >= section.files.length) return null;
    return section.files[index].id == key.value ? index : null;
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

  /// The markers under [global]: a tile's index, and the scrubber's strip
  /// when it lies over the tile.
  List<Object?> _marksAt(Offset global) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, global, View.of(context).viewId);
    return [
      for (final entry in result.path)
        if (entry.target case final RenderMetaData target) target.metaData,
    ];
  }

  int? _indexAt(Offset global) => _marksAt(global).whereType<_TileIndex>().firstOrNull?.index;

  void _dragStart(LongPressStartDetails details) {
    if (!widget.selectable) return;
    final marks = _marksAt(details.globalPosition);
    // A finger resting on the scrubber is there to scrub, not to select.
    if (marks.any((mark) => mark is _ScrubStrip)) return;
    final index = marks.whereType<_TileIndex>().firstOrNull?.index;
    if (index == null) return;
    HapticFeedback.selectionClick();
    _anchor = index;
    _lastIndex = index;
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
    _lastIndex = null;
    _pointer = null;
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  void _selectRunTo(int index) {
    if (index != _lastIndex) {
      _lastIndex = index;
      HapticFeedback.selectionClick();
    }
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
  // Months

  void _toggleMonth(MonthSection month) {
    HapticFeedback.selectionClick();
    widget.selection.replace(toggleMonth(widget.selection.ids, month));
  }

  /// Keeps the laid-out height of [MediaGrid.header], which can change with
  /// what it shows. Layout is where it is known, so it lands a frame later.
  void _noteLeading(double extent) {
    if (extent == _leading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && extent != _leading) setState(() => _leading = extent);
    });
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final columns = ref.watch(photoColumnsProvider);
    final titleStyle = context.text.titleSmall!;
    // Every header is exactly this tall, at any text size, so the
    // scrubber's arithmetic and the laid-out grid never disagree.
    final headerHeight =
        Space.xxl +
        MediaQuery.textScalerOf(context).scale(titleStyle.fontSize!) * titleStyle.height! +
        Space.s;
    final sections = _sections;
    final selected = _selecting ? widget.selection.ids : const <String>{};
    // A page that doesn't fill the screen leaves nothing to scroll.
    if (widget.onNearEnd != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkNearEnd());
    }

    /// The scrolling grid, its tiles [tileSize] across.
    Widget scrollView(double tileSize) {
      final slivers = <Widget>[...widget.header];
      if (widget.files.isEmpty && widget.empty != null) {
        slivers.add(SliverFillRemaining(hasScrollBody: false, child: widget.empty));
      }
      for (final (index, section) in sections.indexed) {
        final header = SliverToBoxAdapter(
          child: _MonthHeader(
            title: section.title,
            height: headerHeight,
            selecting: _selecting,
            allSelected: _selecting && section.allSelected(selected),
            onTap: _selecting || widget.selectable ? () => _toggleMonth(section) : null,
          ),
        );
        slivers
          ..add(
            index == 0
                ? SliverLayoutBuilder(
                    builder: (context, constraints) {
                      _noteLeading(constraints.precedingScrollExtent);
                      return header;
                    },
                  )
                : header,
          )
          ..add(
            SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: GridLayout.spacing,
                crossAxisSpacing: GridLayout.spacing,
              ),
              itemCount: section.files.length,
              findChildIndexCallback: (key) => _tileIndex(section, key),
              itemBuilder: (context, i) {
                final file = section.files[i];
                return MetaData(
                  key: ValueKey(file.id),
                  metaData: _TileIndex(section.start + i),
                  behavior: HitTestBehavior.opaque,
                  child: _MediaTile(
                    file: file,
                    side: tileSize,
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
      return scroll;
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = GridLayout(
              columns: columns,
              width: constraints.maxWidth,
              headerHeight: headerHeight,
              leading: _leading,
              sections: sections,
            );
            return Stack(
              children: [
                scrollView(layout.tileSize),
                // Worth a handle only when the grid runs past two screens.
                if (sections.isNotEmpty && layout.total > constraints.maxHeight * 2)
                  _DateScrubber(controller: _scroll, layout: layout, height: constraints.maxHeight),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Marks a tile for drag selection's hit test.
class _TileIndex {
  const _TileIndex(this.index);

  final int index;
}

/// Marks the scrubber's strip for drag selection's hit test.
class _ScrubStrip {
  const _ScrubStrip();
}

/// A month's title over its photos. Tapping it selects or clears the whole
/// month, and starts a selection when there is none. While selecting, its
/// circle is filled only when all of the month is selected.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.title,
    required this.height,
    required this.selecting,
    required this.allSelected,
    required this.onTap,
  });

  final String title;
  final double height;
  final bool selecting;
  final bool allSelected;

  /// Null where the grid can't select.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxl, Space.gutter, Space.s),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                child: !selecting
                    ? const SizedBox.shrink()
                    : allSelected
                    ? Icon(Icons.check_circle_rounded, size: 22, color: colors.accent)
                    : Icon(Icons.radio_button_unchecked_rounded, size: 22, color: colors.text3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin handle at the grid's right edge. It shows while the grid scrolls
/// and for a second after; dragging it moves the grid with the finger,
/// names the month under it, and on release settles on that month's
/// header. Hidden, it lets touches through, so the edge scrolls as usual.
class _DateScrubber extends StatefulWidget {
  const _DateScrubber({required this.controller, required this.layout, required this.height});

  final ScrollController controller;
  final GridLayout layout;

  /// The grid's height, the length the handle travels plus its own.
  final double height;

  @override
  State<_DateScrubber> createState() => _DateScrubberState();
}

class _DateScrubberState extends State<_DateScrubber> {
  static const _thumbHeight = 40.0;
  static const _fade = Duration(milliseconds: 150);

  bool _visible = false;
  bool _dragging = false;

  /// A finger is on the strip, so the handle stays until it lifts.
  bool _held = false;

  /// The month level with the handle, named by the label while dragging.
  int _month = 0;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(_DateScrubber old) {
    super.didUpdateWidget(old);
    // Fewer months than a moment ago, as when photos leave the grid.
    _month = math.min(_month, widget.layout.sections.length - 1);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrolled);
    _hide?.cancel();
    super.dispose();
  }

  void _scrolled() {
    setState(() => _visible = true);
    if (!_held) _hideLater();
  }

  void _hideLater() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _hold(bool held) {
    _held = held;
    if (held) {
      _hide?.cancel();
    } else if (!_dragging) {
      _hideLater();
    }
  }

  double get _track => math.max(0, widget.height - _thumbHeight);

  /// The grid's scroll position, once the grid has been laid out.
  ScrollPosition? get _position {
    if (!widget.controller.hasClients) return null;
    final position = widget.controller.position;
    return position.hasContentDimensions ? position : null;
  }

  /// Moves the grid so the handle's middle sits under the finger at [dy].
  /// The grid is then scrolled the same fraction of its way as the handle,
  /// so the photos level with the handle are that fraction down the whole
  /// grid, and their month is the one the label names.
  void _jumpTo(double dy) {
    final position = _position;
    if (position == null) return;
    final fraction = _track == 0 ? 0.0 : ((dy - _thumbHeight / 2) / _track).clamp(0.0, 1.0);
    final extent = position.maxScrollExtent;
    position.jumpTo(fraction * extent);
    setState(() => _month = widget.layout.sectionAt(fraction * (extent + widget.height)));
  }

  void _dragStart(DragStartDetails details) {
    setState(() => _dragging = true);
    _jumpTo(details.localPosition.dy);
  }

  void _dragUpdate(DragUpdateDetails details) {
    final before = _month;
    _jumpTo(details.localPosition.dy);
    if (_month != before) HapticFeedback.selectionClick();
  }

  void _dragEnd(DragEndDetails _) {
    // Settle on the month the label named, with its header at the top. The
    // first month goes to the very top, so whatever sits above it shows too.
    if (_position case final position?) {
      position.jumpTo(
        _month == 0 ? 0 : math.min(widget.layout.offsets[_month], position.maxScrollExtent),
      );
    }
    setState(() => _dragging = false);
    _hideLater();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shown = _visible || _dragging;
    final position = _position;
    final fraction = position == null || position.maxScrollExtent <= 0
        ? 0.0
        : (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);
    final top = fraction * _track;

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 32,
            child: IgnorePointer(
              ignoring: !shown,
              // Translucent all the way down: a drag here is the
              // scrubber's, while a tap still reaches the tile beneath.
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _hold(true),
                onPointerUp: (_) => _hold(false),
                onPointerCancel: (_) => _hold(false),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: _dragStart,
                  onVerticalDragUpdate: _dragUpdate,
                  onVerticalDragEnd: _dragEnd,
                  child: const MetaData(
                    metaData: _ScrubStrip(),
                    behavior: HitTestBehavior.translucent,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: top,
            width: 4,
            height: _thumbHeight,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: shown ? 1 : 0,
                duration: _fade,
                curve: Curves.easeOut,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 8 + 4 + 12,
            top: top + _thumbHeight / 2,
            child: IgnorePointer(
              child: FractionalTranslation(
                translation: const Offset(0, -0.5),
                child: AnimatedOpacity(
                  opacity: _dragging ? 1 : 0,
                  duration: _fade,
                  curve: Curves.easeOut,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.line),
                      borderRadius: BorderRadius.circular(Radii.control),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.s, horizontal: Space.m),
                      child: Text(
                        widget.layout.sections[_month].title,
                        style: context.text.titleSmall,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.file,
    required this.side,
    required this.selecting,
    required this.selected,
    required this.onTap,
  });

  final DriveFile file;

  /// The tile's side, which the picture is decoded for even while a
  /// selected tile draws it smaller.
  final double side;
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
                child: FileThumbnail(file: file, expand: true, radius: 0, size: side),
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
