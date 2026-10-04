import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/format/formatters.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/player/data/play_positions.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

void main() {
  const forty = Duration(minutes: 40);

  group('ResumePolicy', () {
    test('a file under three minutes is never kept', () {
      expect(
        ResumePolicy.worthKeeping(
          const Duration(minutes: 1),
          const Duration(minutes: 2),
        ),
        isFalse,
      );
    });

    test('nothing is kept until playback is 30 seconds in', () {
      expect(
        ResumePolicy.worthKeeping(const Duration(seconds: 20), forty),
        isFalse,
      );
      expect(
        ResumePolicy.worthKeeping(const Duration(seconds: 30), forty),
        isTrue,
      );
    });

    test('five minutes into forty is kept', () {
      expect(
        ResumePolicy.worthKeeping(const Duration(minutes: 5), forty),
        isTrue,
      );
    });

    test('the last five percent counts as finished', () {
      expect(
        ResumePolicy.worthKeeping(const Duration(minutes: 39), forty),
        isFalse,
      );
      expect(
        ResumePolicy.worthKeeping(const Duration(minutes: 38), forty),
        isTrue,
      );
    });
  });

  group('PlayPositionStore', () {
    late AppDatabase db;
    late PlayPositionStore positions;
    final now = DateTime(2026, 10, 1);

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      positions = PlayPositionStore(db);
    });
    tearDown(() => db.close());

    DriveFilesCompanion file(
      String id, {
      String? folderId,
      int partCount = 1,
      FileKind kind = FileKind.video,
    }) => DriveFilesCompanion.insert(
      id: id,
      folderId: Value(folderId),
      name: '$id.mp4',
      mimeType: 'video/mp4',
      kind: kind,
      size: 100,
      createdAt: now,
      modifiedAt: now,
      partCount: Value(partCount),
    );

    FilePartsCompanion part(String fileId, int index, int messageId) =>
        FilePartsCompanion.insert(
          fileId: fileId,
          partIndex: index,
          messageId: messageId,
          tdFileId: messageId + 1,
          size: 50,
        );

    FoldersCompanion folder(String id, int messageId) =>
        FoldersCompanion.insert(
          id: id,
          name: id,
          messageId: messageId,
          createdAt: now,
          modifiedAt: now,
        );

    test('saves, reads back and forgets a point', () async {
      await db.savePlayPosition('film', 5 * 60 * 1000, 20 * 60 * 1000);
      final row = (await db.playPositionOf('film'))!;
      expect(row.positionMs, 5 * 60 * 1000);
      expect(row.durationMs, 20 * 60 * 1000);

      await db.savePlayPosition('film', 6 * 60 * 1000, 20 * 60 * 1000);
      expect((await db.playPositionOf('film'))!.positionMs, 6 * 60 * 1000);

      await db.forgetPlayPosition('film');
      expect(await db.playPositionOf('film'), isNull);
    });

    test(
      'record keeps a point worth keeping and forgets one that is not',
      () async {
        await positions.record('film', const Duration(minutes: 5), forty);
        expect(
          await positions.resumePoint('film', forty),
          const Duration(minutes: 5),
        );

        await positions.record(
          'film',
          const Duration(minutes: 39, seconds: 30),
          forty,
        );
        expect(await db.playPositionOf('film'), isNull);

        await positions.record(
          'clip',
          const Duration(minutes: 1),
          const Duration(minutes: 2),
        );
        expect(await db.playPositionOf('clip'), isNull);
      },
    );

    test(
      'resumePoint is null once the point no longer fits the real length',
      () async {
        await db.savePlayPosition('film', 39 * 60 * 1000, 60 * 60 * 1000);
        expect(
          await positions.resumePoint('film', const Duration(hours: 1)),
          isNotNull,
        );
        expect(await positions.resumePoint('film', forty), isNull);
        expect(await positions.resumePoint('other', forty), isNull);
      },
    );

    test('watchResumePoints lists the newest first, three at most', () async {
      for (var i = 0; i < 5; i++) {
        await db.upsertFilePart(file('f$i'), part('f$i', 0, 10 + i));
        await db
            .into(db.playPositions)
            .insert(
              PlayPositionsCompanion.insert(
                fileId: 'f$i',
                positionMs: 60000,
                durationMs: 600000,
                updatedAt: now.add(Duration(minutes: i)),
              ),
            );
      }

      final points = await db
          .watchResumePoints(since: now.subtract(const Duration(days: 1)))
          .first;
      expect(points.map((p) => p.file.id), ['f4', 'f3', 'f2']);
      expect(points.first.positionMs, 60000);
      expect(points.first.durationMs, 600000);
    });

    test(
      'watchResumePoints leaves out trashed, incomplete and stale files',
      () async {
        await db.upsertFilePart(file('kept'), part('kept', 0, 10));
        await db.upsertFilePart(
          file('binned').copyWith(trashedAt: Value(now)),
          part('binned', 0, 11),
        );
        await db.upsertFilePart(
          file('half', partCount: 2),
          part('half', 0, 12),
        );
        await db.upsertFilePart(file('old'), part('old', 0, 13));
        await db.refreshHidden();
        for (final (id, at) in [
          ('kept', now),
          ('binned', now),
          ('half', now),
          ('old', now.subtract(const Duration(days: 61))),
        ]) {
          await db
              .into(db.playPositions)
              .insert(
                PlayPositionsCompanion.insert(
                  fileId: id,
                  positionMs: 60000,
                  durationMs: 600000,
                  updatedAt: at,
                ),
              );
        }

        final points = await db
            .watchResumePoints(since: now.subtract(const Duration(days: 60)))
            .first;
        expect(points.map((p) => p.file.id), ['kept']);
      },
    );

    test('watchResumePoints names the folder, and none at the root', () async {
      await db.upsertFolder(folder('Lectures', 1));
      await db.upsertFilePart(
        file('talk', folderId: 'Lectures'),
        part('talk', 0, 10),
      );
      await db.upsertFilePart(file('loose'), part('loose', 0, 11));
      await db.savePlayPosition('loose', 60000, 600000);
      await db.savePlayPosition('talk', 60000, 600000);

      final points = await db.watchResumePoints(since: now).first;
      expect(points.map((p) => p.file.id), ['talk', 'loose']);
      expect(points[0].folderName, 'Lectures');
      expect(points[1].folderName, isNull);
    });

    test('saving a point lets go of those untouched for 60 days', () async {
      await db
          .into(db.playPositions)
          .insert(
            PlayPositionsCompanion.insert(
              fileId: 'stale',
              positionMs: 60000,
              durationMs: 600000,
              updatedAt: DateTime.now().subtract(const Duration(days: 61)),
            ),
          );
      await db.savePlayPosition('fresh', 60000, 600000);
      expect(await db.playPositionOf('stale'), isNull);
      expect(await db.playPositionOf('fresh'), isNotNull);
    });

    test(
      'signing out clears positions and rebuilding the index keeps them',
      () async {
        await db.savePlayPosition('film', 60000, 600000);
        await db.clearIndex();
        expect(await db.playPositionOf('film'), isNotNull);
        await db.clearAll();
        expect(await db.playPositionOf('film'), isNull);
      },
    );
  });

  group('ContinueItem', () {
    DriveFile audio(
      String id,
      String name, {
      String? folderId,
      int size = 100,
    }) => DriveFile(
      id: id,
      folderId: folderId,
      name: name,
      mimeType: 'audio/mpeg',
      kind: FileKind.audio,
      size: size,
      createdAt: DateTime(2026, 9, 1),
      modifiedAt: DateTime(2026, 9, 1),
      partCount: 1,
      starred: false,
    );

    test('left and progress follow the position', () {
      final item = ContinueItem(
        file: audio('a', 'a.mp3'),
        position: const Duration(minutes: 15),
        length: const Duration(minutes: 60),
        place: 'Files',
      );
      expect(item.left, const Duration(minutes: 45));
      expect(item.progress, 0.25);
    });

    test('progress is 0 without a length', () {
      final item = ContinueItem(
        file: audio('a', 'a.mp3'),
        position: const Duration(minutes: 1),
        length: Duration.zero,
        place: 'Files',
      );
      expect(item.progress, 0);
    });
  });

  group('Formatters.left', () {
    test('says how much is left in the right unit', () {
      expect(
        Formatters.left(const Duration(seconds: 40)),
        'Less than a minute left',
      );
      expect(Formatters.left(const Duration(minutes: 38)), '38 min left');
      expect(Formatters.left(const Duration(minutes: 72)), '1 h 12 min left');
    });

    test('rounds to the nearest minute', () {
      expect(
        Formatters.left(const Duration(minutes: 37, seconds: 48)),
        '38 min left',
      );
      expect(
        Formatters.left(const Duration(minutes: 37, seconds: 12)),
        '37 min left',
      );
      expect(
        Formatters.left(const Duration(minutes: 59, seconds: 40)),
        '1 h left',
      );
    });
  });

  group('PlayQueue', () {
    DriveFile make(String name, FileKind kind, int size) => DriveFile(
      id: name,
      folderId: 'album',
      name: name,
      mimeType: kind == FileKind.audio ? 'audio/mpeg' : 'application/pdf',
      kind: kind,
      size: size,
      createdAt: DateTime(2026, 9, 1),
      modifiedAt: DateTime(2026, 9, 1),
      partCount: 1,
      starred: false,
    );

    final contents = FolderContents(
      folders: const [],
      files: [
        make('chapter 2.mp3', FileKind.audio, 300),
        make('notes.pdf', FileKind.document, 50),
        make('Chapter 1.mp3', FileKind.audio, 100),
        make('chapter 3.mp3', FileKind.audio, 200),
      ],
    );

    test('keeps only audio, in name order', () {
      expect(
        PlayQueue.fromFolder(
          contents,
          const SortOrder(SortField.name),
        ).map((f) => f.name),
        ['Chapter 1.mp3', 'chapter 2.mp3', 'chapter 3.mp3'],
      );
    });

    test('follows a size order, largest first', () {
      expect(
        PlayQueue.fromFolder(
          contents,
          const SortOrder(SortField.size, descending: true),
        ).map((f) => f.name),
        ['chapter 2.mp3', 'chapter 3.mp3', 'Chapter 1.mp3'],
      );
    });
  });
}
