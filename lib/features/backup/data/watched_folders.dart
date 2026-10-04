import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/async/combine.dart';
import '../../../core/files/file_kind.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../files/presentation/file_actions.dart';
import '../../network/data/mobile_data.dart';
import '../../transfers/data/room.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/domain/transfer_wait.dart';
import 'backup_controller.dart';
import 'backup_rules.dart';
import 'phone_folders.dart';

// -----------------------------------------------------------------------------
// Planning, free of the platform so every rule is tested on its own
// -----------------------------------------------------------------------------

/// How long a file has to stay unchanged before it goes up: a recorder or a
/// download may still be writing one that changed more recently.
const Duration watchSettle = Duration(seconds: 60);

/// How long after a check that left files settling the folders are checked
/// again: a little past [watchSettle], so every file that check saw has
/// been still for long enough by then.
const Duration watchRecheck = Duration(seconds: 62);

/// Failed tries after which a file of a watched folder stops being tried.
const int watchMaxFailures = 3;

/// Whether [doc] is a file [filter] sends up. Names that start with a dot
/// are left out, which covers the '.pending-' and '.trashed-' names Android
/// gives files still being written or in its trash, and so are empty files.
bool watchMatches(PhoneDocument doc, WatchFilter filter) {
  if (doc.name.startsWith('.') || doc.size <= 0) return false;
  final kind = FileKind.detect(
    fileName: doc.name,
    mimeType: doc.mimeType.isEmpty ? null : doc.mimeType,
  );
  return switch (filter) {
    WatchFilter.documents => kind == FileKind.document,
    WatchFilter.audio => kind == FileKind.audio,
    WatchFilter.everything => true,
  };
}

/// What one check of a watched folder does with the files it found.
@immutable
class WatchPlan {
  const WatchPlan({
    required this.toUpload,
    required this.alreadyInDrive,
    required this.settling,
    required this.gaveUp,
  });

  /// The files to send up, oldest first.
  final List<PhoneDocument> toUpload;

  /// Files the drive already holds under the same name and size, by
  /// document id, each with the drive file's id.
  final Map<String, String> alreadyInDrive;

  /// Files changed within [watchSettle], left for a later check.
  final int settling;

  /// Files that failed [watchMaxFailures] times, which aren't tried again.
  final int gaveUp;
}

/// Sorts [listing] by what [ledger] knows of each file. A file [filter]
/// leaves out is passed over, and so is one in the drive, one set aside,
/// and one whose upload is still in [inFlight]. One that failed
/// [watchMaxFailures] times counts as [WatchPlan.gaveUp], and one changed
/// within [watchSettle] of [now] as [WatchPlan.settling]. Of the rest, a
/// file whose `name|size` is in [fingerprints] is already in the drive, and
/// everything else goes up, oldest first.
WatchPlan planUploads({
  required List<PhoneDocument> listing,
  required Map<String, WatchedFileRow> ledger,
  required Map<String, String> fingerprints,
  required WatchFilter filter,
  required DateTime now,
  required bool Function(String transferId) inFlight,
}) {
  final toUpload = <PhoneDocument>[];
  final alreadyInDrive = <String, String>{};
  var settling = 0;
  var gaveUp = 0;
  final settledBefore = now.subtract(watchSettle);
  for (final doc in listing) {
    if (!watchMatches(doc, filter)) continue;
    final entry = ledger[doc.id];
    switch (entry?.state) {
      case WatchedFileState.done || WatchedFileState.skipped:
        continue;
      case WatchedFileState.pending
          when entry!.transferId != null && inFlight(entry.transferId!):
        continue;
      case WatchedFileState.failed when entry!.failures >= watchMaxFailures:
        gaveUp++;
        continue;
      default:
    }
    if (doc.modifiedAt.isAfter(settledBefore)) {
      settling++;
      continue;
    }
    final existing = fingerprints['${doc.name}|${doc.size}'];
    if (existing != null) {
      alreadyInDrive[doc.id] = existing;
      continue;
    }
    toUpload.add(doc);
  }
  toUpload.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
  return WatchPlan(
    toUpload: toUpload,
    alreadyInDrive: alreadyInDrive,
    settling: settling,
    gaveUp: gaveUp,
  );
}

