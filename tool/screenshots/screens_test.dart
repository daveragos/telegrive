// Renders the signed-in screens with sample data, for eyeballing the UI
// without a Telegram account. Not part of `flutter test`:
//
//   flutter test tool/screenshots/screens_test.dart --update-goldens
//
// Images land in tool/screenshots/out/.

import 'dart:async';
import 'dart:convert' show base64Encode;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:telegrive/app/app_shell.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/auth/presentation/phone_screen.dart';
import 'package:telegrive/features/auth/presentation/welcome_screen.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/backup/data/local_media.dart';
import 'package:telegrive/features/backup/presentation/backup_screen.dart';
import 'package:telegrive/features/backup/presentation/not_backed_up_screen.dart';
import 'package:telegrive/features/capture/data/device_capture.dart';
import 'package:telegrive/features/photos/data/photos_visibility.dart';
import 'package:telegrive/features/photos/presentation/photos_screen.dart';
import 'package:telegrive/features/search/presentation/search_screen.dart';
import 'package:telegrive/features/photos/presentation/albums_screen.dart';
import 'package:telegrive/features/send/data/telegram_chats.dart';
import 'package:telegrive/features/trash/presentation/trash_screen.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/widgets/file_visuals.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/previews.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/data/telegram_wait.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/data/bulk_edits.dart';
import 'package:telegrive/features/files/presentation/file_list_screen.dart';
import 'package:telegrive/features/files/presentation/file_location.dart';
import 'package:telegrive/features/files/presentation/files_screen.dart';
import 'package:telegrive/features/files/presentation/folder_picker.dart';
import 'package:telegrive/features/home/presentation/home_screen.dart';
import 'package:telegrive/features/import/data/chat_media.dart';
import 'package:telegrive/features/import/presentation/import_screen.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/features/offline/presentation/keep_offline_sheet.dart';
import 'package:telegrive/features/offline/presentation/offline_screen.dart';
import 'package:telegrive/features/settings/data/settings_providers.dart';
import 'package:telegrive/features/settings/presentation/settings_screen.dart';
import 'package:telegrive/features/share/data/recent_destinations.dart';
import 'package:telegrive/features/share/data/share_intake.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/features/transfers/domain/transfer_wait.dart';
import 'package:telegrive/features/transfers/presentation/mobile_data_prompt.dart';
import 'package:telegrive/features/transfers/presentation/transfers_screen.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _gb = 1024 * 1024 * 1024;
const _mb = 1024 * 1024;

class _Session extends DriveSessionNotifier {
  @override
  DriveSession? build() => const DriveSession(
    userId: 1,
    chatId: -1001234567890,
    channelTitle: 'Telegrive',
    firstName: 'Dawit',
    lastName: 'Beyene',
    phoneNumber: '251911000000',
    username: 'dawit',
    isPremium: false,
  );
}

class _Sync extends DriveSync {
  @override
  SyncState build() => SyncState(lastSynced: DateTime.now());
}

class _Network extends NetworkStatus {
  _Network(this._state);

  final NetworkState _state;

  @override
  NetworkState build() => _state;
}

class _Backup extends BackupController {
  _Backup(this._state);

  final BackupState _state;

  @override
  BackupState build() => _state;

  @override
  Future<List<DeviceFolder>> deviceFolders() async => const [
    DeviceFolder(name: 'Camera', count: 2841),
    DeviceFolder(name: 'Screenshots', count: 612),
    DeviceFolder(name: 'WhatsApp Images', count: 1930),
    DeviceFolder(name: 'Telegram', count: 208),
  ];
}

class _Storage extends DeviceStorage {
  @override
  Future<int?> freeBytes() async => 23 * _gb;
}

class _Queue extends TransferQueue {
  _Queue(this._state);

  final TransfersState _state;

  @override
  TransfersState build() => _state;
}

/// A chat's files as if every page were read, for [ImportFilter.media] or
/// the other kinds.
class _ChatMedia extends ChatMedia {
  _ChatMedia(super.source, {required this.documents, required this.photos});

  final ChatMediaState documents;
  final ChatMediaState photos;

  @override
  Future<ChatMediaState> build() async =>
      source.filter == ImportFilter.media ? photos : documents;
}

class _Bulk extends BulkEdits {
  _Bulk(this._edit);

  final BulkEdit? _edit;

  @override
  BulkEdit? build() => _edit;
}

/// Files another app just shared in, waiting for the sheet.
class _Intake extends ShareIntake {
  @override
  List<SharedFile> build() => const [
    SharedFile(path: '/cache/shared/1/Receipt.png', name: 'Receipt.png', size: 2 * _mb + 310000),
    SharedFile(path: '/cache/shared/2/Lunch receipt.pdf', name: 'Lunch receipt.pdf', size: 184000),
  ];
}

/// The folders uploads went into lately, Receipts last.
class _Recent extends RecentDestinations {
  @override
  List<FolderChoice> build() => const [
    FolderChoice('receipts', 'Receipts'),
    FolderChoice('invoices', 'Invoices'),
    FolderChoice(null, 'Files'),
  ];
}

class _Wait extends TelegramWait {
  _Wait(this._until);

  final DateTime? _until;

  @override
  DateTime? build() => _until;
}

Future<void> _loadFonts() async {
  final sdkFonts =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());
  final plex = FontLoader('IBMPlexSans');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    plex.addFont(read('assets/fonts/IBMPlexSans-$weight.ttf'));
  }
  await plex.load();
  // Framework widgets that fall back to Roboto still get real glyphs.
  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(read('$sdkFonts/Roboto-$weight.ttf'));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('$sdkFonts/MaterialIcons-Regular.otf'))).load();
}

typedef _FakePhoto = ({Uint8List mini, int thumbId});

/// Thumbnail id to file path, served through thumbnailPathProvider.
final _thumbPaths = <int, String>{};

