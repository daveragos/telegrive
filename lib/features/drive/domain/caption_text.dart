import 'dart:convert';

import 'package:flutter/foundation.dart';

/// How a stretch of a caption is drawn in Telegram.
enum CaptionStyle {
  bold,
  spoiler,

  /// A quote Telegram folds to three lines until it is tapped.
  expandableQuote,
}

/// One styled stretch of a caption. [offset] and [length] count UTF-16
/// code units, which is how Telegram counts entity offsets and how Dart
/// indexes strings.
@immutable
class StyledRange {
  const StyledRange(this.style, this.offset, this.length);

  final CaptionStyle style;
  final int offset;
  final int length;

  @override
  bool operator ==(Object other) =>
      other is StyledRange &&
      other.style == style &&
      other.offset == offset &&
      other.length == length;

  @override
  int get hashCode => Object.hash(style, offset, length);

  @override
  String toString() => 'StyledRange($style, $offset, $length)';
}

/// Caption or message text with the stretches Telegram draws styled.
@immutable
class EncodedText {
  const EncodedText(this.text, {this.styles = const []});

  final String text;
  final List<StyledRange> styles;

  /// The text under the first stretch drawn in [style], or null when there
  /// is none.
  String? styled(CaptionStyle style) {
    for (final range in styles) {
      if (range.style == style) {
        return text.substring(range.offset, range.offset + range.length);
      }
    }
    return null;
  }
}

/// How a drive record reads in Telegram: a bold first line, an optional
/// line of hashtags, an optional line of notes, and the record's details
/// line folded into a quote under a spoiler.
///
/// ```text
/// Quarterly report.pdf                ← bold
/// #Invoices #starred                  ← tags, tappable in Telegram
/// Part 2 of 3                         ← notes
/// ┃ Telegrive details                 ← quote, folded to three lines
/// ┃ tgfile2;id=…;name=…;…             ← spoiler
/// ```
///
/// Everything above the quote is for people; only the details line is
/// read back, so the layout can change without touching the format.
abstract final class CaptionLayout {
  /// Telegram's caption limit without Premium. Captions keep to it even for
  /// Premium accounts, so an edit after Premium lapses still fits.
  static const int limit = 1024;

  /// What the quote says above the details line.
  static const String detailsLabel = 'Telegrive details';

  /// Longest first line. The details line keeps the full name either way.
  static const int _headLimit = 96;

  /// Builds the text. When it would run past [limit], the notes go first,
  /// then the tags, and then the first line is shortened; the details line
  /// is never cut.
  static EncodedText build({
    required String head,
    List<String> tags = const [],
    String tagSuffix = '',
    List<String> notes = const [],
    required String details,
  }) {
    var headLine = shorten(head, _headLimit);
    var tagLine = tags.isEmpty ? '' : '${tags.join(' ')}$tagSuffix';
    var noteLine = notes.join(' · ');

    int length() => [
      headLine,
      tagLine,
      noteLine,
      detailsLabel,
      details,
    ].where((line) => line.isNotEmpty).fold(-1, (sum, line) => sum + line.length + 1);

    if (length() > limit) noteLine = '';
    if (length() > limit) tagLine = '';
    if (length() > limit) {
      final room = headLine.length - (length() - limit);
      headLine = shorten(headLine, room < 2 ? 2 : room);
    }

    final text = StringBuffer();
    final styles = <StyledRange>[];
    int line(String content, [CaptionStyle? style]) {
      if (content.isEmpty) return text.length;
      if (text.isNotEmpty) text.write('\n');
      final start = text.length;
      if (style != null) styles.add(StyledRange(style, start, content.length));
      text.write(content);
      return start;
    }

    line(headLine, CaptionStyle.bold);
    line(tagLine);
    line(noteLine);
    final quoteStart = line(detailsLabel);
    line(details, CaptionStyle.spoiler);
    styles
      ..add(StyledRange(CaptionStyle.expandableQuote, quoteStart, text.length - quoteStart))
      // In text order, the outer of two stretches that start together first.
      ..sort((a, b) => a.offset != b.offset ? a.offset - b.offset : b.length - a.length);
    return EncodedText(text.toString(), styles: List.unmodifiable(styles));
  }

  /// [text] on one line and at most [max] UTF-16 units long, ending in "…"
  /// when it had to be cut. A cut never splits a surrogate pair.
  static String shorten(String text, int max) {
    final oneLine = text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (oneLine.length <= max) return oneLine;
    var end = max - 1;
    if (end > 0 && _isHighSurrogate(oneLine.codeUnitAt(end - 1))) end--;
    return '${oneLine.substring(0, end)}…';
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}

/// The hashtag a folder goes by in Telegram, made from its name: `Tax
/// returns 2026` is `#Tax_returns_2026`. Tapping it in Telegram lists the
/// folder's message and the files in it.
///
/// Telegram ends a hashtag at anything but a letter, a digit or `_`, and
/// wants one letter at least, so everything else becomes `_` and a name
/// with no letters is tagged `#folder_…`. Tags are for people only: the
/// drive goes by the folder's id, so two folders of the same name share a
/// tag, and files take a folder's new tag when their caption is next
/// written.
abstract final class FolderTag {
  static const int _longest = 48;

