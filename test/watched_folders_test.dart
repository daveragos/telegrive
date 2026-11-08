import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/backup/data/phone_folders.dart';
import 'package:telegrive/features/backup/data/watched_folders.dart';
import 'package:telegrive/features/backup/presentation/backup_screen.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

final _now = DateTime(2026, 10, 4, 14, 0);

PhoneDocument _doc(
  String name, {
  String? id,
  String mime = '',
  int size = 1000,
  Duration age = const Duration(hours: 1),
}) => PhoneDocument(
  id: id ?? 'primary:Download/Bank/$name',
  name: name,
  mimeType: mime,
  size: size,
  modifiedAt: _now.subtract(age),
);

WatchedFileRow _entry(
  PhoneDocument doc,
  WatchedFileState state, {
  String? transferId,
  int failures = 0,
}) => WatchedFileRow(
  ruleId: 'bank',
  documentId: doc.id,
  size: doc.size,
  modifiedAt: doc.modifiedAt,
  state: state,
  transferId: transferId,
  failures: failures,
  updatedAt: _now,
);

WatchPlan _plan(
  List<PhoneDocument> listing, {
  List<WatchedFileRow> ledger = const [],
  Map<String, String> fingerprints = const {},
  WatchFilter filter = WatchFilter.everything,
  Set<String> inFlight = const {},
}) => planUploads(
  listing: listing,
  ledger: {for (final entry in ledger) entry.documentId: entry},
  fingerprints: fingerprints,
  filter: filter,
  now: _now,
  inFlight: inFlight.contains,
);

List<String> _names(WatchPlan plan) => [for (final doc in plan.toUpload) doc.name];

WatchedFolderView _view(
  RuleStatus status, {
  WatchFilter filter = WatchFilter.documents,
  bool checked = true,
}) => WatchedFolderView(
  row: WatchedFolderRow(
    id: 'download',
    treeUri: 'content://com.android.externalstorage.documents/tree/primary%3ADownload',
    label: 'Download',
    filter: filter,
    subfolders: true,
    createdAt: _now,
    checkedAt: checked ? _now : null,
  ),
  uploadedCount: 0,
  status: status,
  destinationLabel: 'Auto upload › Download',
);