/// Draws a small landscape (sky, sun, two hills) at [px] square.
Future<Uint8List> _scene(Color sky, Color ground, int px) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = px.toDouble();
  canvas.drawRect(
    Rect.fromLTWH(0, 0, s, s),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, s), [
        sky,
        Color.lerp(sky, Colors.white, 0.45)!,
      ]),
  );
  canvas.drawCircle(
    Offset(s * 0.7, s * 0.3),
    s * 0.11,
    Paint()..color = const Color(0xFFFFF4D6),
  );
  final far = Path()
    ..moveTo(0, s * 0.7)
    ..quadraticBezierTo(s * 0.3, s * 0.45, s * 0.6, s * 0.66)
    ..quadraticBezierTo(s * 0.8, s * 0.55, s, s * 0.62)
    ..lineTo(s, s)
    ..lineTo(0, s)
    ..close();
  canvas.drawPath(far, Paint()..color = Color.lerp(ground, sky, 0.35)!);
  final near = Path()
    ..moveTo(0, s * 0.82)
    ..quadraticBezierTo(s * 0.45, s * 0.66, s, s * 0.84)
    ..lineTo(s, s)
    ..lineTo(0, s)
    ..close();
  canvas.drawPath(near, Paint()..color = ground);
  final image = await recorder.endRecording().toImage(px, px);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// A photo as the app receives it: Telegram's tiny inline preview plus a
/// thumbnail at the resolution Telegram actually serves (320 px).
Future<_FakePhoto> _fakePhoto(Color sky, Color ground) async {
  final id = _thumbPaths.length + 1;
  final file = File('${Directory.systemTemp.path}/telegrive_thumb_$id.png');
  await file.writeAsBytes(await _scene(sky, ground, 320));
  _thumbPaths[id] = file.path;
  return (mini: await _scene(sky, ground, 24), thumbId: id);
}

DriveFile _file(
  String name,
  int size,
  int hoursAgo, {
  bool starred = false,
  _FakePhoto? thumb,
  int parts = 1,
  int? takenDaysAgo,
  String? folderId,
}) {
  final at = DateTime.now().subtract(Duration(hours: hoursAgo));
  return DriveFile(
    id: name,
    folderId: folderId,
    name: name,
    mimeType: mimeTypeFor(name),
    kind: FileKind.detect(fileName: name, mimeType: mimeTypeFor(name)),
    size: size,
    createdAt: at,
    modifiedAt: at,
    partCount: parts,
    starred: starred,
    minithumbnail: thumb?.mini,
    thumbnailFileId: thumb?.thumbId,
    takenAt: takenDaysAgo == null
        ? null
        : DateTime.now().subtract(Duration(days: takenDaysAgo)),
  );
}

DriveFolder _folder(String name, int daysAgo, {String? parentId}) {
  final at = DateTime.now().subtract(Duration(days: daysAgo));
  return DriveFolder(
    id: name,
    parentId: parentId,
    name: name,
    createdAt: at,
    modifiedAt: at,
  );
}

TransferRow _transfer(
  String name,
  TransferKind kind,
  TransferStatus status,
  int total,
  int done, {
  int parts = 1,
  int completedParts = 0,
  String? error,
  bool wifiOnly = false,
}) => TransferRow(
  id: name,
  kind: kind,
  status: status,
  name: name,
  mimeType: mimeTypeFor(name),
  fileId: name,
  ownsSource: false,
  wifiOnly: wifiOnly,
  origin: TransferOrigin.manual,
  totalBytes: total,
  doneBytes: done,
  partCount: parts,
  completedParts: completedParts,
  error: error,
  createdAt: DateTime.now().subtract(Duration(minutes: done ~/ _mb)),
  finishedAt: status.isFinished
      ? DateTime.now().subtract(const Duration(minutes: 12))
      : null,
);