/// When to check again after [plan]: [watchRecheck] while some file is
/// settling, and never when none is, since only a new file or a sync gives
/// the folder something to send then.
Duration? recheckAfter(WatchPlan plan) => plan.settling > 0 ? watchRecheck : null;

/// Ledger rows that set aside every file in [listing], for a folder added
/// with only its new files wanted.
List<WatchedFilesCompanion> baseline(String ruleId, List<PhoneDocument> listing, DateTime now) => [
  for (final doc in listing)
    WatchedFilesCompanion.insert(
      ruleId: ruleId,
      documentId: doc.id,
      size: doc.size,
      modifiedAt: doc.modifiedAt,
      state: WatchedFileState.skipped,
      updatedAt: now,
    ),
];

// -----------------------------------------------------------------------------
// The watcher
// -----------------------------------------------------------------------------

/// Where one watched folder stands.
enum RulePhase {
  /// Nothing going on; its row says how many files went up and when it was
  /// last checked.
  idle,

  /// Being listed and compared with what it has sent before.
  checking,

  /// Sending its new files up.
  uploading,

  /// Its new files wait, since the phone is on mobile data they may not
  /// use, or that would pass the monthly limit.
  waitingForWifi,

  /// Telegrive can't read it: it was renamed, deleted or on a card that
  /// was taken out.
  noAccess,
}

@immutable
class RuleStatus {
  const RuleStatus({
    this.phase = RulePhase.idle,
    this.total = 0,
    this.done = 0,
    this.current,
    this.waiting = 0,
    this.truncated = false,
  });

  final RulePhase phase;

  /// Files this check is sending up.
  final int total;

  /// How many of [total] are settled: in the drive, failed or cancelled.
  final int done;

  /// Name of the file going up now.
  final String? current;

  /// Files waiting for Wi-Fi, while [phase] is [RulePhase.waitingForWifi].
  final int waiting;

  /// The last listing stopped at [PhoneFolders.listLimit] files.
  final bool truncated;

  double get progress => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);

  RuleStatus copyWith({int? done, String? current}) => RuleStatus(
    phase: phase,
    total: total,
    done: done ?? this.done,
    current: current ?? this.current,
    waiting: waiting,
    truncated: truncated,
  );
}

@immutable
class WatchState {
  const WatchState({this.working = false, this.rules = const {}});

  /// A check is sending files, the moments between two of them included,
  /// which is what keeps the transfer service up.
  final bool working;

  /// Each watched folder's status, by rule id.
  final Map<String, RuleStatus> rules;

  WatchState copyWith({bool? working, Map<String, RuleStatus>? rules}) =>
      WatchState(working: working ?? this.working, rules: rules ?? this.rules);
}

/// Uploads the new files of folders on this phone the person picked, the
/// way photo backup handles the camera roll.
///
/// The folders are checked when the drive opens, when Telegrive returns to
/// the foreground and after each sync, never while it is closed, and again
/// just over a minute after a check that found a file still being written.
/// Each new
/// file is copied into the cache and goes up once, as an ordinary upload
/// that shows in Transfers, into Files › Auto upload › the folder's name,
/// or the drive folder the person chose. A ledger per folder remembers
/// what went up, and a file the drive already holds under the same name
/// and size is recognised and passed over, after a reinstall say. Photo
/// backup's Mobile data choice and monthly limit govern these uploads too.
class WatchedFoldersController extends Notifier<WatchState> {
  static const String rootFolder = 'Auto upload';
  static const int _parallel = 2;

