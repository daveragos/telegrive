import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/file_kind.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../drive/domain/drive_models.dart';

/// Which play positions are worth keeping, so a voice note never resumes
/// and a film watched to its credits starts over next time.
abstract final class ResumePolicy {
  /// Files shorter than this never remember a position.
  static const Duration minLength = Duration(minutes: 3);

  /// Nothing is remembered until playback is this far in.
  static const Duration minPosition = Duration(seconds: 30);

  /// Past this share of the length the file counts as finished.
  static const double finished = 0.95;

  static bool worthKeeping(Duration position, Duration length) =>
      length >= minLength &&
      position >= minPosition &&
      position.inMilliseconds <= length.inMilliseconds * finished;
}

/// Reads and writes where playback stopped, applying [ResumePolicy] on
/// both sides so the table only ever holds points a player would use.
class PlayPositionStore {
  const PlayPositionStore(this._db);

  final AppDatabase _db;

  /// Keeps [position] for [fileId] when it is worth keeping, and otherwise
  /// forgets the file, as when it has been played to its end.
  Future<void> record(String fileId, Duration position, Duration length) =>
      ResumePolicy.worthKeeping(position, length)
      ? _db.savePlayPosition(
          fileId,
          position.inMilliseconds,
          length.inMilliseconds,
        )
      : _db.forgetPlayPosition(fileId);

  /// Where to pick [fileId] up, or null when nothing is kept or the kept
  /// point no longer makes sense against the file's real [length].
  Future<Duration?> resumePoint(String fileId, Duration length) async {
    final row = await _db.playPositionOf(fileId);
    if (row == null) return null;
    final position = Duration(milliseconds: row.positionMs);
    return ResumePolicy.worthKeeping(position, length) ? position : null;
  }

  Future<void> forget(String fileId) => _db.forgetPlayPosition(fileId);
}

final playPositionsProvider = Provider<PlayPositionStore>(
  (ref) => PlayPositionStore(ref.watch(appDatabaseProvider)),
);

/// A row of Home's Continue watching: the file, how far in it is and the
/// name of the place it lives.
class ContinueItem {
  const ContinueItem({
    required this.file,
    required this.position,
    required this.length,
    required this.place,
  });

  final DriveFile file;
  final Duration position;
  final Duration length;

  /// The folder's name, or 'Files' at the root.
  final String place;

  Duration get left => length - position;

  /// How much has been played, from 0 to 1.
  double get progress => length <= Duration.zero
      ? 0
      : (position.inMilliseconds / length.inMilliseconds).clamp(0, 1);
}

/// Up to three files this phone stopped partway through in the last 60
/// days, most recently played first.
final continuePlayingProvider = StreamProvider.autoDispose<List<ContinueItem>>(
  (ref) => ref
      .watch(appDatabaseProvider)
      .watchResumePoints(
        since: DateTime.now().subtract(AppDatabase.keptPositions),
      )
      .map(
        (points) => [
          for (final point in points)
            ContinueItem(
              file: DriveFile.fromRow(point.file),
              position: Duration(milliseconds: point.positionMs),
              length: Duration(milliseconds: point.durationMs),
              place: point.folderName ?? 'Files',
            ),
        ],
      ),
);

/// The files the player moves through on its own.
abstract final class PlayQueue {
  /// The audio files of a folder, in the order its list shows them.
  static List<DriveFile> fromFolder(FolderContents contents, SortOrder sort) =>
      contents
          .sorted(sort)
          .files
          .where((f) => f.kind == FileKind.audio)
          .toList();
}
