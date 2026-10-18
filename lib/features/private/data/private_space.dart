import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../drive/domain/drive_models.dart';
import '../../lock/data/app_lock.dart';

/// Private: folders that show only behind the phone's lock, with everything
/// inside them, on every phone. Which folders are private lives in each
/// folder's own message; this phone only keeps whether Private is open.

/// The private folders themselves, not those inside them, out of the
/// trash, by name: what Private lists.
final privateTopFoldersProvider = StreamProvider.autoDispose<List<DriveFolder>>(
  (ref) => ref.watch(appDatabaseProvider).watchAllFolders().map((rows) {
    final inPrivate = {
      for (final row in rows)
        if (row.inPrivate) row.id,
    };
    return [
      for (final row in rows)
        if (row.private && !row.hidden && !inPrivate.contains(row.parentId))
          DriveFolder.fromRow(row),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }),
);

/// Every folder in Private, by id: a private folder and those inside it.
final _privateFolderIdsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(appDatabaseProvider).watchAllFolders().map(
    (rows) => {
      for (final row in rows)
        if (row.inPrivate) row.id,
    },
  ),
);

/// Which folders' files are out of sight: those in Private while it is
/// closed, none while it is open. Offline, Transfers and the notification
/// a finished batch posts go by it, so nothing in Private is named outside
/// it.
@immutable
class OutOfSight {
  const OutOfSight._(this._ids, this._known);

  /// Nothing is out of sight: Private is open.
  static const none = OutOfSight._({}, true);

  /// The folders in Private aren't read yet, so anything in a folder may be
  /// in one and stays out of sight until they are.
  static const unknown = OutOfSight._({}, false);

  /// What is in the folders [ids] is out of sight.
  const OutOfSight.of(Set<String> ids) : this._(ids, true);

  final Set<String> _ids;
  final bool _known;

  /// Whether nothing is out of sight, whatever folder it is in.
  bool get isNone => _known && _ids.isEmpty;

  /// Whether what is in folder [folderId] is out of sight. Nothing at the
  /// root ever is.
  bool hides(String? folderId) => folderId != null && (!_known || _ids.contains(folderId));
}

final privateOutOfSightProvider = Provider<OutOfSight>((ref) {
  if (ref.watch(privateSpaceProvider)) return OutOfSight.none;
  final ids = ref.watch(_privateFolderIdsProvider);
  // An index that can't be read names nothing anywhere.
  if (ids.hasError) return OutOfSight.none;
  return ids.hasValue ? OutOfSight.of(ids.requireValue) : OutOfSight.unknown;
});

/// Whether Private is open on this phone. It opens with the phone's
/// fingerprint, face or screen lock, and closes once none of its pages is
/// left, when the app goes to the background, or when it is locked.
class PrivateSpace extends Notifier<bool> with WidgetsBindingObserver {
  /// Set while the prompt is up and for [_promptGrace] after: some phones
  /// send the app to the background for the prompt and report it a moment
  /// later, which isn't leaving.
  bool _prompting = false;
  Timer? _promptOver;

  /// Private's pages on screen, the first opened first.
  final List<Object> _pages = [];

  /// Page [page] of Private is on screen.
  void enter(Object page) => _pages.add(page);

  /// Page [page] of Private is gone; Private closes with the last of them.
  void leave(Object page) {
    _pages.remove(page);
    if (_pages.isEmpty) lock();
  }

  /// Whether [page] is the first of Private's pages still on screen, the
  /// one everything else of Private was opened over.
  bool isFirst(Object page) => _pages.firstOrNull == page;

  @override
  bool build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _promptOver?.cancel();
    });
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!this.state || _prompting) return;
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) lock();
  }

  static const _promptGrace = Duration(seconds: 2);

  /// Asks for the phone's lock and opens Private when it passes. False on
  /// a phone with no lock set up, or when the check failed.
  Future<bool> unlock() async {
    if (state) return true;
    _prompting = true;
    _promptOver?.cancel();
    final bool passed;
    try {
      passed = await ref.read(appLockProvider.notifier).confirm('Open Private');
    } finally {
      _promptOver = Timer(_promptGrace, () => _prompting = false);
    }
    if (passed && ref.mounted) state = true;
    return passed;
  }

  void lock() {
    // A page let go as the whole app is taken down finds Private gone.
    if (ref.mounted && state) state = false;
  }

  /// Lets a test open Private without a prompt.
  @visibleForTesting
  void open() => state = true;
}

final privateSpaceProvider = NotifierProvider<PrivateSpace, bool>(PrivateSpace.new);
