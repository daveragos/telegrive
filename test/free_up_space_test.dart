import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/format/formatters.dart';
import 'package:telegrive/core/widgets/file_visuals.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/backup/data/free_up_space.dart';
import 'package:telegrive/features/backup/presentation/free_up_preview_screen.dart';
import 'package:telegrive/features/backup/presentation/free_up_space_sheet.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

const _mb = 1024 * 1024;
const _gb = 1024 * _mb;

/// A backed-up photo's drive copy, taken at [takenAt] when the photo says
/// and added to the drive at [createdAt].
DriveFile _photo(String id, {DateTime? takenAt, DateTime? createdAt, int size = 4 * _mb}) {
  final added = createdAt ?? DateTime(2026, 9, 20);
  return DriveFile(
    id: id,
    folderId: null,
    name: '$id.jpg',
    mimeType: 'image/jpeg',
    kind: FileKind.image,
    size: size,
    createdAt: added,
    modifiedAt: added,
    partCount: 1,
    starred: false,
    takenAt: takenAt,
  );
}

FreeableItem _item(String id, {DateTime? takenAt, DateTime? createdAt, int size = 4 * _mb}) =>
    FreeableItem(
      assetId: 'asset-$id',
      file: _photo(id, takenAt: takenAt, createdAt: createdAt, size: size),
    );

/// Backup at rest, so nothing it does makes the providers work again.
class _Backup extends BackupController {
  @override
  BackupState build() => const BackupState(phase: BackupPhase.upToDate);
}

/// Nothing waits for room, so looking again after Free up finds nothing.
class _Queue extends TransferQueue {
  @override
  TransfersState build() => TransfersState.empty;
}

/// A phone with [free] bytes left of [total].
class _Storage extends DeviceStorage {
  _Storage(this.free, this.total);

  final int? free;
  final int? total;

  @override
  Future<int?> freeBytes() async => free;

  @override
  Future<int?> totalBytes() async => total;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const photoManager = MethodChannel('com.fluttercandies/photo_manager');

  final now = DateTime(2026, 9, 26, 15, 40);

  test('a keep window keeps whole days, counted back from today', () {
    expect(KeepWindow.days30.cutoff(now), DateTime(2026, 8, 27));
    expect(KeepWindow.days90.cutoff(now), DateTime(2026, 6, 28));
    expect(KeepWindow.nothing.cutoff(now), isNull);
    expect(KeepWindow.days30.cutoff(DateTime(2026, 3, 5, 0, 1)), DateTime(2026, 2, 3));
  });

  group('Freeable', () {
    final all = Freeable([
      // Taken years ago and only backed up this week: old.
      _item('beach', takenAt: DateTime(2021, 3, 14), createdAt: DateTime(2026, 9, 20)),
      // Taken last week, though its drive copy is dated 2020: recent.
      _item('lunch', takenAt: DateTime(2026, 9, 19), createdAt: DateTime(2020, 1, 1)),
      // No date of its own, so it counts from when it was backed up: recent.
      _item('meme', createdAt: DateTime(2026, 9, 20)),
      _item('eve', takenAt: DateTime(2026, 8, 26, 23, 59), size: 6 * _mb),
      _item('morning', takenAt: DateTime(2026, 8, 27)),
      _item('spring', takenAt: DateTime(2026, 4, 2), size: 10 * _mb),
    ]);

    test('before a cutoff keeps the ones taken earlier, by the date they were taken', () {
      final old = all.before(KeepWindow.days30.cutoff(now));
      expect(old.assetIds, unorderedEquals(['asset-beach', 'asset-eve', 'asset-spring']));
      expect(all.before(null), same(all));
      expect(all.before(DateTime(2000)).isEmpty, isTrue);
    });

    test('counts, adds up and dates what it holds, newest first', () {
      final old = all.before(DateTime(2026, 8, 27));
      expect(old.count, 3);
      expect(old.bytes, 20 * _mb);
      expect(old.oldest, DateTime(2021, 3, 14));
      expect(old.files.map((f) => f.id), ['eve', 'spring', 'beach']);
      expect(all.files.first.id, 'meme');
      expect(Freeable.none.oldest, isNull);
      expect(Freeable.none.bytes, 0);
    });

    test('the sheet says what goes, from when, and how much', () {
      final old = all.before(KeepWindow.days30.cutoff(now));
      expect(
        describeFreeable(all, old, KeepWindow.days30, now),
        '3 photos and videos from before Aug 27 are backed up to your drive · 20.0 MB, '
        'oldest from 2021. They\'ll be deleted from this phone and stay in Telegrive, '
        'where you can download them again any time.',
      );
      expect(
        describeFreeable(all, all, KeepWindow.nothing, now),
        '6 photos and videos on this phone are backed up to your drive · 32.0 MB, '
        'oldest from 2021. They\'ll be deleted from this phone and stay in Telegrive, '
        'where you can download them again any time.',
      );
      final one = Freeable([_item('beach', takenAt: DateTime(2021, 3, 14))]);
      expect(
        describeFreeable(one, one, KeepWindow.days90, now),
        '1 photo or video from before Jun 28 is backed up to your drive · 4.0 MB, '
        'from 2021. It\'ll be deleted from this phone and stay in Telegrive, where you '
        'can download it again any time.',
      );
    });

    test('a window that keeps everything says so, and nothing backed up says how it fills', () {
      final recent = Freeable([_item('lunch', takenAt: DateTime(2026, 9, 19))]);
      final none = recent.before(KeepWindow.days30.cutoff(now));
      expect(
        describeFreeable(recent, none, KeepWindow.days30, now),
        'Everything backed up from this phone is newer than Aug 27.',
      );
      expect(
        describeFreeable(Freeable.none, Freeable.none, KeepWindow.days30, now),
        'Photos and videos backed up from this phone show up here once they are safely '
        'in your drive.',
      );
      // A cutoff in another year is given in full.
      expect(
        describeFreeable(recent, Freeable.none, KeepWindow.days90, DateTime(2027, 2, 1)),
        'Everything backed up from this phone is newer than Nov 3, 2026.',
      );
    });

    test('the Backup screen row says it in a few words', () {
      final old = all.before(KeepWindow.days30.cutoff(now));
      expect(
        summarizeFreeable(old, KeepWindow.days30, now),
        '20.0 MB of photos from before Aug 27 are backed up',
      );
      expect(
        summarizeFreeable(all, KeepWindow.nothing, now),
        '32.0 MB of backed-up photos are on this phone',
      );
    });
  });

