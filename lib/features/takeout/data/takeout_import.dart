import 'dart:async';
import 'dart:convert' show latin1;
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/files/file_kind.dart';
import '../../../core/files/zip_reader.dart';
import '../../../core/format/formatters.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/media/media_probe.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../backup/data/backup_rules.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/data/bulk_edits.dart';
import '../../files/presentation/file_actions.dart';
import '../../network/data/mobile_data.dart';
import '../../transfers/data/room.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/domain/transfer_error.dart';
import '../domain/takeout_catalog.dart';
import 'takeout_files.dart';

// -----------------------------------------------------------------------------
// Planning, free of the platform so every rule is tested on its own
// -----------------------------------------------------------------------------

/// Where imported photos go: Files › Google Photos › the year each was
/// taken, or Google Photos itself for one with no date.
const String takeoutRootFolder = 'Google Photos';

/// Failed tries after which an item stops being tried, until the person
/// asks for another go.
const int takeoutMaxFailures = 3;

/// The drive folder path for a photo taken at [takenAt].
List<String> takeoutFolderPath(DateTime? takenAt) => [
  takeoutRootFolder,
  if (takenAt != null) '${takenAt.year}',
];

/// The ways a photo is known to be in the drive already: by its name and
/// size, as photo backup knows it; by its name and the second it was taken,
/// which finds the copy Google kept smaller under Storage saver; and by its
/// size and that second, which finds one renamed since. One without a time
/// is known by its name and size alone.
List<String> takeoutMatchKeys(String name, int size, DateTime? takenAt) {
  final second = takenAt == null ? null : takenAt.millisecondsSinceEpoch ~/ 1000;
  return [
    '$name|$size',
    if (second != null) ...['name:${name.toLowerCase()}|taken:$second', 'size:$size|taken:$second'],
  ];
}

/// The drive file [fingerprints] holds for [item] under any of its
/// [takeoutMatchKeys], or null.
String? takeoutMatch(TakeoutItem item, Map<String, String> fingerprints) {
  for (final key in takeoutMatchKeys(item.name, item.size, item.takenAt)) {
    if (fingerprints[key] case final fileId?) return fileId;
  }
  return null;
}

/// The drive file that already holds the photo [item] is the moving part
/// of, when the drive had that photo before the import: found by
/// [takeoutMatch], or recorded as already there. A phone keeps the movement
/// inside the photo file it backed up, so the video Google kept apart adds
/// nothing. Null for anything else, and for a photo the import sent itself,
/// since Google's copy of a photo holds no movement and its video is kept.
String? takeoutMotionHome(
  TakeoutItem item, {
  required Map<String, TakeoutItem> items,
  required Map<String, TakeoutItemRow> ledger,
  required Map<String, String> fingerprints,
}) {
  final stillKey = item.motionOf;
  if (stillKey == null) return null;
  final row = ledger[stillKey];
  switch (row?.state) {
    case TakeoutItemState.inDrive:
      return row!.fileId;
    case TakeoutItemState.done:
      return null;
    default:
      final still = items[stillKey];
      return still == null ? null : takeoutMatch(still, fingerprints);
  }
}

/// Whether a photo file, [bytes], holds its own movement: a Samsung motion
/// photo carries the video after the picture under `MotionPhoto_Data`, and
/// a Pixel one says so in its XMP, `MotionPhoto="1"` or, older,
/// `MicroVideo="1"`. An iPhone Live Photo keeps its movement apart, so its
/// photo says nothing of the kind.
bool takeoutHoldsMotion(List<int> bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  return text.contains('MotionPhoto_Data') ||
      text.contains('MotionPhoto="1"') ||
      text.contains('<Camera:MotionPhoto>1') ||
      text.contains('MicroVideo="1"');
}

/// A video the import sent beside a photo the drive already held, before
/// it knew to leave such videos out.
typedef TakeoutExtraMotion = ({TakeoutItem item, String fileId, String stillId});

/// What a part added later shows about a photo the import already settled:
/// albums it hasn't been put in yet, or a star it hasn't been given. A
/// photo sits in its year's folder and in every album's, and with parts
/// added one at a time those copies can arrive in turn.
@immutable
class TakeoutTouch {
  const TakeoutTouch({required this.item, required this.fileId, this.albums = const [], this.star = false});

  final TakeoutItem item;

  /// The drive file that holds it.
  final String fileId;

  /// Titles of the albums to put it in.
  final List<String> albums;
  final bool star;
}

/// What one look at the import found: what to send, in order, what to add
/// to photos already settled, and how far along it is.
@immutable
class TakeoutPlan {
  const TakeoutPlan({
    required this.toSend,
    required this.progress,
    this.touch = const [],
    this.extraMotion = const [],
    this.missing = const [],
  });

  /// Items still to go up, in the catalog's order. An item whose upload is
  /// already in the queue is among them, to be followed rather than sent
  /// again.
  final List<TakeoutItem> toSend;

  /// Photos already settled that parts added since put in more albums or
  /// starred.
  final List<TakeoutTouch> touch;

  /// Videos sent beside photos the drive already held, to be moved to the
  /// trash if the person wants.
  final List<TakeoutExtraMotion> extraMotion;

  /// Keys of items the import settled whose drive file is gone.
  final List<String> missing;
  final TakeoutProgress progress;
}

/// The album titles a ledger row says the import gave its photo.
Set<String> takeoutGivenAlbums(TakeoutItemRow row) =>
    (row.albums ?? '').split('\n').where((title) => title.isNotEmpty).toSet();

/// How far along the import is, counted in items.
@immutable
class TakeoutProgress {
  const TakeoutProgress({
    this.total = 0,
    this.photos = 0,
    this.videos = 0,
    this.bytes = 0,
    this.albums = 0,
    this.sent = 0,
    this.inDrive = 0,
    this.alreadyThere = 0,
    this.failed = 0,
    this.skipped = 0,
    this.leftBytes = 0,
    this.sentBytes = 0,
    this.blocked = 0,
    this.undescribed = 0,
    this.toTouch = 0,
    this.extraMotion = 0,
    this.missing = 0,
    this.partsLeft = const {},
    this.partsTotal = const {},
  });

  /// Photos and videos in the export, each counted once.
  final int total;
  final int photos;
  final int videos;
  final int bytes;
  final int albums;

  /// Sent up by the import.
  final int sent;

  /// Found already in the drive, and not sent again.
  final int inDrive;

  /// Still to go, but already in the drive by [takeoutMatchKeys], so they
  /// will be passed over.
  final int alreadyThere;

  /// Tried [takeoutMaxFailures] times without going up.
  final int failed;

  /// Left out, by the person or by a cancelled upload.
  final int skipped;

  /// Bytes still to send, leaving out [alreadyThere].
  final int leftBytes;

  /// Bytes of what the import has sent, this run and before.
  final int sentBytes;

  /// Still to go, but only in parts Telegrive can't read now.
  final int blocked;

  /// Without details: their dates came from their names or files.
  final int undescribed;

  /// Photos already settled that still have albums or a star to be given,
  /// from parts added since.
  final int toTouch;

  /// Videos of Live Photos sent beside photos the drive already held.
  final int extraMotion;

  /// Photos and videos the import settled whose file is gone from the
  /// drive.
  final int missing;

  /// Items still to go that each part holds, by part id. A part with none
  /// left can be deleted.
  final Map<String, int> partsLeft;

  /// Items each part holds, by part id.
  final Map<String, int> partsTotal;

  /// Items not settled yet: to send, already there, or blocked.
  int get left => total - sent - inDrive - failed - skipped;

  /// Every item is settled, one way or another, and has every album and
  /// star the parts show.
  bool get finished => total > 0 && left == 0 && toTouch == 0;