  /// Left free on the phone on top of each copy, so a folder of big files
  /// never fills it.
  static const int _keepFree = 200 << 20;

  bool _running = false;
  bool _rerun = false;
  bool _stopRequested = false;
  Timer? _debounce;

  /// Fires once the files a check found still settling are old enough to go
  /// up. It is apart from [_debounce], which every call to [schedule]
  /// replaces.
  Timer? _settle;

  /// Folders removed while a check may still be sending their files.
  final Set<String> _dropped = {};

  /// The uploads checks are waiting on, for what the monthly limit has
  /// already let onto mobile data.
  final Set<String> _following = {};

  /// Ends once the last upload asked for has its name and its place in the
  /// queue, so two files of one name get names of their own.
  Future<void> _naming = Future.value();

  AppDatabase get _db => ref.read(appDatabaseProvider);
  DriveRepository get _repository => ref.read(driveRepositoryProvider);
  PhoneFolders get _folders => ref.read(phoneFoldersProvider);
  Preferences get _prefs => ref.read(preferencesProvider);
  TransferQueue get _queue => ref.read(transferQueueProvider.notifier);

  @override
  WatchState build() {
    ref.listen<DriveSession?>(driveSessionProvider, (previous, next) {
      if (next == null) {
        _stopRequested = true;
      } else if (previous?.chatId != next.chatId) {
        schedule(immediate: true);
      }
    });
    ref.listen<SyncState>(driveSyncProvider, (previous, next) {
      if ((previous?.running ?? false) && !next.running && next.error == null) {
        schedule();
      }
    });
    // Files held for Wi-Fi that were never queued go once it is back.
    ref.listen<NetworkState>(networkStatusProvider, (_, next) {
      final waiting = state.rules.values.any((r) => r.phase == RulePhase.waitingForWifi);
      if (waiting && next.online && !next.metered) schedule(immediate: true);
    });
    ref.onDispose(() {
      _debounce?.cancel();
      _settle?.cancel();
    });
    return const WatchState();
  }

  /// Starts watching [folder], sending what [filter] picks out of it, in
  /// its [subfolders] too, into [destinationId], or Auto upload › its name
  /// when null. With [includeExisting] off, the files in it now are set
  /// aside, those in its subfolders included, so only files added later go
  /// up.
  Future<void> add(
    PickedFolder folder, {
    required WatchFilter filter,
    required bool subfolders,
    String? destinationId,
    required bool includeExisting,
  }) async {
    final id = _repository.newId();
    final now = DateTime.now();
    if (!includeExisting) {
      final listing = await _folders.list(folder.uri, recursive: true);
      await _db.saveWatchedFiles(baseline(id, listing.files, now));
    }
    await _db.saveWatchedFolder(
      WatchedFoldersCompanion.insert(
        id: id,
        treeUri: folder.uri,
        label: folder.name,
        destinationId: Value(destinationId),
        filter: filter,
        subfolders: Value(subfolders),
        createdAt: now,
      ),
    );
    schedule(immediate: true);
  }

  /// Changes what folder [id] sends and where to; the check that follows
  /// goes by the new choice.
  Future<void> update(
    String id, {
    required WatchFilter filter,
    required bool subfolders,
    String? destinationId,
  }) async {
    await _db.updateWatchedFolder(
      id,
      WatchedFoldersCompanion(
        filter: Value(filter),
        subfolders: Value(subfolders),
        destinationId: Value(destinationId),
      ),
    );
    schedule(immediate: true);
  }

  /// Stops watching folder [id]. What it sent stays in the drive, and its
  /// uploads already in Transfers carry on there. Android gets the access
  /// back, unless another watched folder reads the same one.
  Future<void> remove(String id) async {
    final rules = await _db.watchedFolderList();
    final rule = rules.where((r) => r.id == id).firstOrNull;
    if (rule == null) return;
    _dropped.add(id);
    await _db.deleteWatchedFolder(id);
    if (!rules.any((r) => r.id != id && r.treeUri == rule.treeUri)) {
      await _folders.release(rule.treeUri);
    }
    state = state.copyWith(rules: {...state.rules}..remove(id));
  }