void main() {
  late List<DriveFile> files;
  late List<DriveFile> photos;
  late List<DriveFolder> folders;
  late List<(DriveFile, DateTime)> opens;
  late TransfersState transfers;
  late ChatMediaState chatDocuments;
  late ChatMediaState chatPhotos;

  setUpAll(() async {
    await _loadFonts();
  });

  Future<void> prepareData(WidgetTester tester) async {
    await tester.runAsync(() async {
      _thumbPaths.clear();
      final beach = await _fakePhoto(
        const Color(0xFFF2A65A),
        const Color(0xFF5B3A29),
      );
      final forest = await _fakePhoto(
        const Color(0xFF87CEEB),
        const Color(0xFF2F6B4F),
      );
      final city = await _fakePhoto(
        const Color(0xFF2E3A59),
        const Color(0xFF151B28),
      );
      final palette = [
        (const Color(0xFF7DB9E8), const Color(0xFF4E7D3A)),
        (const Color(0xFFF2A65A), const Color(0xFF5B3A29)),
        (const Color(0xFF9BC4E2), const Color(0xFFC9A66B)),
        (const Color(0xFF2E3A59), const Color(0xFF151B28)),
        (const Color(0xFFB8D8D8), const Color(0xFF6E8F72)),
        (const Color(0xFFE8B4A0), const Color(0xFF6B5B73)),
        (const Color(0xFF87CEEB), const Color(0xFF2F6B4F)),
      ];
      final thumbs = [for (final (a, b) in palette) await _fakePhoto(a, b)];
      photos = [
        for (var i = 0; i < 26; i++)
          _file(
            i % 7 == 3
                ? 'VID_2026${i.toString().padLeft(4, '0')}.mp4'
                : 'IMG_2026${i.toString().padLeft(4, '0')}.jpg',
            (3 + i % 5) * _mb,
            i,
            thumb: thumbs[i % thumbs.length],
            takenDaysAgo: i < 9 ? i : (i < 18 ? 32 + i : 70 + i * 2),
            starred: i == 4,
            // A third came from the phone's Screenshots folder.
            folderId: i % 3 == 2 ? 'scr' : null,
          ),
      ];
      ChatItem chatItem(DriveFile file, int messageId) => ChatItem(
        messageId: messageId,
        preview: file,
        size: file.size,
        date: file.momentAt,
      );
      chatPhotos = ChatMediaState(
        items: [
          for (var i = 0; i < 30; i++)
            chatItem(
              _file(
                'Family photo $i.jpg',
                (2.1 * _mb).round() + i * 40000,
                0,
                thumb: thumbs[(i * 3) % thumbs.length],
                takenDaysAgo: 34 + i * 3,
              ),
              900 - i,
            ),
        ],
        totalCount: 30,
      );
      chatDocuments = ChatMediaState(
        items: [
          for (final (index, (name, size, daysAgo)) in [
            ('Lease 2023.pdf', (2.4 * _mb).round(), 3),
            ('Residence permit.pdf', 860000, 11),
            ('Wedding photos.zip', 10 * _mb, 25),
            ('Payslip August.pdf', 310000, 33),
            ('Thesis draft v3.docx', 6 * _mb, 61),
            ('Flight tickets.pdf', 420000, 97),
            ('Insurance policy.pdf', (1.2 * _mb).round(), 140),
            ('Budget 2025.xlsx', 96000, 220),
            ('Car registration.pdf', 540000, 300),
            ('Recipes.pdf', (3.8 * _mb).round(), 410),
            ('CV 2023.pdf', 180000, 520),
            ('Diploma scan.pdf', (4.6 * _mb).round(), 900),
          ].indexed)
            chatItem(
              DriveFile(
                id: ChatItem.previewId(800 - index),
                folderId: null,
                name: name,
                mimeType: mimeTypeFor(name),
                kind: FileKind.detect(fileName: name, mimeType: mimeTypeFor(name)),
                size: size,
                createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
                modifiedAt: DateTime.now().subtract(Duration(days: daysAgo)),
                partCount: 1,
                starred: false,
              ),
              800 - index,
            ),
        ],
        totalCount: 50,
        hiddenSaved: 38,
      );
      files = [
        _file(
          'Lalibela sunrise.jpg',
          6 * _mb + 300000,
          2,
          thumb: beach,
          starred: true,
        ),
        _file(
          'Wedding highlights 4K.mp4',
          (5.6 * _gb).round(),
          5,
          thumb: city,
          parts: 12,
        ),
        _file('Tax return 2025.pdf', 2 * _mb + 420000, 26, starred: true),
        _file('Simien trek.png', 11 * _mb, 30, thumb: forest),
        _file('Project backup.zip', 780 * _mb, 50),
        _file('Budget 2026.xlsx', 88000, 70),
        _file('Tizita — live.mp3', 9 * _mb, 90),
        _file('gramx-release.apk', 62 * _mb, 120),
      ];
    });
    // Opened on this phone, most recent first, each some time after it was
    // added.
    opens = [
      for (final (index, hoursAgo) in [(2, 20), (4, 44), (5, 60), (6, 84), (7, 110)])
        (files[index], DateTime.now().subtract(Duration(hours: hoursAgo))),
    ];
    folders = [
      _folder('Documents', 3),
      _folder('Photos', 1),
      _folder('Work', 9),
    ];
    transfers = TransfersState([
      TransferItem(
        _transfer(
          'Wedding highlights 4K.mp4',
          TransferKind.upload,
          TransferStatus.running,
          (5.6 * _gb).round(),
          (2.3 * _gb).round(),
          parts: 12,
          completedParts: 4,
        ),
        bytesPerSecond: 6.2 * _mb,
      ),
      TransferItem(
        _transfer(
          'Simien trek.png',
          TransferKind.download,
          TransferStatus.running,
          11 * _mb,
          7 * _mb,
        ),
        bytesPerSecond: 2.1 * _mb,
      ),
      TransferItem(
        _transfer(
          'Thesis final.docx',
          TransferKind.upload,
          TransferStatus.queued,
          4 * _mb,
          0,
        ),
        wait: WaitingForTelegram(
          DateTime.now().add(const Duration(minutes: 1, seconds: 12)),
        ),
      ),
      TransferItem(
        _transfer(
          'Tax return 2025.pdf',
          TransferKind.upload,
          TransferStatus.completed,
          2 * _mb,
          2 * _mb,
        ),
      ),
      TransferItem(
        _transfer(
          'Old phone backup.tar',
          TransferKind.upload,
          TransferStatus.failed,
          900 * _mb,
          120 * _mb,
          error: 'The original file is no longer available.',
        ),
      ),
      TransferItem(
        _transfer(
          'Budget 2026.xlsx',
          TransferKind.download,
          TransferStatus.failed,
          88000,
          0,
          error: 'Not enough space on this phone.',
        ),
      ),
    ]);
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    required String location,
    ThemeMode themeMode = ThemeMode.light,
    Map<String, Object> prefs = const {},
    BackupState backup = const BackupState(phase: BackupPhase.off),
    BulkEdit? bulk,
    DateTime? telegramWait,
    NetworkState network = NetworkState.unknown,
    CaptureSupport captureSupport = const CaptureSupport(scan: true, photo: true),
    List<Override> overrides = const [],
    Future<void> Function(AppDatabase db)? seed,
  }) async {
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'backup_prompt_shown': true,
      ...prefs,
    });
    final shared = await SharedPreferences.getInstance();

    // Three of the photos were backed up from this phone.
    final db = AppDatabase(NativeDatabase.memory());
    for (var i = 1; i <= 3; i++) {
      await db.markAssetBackedUp('asset-$i', photos[i].id);
    }
    await seed?.call(db);

    final summary = StorageSummary(
      totals: [
        for (final kind in FileKind.values)
          KindTotal(
            kind,
            files.where((f) => f.kind == kind).length,
            files.where((f) => f.kind == kind).fold(0, (s, f) => s + f.size),
          ),
      ],
    );

    final router = GoRouter(
      initialLocation: location,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/files',
                  builder: (_, state) => FilesScreen(
                    highlight: state.uri.queryParameters['highlight'],
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/photos',
                  builder: (_, _) => const PhotosScreen(),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/backup',
          builder: (_, _) => const BackupScreen(),
          routes: [
            GoRoute(
              path: 'not-backed-up',
              builder: (_, _) => const NotBackedUpScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/search',
          builder: (_, state) => SearchScreen(
            media: state.uri.queryParameters['kind'] == 'media',
            initialFolderId: state.uri.queryParameters['folder'],
          ),
        ),
        GoRoute(path: '/trash', builder: (_, _) => const TrashScreen()),
        GoRoute(path: '/offline', builder: (_, _) => const OfflineScreen()),
        GoRoute(path: '/albums', builder: (_, _) => const AlbumsScreen()),
        GoRoute(path: '/transfers', builder: (_, _) => const TransfersScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(path: '/recent', builder: (_, _) => const FileListScreen.recent()),
        GoRoute(
          path: '/import/:chatId',
          builder: (_, state) => ImportScreen(
            chatId: int.parse(state.pathParameters['chatId']!),
            title: state.uri.queryParameters['title'] ?? '',
            photos: state.uri.queryParameters['photos'] == '1',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          appDatabaseProvider.overrideWithValue(db),
          deviceStorageProvider.overrideWithValue(_Storage()),
          driveSessionProvider.overrideWith(_Session.new),
          driveSyncProvider.overrideWith(_Sync.new),
          transferQueueProvider.overrideWith(() => _Queue(transfers)),
          storageSummaryProvider.overrideWith((ref) => Stream.value(summary)),
          recentActivityProvider(12).overrideWith(
            (ref) => Stream.value(
              RecentEntry.merge(
                opened: opens.take(2).toList(),
                added: files.take(4).toList(),
                limit: 12,
              ),
            ),
          ),
          recentOpenedProvider.overrideWith(
            (ref) => Stream.value([
              for (final (file, at) in opens) RecentEntry(file, at: at, opened: true),
            ]),
          ),
          recentAddedProvider.overrideWith(
            (ref) => Stream.value(files.take(5).toList()),
          ),
          starredFilesProvider.overrideWith(
            (ref) => Stream.value(files.where((f) => f.starred).toList()),
          ),
          folderContentsProvider(null).overrideWith(
            (ref) =>
                Stream.value(FolderContents(folders: folders, files: files)),
          ),
          folderInfoProvider('Work').overrideWith((ref) => Stream.value(folders[2])),
          cacheSizeProvider.overrideWith((ref) async => 734 * _mb),
          backupControllerProvider.overrideWith(() => _Backup(backup)),
          bulkEditsProvider.overrideWith(() => _Bulk(bulk)),
          telegramWaitProvider.overrideWith(() => _Wait(telegramWait)),
          networkStatusProvider.overrideWith(() => _Network(network)),
          captureSupportProvider.overrideWith((ref) async => captureSupport),
          mediaTimelineProvider.overrideWith((ref) => Stream.value(photos)),
          trashProvider.overrideWith(
            (ref) => Stream.value(
              TrashContents(
                folders: [
                  DriveFolder(
                    id: 'old',
                    parentId: 'Documents',
                    name: 'Old taxes',
                    createdAt: DateTime(2024),
                    modifiedAt: DateTime(2024),
                    trashedAt: DateTime.now().subtract(const Duration(days: 12)),
                  ),
                ],
                files: [
                  _file('Draft v1.docx', 900000, 40),
                  _file('Screen recording.mp4', 84 * _mb, 300),
                ].map((f) => DriveFile(
                  id: f.id, folderId: f.size > _mb ? null : 'Clients', name: f.name, mimeType: f.mimeType,
                  kind: f.kind, size: f.size, createdAt: f.createdAt,
                  modifiedAt: f.modifiedAt, partCount: 1, starred: false,
                  trashedAt: DateTime.now().subtract(Duration(days: f.size > _mb ? 26 : 2)),
                )).toList(),
              ),
            ),
          ),
          albumsProvider.overrideWith(
            (ref) => Stream.value([
              DriveAlbum(id: 'a1', name: 'Lalibela 2026', count: 48, coverFileId: photos[1].id),
              DriveAlbum(id: 'a2', name: 'Family', count: 212, coverFileId: photos[6].id),
              DriveAlbum(id: 'a3', name: 'Receipts', count: 17, coverFileId: photos[9].id),
            ]),
          ),
          for (final photo in photos)
            fileInfoProvider(photo.id).overrideWith((ref) => Stream.value(photo)),
          recentChatsProvider.overrideWith(
            (ref) async => const [
              TelegramChat(id: 1, title: 'Saved Messages', isSelf: true),
              TelegramChat(id: 2, title: 'Selam Tesfaye'),
              TelegramChat(id: 3, title: 'Family', isGroup: true),
              TelegramChat(id: 4, title: 'Abebe Kebede'),
              TelegramChat(id: 5, title: 'Design team', isGroup: true),
            ],
          ),
          importChatsProvider.overrideWith(
            (ref) async => const [
              TelegramChat(id: 1, title: 'Saved Messages', isSelf: true),
              TelegramChat(id: 2, title: 'Selam Tesfaye'),
              TelegramChat(id: 3, title: 'Family', isGroup: true),
              TelegramChat(id: 6, title: 'Addis photographers', isGroup: true),
              TelegramChat(id: 7, title: 'Exam answers', isGroup: true, canSave: false),
              TelegramChat(id: 4, title: 'Abebe Kebede'),
            ],
          ),
          chatMediaProvider.overrideWith2(
            (source) => _ChatMedia(source, documents: chatDocuments, photos: chatPhotos),
          ),
          for (final entry in _thumbPaths.entries)
            thumbnailPathProvider(entry.key).overrideWith((ref) async => entry.value),
          ...overrides,
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          routerConfig: router,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    // Decode the sample thumbnails for real; fake-async never finishes it.
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold).first);
      for (final file in [...files, ...photos]) {
        if (file.minithumbnail != null) {
          await precacheImage(MemoryImage(file.minithumbnail!), context);
        }
      }
      for (final path in _thumbPaths.values) {
        await precacheImage(FileImage(File(path)), context);
      }
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// Shadows are drawn for real here (tests flatten them by default), then
  /// switched back so the framework's end-of-test checks pass.
  Future<void> snap(WidgetTester tester, String name) async {
    debugDisableShadows = false;
    for (final view in tester.binding.renderViews) {
      view.markNeedsPaint();
    }
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    try {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('out/$name.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
    // Close the app here, so the database's stream clean-up timers run
    // inside the test rather than after it.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('home', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/home');
    await snap(tester, 'home_light');
  });

  testWidgets('home dark', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/home', themeMode: ThemeMode.dark);
    await snap(tester, 'home_dark');
  });

  testWidgets('home offline', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/home',
      overrides: [
        // Something is kept offline, so Storage offers the way there.
        offlinePinsProvider.overrideWith((ref) => Stream.value({'Work'})),
        offlineUsageProvider.overrideWith((ref) => Stream.value((19, 353 * _mb))),
      ],
    );
    // Scrolled so the row sits above the New button.
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -400));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await snap(tester, 'home_offline');
  });

  testWidgets('home recent', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/home');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -900));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await snap(tester, 'home_recent');
  });

  testWidgets('home all good', (tester) async {
    await prepareData(tester);
    transfers = TransfersState.empty;
    await pumpApp(
      tester,
      location: '/home',
      backup: BackupState(
        phase: BackupPhase.upToDate,
        total: 4847,
        done: 4847,
        lastCompleted: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
    );
    await snap(tester, 'home_all_good');
  });

  testWidgets('home backup stopped', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/home',
      backup: const BackupState(
        phase: BackupPhase.stopped,
        error: 'Telegram took too long to answer.',
      ),
    );
    await snap(tester, 'home_stopped');
  });

  testWidgets('home waiting for wifi', (tester) async {
    await prepareData(tester);
    transfers = TransfersState([
      for (final (name, total, done) in [
        ('Lecture 1.mp4', (1.2 * _gb).round(), 0),
        ('Lecture 2.mp4', (1.2 * _gb).round(), 300 * _mb),
        ('Course notes.pdf', 60 * _mb, 0),
      ])
        TransferItem(
          _transfer(name, TransferKind.download, TransferStatus.queued, total, done, wifiOnly: true),
          wait: const WaitingForWifi(),
        ),
    ]);
    await pumpApp(
      tester,
      location: '/home',
      network: const NetworkState(online: true, metered: true),
      backup: BackupState(
        phase: BackupPhase.upToDate,
        total: 4847,
        done: 4847,
        lastCompleted: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
    );
    await snap(tester, 'home_waiting_for_wifi');
  });

  /// What Search reads straight from the index: two invoices filed under
  /// Work, and a photo and a video from the same trek.
  Future<void> seedSearch(AppDatabase db) async {
    var message = 1;
    Future<void> addFolder(String name, {String? parentId}) => db.upsertFolder(
      FoldersCompanion.insert(
        id: name,
        parentId: Value(parentId),
        name: name,
        messageId: message++,
        createdAt: DateTime(2024),
        modifiedAt: DateTime(2024),
      ),
    );
    Future<void> addFile(DriveFile file) => db.upsertFilePart(
      DriveFilesCompanion.insert(
        id: file.id,
        folderId: Value(file.folderId),
        name: file.name,
        mimeType: file.mimeType,
        kind: file.kind,
        size: file.size,
        createdAt: file.createdAt,
        modifiedAt: file.modifiedAt,
        minithumbnail: Value(
          file.minithumbnail == null ? null : base64Encode(file.minithumbnail!),
        ),
        thumbnailFileId: Value(file.thumbnailFileId),
        takenAt: Value(file.takenAt),
        durationSeconds: Value(file.durationSeconds),
      ),
      FilePartsCompanion.insert(
        fileId: file.id,
        partIndex: 0,
        messageId: message,
        tdFileId: message++,
        size: file.size,
      ),
    );
    DriveFile invoice(String name, String folderId, int size, DateTime at) => DriveFile(
      id: name,
      folderId: folderId,
      name: name,
      mimeType: mimeTypeFor(name),
      kind: FileKind.document,
      size: size,
      createdAt: at,
      modifiedAt: at,
      partCount: 1,
      starred: false,
    );
    final trekked = DateTime.now().subtract(const Duration(days: 300));

    await addFolder('Work');
    await addFolder('Invoices', parentId: 'Work');
    await addFile(invoice('Invoice March.pdf', 'Invoices', 1200000, DateTime(2024, 3, 14, 10)));
    await addFile(invoice('Invoice March hotel.pdf', 'Work', 380000, DateTime(2024, 3, 28, 16)));
    await addFile(files[3]);
    await addFile(
      DriveFile(
        id: 'Simien trek.mp4',
        folderId: null,
        name: 'Simien trek.mp4',
        mimeType: mimeTypeFor('Simien trek.mp4'),
        kind: FileKind.video,
        size: 148 * _mb,
        createdAt: trekked,
        modifiedAt: trekked,
        partCount: 1,
        starred: false,
        minithumbnail: photos[2].minithumbnail,
        thumbnailFileId: photos[2].thumbnailFileId,
        takenAt: trekked,
        durationSeconds: 94,
      ),
    );
  }

  testWidgets('home empty', (tester) async {
    await prepareData(tester);
    files = [];
    opens = [];
    transfers = TransfersState.empty;
    await pumpApp(tester, location: '/home');
    await snap(tester, 'home_empty');
  });

  testWidgets('search', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/home', seed: seedSearch);
    await tester.tap(find.text('Search files and folders'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.enterText(find.byType(TextField), 'invoice march 2024');
    await tester.pump(const Duration(milliseconds: 300));
    await snap(tester, 'search');
  });

  testWidgets('search media', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/photos', seed: seedSearch);
    await tester.tap(find.byTooltip('Search photos and videos'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.enterText(find.byType(TextField), 'trek');
    await tester.pump(const Duration(milliseconds: 300));
    await snap(tester, 'search_media');
  });

  testWidgets('search in folder', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    GoRouter.of(tester.element(find.byType(FilesScreen))).push('/search?folder=Work');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'search_in_folder');
  });

  testWidgets('recent', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/recent');
    await snap(tester, 'recent');
  });

  testWidgets('files list', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    await snap(tester, 'files_list');
  });

  testWidgets('bulk edit waiting', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/files',
      bulk: const BulkEdit(
        label: 'Moving 500 items',
        icon: Icons.drive_file_move_outline,
        done: 212,
        total: 500,
      ),
      telegramWait: DateTime.now().add(const Duration(minutes: 3, seconds: 41)),
    );
    await snap(tester, 'bulk_waiting');
  });

  testWidgets('waiting for network', (tester) async {
    await prepareData(tester);
    transfers = TransfersState([
      for (final item in transfers.items.take(2))
        TransferItem(item.row, wait: const WaitingForNetwork()),
    ]);
    await pumpApp(
      tester,
      location: '/files',
      network: const NetworkState(online: false, metered: false),
    );
    await snap(tester, 'files_waiting_for_network');
  });

  testWidgets('files grid', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/files',
      prefs: {'view_mode': 'grid'},
      overrides: [
        offlinePinsProvider.overrideWith((ref) => Stream.value({'Work'})),
        offlineCopiesProvider.overrideWith(
          (ref) => Stream.value({'Budget 2026.xlsx': '/offline/budget/Budget 2026.xlsx'}),
        ),
      ],
    );
    await snap(tester, 'files_grid');
  });

  testWidgets('show in folder', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    final highlight = Uri.encodeQueryComponent('Tax return 2025.pdf');
    GoRouter.of(tester.element(find.byType(FilesScreen))).go('/files?highlight=$highlight');
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'show_in_folder');
  });

  testWidgets('file sheet', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    await tester.tap(find.byTooltip('More').at(3));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'file_sheet');
  });

  testWidgets('selection', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    await tester.longPress(find.text('Budget 2026.xlsx'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Lalibela sunrise.jpg'));
    await tester.pump(const Duration(milliseconds: 300));
    await snap(tester, 'files_selection');
  });

  testWidgets('save sheet', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    await tester.longPress(find.text('Lalibela sunrise.jpg'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Simien trek.png'));
    await tester.tap(find.text('Budget 2026.xlsx'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Download to this phone'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'save_sheet');
  });

  testWidgets('save sheet on mobile data', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/files',
      network: const NetworkState(online: true, metered: true),
    );
    await tester.longPress(find.text('Project backup.zip'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Simien trek.png'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Download to this phone'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'save_sheet_mobile_data');
  });

  testWidgets('mobile data dialog', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/files',
      network: const NetworkState(online: true, metered: true),
    );
    unawaited(
      askAboutMobileData(
        tester.element(find.byType(Scaffold).first),
        bytes: (1.4 * _gb).round(),
        doing: 'Uploading 3 files',
        files: 3,
        nowLabel: 'Upload now',
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'mobile_data_dialog');
  });

  testWidgets('transfers saving', (tester) async {
    await prepareData(tester);
    TransferItem save(
      String name,
      TransferStatus status,
      int total,
      int done, {
      bool waitsForWifi = false,
    }) => TransferItem(
      _transfer(name, TransferKind.download, status, total, done, wifiOnly: waitsForWifi).copyWith(
        origin: TransferOrigin.save,
        saveTo: const Value(SaveTarget.files),
      ),
      bytesPerSecond: status == TransferStatus.running ? 4.1 * _mb : 0,
      wait: waitsForWifi ? const WaitingForWifi() : null,
    );
    transfers = TransfersState([
      save(
        'Wedding highlights 4K.mp4',
        TransferStatus.queued,
        (5.6 * _gb).round(),
        (1.2 * _gb).round(),
        waitsForWifi: true,
      ),
      save('Project backup.zip', TransferStatus.running, 780 * _mb, 300 * _mb),
      for (var i = 0; i < 40; i++)
        save('IMG_$i.jpg', TransferStatus.queued, 4 * _mb, 0),
      for (var i = 0; i < 212; i++)
        save('Scan $i.pdf', TransferStatus.completed, 2 * _mb, 2 * _mb),
      save('Old notes.txt', TransferStatus.failed, 12000, 0),
      ...transfers.items.take(2),
    ]);
    await pumpApp(tester, location: '/transfers');
    await snap(tester, 'transfers_saving');
  });

  /// The folders Trash's items came from, for their location lines.
  Override trashPlaces() => folderIndexProvider.overrideWith(
    (ref) => Stream.value({
      for (final folder in [...folders, _folder('Clients', 9, parentId: 'Work')])
        folder.id: folder,
    }),
  );

  testWidgets('trash', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/trash', overrides: [trashPlaces()]);
    await snap(tester, 'trash');
  });

  testWidgets('trash deleting', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/trash', overrides: [trashPlaces()]);
    await tester.tap(find.text('Draft v1.docx'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Delete for good'));
    await tester.pump(const Duration(milliseconds: 300));
    await snap(tester, 'trash_deleting');
  });

  testWidgets('albums', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/albums');
    await snap(tester, 'albums');
  });

  testWidgets('photos menu', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/photos');
    await tester.tap(find.byTooltip('More'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'photos_menu');
  });

  testWidgets('photos selection', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/photos');
    final tiles = find.byType(FileThumbnail);
    final gesture = await tester.startGesture(tester.getCenter(tiles.at(1)));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(tester.getCenter(tiles.at(6)));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await snap(tester, 'photos_selection');
  });

  testWidgets('trash sheet', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/photos');
    // The phone's library still holds whatever backup took from it.
    const library = MethodChannel('com.fluttercandies/photo_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      library,
      (call) async => call.method == 'fetchEntityProperties'
          ? {'id': (call.arguments as Map)['id'], 'type': 1, 'width': 4000, 'height': 3000}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(library, null),
    );
    final tiles = find.byType(FileThumbnail);
    final gesture = await tester.startGesture(tester.getCenter(tiles.at(1)));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(tester.getCenter(tiles.at(6)));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Move to Trash'));
    await tester.pump(const Duration(milliseconds: 400));
    await snap(tester, 'trash_sheet');
  });

  testWidgets('send sheet', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    await tester.tap(find.byTooltip('More').at(3));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Send in Telegram'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Selam Tesfaye'));
    await tester.pump(const Duration(milliseconds: 200));
    await snap(tester, 'send_sheet');
  });

  testWidgets('send folder sheet', (tester) async {
    await prepareData(tester);
    final trip = _folder('Lalibela 2026', 0);
    folders = [trip, ...folders];
    await pumpApp(
      tester,
      location: '/files',
      seed: (db) async {
        await db.upsertFolder(
          FoldersCompanion.insert(
            id: trip.id,
            name: trip.name,
            messageId: 1,
            createdAt: trip.createdAt,
            modifiedAt: trip.modifiedAt,
          ),
        );
        for (var i = 1; i <= 3; i++) {
          await db.upsertFilePart(
            DriveFilesCompanion.insert(
              id: 'lalibela-$i',
              folderId: Value(trip.id),
              name: 'IMG_2026010$i.jpg',
              mimeType: 'image/jpeg',
              kind: FileKind.image,
              size: (4.2 * _mb).round(),
              createdAt: trip.createdAt,
              modifiedAt: trip.modifiedAt,
            ),
            FilePartsCompanion.insert(
              fileId: 'lalibela-$i',
              partIndex: 0,
              messageId: 1 + i,
              tdFileId: 1 + i,
              size: (4.2 * _mb).round(),
            ),
          );
        }
      },
    );
    await tester.longPress(find.text('Lalibela 2026'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Send in Telegram'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'send_folder_sheet');
  });

  testWidgets('create sheet', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    await tester.tap(find.text('New'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'create_sheet');
  });

  testWidgets('import chat picker', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    await tester.tap(find.text('New'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Save from a Telegram chat'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'import_chat_picker');
  });

  testWidgets('import documents', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/import/1?title=Saved%20Messages');
    for (final name in ['Lease 2023.pdf', 'Wedding photos.zip', 'Thesis draft v3.docx']) {
      await tester.tap(find.text(name));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'import_documents');
  });

  testWidgets('import photos', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/import/3?title=Family&photos=1');
    final tiles = find.byType(FileThumbnail);
    for (final index in [0, 2, 3]) {
      await tester.tap(tiles.at(index));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'import_photos');
  });

  testWidgets('transfers copying', (tester) async {
    await prepareData(tester);
    TransferItem copy(int index, TransferStatus status) => TransferItem(
      _transfer(
        'Scan $index.pdf',
        TransferKind.upload,
        status,
        2 * _mb,
        status == TransferStatus.completed ? 2 * _mb : 0,
      ).copyWith(
        origin: TransferOrigin.fromChat,
        sourceChatId: const Value(1),
        sourceMessageId: Value(500 + index),
      ),
    );
    transfers = TransfersState([
      for (var i = 0; i < 12; i++) copy(i, TransferStatus.completed),
      copy(12, TransferStatus.running),
      for (var i = 13; i < 80; i++) copy(i, TransferStatus.queued),
    ]);
    await pumpApp(tester, location: '/transfers');
    await snap(tester, 'transfers_copying');
  });

  testWidgets('share sheet', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/home',
      overrides: [
        shareIntakeProvider.overrideWith(_Intake.new),
        recentDestinationsProvider.overrideWith(_Recent.new),
      ],
    );
    await snap(tester, 'share_sheet');
  });

  testWidgets('a phone that can\'t scan or take a photo gets neither row', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files', captureSupport: CaptureSupport.none);
    await tester.tap(find.text('New'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Add to Files'), findsOneWidget);
    expect(find.text('Upload files'), findsOneWidget);
    expect(find.text('Scan a document'), findsNothing);
    expect(find.text('Take a photo'), findsNothing);
    // Put back and closed here, as snap does, for the framework's
    // end-of-test checks and the database's timers.
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('every row of the create sheet fits a 360 by 800 phone', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    // 360 x 800 dp, with a status bar and a gesture bar of 24 dp each.
    const ratio = 2.625;
    tester.view.physicalSize = const Size(360 * ratio, 800 * ratio);
    tester.view.padding = const FakeViewPadding(top: 24 * ratio, bottom: 24 * ratio);
    tester.view.viewPadding = const FakeViewPadding(top: 24 * ratio, bottom: 24 * ratio);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('New'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Scan a document').hitTestable(), findsOneWidget);
    expect(find.text('New folder').hitTestable(), findsOneWidget);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('transfers', (tester) async {
    await prepareData(tester);
    transfers = TransfersState([
      ...transfers.items,
      TransferItem(
        _transfer(
          'Lecture 1.mp4',
          TransferKind.download,
          TransferStatus.queued,
          (1.2 * _gb).round(),
          0,
          wifiOnly: true,
        ),
        wait: const WaitingForWifi(),
      ),
      TransferItem(
        _transfer(
          'Lecture 2.mp4',
          TransferKind.download,
          TransferStatus.queued,
          (1.2 * _gb).round(),
          300 * _mb,
          parts: 3,
          completedParts: 1,
          wifiOnly: true,
        ),
        wait: const WaitingForWifi(),
      ),
      TransferItem(
        _transfer(
          'Field recording.wav',
          TransferKind.upload,
          TransferStatus.queued,
          640 * _mb,
          210 * _mb,
        ),
        wait: const WaitingForNetwork(),
      ),
    ]);
    await pumpApp(tester, location: '/transfers');
    await snap(tester, 'transfers');
  });

  testWidgets('settings', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/settings');
    await snap(tester, 'settings');
  });

  /// Trips on its way, the tax return on the phone, and two receipts that
  /// didn't download.
  OfflineOverview keptOffline() {
    final tax = files.firstWhere((f) => f.name == 'Tax return 2025.pdf');
    return OfflineOverview(
      pins: [
        OfflinePinStatus(
          folder: _folder('Trips', 2),
          wanted: 40,
          bytes: (1.4 * _gb).round(),
          kept: 3,
          keptBytes: 310 * _mb,
          downloading: 37,
          waiting: 0,
          paused: 0,
          leftBytes: (1.1 * _gb).round(),
          failedTransferIds: const [],
        ),
        OfflinePinStatus(
          file: tax,
          wanted: 1,
          bytes: tax.size,
          kept: 1,
          keptBytes: tax.size,
          downloading: 0,
          waiting: 0,
          paused: 0,
          leftBytes: 0,
          failedTransferIds: const [],
        ),
        OfflinePinStatus(
          folder: _folder('Receipts', 14),
          wanted: 17,
          bytes: 48 * _mb,
          kept: 15,
          keptBytes: 41 * _mb,
          downloading: 0,
          waiting: 0,
          paused: 0,
          leftBytes: 0,
          failedTransferIds: const ['receipt-1', 'receipt-2'],
        ),
      ],
      keptFiles: 19,
      keptBytes: 351 * _mb + tax.size,
      downloading: 37,
      downloadingLeft: (1.1 * _gb).round(),
      speed: 2.4 * _mb,
      waitingTransferIds: const [],
      waitingLeft: 0,
      paused: 0,
      pausedLeft: 0,
      progress: 0.24,
    );
  }

  testWidgets('offline', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/offline',
      overrides: [
        offlineOverviewProvider.overrideWith((ref) => AsyncData(keptOffline())),
        offlinePinsProvider.overrideWith(
          (ref) => Stream.value({'Trips', 'Receipts', 'Tax return 2025.pdf'}),
        ),
        offlineCopiesProvider.overrideWith(
          (ref) => Stream.value({'Tax return 2025.pdf': '/offline/tax/Tax return 2025.pdf'}),
        ),
      ],
    );
    await snap(tester, 'offline');
  });

  testWidgets('offline empty', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/offline',
      overrides: [
        offlineOverviewProvider.overrideWith(
          (ref) => const AsyncData(
            OfflineOverview(
              pins: [],
              keptFiles: 0,
              keptBytes: 0,
              downloading: 0,
              downloadingLeft: 0,
              speed: 0,
              waitingTransferIds: [],
              waitingLeft: 0,
              paused: 0,
              pausedLeft: 0,
              progress: 0,
            ),
          ),
        ),
      ],
    );
    await snap(tester, 'offline_empty');
  });

  /// The sheet that keeps Trips offline, over Files, on [network].
  Future<void> keepOfflineSheet(WidgetTester tester, NetworkState network) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files', network: network);
    unawaited(
      showModalBottomSheet<bool>(
        context: tester.element(find.byType(Scaffold).first),
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => KeepOfflineSheet(
          folderName: 'Trips',
          count: 212,
          bytes: 5 * _gb,
          largest: (1.2 * _gb).round(),
          freeBytes: 23 * _gb,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('keep offline sheet', (tester) async {
    await keepOfflineSheet(tester, NetworkState.unknown);
    await snap(tester, 'keep_offline_sheet');
  });

  testWidgets('keep offline sheet on mobile data', (tester) async {
    await keepOfflineSheet(tester, const NetworkState(online: true, metered: true));
    await snap(tester, 'keep_offline_sheet_mobile_data');
  });

  testWidgets('settings mobile data', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/settings');
    await tester.drag(find.byType(ListView).first, const Offset(0, -760));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await snap(tester, 'settings_mobile_data');
  });

  const uploading = BackupState(
    phase: BackupPhase.uploading,
    total: 4847,
    done: 3120,
    current: 'IMG_20260925_181204.jpg',
  );

  testWidgets('photos', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/photos', backup: uploading);
    await snap(tester, 'photos');
  });

  testWidgets('backup settings', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/backup',
      backup: BackupState(
        phase: BackupPhase.upToDate,
        total: 4847,
        done: 4847,
        lastCompleted: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
      prefs: {
        'backup_enabled': true,
        'backup_excluded_folders': ['WhatsApp Images'],
        'photos_hidden_folders': ['Screenshots'],
      },
    );
    await snap(tester, 'backup_settings');
  });

  testWidgets('photos kept out', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/photos',
      backup: BackupState(
        phase: BackupPhase.upToDate,
        total: 4847,
        done: 4847,
        lastCompleted: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
      overrides: [
        hiddenBackupFoldersProvider.overrideWith(
          (ref) => Stream.value({'scr': 'Screenshots'}),
        ),
      ],
    );
    await snap(tester, 'photos_kept_out');
  });

  testWidgets('not backed up', (tester) async {
    await prepareData(tester);
    final scenes = await tester.runAsync(
      () => Future.wait([
        _scene(const Color(0xFF7FB2E5), const Color(0xFF5E8C4A), 160),
        _scene(const Color(0xFFF2B880), const Color(0xFF8C5A3C), 160),
        _scene(const Color(0xFF9AA7C7), const Color(0xFF3F5A6B), 160),
      ]),
    );
    final waiting = [
      for (var i = 0; i < 6; i++)
        PendingAsset(
          assetId: 'waiting-$i',
          takenAt: DateTime.now().subtract(Duration(hours: 5 + i * 26)),
          folder: i == 3 ? 'Screenshots' : 'Camera',
        ),
    ];
    // The first failed photo has gone from the phone, so it has no picture
    // or name; the rest are still there.
    final names = {
      'failed-2': 'VID_20260918_074410.mp4',
      'waiting-0': 'IMG_20260925_181204.jpg',
      'waiting-1': 'IMG_20260924_123517.jpg',
      'waiting-2': 'IMG_20260923_094058.jpg',
      'waiting-3': 'Screenshot_20260922_210731.png',
      'waiting-4': 'IMG_20260921_170322.jpg',
      'waiting-5': 'IMG_20260920_081945.jpg',
    };
    await pumpApp(
      tester,
      location: '/backup/not-backed-up',
      backup: BackupState(
        phase: BackupPhase.waitingForWifi,
        total: 4847,
        done: 4533,
        failed: 2,
        waiting: waiting,
      ),
      overrides: [
        failedBackupAssetsProvider.overrideWith(
          (ref) => Stream.value([
            BackupAssetRow(
              assetId: 'failed-1',
              state: BackupAssetState.failed,
              failures: 3,
              updatedAt: DateTime.now(),
              reason: 'The original file is no longer available.',
            ),
            BackupAssetRow(
              assetId: 'failed-2',
              state: BackupAssetState.failed,
              failures: 3,
              updatedAt: DateTime.now(),
              reason: 'Telegram took too long to answer.',
            ),
          ]),
        ),
        skippedBackupCountProvider.overrideWith((ref) => Stream.value(1)),
        assetThumbnailProvider('failed-1').overrideWith((ref) async => null),
        assetTitleProvider('failed-1').overrideWith((ref) async => null),
        for (final (index, MapEntry(key: id, value: name)) in names.entries.indexed) ...[
          assetThumbnailProvider(id).overrideWith((ref) async => scenes![index % 3]),
          assetTitleProvider(id).overrideWith((ref) async => name),
        ],
      ],
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold).first);
      for (final scene in scenes!) {
        await precacheImage(MemoryImage(scene), context);
      }
    });
    await tester.pump(const Duration(milliseconds: 400));
    await snap(tester, 'not_backed_up');
  });

  testWidgets('photos waiting', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/photos',
      backup: const BackupState(
        phase: BackupPhase.waitingForWifi,
        total: 4847,
        done: 4533,
        failed: 2,
      ),
    );
    await snap(tester, 'photos_waiting');
  });

  testWidgets('transfers with backup', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/transfers', backup: uploading);
    await snap(tester, 'transfers_backup');
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(shared)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: screen,
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('welcome', (tester) async {
    await pumpScreen(tester, const WelcomeScreen());
    await snap(tester, 'welcome');
  });

  testWidgets('phone', (tester) async {
    await pumpScreen(tester, const PhoneScreen());
    await snap(tester, 'phone');
  });

  testWidgets('photos before thumbnails arrive', (tester) async {
    await prepareData(tester);
    // Only Telegram's tiny inline previews: the state a fresh install sees
    // for a moment while thumbnails download.
    _thumbPaths.clear();
    await pumpApp(tester, location: '/photos', backup: uploading);
    await snap(tester, 'photos_loading');
  });
}
