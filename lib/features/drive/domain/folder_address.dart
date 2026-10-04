import 'drive_models.dart';

/// A folder named in a forward comment or a caption: `Wedding`,
/// `Taxes/2026`, or `#Taxes/2026` to make the folders that aren't there.
class FolderAddress {
  const FolderAddress._(this.segments, {required this.create});

  /// The folder names from the root down, as written.
  final List<String> segments;

  /// The address began with `#`, so missing folders are to be made.
  final bool create;

  /// How long a folder name may be, the same as the drive's own limit.
  static const int _longestName = 128;

  /// Reads [text] as an address, or null when it can't be one: empty, more
  /// than one line, longer than a folder name may be, or nothing left once
  /// the `#` and the slashes are taken away.
  static FolderAddress? parse(String text) {
    var clean = text.trim();
    if (clean.isEmpty || clean.contains('\n') || clean.length > _longestName) {
      return null;
    }
    final create = clean.startsWith('#');
    if (create) clean = clean.substring(1);
    final segments = [
      for (final part in clean.split('/'))
        if (part.trim() case final name when name.isNotEmpty) name,
    ];
    if (segments.isEmpty) return null;
    if (segments.any((name) => name.length > _longestName)) return null;
    return FolderAddress._(segments, create: create);
  }

  /// The id of the folder this address names among [folders], which are the
  /// ones the drive shows: the path walked from the root, each name matched
  /// regardless of case, or, for a single name that isn't at the root and
  /// isn't to be made, the one folder anywhere with that name. Null when
  /// there is no such folder, or more than one could be meant.
  String? resolve(List<DriveFolder> folders) {
    String? parentId;
    var found = true;
    for (final name in segments) {
      final match = folders.where((f) => f.parentId == parentId && _sameName(f.name, name));
      if (match.isEmpty) {
        found = false;
        break;
      }
      parentId = match.first.id;
    }
    if (found) return parentId;
    if (segments.length != 1 || create) return null;
    final anywhere = folders.where((f) => _sameName(f.name, segments.single));
    return anywhere.length == 1 ? anywhere.single.id : null;
  }

  static bool _sameName(String a, String b) => a.toLowerCase() == b.toLowerCase();
}