  /// Asks for folder [id] in Android's picker again, for when Telegrive
  /// can't read it, and checks it straight away. Backing out of the
  /// picker changes nothing and answers false. A [PlatformException] coded
  /// `not_persisted` means Android wouldn't keep this access either.
  Future<bool> reauthorize(String id) async {
    final picked = await _folders.pick();
    if (picked == null) return false;
    final rules = await _db.watchedFolderList();
    final rule = rules.where((r) => r.id == id).firstOrNull;
    final others = {for (final r in rules) if (r.id != id) r.treeUri};
    if (rule == null) {
      if (!others.contains(picked.uri)) await _folders.release(picked.uri);
      return false;
    }
    await _db.updateWatchedFolder(id, WatchedFoldersCompanion(treeUri: Value(picked.uri)));
    if (picked.uri != rule.treeUri && !others.contains(rule.treeUri)) {
      await _folders.release(rule.treeUri);
    }
    state = state.copyWith(rules: {...state.rules, id: const RuleStatus()});
    schedule(immediate: true);
    return true;
  }

  /// Forgets every watched folder and gives Android back the access to
  /// each, as part of forgetting the drive on this phone.
  Future<void> forgetAll() async {
    _stopRequested = true;
    _debounce?.cancel();
    _settle?.cancel();
    final rules = await _db.watchedFolderList();
    for (final uri in {for (final rule in rules) rule.treeUri}) {
      await _folders.release(uri);
    }
    for (final rule in rules) {
      _dropped.add(rule.id);
      await _db.deleteWatchedFolder(rule.id);
    }
    state = const WatchState();
  }

  /// 'Use data' on a folder that waits for Wi-Fi. While the Mobile data
  /// choice keeps these files for Wi-Fi, it becomes Photos and videos, as
  /// photo backup's own 'Use data' does; once it lets them go, the waiting
  /// is the monthly limit's, and they go past it the way 'Use data anyway'
  /// lets photo backup. Then the folders are checked again.
  Future<void> useMobileData() async {
    final backup = ref.read(backupControllerProvider.notifier);
    if (foldersMayUseMobileData(_prefs.backupMobileData)) {
      backup.useDataAnyway();
    } else {
      await backup.setMobileData(BackupMobileData.all);
    }
    await followMobileData();
  }

  /// Brings the folder uploads in the queue in line with the Mobile data
  /// choice as it stands, then checks the folders again: those it lets use
  /// mobile data go now, and those it keeps for Wi-Fi step back if they are
  /// under way on it.
  Future<void> followMobileData() async {
    for (final rule in await _db.watchedFolderList()) {
      await _markQueued((await _db.watchedLedger(rule.id)).values);
    }
    schedule(immediate: true);
  }

  /// Checks the folders soon. Syncs come in bursts, so calls that aren't
  /// urgent are run together.
  void schedule({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(seconds: 4),
      () => unawaited(run()),
    );
  }

  Future<void> run() async {
    if (!PhoneFolders.supported) return;
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    try {
      do {
        _rerun = false;
        _stopRequested = false;
        _dropped.clear();
        await _pass();
      } while (_rerun);
    } catch (e, stack) {
      debugPrint('[Folders] check failed: $e\n$stack');
    } finally {
      _running = false;
      if (ref.mounted && state.working) state = state.copyWith(working: false);
    }
  }

