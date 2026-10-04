import 'package:intl/intl.dart';

import '../../../app/theme/tokens.dart';
import '../../drive/domain/drive_models.dart';

/// One month of the photo grid: its header's title and its photos.
class MonthSection {
  const MonthSection({required this.title, required this.files, required this.start});

  /// As the header spells it: 'This month', 'August', 'August 2024'.
  final String title;
  final List<DriveFile> files;

  /// Where the month's first photo sits in the whole grid's list, so a tile
  /// knows its place for drag selection.
  final int start;

  /// Whether every photo of the month is among [selected].
  bool allSelected(Set<String> selected) => files.every((f) => selected.contains(f.id));
}

final _monthName = DateFormat.MMMM();
final _monthAndYear = DateFormat.yMMMM();

/// [files], newest first, cut into months by [DriveFile.momentAt]. The
/// current month is 'This month', others this year go by their name, and
/// earlier ones carry the year.
List<MonthSection> monthSections(List<DriveFile> files, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final sections = <MonthSection>[];
  for (final (index, file) in files.indexed) {
    final moment = file.momentAt;
    final title = moment.year == today.year && moment.month == today.month
        ? 'This month'
        : moment.year == today.year
        ? _monthName.format(moment)
        : _monthAndYear.format(moment);
    if (sections.isEmpty || sections.last.title != title) {
      sections.add(MonthSection(title: title, files: [], start: index));
    }
    sections.last.files.add(file);
  }
  return sections;
}

/// [selected] with every photo of [month] added, or with all of them taken
/// out when the whole month was already selected. One tap on a month means
/// the same wherever it is offered.
Set<String> toggleMonth(Set<String> selected, MonthSection month) {
  final ids = [for (final f in month.files) f.id];
  return month.allSelected(selected)
      ? ({...selected}..removeAll(ids))
      : ({...selected}..addAll(ids));
}

/// Where each month starts in the scrolling grid, worked out from the same
/// numbers the grid lays itself out with: square tiles [columns] across
/// [width] with 2 px between them, a header of [headerHeight] above each
/// month, and [leading] for whatever sits above the first month. The date
/// scrubber jumps by it and names the month at any offset without the grid
/// having built that far.
class GridLayout {
  GridLayout({
    required this.columns,
    required this.width,
    required this.headerHeight,
    required this.leading,
    required this.sections,
  }) : tileSize = (width - (columns - 1) * spacing) / columns;

  /// The gap between tiles, across and down.
  static const double spacing = 2;

  final int columns;
  final double width;
  final double headerHeight;
  final double leading;
  final List<MonthSection> sections;
  final double tileSize;

  /// The scroll offset of each month's header, in [sections] order.
  late final List<double> offsets = _headerOffsets();

  /// How far the grid scrolls in all, to the space kept below its last row.
  /// A screen's footer slivers come on top of it.
  late final double total =
      (sections.isEmpty
          ? leading
          : offsets.last + headerHeight + extentOf(sections.last.files.length)) +
      Space.x3;

  /// The height of [count] tiles in rows of [columns].
  double extentOf(int count) {
    final rows = (count / columns).ceil();
    return rows * (tileSize + spacing) - spacing;
  }

  List<double> _headerOffsets() {
    final offsets = <double>[];
    var at = leading;
    for (final section in sections) {
      offsets.add(at);
      at += headerHeight + extentOf(section.files.length);
    }
    return List.unmodifiable(offsets);
  }

  /// The month showing at the top when the grid is scrolled to [offset]:
  /// the last one whose header starts at or above it, or the first month
  /// while the slivers above it are still in view.
  int sectionAt(double offset) {
    var low = 0;
    var high = offsets.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (offsets[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}