  /// These counts with one more photo given what a later part showed.
  TakeoutProgress touched() => TakeoutProgress(
    total: total,
    photos: photos,
    videos: videos,
    bytes: bytes,
    albums: albums,
    sent: sent,
    inDrive: inDrive,
    alreadyThere: alreadyThere,
    failed: failed,
    skipped: skipped,
    leftBytes: leftBytes,
    sentBytes: sentBytes,
    blocked: blocked,
    undescribed: undescribed,
    toTouch: toTouch > 0 ? toTouch - 1 : 0,
    extraMotion: extraMotion,
    missing: missing,
    partsLeft: partsLeft,
    partsTotal: partsTotal,
  );
}

/// Looks through [catalog] against what the import has settled, [ledger].
/// An item done, in the drive or left out is passed over, and one that
/// failed [takeoutMaxFailures] times counts as failed. Of the rest, one
/// whose every copy is in [unreadable] parts is blocked, one [takeoutMatch]
/// finds in [fingerprints] is already there, and everything is sent in the
/// catalog's order. The video of a photo the drive already held counts as
/// already there too, by [takeoutMotionHome]. An item done or in the drive
/// that the catalog now puts in an album, or stars, beyond what its row
/// says it was given, is to be touched. With [driveFiles], the ids of every
/// file in the drive, an item done or in the drive whose file isn't among
/// them is missing. What the ledger settled about photos of parts no longer
/// read, deleted from the phone say, counts too, so the import still says
/// how it went once its parts are gone.
TakeoutPlan planTakeout({
  required TakeoutCatalog catalog,
  required Map<String, TakeoutItemRow> ledger,
  required Map<String, String> fingerprints,
  Set<String> unreadable = const {},
  Set<String>? driveFiles,
}) {
  final byKey = {for (final item in catalog.items) item.key: item};
  final extraMotion = <TakeoutExtraMotion>[];
  final missing = <String>[];
  void check(TakeoutItem item, TakeoutItemRow row) {
    final fileId = row.fileId;
    if (driveFiles != null && fileId != null && !driveFiles.contains(fileId)) missing.add(item.key);
  }

  final toSend = <TakeoutItem>[];
  final touch = <TakeoutTouch>[];
  var sent = 0, inDrive = 0, alreadyThere = 0, failed = 0, skipped = 0, blocked = 0;
  var leftBytes = 0, sentBytes = 0, undescribed = 0;
  final partsLeft = <String, int>{};
  void touchIfNeeded(TakeoutItem item, TakeoutItemRow row) {
    // A row that doesn't say what it was given is left as it is.
    final fileId = row.fileId;
    if (fileId == null || row.albums == null) return;
    final given = takeoutGivenAlbums(row);
    final albums = [for (final title in item.albums) if (!given.contains(title)) title];
    final star = item.starred && !(row.starred ?? false);
    if (albums.isNotEmpty || star) {
      touch.add(TakeoutTouch(item: item, fileId: fileId, albums: albums, star: star));
    }
  }

  final partsTotal = <String, int>{};
  for (final item in catalog.items) {
    if (!item.described) undescribed++;
    for (final part in {for (final source in item.sources) source.part}) {
      partsTotal[part] = (partsTotal[part] ?? 0) + 1;
    }
    final row = ledger[item.key];
    switch (row?.state) {
      case TakeoutItemState.done:
        sent++;
        sentBytes += item.size;
        touchIfNeeded(item, row!);
        check(item, row);
        if (row.fileId case final fileId?) {
          final still = takeoutMotionHome(item, items: byKey, ledger: ledger, fingerprints: fingerprints);
          if (still != null && still != fileId) extraMotion.add((item: item, fileId: fileId, stillId: still));
        }
        continue;
      case TakeoutItemState.inDrive:
        inDrive++;
        touchIfNeeded(item, row!);
        check(item, row);
        continue;
      case TakeoutItemState.skipped:
        skipped++;
        continue;
      case TakeoutItemState.failed when row!.failures >= takeoutMaxFailures:
        failed++;
        continue;
      default:
    }
    for (final part in {for (final source in item.sources) source.part}) {
      partsLeft[part] = (partsLeft[part] ?? 0) + 1;
    }
    final following = row?.state == TakeoutItemState.pending && row?.transferId != null;
    if (!following && item.sources.every((s) => unreadable.contains(s.part))) {
      blocked++;
      continue;
    }
    if (!following &&
        (takeoutMatch(item, fingerprints) ??
                takeoutMotionHome(item, items: byKey, ledger: ledger, fingerprints: fingerprints)) !=
            null) {
      alreadyThere++;
    } else {
      leftBytes += item.size;
    }
    toSend.add(item);
  }
  // Photos of parts no longer read, settled before they went.
  var gone = 0;
  for (final row in ledger.values) {
    if (byKey.containsKey(row.key)) continue;
    switch (row.state) {
      case TakeoutItemState.done:
        sent++;
      case TakeoutItemState.inDrive:
        inDrive++;
      case TakeoutItemState.skipped:
        skipped++;
      case TakeoutItemState.failed when row.failures >= takeoutMaxFailures:
        failed++;
      default:
        continue;
    }
    gone++;
  }
  return TakeoutPlan(
    toSend: toSend,
    touch: touch,
    extraMotion: extraMotion,
    missing: missing,
    progress: TakeoutProgress(
      total: catalog.items.length + gone,
      photos: catalog.photos,
      videos: catalog.videos,
      bytes: catalog.bytes,
      albums: catalog.albums.length,
      sent: sent,
      inDrive: inDrive,
      alreadyThere: alreadyThere,
      failed: failed,
      skipped: skipped,
      leftBytes: leftBytes,
      sentBytes: sentBytes,
      blocked: blocked,
      undescribed: undescribed,
      toTouch: touch.length,
      extraMotion: extraMotion.length,
      missing: missing.length,
      partsLeft: partsLeft,
      partsTotal: partsTotal,
    ),
  );
}

/// How fast the import goes and how long the [left] bytes take, from
/// [samples] of the bytes it had sent, oldest first, the last at [now]. A
/// speed is told only once the samples span [settle], since a file's first
/// seconds say little about the rest.
({double speed, Duration? timeLeft}) takeoutPaceOf(
  List<(DateTime, int)> samples, {
  required int left,
  Duration settle = const Duration(seconds: 8),
}) {
  if (samples.length < 2) return (speed: 0, timeLeft: null);
  final (since, from) = samples.first;
  final (now, sent) = samples.last;
  final watched = now.difference(since);
  if (watched < settle) return (speed: 0, timeLeft: null);
  final speed = math.max(0, sent - from) / (watched.inMilliseconds / 1000);
  return (speed: speed, timeLeft: speed > 0 ? Duration(seconds: (left / speed).round()) : null);
}

/// The catalog of what [entries] and [details], read from [parts], hold.
TakeoutCatalog takeoutCatalogOf({
  required List<TakeoutPartRow> parts,
  required List<TakeoutEntryRow> entries,
  required List<TakeoutDetailRow> details,
}) {
  final order = [...parts]..sort((a, b) => compareTakeoutParts(a.name, b.name));
  return buildTakeoutCatalog(
    media: [
      for (final row in entries)
        TakeoutMedia(
          row.partId,
          ZipEntry(
            path: row.path,
            method: row.method,
            crc: row.crc,
            compressedSize: row.compressedSize,
            size: row.size,
            headerOffset: row.headerOffset,
          ),
        ),
    ],
    sidecars: [
      for (final row in details)
        if (!row.album)
          TakeoutSidecar(
            folder: _folderOf(row.path),
            fileName: p.posix.basename(row.path),
            title: row.title,
            takenAt: row.takenAt,
            favorited: row.favorited,
          ),
    ],
    albums: [
      for (final row in details)
        if (row.album) TakeoutAlbum(folder: _folderOf(row.path), title: row.title),
    ],
    partOrder: [for (final part in order) part.id],
  );
}

String _folderOf(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}

// -----------------------------------------------------------------------------
// The import
// -----------------------------------------------------------------------------

/// What the import is doing with one photo or video now.
enum TakeoutStep {
  /// Looking for it in the drive.
  checking,

  /// Taking it out of its part into the cache.
  extracting,