  Future<void> _pass() async {
    final session = ref.read(driveSessionProvider);
    if (session == null) return;
    final rules = await _db.watchedFolderList();
    state = state.copyWith(
      rules: {for (final rule in rules) rule.id: state.rules[rule.id] ?? const RuleStatus()},
    );
    if (rules.isEmpty) return;
    // Uploads an earlier run left going are in the queue only once it has
    // read its rows; without them they would be taken for lost and sent a
    // second time.
    await ref.read(transferQueueProvider.notifier).loaded;
    await ref.read(driveSyncProvider.notifier).whenIdle();
    // "Already in the drive" is judged against the index, so it has to hold
    // the whole channel, as photo backup needs it to.
    if (_prefs.lastFullSync(session.chatId) == null || ref.read(driveSyncProvider).error != null) {
      return;
    }
    // A small copy stands for its original under the original's size, so
    // the same photo in a watched folder counts as in the drive too.
    final fingerprints = {
      for (final MapEntry(:key, :value) in (await _repository.mediaFingerprints()).entries)
        key: value.fileId,
    };
    for (final rule in rules) {
      if (_stopRequested) return;
      if (_dropped.contains(rule.id)) continue;
      try {
        await _check(rule, fingerprints);
      } catch (e, stack) {
        debugPrint('[Folders] ${rule.label}: $e\n$stack');
        _setRule(rule.id, const RuleStatus());
      }
    }
  }

  /// Looks through [rule]'s folder and sends up what is new in it.
  Future<void> _check(WatchedFolderRow rule, Map<String, String> fingerprints) async {
    _setRule(rule.id, const RuleStatus(phase: RulePhase.checking));
    if (!await _folders.canRead(rule.treeUri)) {
      _setRule(rule.id, const RuleStatus(phase: RulePhase.noAccess));
      return;
    }
    final listing = await _folders.list(rule.treeUri, recursive: rule.subfolders);
    final now = DateTime.now();
    final ledger = await _reconcile(await _db.watchedLedger(rule.id));
    await _markQueued(ledger.values);
    final transfers = ref.read(transferQueueProvider);
    final plan = planUploads(
      listing: listing.files,
      ledger: ledger,
      fingerprints: fingerprints,
      filter: rule.filter,
      now: now,
      inFlight: (id) => transfers.byId(id)?.status.isPending ?? false,
    );
    if (recheckAfter(plan) case final recheck?) {
      _settle?.cancel();
      _settle = Timer(recheck, () => schedule(immediate: true));
    }
    if (plan.alreadyInDrive.isNotEmpty) {
      final byId = {for (final doc in listing.files) doc.id: doc};
      await _db.saveWatchedFiles([
        for (final MapEntry(key: docId, value: fileId) in plan.alreadyInDrive.entries)
          _entry(rule.id, byId[docId]!, WatchedFileState.done, fileId: fileId),
      ]);
    }
    // Uploads an earlier check queued that wait for Wi-Fi in the queue.
    final held = ledger.values.where((entry) {
      final item = entry.state == WatchedFileState.pending && entry.transferId != null
          ? transfers.byId(entry.transferId!)
          : null;
      return item != null && item.status == TransferStatus.queued && item.wait is WaitingForWifi;
    }).length;
    final status = plan.toUpload.isEmpty
        ? RuleStatus(
            phase: held > 0 ? RulePhase.waitingForWifi : RulePhase.idle,
            waiting: held,
            truncated: listing.truncated,
          )
        : await _send(rule, plan.toUpload, ledger, fingerprints, held: held, truncated: listing.truncated);
    await _db.updateWatchedFolder(rule.id, WatchedFoldersCompanion(checkedAt: Value(DateTime.now())));
    _setRule(rule.id, status);
  }