  static final RegExp _allowed = RegExp(r'[\p{L}\p{M}\p{Nd}_]', unicode: true);
  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);

  static String of(String name) {
    final slug = StringBuffer();
    for (final rune in name.runes) {
      final char = String.fromCharCode(rune);
      slug.write(_allowed.hasMatch(char) ? char : '_');
    }
    var tag = slug
        .toString()
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final runes = tag.runes.toList();
    if (runes.length > _longest) {
      tag = String.fromCharCodes(runes.take(_longest)).replaceAll(RegExp(r'_$'), '');
    }
    if (!_letter.hasMatch(tag)) tag = tag.isEmpty ? 'folder' : 'folder_$tag';
    return '#$tag';
  }
}

/// The details line every drive record carries: a kind word such as
/// `tgfile2`, then `key=value` fields split by `;`.
///
/// ```text
/// tgfile2;id=7f3c…;name=Quarterly report.pdf;type=application/pdf;size=123456;…
/// ```
///
/// Values are kept readable. Only what would break the line, or what
/// Telegram would turn into a hashtag, mention or cashtag inside it, is
/// written as `%` and the UTF-8 bytes in hex: `%` itself, `;`, `#`, `@`, `$`, line
/// breaks and other control characters, and the direction marks Telegram
/// strips from text. In a list, `,` separates the items.
abstract final class DetailsLine {
  /// [kind] followed by [fields] in the order given.
  static String write(String kind, List<MapEntry<String, String>> fields) {
    final line = StringBuffer(kind);
    for (final MapEntry(:key, :value) in fields) {
      line
        ..write(';')
        ..write(key)
        ..write('=')
        ..write(value);
    }
    return line.toString();
  }

  /// The fields of the last line of [text] that starts with [kind], as
  /// written, or null when there is none. A key written twice keeps its
  /// last value. [value] and [items] read what a field holds.
  static Map<String, String>? read(String kind, String text) {
    final lines = text.split('\n');
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line != kind && !line.startsWith('$kind;')) continue;
      return {
        for (final field in line.substring(kind.length).split(';'))
          if (field.indexOf('=') case final equals when equals > 0)
            field.substring(0, equals): field.substring(equals + 1),
      };
    }
    return null;
  }

  static String escape(String value, {bool inList = false}) {
    final out = StringBuffer();
    for (final rune in value.runes) {
      if (_mustEscape(rune) || (inList && rune == 0x2C)) {
        for (final byte in utf8.encode(String.fromCharCode(rune))) {
          out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      } else {
        out.writeCharCode(rune);
      }
    }
    return out.toString();
  }

  /// A field as [read] gave it, with its escapes undone, or null when one
  /// is malformed.
  static String? value(String written) {
    if (!written.contains('%')) return written;
    final out = StringBuffer();
    var i = 0;
    while (i < written.length) {
      final percent = written.indexOf('%', i);
      if (percent < 0) {
        out.write(written.substring(i));
        break;
      }
      out.write(written.substring(i, percent));
      final bytes = <int>[];
      var j = percent;
      while (j < written.length && written.codeUnitAt(j) == 0x25) {
        if (j + 3 > written.length) return null;
        final hex = written.substring(j + 1, j + 3);
        if (!_hexPair.hasMatch(hex)) return null;
        bytes.add(int.parse(hex, radix: 16));
        j += 3;
      }
      try {
        out.write(utf8.decode(bytes));
      } on FormatException {
        return null;
      }
      i = j;
    }
    return out.toString();
  }

  static final RegExp _hexPair = RegExp(r'^[0-9A-Fa-f]{2}$');

  /// [items] as one field, each escaped, `,` between them.
  static String list(List<String> items) =>
      items.map((item) => escape(item, inList: true)).join(',');

  /// The items of a field [list] wrote, or null when one is malformed.
  static List<String>? items(String written) {
    if (written.isEmpty) return const [];
    final items = <String>[];
    for (final item in written.split(',')) {
      final unescaped = value(item);
      if (unescaped == null) return null;
      items.add(unescaped);
    }
    return items;
  }

  static bool _mustEscape(int rune) =>
      rune < 0x20 ||
      rune == 0x7F ||
      rune == 0x25 || // %
      rune == 0x3B || // ;
      rune == 0x23 || // # would start a hashtag
      rune == 0x40 || // @ would start a mention
      rune == 0x24 || // $ would start a cashtag
      rune == 0x200E ||
      rune == 0x200F ||
      (rune >= 0x2028 && rune <= 0x202E) ||
      rune == 0x0333 ||
      rune == 0x033F ||
      rune == 0x030A ||
      rune == 0xFEFF;
}