  /// Its upload is in the queue.
  uploading,

  /// Putting a copy the drive already holds in its albums, or starring it.
  updating,
}

/// A photo or video the import has in hand.
@immutable
class TakeoutFlight {
  const TakeoutFlight({
    required this.key,
    required this.name,
    required this.size,
    required this.step,
    this.part,
    this.transferId,
  });

  final String key;
  final String name;
  final int size;
  final TakeoutStep step;

  /// The part it is coming out of, as the list names it, while extracting.
  final String? part;

  /// Its upload, while uploading.
  final String? transferId;
}

/// Where the import stands.
enum TakeoutPhase {
  /// Nothing going on: no parts yet, not started, paused, or done.
  idle,

  /// Reading the parts' lists of files and the details in them.
  reading,

  /// Sending photos and videos up.
  importing,

  /// The next ones wait, since the phone is on mobile data they may not
  /// use, or that would pass the monthly limit.
  waitingForWifi,

  /// The phone hasn't room to take the next file out of its part.
  waitingForRoom,
}

@immutable
class TakeoutState {
  const TakeoutState({
    this.phase = TakeoutPhase.idle,
    this.running = false,
    this.progress,
    this.current,
    this.reading,
    this.roomNeeded = 0,
    this.working = false,
    this.flights = const [],
    this.speed = 0,
    this.timeLeft,
    this.uploadedBytes = 0,
    this.withoutPreview = (count: 0, bytes: 0),
  });

  final TakeoutPhase phase;

  /// The person started the import and hasn't paused it.
  final bool running;

  /// Null until the parts have been looked through.
  final TakeoutProgress? progress;

  /// Name of the file going up now.
  final String? current;

  /// Name of the part being read now.
  final String? reading;

  /// Bytes more the phone needs free, while [phase] is waiting for room.
  final int roomNeeded;

  /// Files are being sent, the moments between two of them included,
  /// which is what keeps the transfer service up.
  final bool working;

  /// The photos and videos in hand, in the order they were taken up.
  final List<TakeoutFlight> flights;

  /// Bytes a second the import has sent over the last minute, the gaps
  /// between files included, so it speaks for the whole import rather than
  /// the files in hand; 0 until it has watched long enough to say.
  final double speed;

  /// How long the bytes still to send take at [speed]; null while that
  /// can't be told.
  final Duration? timeLeft;

  /// Bytes the import has sent, those of the files in hand so far included.
  final int uploadedBytes;

  /// Photos and videos the import sent that have no preview, and their
  /// bytes, which making previews fetches and sends again.
  final ({int count, int bytes}) withoutPreview;

  /// This state with what is given changed. What goes on now, [current]
  /// and [reading], is never carried over, since it is always about to
  /// change.
  TakeoutState copyWith({
    TakeoutPhase? phase,
    bool? running,
    TakeoutProgress? progress,
    String? current,
    String? reading,
    int? roomNeeded,
    bool? working,
    List<TakeoutFlight>? flights,
    ({double speed, Duration? timeLeft, int uploadedBytes})? pace,
    bool clearPace = false,
    ({int count, int bytes})? withoutPreview,
  }) => TakeoutState(
    phase: phase ?? this.phase,
    running: running ?? this.running,
    progress: progress ?? this.progress,
    current: current,
    reading: reading,
    roomNeeded: roomNeeded ?? this.roomNeeded,
    working: working ?? this.working,
    flights: flights ?? this.flights,
    speed: clearPace ? 0 : pace?.speed ?? speed,
    timeLeft: clearPace ? null : (pace == null ? timeLeft : pace.timeLeft),
    uploadedBytes: pace?.uploadedBytes ?? uploadedBytes,
    withoutPreview: withoutPreview ?? this.withoutPreview,
  );
}

/// What came of sending one item.
enum _Outcome { settled, waitForWifi, waitForRoom, stopped }

/// Imports a Google Photos export: the zip files Takeout makes, picked on
/// this phone and read where they lie.
///
/// Each part's list of files and the JSON details in it are read once and
/// kept, so the photos are matched with their details across every part
/// added, then go up two at a time, each taken out of its part into the
/// cache and queued as an upload into Files › Google Photos › its year,
/// carrying when it was taken, its albums and its star in its caption. A
/// ledger keyed by each file's size and checksum remembers what went up,
/// so a photo in several albums goes up once, a photo the drive already
/// holds by [takeoutMatchKeys] is passed over, and a later export picks
/// up where this one ended. Photo backup's Mobile data choice and monthly
/// limit govern these uploads too.
///
/// It runs while Telegrive is open, carrying on when it opens again if it
/// was running, and never on its own while it is closed.
class TakeoutImport extends Notifier<TakeoutState> {
  static const int _parallel = 2;

  /// Left free on the phone on top of each file taken out, so a part of
  /// big videos never fills it.
  static const int _keepFree = 200 << 20;

  /// JSON files read in one go while a part is read.
  static const int _jsonBatch = 512;

  bool _running = false;
  bool _rerun = false;
  bool _stopRequested = false;
  Timer? _debounce;

  /// What the parts hold, matched; null once a part is added, read or
  /// removed, until the next look.
  TakeoutCatalog? _catalog;

  /// The uploads being followed, for what the monthly limit has already let
  /// onto mobile data.
  final Set<String> _following = {};

  /// The photos and videos in hand, by key, as [TakeoutState.flights] shows
  /// them.
  final Map<String, TakeoutFlight> _flights = {};

  /// Bytes sent, sampled each second while sending, over the last
  /// [_paceWindow], for [TakeoutState.speed].
  final List<(DateTime, int)> _samples = [];
  Timer? _sampler;
  static const Duration _paceWindow = Duration(seconds: 60);

  /// The least watching before a speed is told: a file's first seconds say
  /// little about the rest.
  static const Duration _paceSettle = Duration(seconds: 8);

  /// Whether each Live Photo's photo holds its own movement, by key, as read
  /// from its part once.
  final Map<String, bool> _holdsMotion = {};

  /// Files this run couldn't make a preview of, by id, so making previews
  /// again doesn't fetch them for nothing.
  final Set<String> _noPicture = {};

  /// Every item of the catalog by key, for the moving parts of Live Photos
  /// to find their photos.
  Map<String, TakeoutItem> _items = const {};

  /// What the last look found to offer the person: videos sent beside
  /// photos the drive already held, and items whose file is gone.
  List<TakeoutExtraMotion> _extraMotion = const [];
  List<String> _missing = const [];

  /// Album ids by title, and folder ids by path, found or made this run.
  final Map<String, String> _albumIds = {};
  final Map<String, String> _folderIds = {};

  /// Ends once the last upload asked for has its name and its place in the
  /// queue, so two files of one name get names of their own.
  Future<void> _naming = Future.value();

  /// Ends once the last folder or album asked for is found or made, so two
  /// uploads going at once that need the same one don't each make it.
  Future<void> _making = Future.value();

  AppDatabase get _db => ref.read(appDatabaseProvider);
  DriveRepository get _repository => ref.read(driveRepositoryProvider);
  TakeoutFiles get _files => ref.read(takeoutFilesProvider);
  Preferences get _prefs => ref.read(preferencesProvider);
  TransferQueue get _queue => ref.read(transferQueueProvider.notifier);

  @override
  TakeoutState build() {
    ref.listen<DriveSession?>(driveSessionProvider, (previous, next) {
      if (next == null) {
        _stopRequested = true;
      } else if (previous?.chatId != next.chatId) {
        _albumIds.clear();
        _folderIds.clear();
        schedule(immediate: true);
      }
    });
    ref.listen<SyncState>(driveSyncProvider, (previous, next) {
      if ((previous?.running ?? false) && !next.running && next.error == null && state.running) {
        schedule();
      }
    });
    ref.listen<NetworkState>(networkStatusProvider, (_, next) {
      if (state.phase == TakeoutPhase.waitingForWifi && next.online && !next.metered) {
        schedule(immediate: true);
      }
    });
    ref.onDispose(() {
      _debounce?.cancel();
      _sampler?.cancel();
    });
    return TakeoutState(running: ref.read(preferencesProvider).takeoutRunning);
  }