  /// Settles what [ledger] says is still going up against the queue: an
  /// upload that landed is in the drive, one the person cancelled is set
  /// aside, and one that failed, or is gone without its file reaching the
  /// drive, counts a failure. A failed one the person retried in Transfers
  /// is going up again, and is followed as such.
  Future<Map<String, WatchedFileRow>> _reconcile(Map<String, WatchedFileRow> ledger) async {
    final transfers = ref.read(transferQueueProvider);
    final changed = <String, WatchedFileRow>{};
    for (final entry in ledger.values) {
      final transferId = entry.transferId;
      if (transferId == null) continue;
      final pending = entry.state == WatchedFileState.pending;
      if (!pending && entry.state != WatchedFileState.failed) continue;
      final row = transfers.byId(transferId)?.row;
      final status = row?.status;
      final WatchedFileState next;
      if (status != null && status.isPending) {
        if (pending) continue;
        next = WatchedFileState.pending;
      } else if (status == TransferStatus.completed) {
        next = WatchedFileState.done;
      } else if (!pending) {
        continue;
      } else if (status == TransferStatus.cancelled) {
        next = WatchedFileState.skipped;
      } else if (status == null && await _repository.fileById(entry.fileId ?? '') != null) {
        // Cleared from Transfers once it had landed.
        next = WatchedFileState.done;
      } else {
        next = WatchedFileState.failed;
      }
      changed[entry.documentId] = entry.copyWith(
        state: next,
        fileId: Value(row?.fileId ?? entry.fileId),
        failures: next == WatchedFileState.failed ? entry.failures + 1 : entry.failures,
        updatedAt: DateTime.now(),
      );
    }
    if (changed.isEmpty) return ledger;
    await _db.saveWatchedFiles([for (final row in changed.values) row.toCompanion(false)]);
    return {...ledger, ...changed};
  }

  /// Marks the uploads [entries] are waiting on by the Mobile data choice
  /// as it stands: kept for Wi-Fi while it doesn't let these files use
  /// mobile data, let go once it does.
  Future<void> _markQueued(Iterable<WatchedFileRow> entries) async {
    final ids = [
      for (final entry in entries)
        if (entry.state == WatchedFileState.pending && entry.transferId != null) entry.transferId!,
    ];
    if (ids.isEmpty) return;
    if (foldersMayUseMobileData(_prefs.backupMobileData)) {
      await _queue.useMobileData(ids);
    } else {
      await _queue.waitForWifi(ids);
    }
  }

  /// Sends [files] of [rule] up, [_parallel] at a time, and says where the
  /// folder stands after. It stops early once the phone is on mobile data
  /// the files may not use, when the phone runs short of room, and when the
  /// folder is removed.
  Future<RuleStatus> _send(
    WatchedFolderRow rule,
    List<PhoneDocument> files,
    Map<String, WatchedFileRow> ledger,
    Map<String, String> fingerprints, {
    required int held,
    required bool truncated,
  }) async {
    RuleStatus waitingFor(int left) => RuleStatus(
      phase: RulePhase.waitingForWifi,
      waiting: left + held,
      truncated: truncated,
    );
    if (!await _mayGo(files.first.size)) return waitingFor(files.length);

    final destination = await _destinationOf(rule);
    var status = RuleStatus(phase: RulePhase.uploading, total: files.length, truncated: truncated);
    void show(RuleStatus next) {
      status = next;
      _setRule(rule.id, next);
    }

    show(status);
    state = state.copyWith(working: true);
    final queue = files.iterator;
    var waiting = false;
    var full = false;
    bool stopped() => _stopRequested || _dropped.contains(rule.id) || waiting || full;

    Future<void> worker() async {
      while (!stopped() && queue.moveNext()) {
        final doc = queue.current;
        if (!await _mayGo(doc.size)) {
          waiting = true;
          return;
        }
        final entry = ledger[doc.id];
        if (await Room.shortfall(ref.read(deviceStorageProvider), doc.size + _keepFree) != null) {
          await _failed(rule.id, doc, entry);
          full = true;
          return;
        }
        show(status.copyWith(current: doc.name));
        if (!await _upload(rule, doc, destination, entry, fingerprints)) {
          waiting = true;
          return;
        }
        show(status.copyWith(done: status.done + 1));
      }
    }

    await Future.wait([for (var i = 0; i < _parallel; i++) worker()]);
    if (waiting) return waitingFor(math.max(0, files.length - status.done));
    return RuleStatus(truncated: truncated);
  }