  test('a phone is low on space under 2 GB free or under a tenth of its storage', () {
    expect(isLowSpace((1.9 * _gb).round(), 256 * _gb), isTrue);
    expect(isLowSpace(2 * _gb, null), isFalse);
    expect(isLowSpace(2 * _gb - 1, null), isTrue);
    expect(isLowSpace(12 * _gb, 128 * _gb), isTrue);
    expect(isLowSpace(13 * _gb, 128 * _gb), isFalse);
    expect(isLowSpace(23 * _gb, 128 * _gb), isFalse);
  });

  group('the window kept', () {
    Future<ProviderContainer> containerWith(Map<String, Object> values) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(values);
      final shared = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(shared)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is 30 days until someone picks, and is remembered', () async {
      expect((await containerWith({})).read(freeUpKeepProvider), KeepWindow.days30);
      expect(
        (await containerWith({'free_up_keep': 'weekly'})).read(freeUpKeepProvider),
        KeepWindow.days30,
      );

      final first = await containerWith({});
      await first.read(freeUpKeepProvider.notifier).set(KeepWindow.days90);
      expect(first.read(freeUpKeepProvider), KeepWindow.days90);
      final shared = await SharedPreferences.getInstance();
      expect(shared.getString('free_up_keep'), 'days90');
      expect(Preferences(shared).freeUpKeep, 'days90');

      final next = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(shared)],
      );
      addTearDown(next.dispose);
      expect(next.read(freeUpKeepProvider), KeepWindow.days90);
    });
  });

  group('freeableProvider', () {
    late AppDatabase db;
    late Set<String> library;
    late bool allowed;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final today = DateTime.now();
      var messageId = 0;
      Future<void> backedUp(String id, {DateTime? takenAt, DateTime? trashedAt}) async {
        messageId++;
        await db.upsertFilePart(
          DriveFilesCompanion.insert(
            id: id,
            name: '$id.jpg',
            mimeType: 'image/jpeg',
            kind: FileKind.image,
            size: 3 * _mb,
            createdAt: today,
            modifiedAt: today,
            takenAt: Value(takenAt),
            trashedAt: Value(trashedAt),
          ),
          FilePartsCompanion.insert(
            fileId: id,
            partIndex: 0,
            messageId: messageId,
            tdFileId: messageId,
            size: 3 * _mb,
          ),
        );
        await db.markAssetBackedUp('asset-$id', id);
      }

      await backedUp('old', takenAt: DateTime(2021, 3, 14));
      await backedUp('recent', takenAt: today.subtract(const Duration(days: 3)));
      await backedUp('undated');
      await backedUp('gone', takenAt: DateTime(2020));
      await backedUp('binned', takenAt: DateTime(2020), trashedAt: today);
      library = {'asset-old', 'asset-recent', 'asset-undated', 'asset-binned', 'asset-other'};
      allowed = true;

      Map<String, Object> asset(String id) => {'id': id, 'type': 1, 'width': 4000, 'height': 3000};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        photoManager,
        (call) async {
          final arguments = call.arguments as Map?;
          switch (call.method) {
            case 'getPermissionState':
              return allowed ? PermissionState.authorized.index : PermissionState.denied.index;
            case 'getAssetPathList':
              return {
                'data': [
                  {'id': 'all', 'name': 'Recent', 'isAll': true, 'assetCount': library.length},
                ],
              };
            case 'getAssetCountFromPath':
              return library.length;
            case 'getAssetListPaged':
              final size = arguments!['size'] as int;
              return {
                'data': [
                  for (final id in library.skip((arguments['page'] as int) * size).take(size))
                    asset(id),
                ],
              };
          }
          return null;
        },
      );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        photoManager,
        null,
      );
      await db.close();
    });

    Future<ProviderContainer> container() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final shared = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          appDatabaseProvider.overrideWithValue(db),
          backupControllerProvider.overrideWith(_Backup.new),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('holds what the phone still has of what is safely in the drive', () async {
      final ref = await container();
      final all = await ref.read(freeableProvider.future);
      expect(all.assetIds, unorderedEquals(['asset-old', 'asset-recent', 'asset-undated']));
      final old = all.items.singleWhere((item) => item.assetId == 'asset-old');
      expect((old.file.id, old.bytes, old.momentAt), ('old', 3 * _mb, DateTime(2021, 3, 14)));

      // The remembered window decides what goes.
      final sub = ref.listen(freeUpCandidatesProvider, (_, _) {});
      expect(sub.read().requireValue.assetIds, ['asset-old']);
      await ref.read(freeUpKeepProvider.notifier).set(KeepWindow.nothing);
      expect(
        ref.read(freeUpCandidatesProvider).requireValue.assetIds,
        unorderedEquals(['asset-old', 'asset-recent', 'asset-undated']),
      );
    });

    test('holds nothing without photo access', () async {
      allowed = false;
      final ref = await container();
      expect((await ref.read(freeableProvider.future)).isEmpty, isTrue);
    });

    test('low space comes from the phone, and a phone that won\'t say is not low', () async {
      Future<bool> lowWith(DeviceStorage storage) async {
        final ref = ProviderContainer(
          overrides: [
            backupControllerProvider.overrideWith(_Backup.new),
            deviceStorageProvider.overrideWithValue(storage),
          ],
        );
        addTearDown(ref.dispose);
        return ref.read(lowSpaceProvider.future);
      }

      expect(await lowWith(_Storage(9 * _gb, 128 * _gb)), isTrue);
      expect(await lowWith(_Storage(1 * _gb, null)), isTrue);
      expect(await lowWith(_Storage(23 * _gb, 128 * _gb)), isFalse);
      expect(await lowWith(_Storage(null, 128 * _gb)), isFalse);
    });
  });

  group('the sheet', () {
    late List<List<String>> phoneDeletes;

    /// Six backed-up photos: four older than 30 days, of which three are
    /// older than 90, and two from this week.
    Freeable sample() {
      final today = DateTime.now();
      DateTime daysAgo(int days) => today.subtract(Duration(days: days));
      return Freeable([
        _item('a', takenAt: DateTime(2021, 3, 14), size: 300 * _mb),
        _item('b', takenAt: DateTime(2023, 7, 1), size: 200 * _mb),
        _item('c', takenAt: daysAgo(120), size: 100 * _mb),
        _item('d', takenAt: daysAgo(45), size: 50 * _mb),
        _item('e', takenAt: daysAgo(2), size: 20 * _mb),
        _item('f', takenAt: daysAgo(1), size: 10 * _mb),
      ]);
    }

    Future<void> pumpSheet(
      WidgetTester tester,
      Freeable all, {
      Map<String, Object> prefs = const {},
    }) async {
      // A phone's screen, so the preview fits every month it shows.
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(prefs);
      final shared = await SharedPreferences.getInstance();
      phoneDeletes = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(photoManager, (call) async {
        if (call.method != 'deleteWithIds') return null;
        final ids = ((call.arguments as Map)['ids'] as List).cast<String>();
        phoneDeletes.add(ids);
        return ids;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(photoManager, null),
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Center(
                child: Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () => showFreeUpSpace(context, ref),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(path: '/free-up', builder: (_, _) => const FreeUpPreviewScreen()),
          GoRoute(
            path: '/viewer/:fileId',
            builder: (_, state) =>
                Scaffold(body: Text('Viewing ${state.pathParameters['fileId']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(shared),
            freeableProvider.overrideWith((ref) async => all),
            transferQueueProvider.overrideWith(_Queue.new),
            deviceStorageProvider.overrideWithValue(_Storage(23 * _gb, 128 * _gb)),
          ],
          child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    KeepWindow selected(WidgetTester tester) => tester
        .widget<SegmentedButton<KeepWindow>>(find.byType(SegmentedButton<KeepWindow>))
        .selected
        .single;

    FilledButton freeUp(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byType(FilledButton));

    testWidgets('keeps 30 days at first, and a change shows at once and is remembered', (
      tester,
    ) async {
      await pumpSheet(tester, sample());
      expect(find.text('Keep on this phone'), findsOneWidget);
      expect(selected(tester), KeepWindow.days30);
      // The title and the button.
      expect(find.text('Free up ${Formatters.bytes(650 * _mb)}'), findsNWidgets(2));
      expect(find.textContaining('4 photos and videos from before '), findsOneWidget);
      expect(find.textContaining('oldest from 2021'), findsOneWidget);

      await tester.tap(find.text('90 days'));
      await tester.pumpAndSettle();
      expect(selected(tester), KeepWindow.days90);
      expect(find.text('Free up ${Formatters.bytes(600 * _mb)}'), findsNWidgets(2));
      expect(find.textContaining('3 photos and videos from before '), findsOneWidget);

      await tester.tap(find.text('Nothing'));
      await tester.pumpAndSettle();
      expect(find.text('Free up ${Formatters.bytes(680 * _mb)}'), findsNWidgets(2));
      expect(find.textContaining('6 photos and videos on this phone are'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString('free_up_keep'),
        KeepWindow.nothing.name,
      );

      // Closed and opened again, it keeps the last choice.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(selected(tester), KeepWindow.nothing);
    });

    testWidgets('a window that keeps everything turns Free up off until a wider one', (
      tester,
    ) async {
      final today = DateTime.now();
      await pumpSheet(
        tester,
        Freeable([_item('e', takenAt: today.subtract(const Duration(days: 2)))]),
        prefs: {'free_up_keep': 'days90'},
      );
      expect(selected(tester), KeepWindow.days90);
      expect(find.textContaining('Everything backed up from this phone is newer'), findsOneWidget);
      expect(find.text('Free up space'), findsOneWidget);
      expect(freeUp(tester).onPressed, isNull);
      expect(find.text('Show them'), findsNothing);

      await tester.tap(find.text('Nothing'));
      await tester.pumpAndSettle();
      expect(freeUp(tester).onPressed, isNotNull);
      expect(find.text('Free up ${Formatters.bytes(4 * _mb)}'), findsNWidgets(2));
    });

    testWidgets('with nothing backed up there is only Close', (tester) async {
      await pumpSheet(tester, Freeable.none);
      expect(find.text('Nothing to free up'), findsOneWidget);
      expect(find.byType(SegmentedButton<KeepWindow>), findsNothing);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('Show them lists exactly what goes, selects nothing and opens a photo', (
      tester,
    ) async {
      await pumpSheet(tester, sample());
      await tester.tap(find.text('Show them'));
      await tester.pumpAndSettle();

      expect(find.byType(FreeUpPreviewScreen), findsOneWidget);
      expect(find.textContaining('Before '), findsOneWidget);
      expect(find.text('4 items · ${Formatters.bytes(650 * _mb)}'), findsOneWidget);
      final shown = tester.widgetList<FileThumbnail>(find.byType(FileThumbnail));
      expect(shown.map((t) => t.file.id), ['d', 'c', 'b', 'a']);

      await tester.longPress(find.byType(FileThumbnail).first);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      await tester.tap(find.byType(FileThumbnail).first);
      await tester.pumpAndSettle();
      expect(find.text('Viewing d'), findsOneWidget);

      // Back on the sheet, where the choice still stands.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(find.text('Keep on this phone'), findsOneWidget);
    });

    testWidgets('Free up deletes only what is older than the window', (tester) async {
      await pumpSheet(tester, sample());
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(phoneDeletes, [
        ['asset-a', 'asset-b', 'asset-c', 'asset-d'],
      ]);
      expect(find.text('Freed up space: 4 items deleted from this phone'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('more than 500 says Android asks once per 500', (tester) async {
      await pumpSheet(
        tester,
        Freeable([
          for (var i = 0; i < 501; i++) _item('$i', takenAt: DateTime(2022, 1, 1 + i % 28)),
        ]),
      );
      expect(find.text('Android asks you to confirm, once per 500 items.'), findsOneWidget);
    });
  });
}
