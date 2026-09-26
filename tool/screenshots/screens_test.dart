// Renders the signed-in screens with sample data, for eyeballing the UI
// without a Telegram account. Not part of `flutter test`:
//
//   flutter test tool/screenshots/screens_test.dart --update-goldens
//
// Images land in tool/screenshots/out/.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:telegrive/app/app_shell.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/auth/presentation/phone_screen.dart';
import 'package:telegrive/features/auth/presentation/welcome_screen.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/backup/presentation/backup_screen.dart';
import 'package:telegrive/features/photos/presentation/photos_screen.dart';
import 'package:telegrive/features/search/presentation/search_screen.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/previews.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/files_screen.dart';
import 'package:telegrive/features/home/presentation/home_screen.dart';
import 'package:telegrive/features/settings/data/settings_providers.dart';
import 'package:telegrive/features/settings/presentation/settings_screen.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/features/transfers/presentation/transfers_screen.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
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


class _Queue extends TransferQueue {
  _Queue(this._state);

  final TransfersState _state;

  @override
  TransfersState build() => _state;
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
}) {
  final at = DateTime.now().subtract(Duration(hours: hoursAgo));
  return DriveFile(
    id: name,
    folderId: null,
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

DriveFolder _folder(String name, int daysAgo) {
  final at = DateTime.now().subtract(Duration(days: daysAgo));
  return DriveFolder(
    id: name,
    parentId: null,
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
}) => TransferRow(
  id: name,
  kind: kind,
  status: status,
  name: name,
  mimeType: mimeTypeFor(name),
  fileId: name,
  ownsSource: false,
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
  late TransfersState transfers;

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
          ),
      ];
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
    ]);
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    required String location,
    ThemeMode themeMode = ThemeMode.light,
    Map<String, Object> prefs = const {},
    BackupState backup = const BackupState(phase: BackupPhase.off),
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
                GoRoute(path: '/files', builder: (_, _) => const FilesScreen()),
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
        GoRoute(path: '/backup', builder: (_, _) => const BackupScreen()),
        GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
        GoRoute(path: '/transfers', builder: (_, _) => const TransfersScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          driveSessionProvider.overrideWith(_Session.new),
          driveSyncProvider.overrideWith(_Sync.new),
          transferQueueProvider.overrideWith(() => _Queue(transfers)),
          storageSummaryProvider.overrideWith((ref) => Stream.value(summary)),
          recentFilesProvider.overrideWith(
            (ref) => Stream.value(files.take(5).toList()),
          ),
          starredFilesProvider.overrideWith(
            (ref) => Stream.value(files.where((f) => f.starred).toList()),
          ),
          folderContentsProvider(null).overrideWith(
            (ref) =>
                Stream.value(FolderContents(folders: folders, files: files)),
          ),
          cacheSizeProvider.overrideWith((ref) async => 734 * _mb),
          backupControllerProvider.overrideWith(() => _Backup(backup)),
          mediaTimelineProvider.overrideWith((ref) => Stream.value(photos)),
          for (final entry in _thumbPaths.entries)
            thumbnailPathProvider(entry.key).overrideWith((ref) async => entry.value),
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

  testWidgets('search', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/home');
    await tester.tap(find.text('Search files and folders'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'search');
  });

  testWidgets('files list', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    await snap(tester, 'files_list');
  });

  testWidgets('files grid', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files', prefs: {'view_mode': 'grid'});
    await snap(tester, 'files_grid');
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

  testWidgets('create sheet', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    await tester.tap(find.text('New'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'create_sheet');
  });

  testWidgets('transfers', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/transfers');
    await snap(tester, 'transfers');
  });

  testWidgets('settings', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/settings');
    await snap(tester, 'settings');
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
      },
    );
    await snap(tester, 'backup_settings');
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