  /// Copies [doc] into the cache and sends it up into [destination], and
  /// records how that went. False when the upload steps back into the
  /// queue to wait for Wi-Fi: the queue starts it again by itself, and a
  /// later check follows it from the ledger.
  Future<bool> _upload(
    WatchedFolderRow rule,
    PhoneDocument doc,
    String destination,
    WatchedFileRow? entry,
    Map<String, String> fingerprints,
  ) async {
    // An upload an earlier check left failed in Transfers gives way to this
    // one, so its Retry can't send the file a second time.
    if (entry?.transferId case final old?) await _queue.remove(old);
    final String id;
    try {
      final copy = await _folders.copy(rule.treeUri, doc);
      id = await _enqueue(doc, copy, destination);
    } catch (e) {
      debugPrint('[Folders] ${doc.name}: $e');
      await _failed(rule.id, doc, entry);
      return true;
    }
    await _db.saveWatchedFiles([
      _entry(
        rule.id,
        doc,
        WatchedFileState.pending,
        transferId: id,
        fileId: ref.read(transferQueueProvider).byId(id)?.row.fileId,
        failures: entry?.failures ?? 0,
      ),
    ]);
    _following.add(id);
    try {
      final row = await untilEndedOrHeld(ref, id);
      if (row == null) return false;
      switch (row.status) {
        case TransferStatus.completed:
          fingerprints['${doc.name}|${doc.size}'] = row.fileId;
          await _db.saveWatchedFiles([
            _entry(rule.id, doc, WatchedFileState.done, transferId: id, fileId: row.fileId),
          ]);
        case TransferStatus.cancelled:
          await _db.saveWatchedFiles([
            _entry(rule.id, doc, WatchedFileState.skipped, transferId: id),
          ]);
        default:
          await _failed(rule.id, doc, entry, transferId: id);
      }
      return true;
    } finally {
      _following.remove(id);
    }
  }

  /// Queues the upload of [copy], made from [doc], into [destination]. A
  /// name the folder already has, or that an upload is still taking there,
  /// gets a number, since there is nobody to ask. The upload waits for
  /// Wi-Fi unless the Mobile data choice lets these files use mobile data,
  /// so it steps back if the phone leaves Wi-Fi while it runs.
  Future<String> _enqueue(PhoneDocument doc, ({String path, int size}) copy, String destination) {
    final queued = _naming.then((_) async {
      final [name] = await FileActions.namesKeepingBoth(
        _repository,
        ref.read(transferQueueProvider),
        [doc.name],
        folderId: destination,
      );
      final path = name == doc.name ? copy.path : await FileActions.renamedOnDisk(copy.path, name);
      final ids = await _queue.enqueueUploads([
        UploadRequest(
          name: name,
          path: path,
          size: copy.size,
          ownsSource: true,
          wifiOnly: !foldersMayUseMobileData(_prefs.backupMobileData),
        ),
      ], folderId: destination);
      if (ids.isEmpty) throw const DriveException('Couldn\'t start the upload.');
      return ids.single;
    });
    _naming = queued.then((_) {}, onError: (_) {});
    return queued;
  }

  /// Whether a file of [bytes] may go up on the network the phone is on
  /// now: always off mobile data, and on it as the Mobile data choice and
  /// the monthly limit allow, counting what the uploads under way still
  /// have to send.
  Future<bool> _mayGo(int bytes) async {
    if (!ref.read(networkStatusProvider).metered) return true;
    final mode = _prefs.backupMobileData;
    if (!foldersMayUseMobileData(mode)) return false;
    await ref.read(mobileDataProvider.notifier).refresh();
    final transfers = ref.read(transferQueueProvider);
    var committed = 0;
    for (final id in _following) {
      final row = transfers.byId(id)?.row;
      if (row == null || !row.status.isPending || row.wifiOnly) continue;
      committed += row.totalBytes - row.doneBytes;
    }
    return folderAllowance(data: ref.read(mobileDataProvider), mode: mode, bytes: committed + bytes) ==
        BackupAllowance.go;
  }