  /// Opens Android's picker for the parts and adds the ones picked, then
  /// reads them. A part picked again by the same name, a second download
  /// of it say, takes the earlier one's place and is read afresh. Answers
  /// how many were picked.
  Future<int> addParts() async {
    final picked = await _files.pick();
    if (picked.isEmpty) return 0;
    final existing = await _db.takeoutPartList();
    final now = DateTime.now();
    for (final (index, archive) in picked.indexed) {
      final same = existing.where((part) => part.name == archive.name || part.uri == archive.uri).firstOrNull;
      if (same != null && same.uri != archive.uri) await _files.release(same.uri);
      await _db.saveTakeoutPart(
        TakeoutPartsCompanion.insert(
          id: same?.id ?? _repository.newId(),
          uri: archive.uri,
          name: archive.name,
          size: archive.size,
          // Keep the picker's order between parts picked together.
          addedAt: same?.addedAt ?? now.add(Duration(microseconds: index)),
          readAt: const Value(null),
          problem: const Value(null),
          deletedAt: const Value(null),
        ),
      );
    }
    _catalog = null;
    _rethink();
    return picked.length;
  }

  /// Starts the import, or carries on after a pause.
  Future<void> start() async {
    await _prefs.setTakeoutRunning(true);
    state = state.copyWith(running: true);
    await _queue.resumeAll((row) => row.origin == TransferOrigin.takeout);
    schedule(immediate: true);
  }

  /// Pauses the import: nothing new starts, and the uploads under way stop
  /// where they are, to carry on from there.
  Future<void> pause() async {
    await _prefs.setTakeoutRunning(false);
    _stopRequested = true;
    state = state.copyWith(running: false);
    await _queue.pauseAll((row) => row.origin == TransferOrigin.takeout);
  }

  /// Moves to the trash the videos the import sent beside Live Photos the
  /// drive already held, one at a time as a bulk change, so the screen can
  /// say how far it got and Stop can end it. Each is recorded as held by
  /// its photo as it goes, so none is sent again, stopped or not.
  Future<BulkOutcome> trashExtraMotion() async {
    final extra = _extraMotion;
    final ledger = await _db.takeoutLedger();
    final outcome = await ref.read(bulkEditsProvider.notifier).run<TakeoutExtraMotion>(
      label: 'Moving ${Formatters.count(extra.length, 'video')} to the trash',
      icon: Icons.delete_outline_rounded,
      items: extra,
      apply: (motion) async {
        final row = ledger[motion.item.key];
        if (row == null) return;
        if (await _repository.fileById(motion.fileId) case final file?) {
          await _repository.trash(files: [file]);
        }
        await _db.saveTakeoutItems([
          row
              .copyWith(state: TakeoutItemState.inDrive, fileId: Value(motion.stillId), updatedAt: DateTime.now())
              .toCompanion(false),
        ]);
      },
    );
    schedule(immediate: true);
    return outcome;
  }

  /// Gives the items whose file went from the drive another go: they count
  /// as never sent, and go up again from the parts still on the phone.
  Future<void> importMissingAgain() async {
    await _db.forgetTakeoutItems(_missing);
    _rethink();
  }

  /// Gives the items that failed [takeoutMaxFailures] times another go.
  Future<void> retryFailed() async {
    final ledger = await _db.takeoutLedger();
    await _db.forgetTakeoutItems([
      for (final row in ledger.values)
        if (row.state == TakeoutItemState.failed) row.key,
    ]);
    schedule(immediate: true);
  }

  /// Takes part [id] off the list and gives Android back the access to it.
  /// What it already sent stays in the drive and in the ledger, and the
  /// details read from it stay for photos in other parts.
  Future<void> removePart(String id) async {
    final part = (await _db.takeoutPartList()).where((p) => p.id == id).firstOrNull;
    if (part == null) return;
    if (part.deletedAt == null) await _files.release(part.uri);
    await _db.removeTakeoutPart(id);
    _catalog = null;
    _rethink();
  }

  /// Deletes part [id] from the phone, so the next can be downloaded in its
  /// room. It stays on the list as done. False when the app that holds it
  /// won't let Telegrive delete it.
  Future<bool> deletePart(String id) async {
    final part = (await _db.takeoutPartList()).where((p) => p.id == id).firstOrNull;
    if (part == null || part.deletedAt != null) return true;
    if (!await _files.delete(part.uri)) return false;
    await _db.markTakeoutPartDeleted(id, DateTime.now());
    _catalog = null;
    _rethink();
    return true;
  }

  /// Forgets the import on this phone: its parts, with the access to each
  /// given back, and what it settled, and calls off its uploads under way.
  /// What it sent stays in the drive.
  Future<void> startOver() async {
    await pause();
    for (final item in ref.read(transferQueueProvider).items) {
      if (item.origin == TransferOrigin.takeout && item.status.isPending) await _queue.cancel(item.id);
    }
    await _forget();
    state = const TakeoutState();
    schedule(immediate: true);
  }

  /// Forgets the import, as part of forgetting the drive on this phone.
  Future<void> forgetAll() async {
    _stopRequested = true;
    _debounce?.cancel();
    await _prefs.setTakeoutRunning(false);
    await _forget();
    state = const TakeoutState();
  }

  Future<void> _forget() async {
    for (final part in await _db.takeoutPartList()) {
      await _files.release(part.uri);
    }
    await _files.closeAll();
    await _db.clearTakeout();
    _catalog = null;
    _albumIds.clear();
    _folderIds.clear();
    _holdsMotion.clear();
  }

  /// Takes a sample of what the import has sent, and works out from the
  /// samples of the last minute how fast it goes and how long the rest
  /// takes. The bytes of the files in hand count as they go, so the speed
  /// moves smoothly, and the time spent between files counts too.
  void _sample() {
    final progress = state.progress;
    if (!ref.mounted || progress == null) return;
    final transfers = ref.read(transferQueueProvider);
    var inHand = 0;
    for (final flight in _flights.values) {
      if (flight.transferId case final id?) inHand += transfers.byId(id)?.row.doneBytes ?? 0;
    }
    final now = DateTime.now();
    final sent = progress.sentBytes + inHand;
    _samples.add((now, sent));
    while (_samples.length > 2 && now.difference(_samples.first.$1) > _paceWindow) {
      _samples.removeAt(0);
    }
    final pace = takeoutPaceOf(_samples, left: math.max(0, progress.leftBytes - inHand), settle: _paceSettle);
    state = state.copyWith(
      current: state.current,
      pace: (speed: pace.speed, timeLeft: pace.timeLeft, uploadedBytes: sent),
    );
  }

  /// Says that [item] is at [step] now.
  void _fly(TakeoutItem item, TakeoutStep step, {String? part, String? transferId}) {
    _flights[item.key] = TakeoutFlight(
      key: item.key,
      name: item.name,
      size: item.size,
      step: step,
      part: part,
      transferId: transferId,
    );
    if (ref.mounted) state = state.copyWith(flights: [..._flights.values], current: item.name);
  }

  /// [key] is out of hand.
  void _land(String key) {
    if (_flights.remove(key) == null || !ref.mounted) return;
    state = state.copyWith(flights: [..._flights.values], current: state.current);
  }

  /// Has a pass under way stop once the files it is sending are through, so
  /// the next one starts from the parts as they now are.
  void _rethink() {
    if (_running) _stopRequested = true;
    schedule(immediate: true);
  }

