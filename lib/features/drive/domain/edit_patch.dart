import 'package:flutter/foundation.dart';

import 'manifest.dart';

/// One field of a waiting change: the value Telegram had when the change
/// was made, and the value wanted.
@immutable
class EditField {
  const EditField(this.base, this.want);

  final Object? base;
  final Object? want;
}

/// A change made on this phone to one file, folder or album that is still
/// to reach Telegram, field by field, under the manifest's short keys: `n`
/// the name, `f` a file's folder, `p` a folder's parent, `st` the star,
/// `tr` when it went to the trash (epoch milliseconds cut to the whole
/// second, null once restored) and `al` the ids of a file's albums, sorted.
///
/// Each field keeps the value it started from as well as the one wanted,
/// so later edits fold into the same patch, an edit taken back leaves
/// nothing to send, and a field another device changed meanwhile can be
/// told apart from one that still says what this phone last saw.
@immutable
class EditPatch {
  const EditPatch(this.fields);

  /// The fields that differ, by short key. A patch never holds a field
  /// whose wanted value is the one it started from.
  final Map<String, EditField> fields;

  /// The fields that differ between [before] and [after].
  factory EditPatch.fileDiff(FileManifest before, FileManifest after) =>
      _diff(fileValues(before), fileValues(after));

  /// The fields that differ between [before] and [after].
  factory EditPatch.folderDiff(FolderManifest before, FolderManifest after) =>
      _diff(folderValues(before), folderValues(after));

  /// An album called [from] renamed [to].
  factory EditPatch.albumRename(String from, String to) => _diff({'n': from}, {'n': to});

  factory EditPatch.fromJson(Map<String, Object?> json) => EditPatch({
    for (final MapEntry(:key, :value) in json.entries)
      if (value case {'b': final base, 'w': final want})
        key: EditField(_read(key, base), _read(key, want)),
  });

  Map<String, Object?> toJson() => {
    for (final MapEntry(:key, value: field) in fields.entries)
      key: {'b': field.base, 'w': field.want},
  };

  bool get isEmpty => fields.isEmpty;

  /// What a patch can hold of a file's manifest.
  static Map<String, Object?> fileValues(FileManifest manifest) => {
    'n': manifest.name,
    'f': manifest.folderId,
    'st': manifest.starred,
    'tr': trashedValue(manifest.trashedAt),
    'al': _ids(manifest.albums),
  };

  /// What a patch can hold of a folder's manifest.
  static Map<String, Object?> folderValues(FolderManifest manifest) => {
    'n': manifest.name,
    'p': manifest.parentId,
    'st': manifest.starred,
    'tr': trashedValue(manifest.trashedAt),
  };

  /// A time of going to the trash as a patch holds it: epoch milliseconds
  /// cut to the whole second, which is all the index keeps. A change starts
  /// from what the index holds while a caption on Telegram carries the
  /// milliseconds, so both are cut the same way to compare equal.
  static int? trashedValue(DateTime? time) =>
      time == null ? null : time.millisecondsSinceEpoch ~/ 1000 * 1000;

  /// [manifest] with [values], keyed as [fileValues] keys them, in place of
  /// its own. A restore clears what replaced the file, as any restore does.
  static FileManifest applyToFile(FileManifest manifest, Map<String, Object?> values) {
    var next = manifest;
    for (final MapEntry(:key, :value) in values.entries) {
      next = switch (key) {
        'n' => next.copyWith(name: value! as String),
        'f' =>
          value == null
              ? next.copyWith(clearFolder: true)
              : next.copyWith(folderId: value as String),
        'st' => next.copyWith(starred: value! as bool),
        'tr' =>
          value == null ? next.copyWith(restore: true) : next.copyWith(trashedAt: _time(value)),
        'al' => next.copyWith(albums: _ids(value)),
        _ => next,
      };
    }
    return next;
  }