  /// The drive folder [rule]'s files go into: the one it names while the
  /// drive shows it, otherwise Auto upload › its name, made on first use
  /// and remembered.
  Future<String> _destinationOf(WatchedFolderRow rule) async {
    final chosen = rule.destinationId;
    if (chosen != null && await _repository.shownFolder(chosen) != null) return chosen;
    final id = await _repository.ensureFolderPath([rootFolder, rule.label]);
    await _db.updateWatchedFolder(rule.id, WatchedFoldersCompanion(destinationId: Value(id)));
    return id;
  }

  /// Records a failed try at [doc], after [entry]'s.
  Future<void> _failed(
    String ruleId,
    PhoneDocument doc,
    WatchedFileRow? entry, {
    String? transferId,
  }) => _db.saveWatchedFiles([
    _entry(
      ruleId,
      doc,
      WatchedFileState.failed,
      transferId: transferId,
      failures: (entry?.failures ?? 0) + 1,
    ),
  ]);

  static WatchedFilesCompanion _entry(
    String ruleId,
    PhoneDocument doc,
    WatchedFileState state, {
    String? fileId,
    String? transferId,
    int failures = 0,
  }) => WatchedFilesCompanion.insert(
    ruleId: ruleId,
    documentId: doc.id,
    size: doc.size,
    modifiedAt: doc.modifiedAt,
    state: state,
    fileId: Value(fileId),
    transferId: Value(transferId),
    failures: Value(failures),
    updatedAt: DateTime.now(),
  );

  void _setRule(String id, RuleStatus status) {
    if (!ref.mounted || _dropped.contains(id)) return;
    state = state.copyWith(rules: {...state.rules, id: status});
  }
}

final watchedFoldersProvider = NotifierProvider<WatchedFoldersController, WatchState>(
  WatchedFoldersController.new,
);

/// A watched folder as its row on the Backup screen shows it.
@immutable
class WatchedFolderView {
  const WatchedFolderView({
    required this.row,
    required this.uploadedCount,
    required this.status,
    required this.destinationLabel,
  });

  final WatchedFolderRow row;

  /// How many of its files are in the drive.
  final int uploadedCount;
  final RuleStatus status;

  /// Where its files go, as 'Auto upload › Bank'.
  final String destinationLabel;
}

/// The watched folders with what each has sent, where to and where it
/// stands, live.
final watchedFolderViewsProvider = StreamProvider.autoDispose<List<WatchedFolderView>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final repository = ref.watch(driveRepositoryProvider);
  final statuses = ref.watch(watchedFoldersProvider.select((s) => s.rules));
  return combineLatest2(
    db.watchWatchedFolders(),
    db.watchUploadedCounts(),
    (rows, counts) => (rows, counts),
  ).asyncMap(
    (data) async => [
      for (final row in data.$1)
        WatchedFolderView(
          row: row,
          uploadedCount: data.$2[row.id] ?? 0,
          status: statuses[row.id] ?? const RuleStatus(),
          destinationLabel: await watchedDestination(repository, row),
        ),
    ],
  );
});

/// Where [rule]'s files go, as its path in the drive: the folder it names
/// while the drive shows it, otherwise Auto upload › its own name, which
/// the next upload makes.
Future<String> watchedDestination(DriveRepository repository, WatchedFolderRow rule) async {
  final id = rule.destinationId;
  if (id != null && await repository.shownFolder(id) != null) {
    final path = await repository.pathTo(id);
    if (path.isNotEmpty) return path.map((folder) => folder.name).join(' › ');
  }
  return '${WatchedFoldersController.rootFolder} › ${rule.label}';
}