  /// Looks at the import soon. Syncs come in bursts, so calls that aren't
  /// urgent are run together.
  void schedule({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(immediate ? Duration.zero : const Duration(seconds: 4), () => unawaited(run()));
  }

  Future<void> run() async {
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    try {
      do {
        _rerun = false;
        _stopRequested = false;
        await _pass();
      } while (_rerun);
    } catch (e, stack) {
      debugPrint('[Takeout] pass failed: $e\n$stack');
      if (ref.mounted) state = state.copyWith(phase: TakeoutPhase.idle);
    } finally {
      _running = false;
      if (ref.mounted && state.working) state = state.copyWith(working: false);
    }
  }

  Future<void> _pass() async {
    final session = ref.read(driveSessionProvider);
    if (session == null) return;
    final parts = await _db.takeoutPartList();
    if (parts.isEmpty) {
      state = TakeoutState(running: state.running);
      return;
    }
    await _readParts(parts);
    if (_stopRequested) return;

    // Uploads an earlier run left going are in the queue only once it has
    // read its rows; without them they would be taken for lost and sent a
    // second time.
    await _queue.loaded;
    await ref.read(driveSyncProvider.notifier).whenIdle();
    // "Already in the drive" is judged against the index, so nothing goes
    // until it holds the whole channel, as photo backup needs it to.
    final synced = _prefs.lastFullSync(session.chatId) != null && ref.read(driveSyncProvider).error == null;
    final driveRows = synced ? await _db.fileMatchRows() : const <({String id, String name, int size, DateTime? takenAt})>[];
    final fingerprints = {
      for (final file in driveRows)
        for (final key in takeoutMatchKeys(file.name, file.size, file.takenAt)) key: file.id,
    };
    final current = await _db.takeoutPartList();
    final catalog = _catalog ??= takeoutCatalogOf(
      parts: current,
      entries: await _db.takeoutEntryList(),
      details: await _db.takeoutDetailList(),
    );
    final unreadable = {
      for (final part in current)
        if (part.problem != null) part.id,
    };
    final ledger = await _reconcile(await _db.takeoutLedger());
    final plan = planTakeout(
      catalog: catalog,
      ledger: ledger,
      fingerprints: fingerprints,
      unreadable: unreadable,
      driveFiles: synced ? {for (final file in driveRows) file.id} : null,
    );
    _items = {for (final item in catalog.items) item.key: item};
    _extraMotion = plan.extraMotion;
    _missing = plan.missing;
    state = state.copyWith(
      phase: TakeoutPhase.idle,
      progress: plan.progress,
      roomNeeded: 0,
      withoutPreview: synced ? await _previewless() : null,
    );
    if (plan.progress.finished && state.running) await _done();
    if (!synced || !state.running || (plan.toSend.isEmpty && plan.touch.isEmpty)) return;
    await _send(plan, ledger, fingerprints, unreadable);
  }

  /// Reads each part not read yet: its list of files, and the details in
  /// its JSON files. A part that can't be read is marked with why.
  Future<void> _readParts(List<TakeoutPartRow> parts) async {
    for (final part in parts) {
      if (_stopRequested) return;
      if (part.deletedAt != null) continue;
      if (part.readAt != null && part.problem != TakeoutPartProblem.noAccess) continue;
      if (part.problem != null && part.problem != TakeoutPartProblem.noAccess) continue;
      try {
        if (!await _files.canRead(part.uri)) throw const TakeoutAccessException('No access');
        state = state.copyWith(phase: TakeoutPhase.reading, reading: part.name);
        _catalog = null;
        if (part.readAt != null) {
          // Readable again, as it was when it was read.
          await _db.updateTakeoutPart(part.id, const TakeoutPartsCompanion(problem: Value(null)));
          continue;
        }
        final source = _files.open(part.uri, part.size);
        final kept = (await ZipReader.entries(source)).where(takeoutKeeps).toList();
        final media = [for (final e in kept) if (!isTakeoutJson(e)) e];
        final jsons = [for (final e in kept) if (isTakeoutJson(e)) e];
        final details = <TakeoutDetailsCompanion>[];
        for (var start = 0; start < jsons.length; start += _jsonBatch) {
          if (_stopRequested) return;
          final batch = jsons.sublist(start, math.min(jsons.length, start + _jsonBatch));
          for (final (entry, bytes) in await _readJson(source, batch)) {
            final parsed = parseTakeoutJson(entry.path, bytes);
            if (parsed is TakeoutSidecar) {
              details.add(
                TakeoutDetailsCompanion.insert(
                  partId: part.id,
                  path: entry.path,
                  album: false,
                  title: parsed.title,
                  takenAt: Value(parsed.takenAt),
                  favorited: Value(parsed.favorited),
                ),
              );
            } else if (parsed is TakeoutAlbum) {
              details.add(
                TakeoutDetailsCompanion.insert(partId: part.id, path: entry.path, album: true, title: parsed.title),
              );
            }
          }
        }
        await _db.replaceTakeoutContents(part.id, [
          for (final e in media)
            TakeoutEntriesCompanion.insert(
              partId: part.id,
              path: e.path,
              method: e.method,
              crc: e.crc,
              compressedSize: e.compressedSize,
              size: e.size,
              headerOffset: e.headerOffset,
            ),
        ], details);
        await _db.updateTakeoutPart(
          part.id,
          TakeoutPartsCompanion(readAt: Value(DateTime.now()), problem: const Value(null)),
        );
      } on ZipFormatException catch (e) {
        debugPrint('[Takeout] ${part.name}: $e');
        await _db.updateTakeoutPart(part.id, TakeoutPartsCompanion(problem: Value(_problemOf(e.problem))));
      } on TakeoutAccessException catch (e) {
        debugPrint('[Takeout] ${part.name}: $e');
        await _db.updateTakeoutPart(part.id, const TakeoutPartsCompanion(problem: Value(TakeoutPartProblem.noAccess)));
      }
    }
  }

  /// The contents of [batch], in one go, or one by one when that fails, so
  /// a damaged JSON file costs only its own details.
  Future<List<(ZipEntry, List<int>)>> _readJson(ZipSource source, List<ZipEntry> batch) async {
    try {
      final contents = await ZipReader.contents(source, batch);
      return [for (final (i, entry) in batch.indexed) (entry, contents[i])];
    } on ZipFormatException catch (e) {
      if (e.problem == ZipProblem.incomplete) rethrow;
      return [
        for (final entry in batch)
          if (await _readOne(source, entry) case final bytes?) (entry, bytes),
      ];
    }
  }

  Future<List<int>?> _readOne(ZipSource source, ZipEntry entry) async {
    try {
      return (await ZipReader.contents(source, [entry])).single;
    } on ZipFormatException catch (e) {
      if (e.problem == ZipProblem.incomplete) rethrow;
      debugPrint('[Takeout] ${entry.path}: $e');
      return null;
    }
  }

  static TakeoutPartProblem _problemOf(ZipProblem problem) => switch (problem) {
    ZipProblem.notZip => TakeoutPartProblem.notZip,
    ZipProblem.incomplete => TakeoutPartProblem.incomplete,
    ZipProblem.damaged || ZipProblem.unsupported => TakeoutPartProblem.damaged,
  };

  /// Settles what [ledger] says is still going up against the queue: an
  /// upload that landed is done, one the person cancelled is left out, and
  /// one that failed, or is gone without its file reaching the drive,
  /// counts a failure. One still in the queue is left to be followed.
  Future<Map<String, TakeoutItemRow>> _reconcile(Map<String, TakeoutItemRow> ledger) async {
    final transfers = ref.read(transferQueueProvider);
    final changed = <String, TakeoutItemRow>{};
    for (final row in ledger.values) {
      final transferId = row.transferId;
      if (row.state != TakeoutItemState.pending || transferId == null) continue;
      final transfer = transfers.byId(transferId)?.row;
      if (transfer != null && transfer.status.isPending) continue;
      final TakeoutItemState next;
      if (transfer?.status == TransferStatus.completed ||
          (transfer == null && await _repository.isWhole(row.fileId ?? ''))) {
        next = TakeoutItemState.done;
      } else if (transfer?.status == TransferStatus.cancelled) {
        next = TakeoutItemState.skipped;
      } else {
        next = TakeoutItemState.failed;
      }
      changed[row.key] = row.copyWith(
        state: next,
        transferId: const Value(null),
        failures: next == TakeoutItemState.failed ? row.failures + 1 : row.failures,
        reason: Value(next == TakeoutItemState.failed ? describeTransferError(transfer?.error) : null),
        updatedAt: DateTime.now(),
      );
    }
    if (changed.isEmpty) return ledger;
    await _db.saveTakeoutItems([for (final row in changed.values) row.toCompanion(false)]);
    return {...ledger, ...changed};
  }

  /// Gives the photos [plan] touches their albums and stars, one at a time
  /// since each is an edit, then sends what it lists, [_parallel] at a
  /// time, keeping the counts in [state] up to date. It stops early once
  /// the phone is on mobile data the files may not use, when the phone runs
  /// short of room, and when the import is paused.
  Future<void> _send(
    TakeoutPlan plan,
    Map<String, TakeoutItemRow> ledger,
    Map<String, String> fingerprints,
    Set<String> unreadable,
  ) async {
    var progress = plan.progress;
    state = state.copyWith(phase: TakeoutPhase.importing, working: true, clearPace: true);
    _samples.clear();
    _sampler?.cancel();
    _sampler = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
    for (final touch in plan.touch) {
      if (_stopRequested || !state.running || !ref.mounted) break;
      state = state.copyWith(current: touch.item.name);
      final row = ledger[touch.item.key];
      if (row == null) continue;
      _fly(touch.item, TakeoutStep.updating);
      try {
        ledger[touch.item.key] = await _touch(touch, row);
        progress = progress.touched();
        state = state.copyWith(progress: progress, current: touch.item.name);
      } catch (e) {
        // Tried again on the next look.
        debugPrint('[Takeout] ${touch.item.name}: $e');
      } finally {
        _land(touch.item.key);
      }
    }
    final queue = plan.toSend.iterator;
    _Outcome? stop;
    var roomNeeded = 0;

    Future<void> worker() async {
      while (stop == null && !_stopRequested && state.running && queue.moveNext()) {
        final item = queue.current;
        if (ref.mounted) state = state.copyWith(current: item.name);
        final (outcome, row) = await _sendOne(item, ledger, fingerprints, unreadable, (bytes) => roomNeeded = bytes);
        if (row != null) ledger[item.key] = row;
        if (outcome != _Outcome.settled) {
          stop ??= outcome;
          return;
        }
        progress = _advance(progress, item, row);
        if (ref.mounted) state = state.copyWith(progress: progress, current: state.current);
      }
    }

    await Future.wait([for (var i = 0; i < _parallel; i++) worker()]);
    _sampler?.cancel();
    _sampler = null;
    if (!ref.mounted) return;
    state = state.copyWith(
      clearPace: true,
      phase: switch (stop) {
        _Outcome.waitForWifi => TakeoutPhase.waitingForWifi,
        _Outcome.waitForRoom => TakeoutPhase.waitingForRoom,
        _ => TakeoutPhase.idle,
      },
      roomNeeded: roomNeeded,
      working: false,
    );
    if (progress.finished) await _done();
    // What went up this time may lack a preview too.
    final previewless = await _previewless();
    if (ref.mounted) state = state.copyWith(withoutPreview: previewless);
  }

  /// How many photos and videos the import sent have no preview, and their
  /// bytes.
  Future<({int count, int bytes})> _previewless() async {
    final rows = await _withoutPreview();
    return (count: rows.length, bytes: rows.fold(0, (sum, row) => sum + row.size));
  }

  /// Everything is settled, so the import is done: a part added later waits
  /// for Import rather than going up on its own.
  Future<void> _done() async {
    await _prefs.setTakeoutRunning(false);
    if (ref.mounted) state = state.copyWith(running: false);
  }

  /// [progress] after [item] came to [after].
  static TakeoutProgress _advance(TakeoutProgress progress, TakeoutItem item, TakeoutItemRow? after) {
    final settledNow = switch (after?.state) {
      TakeoutItemState.done || TakeoutItemState.inDrive || TakeoutItemState.skipped => true,
      TakeoutItemState.failed => after!.failures >= takeoutMaxFailures,
      _ => false,
    };
    if (!settledNow) return progress;
    final wasThere = after!.state == TakeoutItemState.inDrive;
    final partsLeft = {...progress.partsLeft};
    for (final part in {for (final source in item.sources) source.part}) {
      final left = (partsLeft[part] ?? 1) - 1;
      if (left <= 0) {
        partsLeft.remove(part);
      } else {
        partsLeft[part] = left;
      }
    }
    return TakeoutProgress(
      total: progress.total,
      photos: progress.photos,
      videos: progress.videos,
      bytes: progress.bytes,
      albums: progress.albums,
      sent: progress.sent + (after.state == TakeoutItemState.done ? 1 : 0),
      inDrive: progress.inDrive + (wasThere ? 1 : 0),
      alreadyThere: math.max(0, progress.alreadyThere - (wasThere ? 1 : 0)),
      failed: progress.failed + (after.state == TakeoutItemState.failed ? 1 : 0),
      skipped: progress.skipped + (after.state == TakeoutItemState.skipped ? 1 : 0),
      leftBytes: wasThere ? progress.leftBytes : math.max(0, progress.leftBytes - item.size),
      sentBytes: progress.sentBytes + (after.state == TakeoutItemState.done ? item.size : 0),
      blocked: progress.blocked,
      undescribed: progress.undescribed,
      toTouch: progress.toTouch,
      extraMotion: progress.extraMotion,
      missing: progress.missing,
      partsLeft: partsLeft,
      partsTotal: progress.partsTotal,
    );
  }

  /// Puts the drive file [touch] names in its albums and stars it, then
  /// records that in [row]. A file gone from the drive needs nothing.
  Future<TakeoutItemRow> _touch(TakeoutTouch touch, TakeoutItemRow row) async {
    final file = await _repository.fileById(touch.fileId);
    if (file != null) {
      await _repository.addDetails(
        file,
        albumIds: [for (final title in touch.albums) await _albumFor(title)],
        star: touch.star,
      );
    }
    final given = row.copyWith(
      albums: Value(([...takeoutGivenAlbums(row), ...touch.albums]..sort()).join('\n')),
      starred: Value((row.starred ?? false) || touch.star),
      updatedAt: DateTime.now(),
    );
    await _db.saveTakeoutItems([given.toCompanion(false)]);
    return given;
  }

  /// Sends [item] up, or follows its upload already in the queue, and
  /// records how that went. Answers why it stopped, when it did, with the
  /// item's ledger row as it stands.
  Future<(_Outcome, TakeoutItemRow?)> _sendOne(
    TakeoutItem item,
    Map<String, TakeoutItemRow> ledger,
    Map<String, String> fingerprints,
    Set<String> unreadable,
    void Function(int bytes) needsRoom,
  ) async {
    _fly(item, TakeoutStep.checking);
    try {
      return await _sendInHand(item, ledger, fingerprints, unreadable, needsRoom);
    } finally {
      _land(item.key);
    }
  }

  Future<(_Outcome, TakeoutItemRow?)> _sendInHand(
    TakeoutItem item,
    Map<String, TakeoutItemRow> ledger,
    Map<String, String> fingerprints,
    Set<String> unreadable,
    void Function(int bytes) needsRoom,
  ) async {
    var row = ledger[item.key];
    final isVideo = item.kind == FileKind.video;
    String? transferId = row?.state == TakeoutItemState.pending ? row?.transferId : null;
    if (transferId != null && ref.read(transferQueueProvider).byId(transferId)?.status.isPending != true) {
      transferId = null;
    }

    if (transferId == null) {
      final home =
          takeoutMatch(item, fingerprints) ??
          takeoutMotionHome(item, items: _items, ledger: ledger, fingerprints: fingerprints);
      if (home == null && await _stillHoldsMotion(item)) {
        // The photo carries this video inside it, so sending it again would
        // only put the movement in the drive twice.
        final still = ledger[item.motionOf!];
        return (
          _Outcome.settled,
          await _save(item, TakeoutItemState.inDrive, fileId: still?.fileId, given: true),
        );
      }
      if (home case final fileId?) {
        _fly(item, TakeoutStep.updating);
        try {
          await _addDetails(fileId, item);
        } catch (e) {
          debugPrint('[Takeout] ${item.name}: $e');
          return (_Outcome.settled, await _failed(item, row, e));
        }
        return (_Outcome.settled, await _save(item, TakeoutItemState.inDrive, fileId: fileId, given: true));
      }
      if (!await _mayGo(item.size, isVideo: isVideo)) return (_Outcome.waitForWifi, row);
      if (await Room.shortfall(ref.read(deviceStorageProvider), item.size + _keepFree) case (final needed, final free)?) {
        needsRoom(needed - free);
        return (_Outcome.waitForRoom, row);
      }
      final ({String id, String fileId})? queued;
      try {
        queued = await _start(item, unreadable, isVideo: isVideo);
      } on _Blocked {
        return (_Outcome.settled, row);
      } catch (e) {
        debugPrint('[Takeout] ${item.name}: $e');
        return (_Outcome.settled, await _failed(item, row, e));
      }
      if (queued == null) return (_Outcome.settled, row);
      transferId = queued.id;
      row = await _save(
        item,
        TakeoutItemState.pending,
        transferId: transferId,
        fileId: queued.fileId,
        failures: row?.failures ?? 0,
        given: true,
      );
    }

    _following.add(transferId);
    _fly(item, TakeoutStep.uploading, transferId: transferId);
    try {
      final ended = await _untilSettled(transferId);
      if (ended == null) {
        return (_stopRequested || !state.running ? _Outcome.stopped : _Outcome.waitForWifi, row);
      }
      if (ended.status == TransferStatus.paused) {
        // Paused from the notification, which pauses the import with it.
        if (state.running) await pause();
        return (_Outcome.stopped, row);
      }
      switch (ended.status) {
        case TransferStatus.completed:
          for (final key in takeoutMatchKeys(item.name, item.size, item.takenAt)) {
            fingerprints[key] = ended.fileId;
          }
          return (
            _Outcome.settled,
            await _save(item, TakeoutItemState.done, fileId: ended.fileId, given: true, carried: row),
          );
        case TransferStatus.cancelled:
          return (_Outcome.settled, await _save(item, TakeoutItemState.skipped));
        default:
          return (
            _Outcome.settled,
            await _save(
              item,
              TakeoutItemState.failed,
              failures: (row?.failures ?? 0) + 1,
              reason: describeTransferError(ended.error),
            ),
          );
      }
    } finally {
      _following.remove(transferId);
    }
  }

  /// Takes [item] out of the first part that can be read into the cache and
  /// queues its upload; answers the upload's id and the drive file it goes
  /// up as. A part found unreadable is marked so and the next is tried;
  /// when none is left, [_Blocked].
  Future<({String id, String fileId})?> _start(TakeoutItem item, Set<String> unreadable, {required bool isVideo}) async {
    final cache = await getTemporaryDirectory();
    final dir = Directory(p.join(cache.path, 'takeout', '${DateTime.now().microsecondsSinceEpoch}'));
    await dir.create(recursive: true);
    final path = p.join(dir.path, DeviceStorage.safeName(item.name));
    final parts = {for (final part in await _db.takeoutPartList()) part.id: part};
    var extracted = false;
    for (final source in item.sources) {
      final part = parts[source.part];
      if (part == null || unreadable.contains(part.id)) continue;
      _fly(
        item,
        TakeoutStep.extracting,
        part: switch (takeoutPartNumber(part.name)) {
          (:final number, export: _) => 'part $number',
          null => part.name,
        },
      );
      try {
        final zip = _files.open(part.uri, part.size);
        final [offset] = await ZipReader.dataOffsets(zip, [source.entry]);
        await zip.extract(source.entry, offset, path);
        extracted = true;
        break;
      } on TakeoutAccessException {
        unreadable.add(part.id);
        await _db.updateTakeoutPart(part.id, const TakeoutPartsCompanion(problem: Value(TakeoutPartProblem.noAccess)));
      } on ZipFormatException catch (e) {
        if (e.problem != ZipProblem.incomplete) {
          await _deleteQuietly(dir);
          rethrow;
        }
        unreadable.add(part.id);
        await _db.updateTakeoutPart(part.id, const TakeoutPartsCompanion(problem: Value(TakeoutPartProblem.incomplete)));
      }
    }
    if (!extracted) {
      await _deleteQuietly(dir);
      throw const _Blocked();
    }
    try {
      final takenAt = item.takenAt ?? await MediaProbe.takenAt(path, video: isVideo);
      final folderId = await _folderFor(takenAt);
      final albumIds = [for (final title in item.albums) await _albumFor(title)];
      final mobileData = mayUseMobileData(_prefs.backupMobileData, isVideo: isVideo);
      // Telegram makes no preview for a video sent as a file, nor for a
      // HEIC photo, so each goes with one made here, as backup's do.
      final thumbnail = await MediaProbe.thumbnail(path, video: isVideo, out: await _thumbnailPath());
      return await _enqueue(
        UploadRequest(
          name: item.name,
          path: path,
          size: item.size,
          ownsSource: true,
          origin: TransferOrigin.takeout,
          takenAt: takenAt,
          albumIds: albumIds,
          starred: item.starred,
          wifiOnly: !mobileData,
          thumbnailPath: thumbnail,
        ),
        folderId,
      );
    } catch (_) {
      await _deleteQuietly(dir);
      rethrow;
    }
  }

  /// A fresh path for a preview in the cache, where the upload queue deletes
  /// it once the upload it goes with is through.
  static Future<String> _thumbnailPath() async =>
      p.join((await getTemporaryDirectory()).path, 'telegrive-thumbs', 'takeout-${DateTime.now().microsecondsSinceEpoch}.jpg');

  /// Gives the photos and videos the import sent without a preview one each,
  /// smallest first, as a bulk change the screen follows: each is fetched,
  /// a preview made from it, and its bytes sent again into the same message
  /// with the preview, since Telegram takes a preview only with its file.
  /// Wi-Fi only, since each costs its size twice. Stops when the phone runs
  /// short of room.
  /// Answers how it went, with how many files made no picture.
  Future<({BulkOutcome outcome, int noPicture})> makePreviews() async {
    if (ref.read(networkStatusProvider).metered) {
      throw const DriveException('Connect to Wi-Fi first: each file is fetched and sent again.');
    }
    final files = [for (final row in await _withoutPreview()) if (!_noPicture.contains(row.id)) row];
    var noPicture = 0;
    final cache = await getTemporaryDirectory();
    final outcome = await ref.read(bulkEditsProvider.notifier).run<FileRow>(
      label: 'Making previews for ${Formatters.count(files.length, 'file')}',
      icon: Icons.image_outlined,
      items: files,
      apply: (row) async {
        if (await Room.shortfall(ref.read(deviceStorageProvider), row.size * 2 + _keepFree) != null) {
          throw const DriveException('This phone needs more room to make the rest.');
        }
        final file = DriveFile.fromRow(row);
        // A copy already on the phone, kept offline say, is the person's and
        // stays; one fetched for this goes once it has served.
        final kept = await _queue.localPathIfAvailable(file);
        final local = kept ?? await _queue.download(file);
        final dir = Directory(p.join(cache.path, 'takeout', 'preview-${DateTime.now().microsecondsSinceEpoch}'));
        try {
          await dir.create(recursive: true);
          // A copy of its own, so Telegram takes it as a file to send rather
          // than the one it already holds.
          final copy = await File(local).copy(p.join(dir.path, DeviceStorage.safeName(row.name)));
          final thumbnail = await MediaProbe.thumbnail(
            copy.path,
            video: row.kind == FileKind.video,
            out: p.join(dir.path, 'preview.jpg'),
          );
          if (thumbnail == null) {
            _noPicture.add(row.id);
            noPicture++;
            return;
          }
          await _repository.addPreview(row.id, path: copy.path, thumbnailPath: thumbnail);
        } finally {
          await _deleteQuietly(dir);
          if (kept == null) await _deleteFileQuietly(local);
        }
      },
    );
    schedule(immediate: true);
    return (outcome: outcome, noPicture: noPicture);
  }

  /// The files the import sent that have no preview from Telegram.
  Future<List<FileRow>> _withoutPreview() async {
    final ledger = await _db.takeoutLedger();
    return _db.filesWithoutPreview([
      for (final row in ledger.values)
        if (row.state == TakeoutItemState.done && row.fileId != null) row.fileId!,
    ]);
  }

  static Future<void> _deleteFileQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (e) {
      debugPrint('[Takeout] $e');
    }
  }