  /// [manifest] with [values], keyed as [folderValues] keys them, in place
  /// of its own, and [modifiedAt] when given.
  static FolderManifest applyToFolder(
    FolderManifest manifest,
    Map<String, Object?> values, {
    DateTime? modifiedAt,
  }) => FolderManifest(
    id: manifest.id,
    name: values.containsKey('n') ? values['n']! as String : manifest.name,
    parentId: values.containsKey('p') ? values['p'] as String? : manifest.parentId,
    createdAt: manifest.createdAt,
    modifiedAt: modifiedAt ?? manifest.modifiedAt,
    trashedAt: values.containsKey('tr') ? _time(values['tr']) : manifest.trashedAt,
    starred: values.containsKey('st') ? values['st']! as bool : manifest.starred,
    extra: manifest.extra,
  );

  /// This patch followed by [newer]: each field starts where this patch
  /// started it and ends where [newer] wants it. A field that ends where it
  /// started goes, so an edit and its Undo leave nothing to send.
  EditPatch then(EditPatch newer) => _settled({
    ...fields,
    for (final MapEntry(:key, value: field) in newer.fields.entries)
      key: EditField(fields.containsKey(key) ? fields[key]!.base : field.base, field.want),
  });

  /// What to write over [remote], the values Telegram holds now, and which
  /// fields to leave as they are because another device changed them. A
  /// field Telegram already holds as wanted needs nothing; one still at the
  /// value this patch started from takes the wanted value; any other is
  /// [skipped], so the other device's version stays. Albums never clash:
  /// the ones this patch added go in and the ones it took out come out,
  /// whatever the other device did to the rest.
  ({Map<String, Object?> apply, Set<String> skipped}) resolve(Map<String, Object?> remote) {
    final apply = <String, Object?>{};
    final skipped = <String>{};
    for (final MapEntry(:key, value: field) in fields.entries) {
      final now = remote[key];
      if (key == 'al') {
        final merged = _mergeAlbums(now, field);
        if (!_same(key, merged, now)) apply[key] = merged;
      } else if (_same(key, now, field.want)) {
        continue;
      } else if (_same(key, now, field.base)) {
        apply[key] = field.want;
      } else {
        skipped.add(key);
      }
    }
    return (apply: apply, skipped: skipped);
  }

  /// [remote] as this phone shows it while the patch waits: every wanted
  /// value in place of what Telegram holds, with albums merged the way
  /// [resolve] merges them.
  Map<String, Object?> over(Map<String, Object?> remote) => {
    ...remote,
    for (final MapEntry(:key, value: field) in fields.entries)
      key: key == 'al' ? _mergeAlbums(remote[key], field) : field.want,
  };

  /// What is left of this patch once [sent] went out: a field [sent] had
  /// starts from what [sent] wanted, so a field that still wants that is
  /// settled and goes, and one changed since keeps only the newer change.
  EditPatch rebase(EditPatch sent) => _settled({
    for (final MapEntry(:key, value: field) in fields.entries)
      key: switch (sent.fields[key]) {
        final EditField out => EditField(out.want, field.want),
        null => field,
      },
  });

  static EditPatch _diff(Map<String, Object?> before, Map<String, Object?> after) => _settled({
    for (final MapEntry(:key, :value) in after.entries) key: EditField(before[key], value),
  });

  static EditPatch _settled(Map<String, EditField> fields) => EditPatch({
    for (final MapEntry(:key, value: field) in fields.entries)
      if (!_same(key, field.base, field.want)) key: field,
  });

  static List<String> _mergeAlbums(Object? remote, EditField field) {
    final base = _ids(field.base).toSet();
    final want = _ids(field.want).toSet();
    final merged = {..._ids(remote), ...want.difference(base)}.difference(base.difference(want));
    return _ids(merged);
  }

  static bool _same(String key, Object? a, Object? b) =>
      key == 'al' ? setEquals(_ids(a).toSet(), _ids(b).toSet()) : a == b;

  static Object? _read(String key, Object? value) => key == 'al' ? _ids(value) : value;

  static List<String> _ids(Object? value) => [
    if (value is Iterable)
      for (final id in value)
        if (id is String) id,
  ]..sort();

  static DateTime? _time(Object? millis) =>
      millis is int ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
}
