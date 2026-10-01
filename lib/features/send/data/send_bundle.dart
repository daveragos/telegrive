import 'package:flutter/foundation.dart';

import '../../drive/domain/drive_models.dart';

/// Files that arrive together in a chat, after a [header] line naming the
/// subfolder they came from. The sent folder's own files have no header.
@immutable
class SendGroup {
  const SendGroup({this.header, required this.files});

  /// The subfolder's path below the sent folder, such as 'Day 2 › Gondar'.
  final String? header;
  final List<DriveFile> files;
}

/// What a send puts in a chat, in order: groups of files, the headerless
/// one first and the rest by header, each file in name order or, for
/// photos, in the order they were taken.
@immutable
class SendBundle {
  const SendBundle(this.groups);

  /// [items] from DriveRepository.collectForSaving, grouped by the folders
  /// leading to each, which start with the sent folder's own name. With
  /// [stripTop], for a single folder sent on its own, that name is left
  /// out, so its own files go first without a header and each subfolder is
  /// named from inside it. With [byMoment], files go oldest first.
  static SendBundle fromItems(
    List<SaveItem> items, {
    bool stripTop = false,
    bool byMoment = false,
  }) {
    final byHeader = <String?, List<DriveFile>>{};
    for (final item in items) {
      final names = stripTop ? item.folders.skip(1) : item.folders;
      final header = names.isEmpty ? null : names.join(' › ');
      (byHeader[header] ??= []).add(item.file);
    }
    final headers = byHeader.keys.toList()
      ..sort((a, b) {
        if (a == null || b == null) return a == b ? 0 : (a == null ? -1 : 1);
        final order = a.toLowerCase().compareTo(b.toLowerCase());
        return order != 0 ? order : a.compareTo(b);
      });
    return SendBundle([
      for (final header in headers)
        SendGroup(
          header: header,
          files: _ordered(byHeader[header]!, byMoment: byMoment),
        ),
    ]);
  }

  /// [files] as one group with no header.
  static SendBundle fromFiles(List<DriveFile> files, {bool byMoment = false}) =>
      SendBundle([
        if (files.isNotEmpty)
          SendGroup(files: _ordered(files, byMoment: byMoment)),
      ]);

  final List<SendGroup> groups;

  int get fileCount => groups.fold(0, (sum, group) => sum + group.files.length);

  int get bytes => groups.fold(
    0,
    (sum, group) => group.files.fold(sum, (total, file) => total + file.size),
  );

  /// Whether any file is kept in parts, which arrive as numbered parts.
  bool get anySplit =>
      groups.any((group) => group.files.any((file) => file.isSplit));

  /// The first file to go, for a title that names it.
  DriveFile? get firstFile => groups.firstOrNull?.files.firstOrNull;

  static List<DriveFile> _ordered(
    List<DriveFile> files, {
    required bool byMoment,
  }) {
    int byName(DriveFile a, DriveFile b) {
      final order = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return order != 0 ? order : a.id.compareTo(b.id);
    }

    return [...files]..sort(
      byMoment
          ? (a, b) {
              final order = a.momentAt.compareTo(b.momentAt);
              return order != 0 ? order : byName(a, b);
            }
          : byName,
    );
  }
}