  /// Queues [request] into [folderId], and answers the upload's id with the
  /// drive file it goes up as, read as it joins the queue, before a small
  /// file can land and leave it. A name the folder already has, or that an
  /// upload is still taking there, gets a number, since there is nobody to
  /// ask.
  Future<({String id, String fileId})?> _enqueue(UploadRequest request, String folderId) {
    final queued = _naming.then((_) async {
      final [name] = await FileActions.namesKeepingBoth(
        _repository,
        ref.read(transferQueueProvider),
        [request.name],
        folderId: folderId,
      );
      final path = name == request.name ? request.path! : await FileActions.renamedOnDisk(request.path!, name);
      final ids = await _queue.enqueueUploads([request.copyWith(name: name, path: path)], folderId: folderId);
      final id = ids.firstOrNull;
      final fileId = id == null ? null : ref.read(transferQueueProvider).byId(id)?.row.fileId;
      return id == null || fileId == null ? null : (id: id, fileId: fileId);
    });
    _naming = queued.then((_) {}, onError: (_) {});
    return queued;
  }

  /// Waits for upload [id] to end, and answers its final row, or its row
  /// once it is paused, or null once it is back in the queue waiting for
  /// Wi-Fi.
  Future<TransferRow?> _untilSettled(String id) async {
    final ended = Completer<TransferRow?>();
    final queue = ref.listen<TransfersState>(transferQueueProvider, (_, transfers) {
      final row = transfers.byId(id)?.row;
      if (row == null || ended.isCompleted) return;
      if (row.status == TransferStatus.paused) {
        ended.complete(row);
      } else if (row.status == TransferStatus.queued && row.wifiOnly && ref.read(networkStatusProvider).metered) {
        ended.complete(null);
      }
    }, fireImmediately: true);
    unawaited(
      _queue.whenFinished(id).then((row) {
        if (!ended.isCompleted) ended.complete(row);
      }),
    );
    try {
      return await ended.future;
    } finally {
      queue.close();
    }
  }