void main() {
  group('watchMatches', () {
    final statement = _doc('Statement-0925.pdf', mime: 'application/pdf');
    final memo = _doc('Voice memo 12.m4a', mime: 'audio/mp4');
    final photo = _doc('IMG_2041.jpg', mime: 'image/jpeg');

    test('documents and PDFs take documents only', () {
      expect(watchMatches(statement, WatchFilter.documents), isTrue);
      expect(watchMatches(_doc('Notes.docx'), WatchFilter.documents), isTrue);
      expect(watchMatches(memo, WatchFilter.documents), isFalse);
      expect(watchMatches(photo, WatchFilter.documents), isFalse);
    });

    test('audio takes recordings and music only', () {
      expect(watchMatches(memo, WatchFilter.audio), isTrue);
      expect(watchMatches(statement, WatchFilter.audio), isFalse);
      expect(watchMatches(photo, WatchFilter.audio), isFalse);
    });

    test('a file the provider gives no type is known by its name', () {
      expect(watchMatches(_doc('Call with Abebe.mp3'), WatchFilter.audio), isTrue);
      expect(watchMatches(_doc('Lease.pdf'), WatchFilter.documents), isTrue);
    });

    test('everything takes any kind', () {
      for (final doc in [statement, memo, photo, _doc('backup.zip')]) {
        expect(watchMatches(doc, WatchFilter.everything), isTrue, reason: doc.name);
      }
    });

    test('hidden names, files still being written and empty files are left out', () {
      for (final doc in [
        _doc('.nomedia'),
        _doc('.pending-1759579200-Statement.pdf', mime: 'application/pdf'),
        _doc('.trashed-1759579200-Old.pdf', mime: 'application/pdf'),
        _doc('Empty.pdf', mime: 'application/pdf', size: 0),
      ]) {
        for (final filter in WatchFilter.values) {
          expect(watchMatches(doc, filter), isFalse, reason: '${doc.name}, $filter');
        }
      }
    });
  });

  group('planUploads', () {
    test('sends what the filter takes and leaves the rest', () {
      final plan = _plan(
        [
          _doc('Statement.pdf'),
          _doc('Memo.m4a'),
          _doc('Photo.jpg'),
          _doc('.pending-Next.pdf'),
          _doc('Empty.zip', size: 0),
        ],
        filter: WatchFilter.documents,
      );
      expect(_names(plan), ['Statement.pdf']);
      expect(plan.alreadyInDrive, isEmpty);
      expect(plan.settling, 0);
      expect(plan.gaveUp, 0);
      // Hidden and empty files aren't counted as left out: no filter sends them.
      expect(plan.leftOut, 2);
      expect(_plan([_doc('Memo.m4a'), _doc('Photo.jpg')]).leftOut, 0);
    });

    test('a file changed less than a minute ago waits as settling', () {
      final plan = _plan([
        _doc('Downloading.pdf', age: const Duration(seconds: 20)),
        _doc('Just old enough.pdf', age: const Duration(seconds: 61)),
      ]);
      expect(_names(plan), ['Just old enough.pdf']);
      expect(plan.settling, 1);
    });

    test('a check that left files settling is followed by another once they are old enough', () {
      final settling = _plan([_doc('Downloading.pdf', age: const Duration(seconds: 20))]);
      expect(recheckAfter(settling), watchRecheck);
      expect(watchRecheck, greaterThan(watchSettle));
      expect(recheckAfter(_plan([_doc('Statement.pdf')])), isNull);
    });

    test('files in the drive and files set aside are passed over', () {
      final done = _doc('Done.pdf');
      final skipped = _doc('Skipped.pdf');
      final plan = _plan(
        [done, skipped, _doc('New.pdf')],
        ledger: [_entry(done, WatchedFileState.done), _entry(skipped, WatchedFileState.skipped)],
      );
      expect(_names(plan), ['New.pdf']);
    });

    test('a file whose upload is still in flight is left to it, one whose upload is gone goes again', () {
      final going = _doc('Going.pdf');
      final lost = _doc('Lost.pdf');
      final plan = _plan(
        [going, lost],
        ledger: [
          _entry(going, WatchedFileState.pending, transferId: 't1'),
          _entry(lost, WatchedFileState.pending, transferId: 't2'),
        ],
        inFlight: {'t1'},
      );
      expect(_names(plan), ['Lost.pdf']);
    });

    test('a failed file is tried again until it has failed three times', () {
      final twice = _doc('Twice.pdf');
      final thrice = _doc('Thrice.pdf');
      final plan = _plan(
        [twice, thrice],
        ledger: [
          _entry(twice, WatchedFileState.failed, failures: 2),
          _entry(thrice, WatchedFileState.failed, failures: watchMaxFailures),
        ],
      );
      expect(_names(plan), ['Twice.pdf']);
      expect(plan.gaveUp, 1);
    });

    test('a file the drive has under the same name and size is already in it', () {
      final kept = _doc('Statement.pdf', size: 52340);
      final resized = _doc('Lease.pdf', size: 900);
      final plan = _plan(
        [kept, resized],
        fingerprints: {'Statement.pdf|52340': 'file-1', 'Lease.pdf|901': 'file-2'},
      );
      expect(plan.alreadyInDrive, {kept.id: 'file-1'});
      expect(_names(plan), ['Lease.pdf']);
    });

    test('the oldest file goes first', () {
      final plan = _plan([
        _doc('Tuesday.pdf', age: const Duration(days: 1)),
        _doc('Today.pdf', age: const Duration(minutes: 5)),
        _doc('Last week.pdf', age: const Duration(days: 7)),
      ]);
      expect(_names(plan), ['Last week.pdf', 'Tuesday.pdf', 'Today.pdf']);
    });
  });

  test('baseline sets every listed file aside', () {
    final listing = [
      _doc('Statement.pdf'),
      _doc('Memo.m4a', id: 'primary:Download/Bank/2025/Memo.m4a'),
      _doc('.nomedia'),
    ];
    final rows = baseline('bank', listing, _now);
    expect(rows, hasLength(3));
    for (final (index, row) in rows.indexed) {
      expect(row.ruleId.value, 'bank');
      expect(row.documentId.value, listing[index].id);
      expect(row.state.value, WatchedFileState.skipped);
      expect(row.size.value, listing[index].size);
    }
    final plan = _plan(listing, ledger: [
      for (final row in rows)
        _entry(listing.firstWhere((d) => d.id == row.documentId.value), WatchedFileState.skipped),
    ]);
    expect(plan.toUpload, isEmpty);
  });

  group('the row says what stayed on the phone', () {
    test('a folder whose files the filter all leaves out says so', () {
      final detail = watchedFolderDetail(_view(const RuleStatus(leftOut: 14)));
      expect(detail, startsWith('0 uploaded to Auto upload › Download · checked '));
      expect(detail, endsWith('. 14 files aren\'t documents or PDFs, so they stay on the phone.'));
      expect(
        watchedFolderDetail(_view(const RuleStatus(leftOut: 1), filter: WatchFilter.audio)),
        endsWith('. 1 file isn\'t audio, so it stays on the phone.'),
      );
    });

    test('files still settling and files that failed are named', () {
      final detail = watchedFolderDetail(_view(const RuleStatus(failed: 3, settling: 1)));
      expect(detail, contains('. 3 files couldn\'t upload. 1 new file goes up in a minute.'));
      expect(
        watchedFolderDetail(_view(const RuleStatus(settling: 2))),
        endsWith('. 2 new files go up in a minute.'),
      );
    });

    test('a folder with nothing left behind says only what went up', () {
      final detail = watchedFolderDetail(_view(const RuleStatus()));
      expect(detail, startsWith('0 uploaded to Auto upload › Download · checked '));
      expect(detail, isNot(endsWith('.')));
      expect(watchedFolderDetail(_view(const RuleStatus(), checked: false)), 'Not checked yet');
    });

    test('a status keeps what was left behind through a copy', () {
      const status = RuleStatus(leftOut: 4, settling: 1, failed: 2);
      final next = status.copyWith(done: 1);
      expect((next.leftOut, next.settling, next.failed), (4, 1, 2));
    });
  });

  test('Retry gives a folder\'s failed files their tries back, and only its own', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final given = _doc('Given up.pdf');
    final once = _doc('Once.pdf');
    final done = _doc('Done.pdf');
    final other = WatchedFileRow(
      ruleId: 'other',
      documentId: given.id,
      size: given.size,
      modifiedAt: given.modifiedAt,
      state: WatchedFileState.failed,
      failures: watchMaxFailures,
      updatedAt: _now,
    );
    await db.saveWatchedFiles([
      for (final row in [
        _entry(given, WatchedFileState.failed, failures: watchMaxFailures),
        _entry(once, WatchedFileState.failed, failures: 1),
        _entry(done, WatchedFileState.done, failures: 2),
        other,
      ])
        row.toCompanion(false),
    ]);

    await db.resetWatchedFailures('bank');

    final ledger = await db.watchedLedger('bank');
    expect(ledger[given.id]!.failures, 0);
    expect(ledger[given.id]!.state, WatchedFileState.failed);
    expect(ledger[once.id]!.failures, 0);
    expect(ledger[done.id]!.failures, 2);
    expect((await db.watchedLedger('other'))[given.id]!.failures, watchMaxFailures);
    final plan = _plan([given, once, done], ledger: ledger.values.toList());
    expect(_names(plan), ['Given up.pdf', 'Once.pdf']);
    expect(plan.gaveUp, 0);
  });
}