  /// Whether a file of [bytes] may go up on the network the phone is on
  /// now: always off mobile data, and on it as the Mobile data choice and
  /// the monthly limit allow, counting what the uploads under way still
  /// have to send.
  Future<bool> _mayGo(int bytes, {required bool isVideo}) async {
    if (!ref.read(networkStatusProvider).metered) return true;
    final mode = _prefs.backupMobileData;
    if (!mayUseMobileData(mode, isVideo: isVideo)) return false;
    await ref.read(mobileDataProvider.notifier).refresh();
    final transfers = ref.read(transferQueueProvider);
    var committed = 0;
    for (final id in _following) {
      final row = transfers.byId(id)?.row;
      if (row == null || !row.status.isPending || row.wifiOnly) continue;
      committed += row.totalBytes - row.doneBytes;
    }
    return backupAllowance(
          data: ref.read(mobileDataProvider),
          mode: mode,
          isVideo: isVideo,
          bytes: committed + bytes,
        ) ==
        BackupAllowance.go;
  }

  /// Whether [item] is the video of a Live Photo whose photo holds the
  /// movement itself, read from the photo's part the first time it is asked.
  /// A photo too big to read whole, or a part that can't be read, counts as
  /// not holding it, so the video goes up and nothing is lost.
  Future<bool> _stillHoldsMotion(TakeoutItem item) async {
    final stillKey = item.motionOf;
    if (stillKey == null) return false;
    if (_holdsMotion[stillKey] case final known?) return known;
    final still = _items[stillKey];
    if (still == null) return false;
    final parts = {for (final part in await _db.takeoutPartList()) part.id: part};
    for (final source in still.sources) {
      final part = parts[source.part];
      if (part == null || part.deletedAt != null || part.problem != null) continue;
      if (source.entry.size > 64 << 20) break;
      try {
        final [bytes] = await ZipReader.contents(_files.open(part.uri, part.size), [source.entry]);
        return _holdsMotion[stillKey] = takeoutHoldsMotion(bytes);
      } on Object catch (e) {
        debugPrint('[Takeout] ${still.name}: $e');
      }
    }
    return _holdsMotion[stillKey] = false;
  }

  /// Puts the drive file [fileId], which already holds [item], in its
  /// albums and stars it when Google Photos had it starred.
  Future<void> _addDetails(String fileId, TakeoutItem item) async {
    if (item.albums.isEmpty && !item.starred) return;
    final file = await _repository.fileById(fileId);
    if (file == null) return;
    await _repository.addDetails(
      file,
      albumIds: [for (final title in item.albums) await _albumFor(title)],
      star: item.starred,
    );
  }

  /// The drive folder for a photo taken at [takenAt], made on first use.
  Future<String> _folderFor(DateTime? takenAt) => _oneAtATime(() async {
    final path = takeoutFolderPath(takenAt);
    final key = path.join('/');
    final known = _folderIds[key];
    if (known != null && await _repository.shownFolder(known) != null) return known;
    return _folderIds[key] = await _repository.ensureFolderPath(path);
  });

  /// The album called [title], the one already in the drive by that name
  /// or a new one.
  Future<String> _albumFor(String title) => _oneAtATime(() async {
    final known = _albumIds[title];
    if (known != null && await _db.albumById(known) != null) return known;
    final existing = await _db.albumNamed(title);
    return _albumIds[title] = existing?.id ?? await _repository.createAlbum(title);
  });

  /// Runs [find] after every lookup asked for before it has ended.
  Future<T> _oneAtATime<T>(Future<T> Function() find) {
    final found = _making.then((_) => find());
    _making = found.then((_) {}, onError: (_) {});
    return found;
  }

  Future<TakeoutItemRow> _failed(TakeoutItem item, TakeoutItemRow? row, Object error) => _save(
    item,
    TakeoutItemState.failed,
    failures: (row?.failures ?? 0) + 1,
    reason: switch (error) {
      ZipFormatException() => 'It was damaged in the download.',
      DriveException(:final message) => message,
      _ => 'Something went wrong.',
    },
  );

  /// Records where [item] stands. One [given] its albums and star, by its
  /// upload's caption or an edit, says so.
  Future<TakeoutItemRow> _save(
    TakeoutItem item,
    TakeoutItemState state, {
    String? fileId,
    String? transferId,
    int failures = 0,
    String? reason,
    bool given = false,
    TakeoutItemRow? carried,
  }) async {
    final row = TakeoutItemRow(
      key: item.key,
      state: state,
      fileId: fileId,
      transferId: transferId,
      failures: failures,
      reason: reason,
      updatedAt: DateTime.now(),
      // An upload carries the albums and star it was queued with.
      albums: given ? (carried?.albums ?? item.albums.join('\n')) : null,
      starred: given ? (carried?.starred ?? item.starred) : null,
    );
    await _db.saveTakeoutItems([row.toCompanion(false)]);
    return row;
  }

  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('[Takeout] $e');
    }
  }
}

/// Every copy of an item is in a part that can't be read now.
class _Blocked implements Exception {
  const _Blocked();
}

final takeoutImportProvider = NotifierProvider<TakeoutImport, TakeoutState>(TakeoutImport.new);
