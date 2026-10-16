// Renders the signed-in screens with sample data, for eyeballing the UI
// without a Telegram account. Not part of `flutter test`:
//
//   flutter test tool/screenshots/screens_test.dart --update-goldens
//
// Images land in tool/screenshots/out/.

import 'dart:async';
import 'dart:convert' show base64Encode, jsonEncode;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/app/app_shell.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/auth/presentation/phone_screen.dart';
import 'package:telegrive/features/auth/presentation/welcome_screen.dart';
import 'package:telegrive/features/backup/data/background_health.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/backup/data/free_up_space.dart';
import 'package:telegrive/features/backup/data/local_media.dart';
import 'package:telegrive/features/backup/data/phone_folders.dart';
import 'package:telegrive/features/backup/data/watched_folders.dart';
import 'package:telegrive/features/backup/presentation/backup_queue_screen.dart';
import 'package:telegrive/features/backup/presentation/backup_screen.dart';
import 'package:telegrive/features/backup/presentation/free_up_preview_screen.dart';
import 'package:telegrive/features/backup/presentation/not_backed_up_screen.dart';
import 'package:telegrive/features/capture/data/device_capture.dart';
import 'package:telegrive/features/checkup/data/drive_checkup.dart';
import 'package:telegrive/features/checkup/presentation/checkup_screen.dart';
import 'package:telegrive/features/photos/data/photos_visibility.dart';
import 'package:telegrive/features/photos/presentation/photos_screen.dart';
import 'package:telegrive/features/search/presentation/search_screen.dart';
import 'package:telegrive/features/photos/presentation/albums_screen.dart';
import 'package:telegrive/features/photos/presentation/media_grid.dart';
import 'package:telegrive/features/photos/presentation/media_grid_layout.dart';
import 'package:telegrive/features/player/data/play_positions.dart';
import 'package:telegrive/features/player/presentation/player_controls.dart';
import 'package:telegrive/features/send/data/telegram_chats.dart';
import 'package:telegrive/features/trash/presentation/trash_screen.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/widgets/file_visuals.dart';
import 'package:telegrive/core/widgets/selection_bar.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/previews.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/data/edit_outbox.dart';
import 'package:telegrive/features/drive/data/forward_filer.dart';
import 'package:telegrive/features/drive/data/forward_origin.dart';
import 'package:telegrive/features/drive/data/telegram_wait.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/drive/presentation/waiting_changes_screen.dart';
import 'package:telegrive/features/files/data/bulk_edits.dart';
import 'package:telegrive/features/files/presentation/file_actions.dart';
import 'package:telegrive/features/files/presentation/file_list_screen.dart';
import 'package:telegrive/features/files/presentation/file_location.dart';
import 'package:telegrive/features/files/presentation/files_screen.dart';
import 'package:telegrive/features/files/presentation/folder_picker.dart';
import 'package:telegrive/features/home/presentation/home_screen.dart';
import 'package:telegrive/features/import/data/chat_media.dart';
import 'package:telegrive/features/import/presentation/import_screen.dart';
import 'package:telegrive/features/network/data/connection_health.dart';
import 'package:telegrive/features/network/data/mobile_data.dart';
import 'package:telegrive/features/network/data/proxies.dart';
import 'package:telegrive/features/network/domain/proxy_link.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/features/offline/presentation/keep_offline_sheet.dart';
import 'package:telegrive/features/offline/presentation/offline_screen.dart';
import 'package:telegrive/features/picker/data/picker_access.dart';
import 'package:telegrive/features/settings/data/settings_providers.dart';
import 'package:telegrive/features/settings/presentation/settings_screen.dart';
import 'package:telegrive/features/share/data/recent_destinations.dart';
import 'package:telegrive/features/share/data/share_intake.dart';
import 'package:telegrive/features/space/data/phone_usage.dart';
import 'package:telegrive/features/space/presentation/space_screen.dart';
import 'package:telegrive/features/takeout/data/takeout_import.dart';
import 'package:telegrive/features/takeout/presentation/takeout_screen.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/features/transfers/domain/transfer_wait.dart';
import 'package:telegrive/features/transfers/presentation/mobile_data_prompt.dart';
import 'package:telegrive/features/transfers/presentation/transfers_screen.dart';
import 'package:telegrive/features/viewer/presentation/image_viewer_screen.dart';
import 'package:telegrive/features/viewer/presentation/vertical_swipe.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

const _gb = 1024 * 1024 * 1024;
const _mb = 1024 * 1024;

const _account = DriveSession(
  userId: 1,
  chatId: -1001234567890,
  channelTitle: 'Telegrive',
  firstName: 'Dawit',
  lastName: 'Beyene',
  phoneNumber: '251911000000',
  username: 'dawit',
  isPremium: false,
);

class _Session extends DriveSessionNotifier {
  @override
  DriveSession? build() => _account;
}

/// What the phone keeps of [_account]'s drive, read in full a moment ago,
/// so Home shows it from the index before Telegram answers.
Map<String, Object> _savedDrive() => {
  'drive_snapshot': jsonEncode(_account.toJson()),
  'drive_chat_${_account.userId}': _account.chatId,
  'full_sync_${_account.chatId}': DateTime.now().millisecondsSinceEpoch,
};

class _Sync extends DriveSync {
  @override
  SyncState build() => SyncState(lastSynced: DateTime.now());
}

/// An inactive-account timer of [_days], without asking Telegram.
class _AccountTtl extends AccountTtlNotifier {
  _AccountTtl(this._days);

  final int _days;

  @override
  Future<int> build() async => _days;
}

/// A check-up with something to say in most rows: a one-month auto-delete
/// timer on the channel, a split file missing a part, three backed-up
/// photos gone from the drive, four items in the trash about to go, no
/// two-step verification and a six-month inactivity timer.
class _Checkup extends DriveCheckup {
  @override
  Future<CheckupReport> build() async {
    final now = DateTime.now();
    return CheckupReport(
      at: now,
      findings: [
        const ChannelFinding.autoDelete(2592000, supergroupId: 7),
        IndexFinding(
          lastFull: now.subtract(const Duration(hours: 3)),
          error: null,
          running: false,
          scanned: 0,
        ),
        SplitFinding(
          total: 4,
          incomplete: [
            (
              file: DriveFile(
                id: 'holiday',
                folderId: null,
                name: 'Summer holiday 4K.mp4',
                mimeType: 'video/mp4',
                kind: FileKind.video,
                size: 5600 * _mb,
                createdAt: DateTime(2026, 7, 14),
                modifiedAt: DateTime(2026, 7, 14),
                partCount: 12,
                starred: false,
              ),
              missingParts: [7],
            ),
          ],
        ),
        BackupFinding(
          enabled: true,
          outcome: VerifyOutcome.gaps,
          verifiedCount: 3120,
          missingCount: 3,
          verifiedAt: now,
        ),
        const TrashFinding(count: 12, dueSoon: 4),
        const TwoStepFinding(false),
        const AccountTtlFinding(180),
      ],
    );
  }
}

class _Network extends NetworkStatus {
  _Network(this._state);

  final NetworkState _state;

  @override
  NetworkState build() => _state;
}

class _Health extends ConnectionHealthNotifier {
  _Health(this._health);

  final ConnectionHealth _health;

  @override
  ConnectionHealth build() => _health;
}

/// Saved proxies whose pings are already in.
class _Proxies extends ProxyController {
  _Proxies(this._entries);

  final List<ProxyEntry> _entries;

  @override
  Future<List<ProxyEntry>> build() async => _entries;

  @override
  Future<void> pingAll() async {}
}

/// A Google Photos import that stays where the screen should show it.
class _Takeout extends TakeoutImport {
  _Takeout(this._state);

  final TakeoutState _state;

  @override
  TakeoutState build() => _state;

  @override
  void schedule({bool immediate = false}) {}
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

/// The monthly mobile data count as [_state] has it, without asking TDLib.
class _MobileData extends MobileDataController {
  _MobileData(this._state);

  final MobileDataState _state;

  @override
  MobileDataState build() => _state;
}

/// No monthly limit, with this month's use measured.
final _noLimit = MobileDataState(
  metered: false,
  limit: null,
  renewDay: 1,
  periodStart: DateTime(2026, 10),
  periodEnd: DateTime(2026, 11),
  mobileBytes: (1.4 * _gb).round(),
  wifiBytes: (6.2 * _gb).round(),
  measured: true,
);

/// 380 MB of a 400 MB limit used, renewing on the 3rd.
final _nearLimit = MobileDataState(
  metered: false,
  limit: 400 * _mb,
  renewDay: 3,
  periodStart: DateTime(2026, 9, 3),
  periodEnd: DateTime(2026, 10, 3),
  mobileBytes: 380 * _mb,
  wifiBytes: (6.2 * _gb).round(),
  measured: true,
);

class _Storage extends DeviceStorage {
  @override
  Future<int?> freeBytes() async => 23 * _gb;

  @override
  Future<int?> totalBytes() async => 128 * _gb;
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

/// Download › Bank as Android's folder picker hands it over, holding 42
/// statements, 18.3 MB in all.
class _PhoneFolders extends PhoneFolders {
  static const _bank = 'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FBank';

  @override
  Future<PickedFolder?> pick() async => const PickedFolder(uri: _bank, name: 'Bank');

  @override
  Future<({List<PhoneDocument> files, bool truncated})> list(
    String uri, {
    required bool recursive,
  }) async => (
    files: [
      for (var i = 0; i < 42; i++)
        PhoneDocument(
          id: 'primary:Download/Bank/Statement-$i.pdf',
          name: 'Statement-${2023 + i ~/ 12}-${(i % 12 + 1).toString().padLeft(2, '0')}.pdf',
          mimeType: 'application/pdf',
          size: i == 41 ? 492940 : 456000,
          modifiedAt: DateTime(2023, 1 + i, 3),
        ),
    ],
    truncated: false,
  );
}

/// Two watched folders: Bank sending its new statements, and Recordings
/// checked this afternoon with everything in it up.
List<WatchedFolderView> _watchedFolders() {
  final now = DateTime.now();
  WatchedFolderRow row(String label, {required DateTime checkedAt}) => WatchedFolderRow(
    id: label,
    treeUri: 'content://com.android.externalstorage.documents/tree/primary%3A$label',
    label: label,
    destinationId: 'auto-$label',
    filter: label == 'Bank' ? WatchFilter.documents : WatchFilter.audio,
    subfolders: true,
    createdAt: DateTime(2026, 9, 1),
    checkedAt: checkedAt,
  );
  return [
    WatchedFolderView(
      row: row('Bank', checkedAt: now.subtract(const Duration(days: 2))),
      uploadedCount: 64,
      status: const RuleStatus(
        phase: RulePhase.uploading,
        total: 12,
        done: 2,
        current: 'Invoice-0925.pdf',
      ),
      destinationLabel: 'Auto upload › Bank',
    ),
    WatchedFolderView(
      row: row('Recordings', checkedAt: DateTime(now.year, now.month, now.day, 14, 14)),
      uploadedCount: 118,
      status: const RuleStatus(),
      destinationLabel: 'Auto upload › Recordings',
    ),
  ];
}

/// Files another app just shared in, waiting for the sheet.
class _Intake extends ShareIntake {
  @override
  List<SharedFile> build() => const [
    SharedFile(
      path: '/cache/shared/1/Receipt.png',
      name: 'Receipt.png',
      size: 2 * _mb + 310000,
    ),
    SharedFile(
      path: '/cache/shared/2/Lunch receipt.pdf',
      name: 'Lunch receipt.pdf',
      size: 184000,
    ),
  ];
}

/// A receipt that was shared in, and a video the phone had no room to take.
class _IntakeTooBig extends ShareIntake {
  @override
  List<SharedFile> build() => const [
    SharedFile(
      path: '/cache/shared/1/Receipt.png',
      name: 'Receipt.png',
      size: 2 * _mb + 310000,
    ),
    SharedFile(
      path: null,
      name: 'Wedding.mp4',
      size: 1288490189,
      tooBig: true,
      free: 180 * _mb,
    ),
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
  int? durationSeconds,
  bool adopted = false,
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
    durationSeconds: durationSeconds,
    adopted: adopted,
  );
}

/// Files that came into the channel without a manifest and wait under
/// Forwarded: two forwards and one sent from another Telegram app, each with
/// where it came from, as the origin provider answers.
final _forwarded = <(DriveFile, ForwardOrigin)>[
  (
    _file('photo_2231.jpg', 2 * _mb + 180000, 30, adopted: true),
    (forwarded: true, name: 'Selam Tesfaye'),
  ),
  (
    _file('Venue contract.pdf', 640000, 31, adopted: true),
    (forwarded: true, name: 'Family'),
  ),
  (
    _file('voice_12.ogg', 96000, 52, adopted: true, durationSeconds: 48),
    (forwarded: false, name: null),
  ),
];

/// Home's report of what the filer just moved.
class _Filer extends ForwardFiler {
  _Filer(this._summary);

  final FilingSummary? _summary;

  @override
  FilingSummary? build() => _summary;
}

/// Changes waiting to reach Telegram, as [_state] says, without an index.
class _Outbox extends EditOutbox {
  _Outbox(this._state);

  final OutboxState _state;

  @override
  OutboxState build() => _state;
}

/// [count] photos backed up from this phone and still on it, [each] bytes
/// apiece, three a day going back from [fromDaysAgo] days ago.
Freeable _backedUp(int count, int each, {int fromDaysAgo = 0}) => Freeable([
  for (var i = 0; i < count; i++)
    FreeableItem(
      assetId: 'asset-$i',
      file: _file(
        'IMG_$i.jpg',
        each,
        24 * (fromDaysAgo + i ~/ 3),
        takenDaysAgo: fromDaysAgo + i ~/ 3,
      ),
    ),
]);

DriveFolder _folder(
  String name,
  int daysAgo, {
  String? parentId,
  bool starred = false,
}) {
  final at = DateTime.now().subtract(Duration(days: daysAgo));
  return DriveFolder(
    id: name,
    parentId: parentId,
    name: name,
    createdAt: at,
    modifiedAt: at,
    starred: starred,
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
    // The Backup screen shows the watched folders as it does on Android.
    // ignore: invalid_use_of_visible_for_testing_member
    PhoneFolders.supported = true;
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
            // The clips know how long they run, the first one 1:24.
            durationSeconds: i % 7 == 3 ? 84 + (i - 3) * 11 : null,
          ),
        // A trip from over a year ago, so the timeline runs long enough for
        // the date scrubber and has a month that carries its year.
        for (var i = 0; i < 24; i++)
          _file(
            'IMG_2025${i.toString().padLeft(4, '0')}.jpg',
            (2 + i % 4) * _mb,
            400 * 24 + i,
            thumb: thumbs[(i * 2 + 1) % thumbs.length],
            takenDaysAgo: 400 + i,
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
                kind: FileKind.detect(
                  fileName: name,
                  mimeType: mimeTypeFor(name),
                ),
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
          durationSeconds: 4360,
        ),
        _file('Tax return 2025.pdf', 2 * _mb + 420000, 26, starred: true),
        _file('Simien trek.png', 11 * _mb, 30, thumb: forest),
        _file('Project backup.zip', 780 * _mb, 50),
        _file('Budget 2026.xlsx', 88000, 70),
        _file('Tizita — live.mp3', 9 * _mb, 90, durationSeconds: 251),
        _file('gramx-release.apk', 62 * _mb, 120),
      ];
    });
    // Opened on this phone, most recent first, each some time after it was
    // added.
    opens = [
      for (final (index, hoursAgo) in [
        (2, 20),
        (4, 44),
        (5, 60),
        (6, 84),
        (7, 110),
      ])
        (files[index], DateTime.now().subtract(Duration(hours: hoursAgo))),
    ];
    folders = [
      _folder('Documents', 3),
      _folder('Photos', 1),
      _folder('Work', 9, starred: true),
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
    MobileDataState? mobileData,
    CaptureSupport captureSupport = const CaptureSupport(
      scan: true,
      photo: true,
    ),
    bool notificationsEnabled = true,
    List<Override> overrides = const [],
    Future<void> Function(AppDatabase db)? seed,
    Freeable? freeable,
    bool forwarded = false,
    List<WatchedFolderView>? watched,
    bool connecting = false,
    BackgroundHealth? background,
  }) async {
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'backup_prompt_shown': true,
      if (connecting) ..._savedDrive(),
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
            GoRoute(
              path: 'queue',
              builder: (_, _) => const BackupQueueScreen(),
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
        GoRoute(
          path: '/free-up',
          builder: (_, _) => const FreeUpPreviewScreen(),
        ),
        GoRoute(path: '/trash', builder: (_, _) => const TrashScreen()),
        GoRoute(path: '/takeout', builder: (_, _) => const TakeoutScreen()),
        GoRoute(path: '/offline', builder: (_, _) => const OfflineScreen()),
        GoRoute(
          path: '/space',
          builder: (_, state) => SpaceScreen(
            focusPhone: state.uri.queryParameters['focus'] == 'phone',
          ),
        ),
        GoRoute(path: '/albums', builder: (_, _) => const AlbumsScreen()),
        GoRoute(path: '/transfers', builder: (_, _) => const TransfersScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(path: '/checkup', builder: (_, _) => const CheckupScreen()),
        GoRoute(
          path: '/changes',
          builder: (_, _) => const WaitingChangesScreen(),
        ),
        GoRoute(
          path: '/recent',
          builder: (_, _) => const FileListScreen.recent(),
        ),
        GoRoute(
          path: '/starred',
          builder: (_, _) => const FileListScreen.starred(),
        ),
        GoRoute(
          path: '/import/:chatId',
          builder: (_, state) => ImportScreen(
            chatId: int.parse(state.pathParameters['chatId']!),
            title: state.uri.queryParameters['title'] ?? '',
            photos: state.uri.queryParameters['photos'] == '1',
          ),
        ),
        GoRoute(
          path: '/viewer/:fileId',
          builder: (_, state) => ImageViewerScreen(
            fileId: state.pathParameters['fileId']!,
            source: state.uri.queryParameters['from'],
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
          // A phone with plenty of memory, so Save memory starts off.
          deviceProfileProvider.overrideWithValue(
            const DeviceProfile(
              lowRam: false,
              memoryClassMb: 256,
              totalRamBytes: 8 << 30,
            ),
          ),
          // While connecting, Home shows the drive saved when it last
          // opened, before its session is open.
          driveSessionProvider.overrideWith(
            connecting ? DriveSessionNotifier.new : _Session.new,
          ),
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
              for (final (file, at) in opens)
                RecentEntry(file, at: at, opened: true),
            ]),
          ),
          recentAddedProvider.overrideWith(
            (ref) => Stream.value(files.take(5).toList()),
          ),
          starredFilesProvider.overrideWith(
            (ref) => Stream.value(files.where((f) => f.starred).toList()),
          ),
          starredFoldersProvider.overrideWith(
            (ref) => Stream.value(folders.where((f) => f.starred).toList()),
          ),
          starredFolderSizesProvider.overrideWith(
            (ref) => Stream.value({
              'Work': const FolderSize('Work', 'Work', 12, 340 * _mb),
            }),
          ),
          folderContentsProvider(null).overrideWith(
            (ref) => Stream.value(
              FolderContents(
                folders: folders,
                files: [
                  ...files,
                  if (forwarded)
                    for (final (file, _) in _forwarded) file,
                ],
              ),
            ),
          ),
          for (final (file, origin) in _forwarded)
            forwardOriginProvider(file.id).overrideWith((ref) async => origin),
          folderInfoProvider('Work')
              .overrideWith((ref) => Stream.value(folders[2])),
          cacheSizeProvider.overrideWith((ref) async => 734 * _mb),
          // Settings draws its file picker switch as it does on a phone.
          pickerSupportedProvider.overrideWithValue(true),
          backgroundHealthProvider.overrideWith((ref) async => background),
          notificationsEnabledProvider.overrideWith(
            (ref) async => notificationsEnabled,
          ),
          backupControllerProvider.overrideWith(() => _Backup(backup)),
          // What Telegram's Devices list calls this phone, and the
          // inactive-account timer, for Settings and the check-up.
          currentSessionProvider.overrideWith(
            (ref) async => 'Telegrive 1.0.0 · Pixel 8 · Android 15',
          ),
          accountTtlProvider.overrideWith(() => _AccountTtl(180)),
          driveCheckupProvider.overrideWith(_Checkup.new),
          bulkEditsProvider.overrideWith(() => _Bulk(bulk)),
          telegramWaitProvider.overrideWith(() => _Wait(telegramWait)),
          networkStatusProvider.overrideWith(() => _Network(network)),
          mobileDataProvider.overrideWith(
            () => _MobileData(mobileData ?? _noLimit),
          ),
          captureSupportProvider.overrideWith((ref) async => captureSupport),
          mediaTimelineProvider.overrideWith((ref) => Stream.value(photos)),
          // Every sample photo is still on the phone and safely backed up.
          watchedFolderViewsProvider.overrideWith(
            (ref) => Stream.value(watched ?? _watchedFolders()),
          ),
          phoneFoldersProvider.overrideWithValue(_PhoneFolders()),
          freeableProvider.overrideWith(
            (ref) async =>
                freeable ??
                Freeable([
                  for (final photo in photos)
                    FreeableItem(assetId: 'a-${photo.id}', file: photo),
                ]),
          ),
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
                    trashedAt: DateTime.now().subtract(
                      const Duration(days: 12),
                    ),
                  ),
                ],
                files:
                    [
                          _file('Draft v1.docx', 900000, 40),
                          _file('Screen recording.mp4', 84 * _mb, 300),
                        ]
                        .map(
                          (f) => DriveFile(
                            id: f.id,
                            folderId: f.size > _mb ? null : 'Clients',
                            name: f.name,
                            mimeType: f.mimeType,
                            kind: f.kind,
                            size: f.size,
                            createdAt: f.createdAt,
                            modifiedAt: f.modifiedAt,
                            partCount: 1,
                            starred: false,
                            trashedAt: DateTime.now().subtract(
                              Duration(days: f.size > _mb ? 26 : 2),
                            ),
                            // The draft went to the trash when a newer
                            // upload replaced it.
                            replacedBy: f.size > _mb ? null : 'draft-v2',
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
          albumsProvider.overrideWith(
            (ref) => Stream.value([
              DriveAlbum(
                id: 'a1',
                name: 'Lalibela 2026',
                count: 48,
                coverFileId: photos[1].id,
              ),
              DriveAlbum(
                id: 'a2',
                name: 'Family',
                count: 212,
                coverFileId: photos[6].id,
              ),
              DriveAlbum(
                id: 'a3',
                name: 'Receipts',
                count: 17,
                coverFileId: photos[9].id,
              ),
            ]),
          ),
          for (final photo in photos)
            fileInfoProvider(photo.id)
                .overrideWith((ref) => Stream.value(photo)),
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
              TelegramChat(
                id: 7,
                title: 'Exam answers',
                isGroup: true,
                canSave: false,
              ),
              TelegramChat(id: 4, title: 'Abebe Kebede'),
            ],
          ),
          chatMediaProvider.overrideWith2(
            (source) => _ChatMedia(
              source,
              documents: chatDocuments,
              photos: chatPhotos,
            ),
          ),
          for (final entry in _thumbPaths.entries)
            thumbnailPathProvider(entry.key)
                .overrideWith((ref) async => entry.value),
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
        // Rows and small covers decode them at their own size.
        for (final side in const [40.0, 44.0, 52.0]) {
          final px = (side * MediaQuery.devicePixelRatioOf(context)).ceil();
          await precacheImage(FileThumbnail.telegramImage(path, px), context);
        }
      }
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// An action in the bar at the foot of a screen that is selecting.
  Finder barAction(String label) => find.descendant(
    of: find.byType(SelectionActionBar),
    matching: find.text(label),
  );

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
        offlineUsageProvider.overrideWith(
          (ref) => Stream.value((19, 353 * _mb)),
        ),
      ],
    );
    // Scrolled so the row sits above the New button.
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -400),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await snap(tester, 'home_offline');
  });

  testWidgets('home recent', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/home');
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -900),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await snap(tester, 'home_recent');
  });

  /// Home with two files partway through: a film at the root and a track
  /// in Music, so the header reads Continue playing.
  testWidgets('home continue', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/home',
      overrides: [
        continuePlayingProvider.overrideWith(
          (ref) => Stream.value([
            ContinueItem(
              file: _file(
                'Wedding highlights 4K.mp4',
                (5.6 * _gb).round(),
                20,
                durationSeconds: 5040,
              ),
              position: const Duration(minutes: 46, seconds: 12),
              length: const Duration(minutes: 84),
              place: 'Files',
            ),
            ContinueItem(
              file: _file(
                'Tizita — live.mp3',
                48 * _mb,
                30,
                folderId: 'Music',
                durationSeconds: 1120,
              ),
              position: const Duration(minutes: 16, seconds: 30),
              length: const Duration(minutes: 18, seconds: 40),
              place: 'Music',
            ),
          ]),
        ),
      ],
    );
    await snap(tester, 'home_continue');
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

  /// Home on a cold start, from the index, while Telegram starts behind it.
  testWidgets('home connecting', (tester) async {
    await prepareData(tester);
    transfers = TransfersState.empty;
    await pumpApp(
      tester,
      location: '/home',
      connecting: true,
      backup: const BackupState(phase: BackupPhase.waitingForDrive),
    );
    expect(find.text('Connecting to Telegram'), findsOneWidget);
    expect(find.text('DB'), findsOneWidget);
    await snap(tester, 'home_connecting');
  });

  /// Home with three changes made on the bus, waiting for a connection.
  testWidgets('home waiting changes', (tester) async {
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
      overrides: [
        editOutboxProvider.overrideWith(
          () => _Outbox(const OutboxState(waiting: 3)),
        ),
      ],
    );
    expect(find.text('3 changes waiting for the network'), findsOneWidget);
    await snap(tester, 'home_waiting_changes');
  });

  /// Waiting changes with a rename and move, a trash and an album add.
  testWidgets('waiting changes', (tester) async {
    await prepareData(tester);
    final lease = _file('Lease.pdf', 1800000, 2, folderId: 'Work');
    final draft = _file('Draft v1.docx', 900000, 40);
    final photo = photos[1];
    await pumpApp(
      tester,
      location: '/changes',
      overrides: [
        pendingEditsProvider.overrideWith(
          (ref) => Stream.value([
            PendingEditView(
              target: EditTarget.file,
              id: lease.id,
              name: lease.name,
              file: lease,
              description: 'Renamed from "Scan 12.pdf" · Moved to Work',
            ),
            PendingEditView(
              target: EditTarget.file,
              id: draft.id,
              name: draft.name,
              file: draft,
              description: 'Moved to Trash',
            ),
            PendingEditView(
              target: EditTarget.file,
              id: photo.id,
              name: photo.name,
              file: photo,
              description: 'Added to "Lalibela 2026"',
            ),
          ]),
        ),
        pendingItemIdsProvider.overrideWith(
          (ref) => Stream.value({lease.id, draft.id, photo.id}),
        ),
      ],
    );
    expect(find.text('Waiting changes'), findsOneWidget);
    await snap(tester, 'waiting_changes');
  });

  /// Home just after forwards named Wedding in their comment went there.
  testWidgets('home filed', (tester) async {
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
      overrides: [
        forwardFilerProvider.overrideWith(
          () => _Filer(
            const FilingSummary(
              count: 12,
              folderNames: ['Wedding'],
              folderId: 'Wedding',
            ),
          ),
        ),
      ],
    );
    expect(find.text('Filed 12 forwarded files into Wedding'), findsOneWidget);
    await snap(tester, 'home_filed');
  });

  testWidgets('home low space', (tester) async {
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
      // Two years of photos from before the last 30 days.
      freeable: _backedUp(2140, (4.45 * _mb).round(), fromDaysAgo: 40),
      overrides: [lowSpaceProvider.overrideWith((ref) async => true)],
    );
    expect(find.text('Free up'), findsOneWidget);
    await snap(tester, 'home_low_space');
  });

  /// Home with everything backed up, while Android isn't running the
  /// checks that back up with the app closed.
  testWidgets('home backup warning', (tester) async {
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
      background: const BackgroundHealth(watching: false),
    );
    expect(find.text('Backup can\'t run while the app is closed'), findsOneWidget);
    await snap(tester, 'home_backup_warning');
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
          _transfer(
            name,
            TransferKind.download,
            TransferStatus.queued,
            total,
            done,
            wifiOnly: true,
          ),
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

  testWidgets('home phone full', (tester) async {
    await prepareData(tester);
    transfers = TransfersState([
      for (final (name, total) in [
        ('Family trip.mp4', (1.2 * _gb).round()),
        ('Course notes.pdf', 60 * _mb),
      ])
        TransferItem(
          _transfer(
            name,
            TransferKind.download,
            TransferStatus.queued,
            total,
            0,
          ),
          wait: WaitingForRoom((1.2 * _gb).round() + 64 * _mb, 180 * _mb),
        ),
    ]);
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
    await snap(tester, 'home_phone_full');
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
    DriveFile invoice(String name, String folderId, int size, DateTime at) =>
        DriveFile(
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
    await addFile(
      invoice(
        'Invoice March.pdf',
        'Invoices',
        1200000,
        DateTime(2024, 3, 14, 10),
      ),
    );
    await addFile(
      invoice(
        'Invoice March hotel.pdf',
        'Work',
        380000,
        DateTime(2024, 3, 28, 16),
      ),
    );
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
    folders = [];
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
    GoRouter.of(tester.element(find.byType(FilesScreen)))
        .push('/search?folder=Work');
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

  /// The root with three files that came in without a manifest waiting
  /// under Forwarded.
  testWidgets('files list', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files', forwarded: true);
    await snap(tester, 'files_list');
  });

  testWidgets('files list dark', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files', forwarded: true, themeMode: ThemeMode.dark);
    await snap(tester, 'files_list_dark');
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
      forwarded: true,
      overrides: [
        offlinePinsProvider.overrideWith((ref) => Stream.value({'Work'})),
        offlineCopiesProvider.overrideWith(
          (ref) => Stream.value({
            'Budget 2026.xlsx': '/offline/budget/Budget 2026.xlsx',
          }),
        ),
      ],
    );
    await snap(tester, 'files_grid');
  });

  testWidgets('show in folder', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    final highlight = Uri.encodeQueryComponent('Tax return 2025.pdf');
    GoRouter.of(tester.element(find.byType(FilesScreen)))
        .go('/files?highlight=$highlight');
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

  testWidgets('starred', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/starred');
    await snap(tester, 'starred');
  });

  testWidgets('starred selection', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/starred');
    await tester.tap(find.byTooltip('Select'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Lalibela sunrise.jpg'));
    await tester.pump(const Duration(milliseconds: 300));
    await snap(tester, 'starred_selection');
  });

  testWidgets('save sheet', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    await tester.longPress(find.text('Lalibela sunrise.jpg'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Simien trek.png'));
    await tester.tap(find.text('Budget 2026.xlsx'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(barAction('Download'));
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
    await tester.tap(barAction('Download'));
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
      _transfer(
        name,
        TransferKind.download,
        status,
        total,
        done,
        wifiOnly: waitsForWifi,
      ).copyWith(
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
      for (final folder in [
        ...folders,
        _folder('Clients', 9, parentId: 'Work'),
      ])
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

  /// The third photo on the timeline as Details finds it: in the phone's
  /// Camera folder under Photo backup, and in two albums. pumpApp already
  /// records it as backed up from this phone.
  Future<void> seedViewer(AppDatabase db) async {
    final photo = photos[2];
    var message = 1;
    for (final (id, name, parentId) in [
      ('backup', 'Photo backup', null),
      (photo.folderId!, 'Camera', 'backup'),
    ]) {
      await db.upsertFolder(
        FoldersCompanion.insert(
          id: id,
          parentId: Value(parentId),
          name: name,
          messageId: message++,
          createdAt: DateTime(2026),
          modifiedAt: DateTime(2026),
        ),
      );
    }
    for (final (id, name) in [('a1', 'Lalibela 2026'), ('a2', 'Family')]) {
      await db.upsertAlbum(
        AlbumsCompanion.insert(
          id: id,
          name: name,
          messageId: message++,
          createdAt: DateTime(2026),
          modifiedAt: DateTime(2026),
        ),
      );
    }
    await db.setFileAlbums(photo.id, ['a1', 'a2']);
  }

  /// The photo has come down from Telegram, so the viewer shows it whole.
  Override fetched(DriveFile photo) =>
      filePreviewProvider(photo.id).overrideWith(
        (ref) => Stream.value(
          PreviewProgress(
            received: photo.size,
            total: photo.size,
            path: _thumbPaths[photo.thumbnailFileId],
          ),
        ),
      );

  /// Opens the third photo from the Photos tab, as a tap on its tile does.
  Future<void> openViewer(WidgetTester tester) async {
    await pumpApp(
      tester,
      location: '/photos',
      seed: seedViewer,
      overrides: [fetched(photos[2])],
    );
    GoRouter.of(tester.element(find.byType(PhotosScreen)))
        .push('/viewer/${Uri.encodeComponent(photos[2].id)}?from=photos');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('viewer', (tester) async {
    await prepareData(tester);
    await openViewer(tester);
    await snap(tester, 'viewer');
  });

  testWidgets('viewer details', (tester) async {
    await prepareData(tester);
    await openViewer(tester);
    await tester.drag(find.byType(VerticalSwipe), const Offset(0, -120));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'viewer_details');
  });

  /// The third photo on the timeline is still a small copy: the viewer
  /// says so, and so does its menu.
  testWidgets('file sheet small copy', (tester) async {
    await prepareData(tester);
    final photo = photos[2];
    photos[2] = DriveFile(
      id: photo.id,
      folderId: photo.folderId,
      name: 'IMG_2041.HEIC',
      mimeType: 'image/jpeg',
      kind: photo.kind,
      size: 312 * 1024,
      createdAt: photo.createdAt,
      modifiedAt: photo.modifiedAt,
      partCount: 1,
      starred: false,
      minithumbnail: photo.minithumbnail,
      thumbnailFileId: photo.thumbnailFileId,
      takenAt: photo.takenAt,
      originalSize: (6.1 * _mb).round(),
    );
    await openViewer(tester);
    await tester.tap(find.byTooltip('More'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'file_sheet_small_copy');
  });

  /// The first clip on the timeline, waiting on its poster: nothing comes
  /// down until Play is tapped.
  testWidgets('viewer video', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/photos', seed: seedViewer);
    GoRouter.of(tester.element(find.byType(PhotosScreen)))
        .push('/viewer/${Uri.encodeComponent(photos[3].id)}?from=photos');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'viewer_video');
  });

  /// The player's chrome on a lecture, drawn without a player behind it:
  /// 30 second skips for a long file and the speed button at 1.5×.
  testWidgets('player controls', (tester) async {
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
          theme: AppTheme.dark(),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: PlayerControls(
              file: _file(
                'Lecture 7 — Thermodynamics.mp4',
                1200 * _mb,
                30,
                durationSeconds: 4360,
              ),
              value: const VideoPlayerValue(
                duration: Duration(hours: 1, minutes: 12, seconds: 40),
                position: Duration(minutes: 42, seconds: 10),
                isInitialized: true,
                isPlaying: true,
              ),
              onPlay: () {},
              onSkip: (_) {},
              onSeek: (_) {},
              step: const Duration(seconds: 30),
              speed: 1.5,
              onSpeed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await snap(tester, 'player_controls');
  });

  /// The same chrome on an audiobook chapter playing through its folder:
  /// Previous and Next around the skips, and the line saying it picked up
  /// at 42:10 with Start over beside it.
  testWidgets('player audio queue', (tester) async {
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
          theme: AppTheme.dark(),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: PlayerControls(
              file: _file(
                'Chapter 3 — The long road.mp3',
                48 * _mb,
                30,
                folderId: 'Audiobook',
                durationSeconds: 4360,
              ),
              value: const VideoPlayerValue(
                duration: Duration(hours: 1, minutes: 12, seconds: 40),
                position: Duration(minutes: 42, seconds: 10),
                isInitialized: true,
                isPlaying: true,
              ),
              onPlay: () {},
              onSkip: (_) {},
              onSeek: (_) {},
              step: const Duration(seconds: 30),
              speed: 1,
              onSpeed: () {},
              resumedFrom: const Duration(minutes: 42, seconds: 10),
              onStartOver: () {},
              hasQueue: true,
              onPrevious: () {},
              onNext: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await snap(tester, 'player_audio_queue');
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
          ? {
              'id': (call.arguments as Map)['id'],
              'type': 1,
              'width': 4000,
              'height': 3000,
            }
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        library,
        null,
      ),
    );
    final tiles = find.byType(FileThumbnail);
    final gesture = await tester.startGesture(tester.getCenter(tiles.at(1)));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(tester.getCenter(tiles.at(6)));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(barAction('Trash'));
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
    await tester.tap(barAction('Send'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'send_folder_sheet');
  });

  testWidgets('create sheet', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    await tester.tap(find.byTooltip('New'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'create_sheet');
  });

  testWidgets('import chat picker', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    await tester.tap(find.byTooltip('New'));
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
    for (final name in [
      'Lease 2023.pdf',
      'Wedding photos.zip',
      'Thesis draft v3.docx',
    ]) {
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

  testWidgets('share sheet too big', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/home',
      overrides: [
        shareIntakeProvider.overrideWith(_IntakeTooBig.new),
        recentDestinationsProvider.overrideWith(_Recent.new),
      ],
    );
    await snap(tester, 'share_sheet_too_big');
  });

  testWidgets('a phone that can\'t scan or take a photo gets neither row', (
    tester,
  ) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/files',
      captureSupport: CaptureSupport.none,
    );
    await tester.tap(find.byTooltip('New'));
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

  testWidgets('every row of the create sheet fits a 360 by 800 phone', (
    tester,
  ) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    // 360 x 800 dp, with a status bar and a gesture bar of 24 dp each.
    const ratio = 2.625;
    tester.view.physicalSize = const Size(360 * ratio, 800 * ratio);
    tester.view.padding = const FakeViewPadding(
      top: 24 * ratio,
      bottom: 24 * ratio,
    );
    tester.view.viewPadding = const FakeViewPadding(
      top: 24 * ratio,
      bottom: 24 * ratio,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('New'));
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
      // Slow enough that what is moving takes a while, so the header says
      // when it should be done.
      for (final item in transfers.items)
        item.status == TransferStatus.running
            ? TransferItem(item.row, bytesPerSecond: item.bytesPerSecond / 3)
            : item,
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
      TransferItem(
        _transfer(
          'Conference talk.mkv',
          TransferKind.upload,
          TransferStatus.queued,
          (5.8 * _gb).round(),
          8 * 512 * _mb,
          parts: 12,
          completedParts: 8,
        ),
      ),
      TransferItem(
        _transfer(
          'Family trip.mp4',
          TransferKind.upload,
          TransferStatus.queued,
          (1.2 * _gb).round(),
          0,
        ),
        wait: WaitingForRoom((1.2 * _gb).round() + 64 * _mb, 180 * _mb),
      ),
    ]);
    await pumpApp(tester, location: '/transfers');
    // A taller phone, so the rows waiting for room and continuing after a
    // restart show below the others.
    tester.view.physicalSize = const Size(1080, 2700);
    await tester.pump(const Duration(milliseconds: 100));
    await snap(tester, 'transfers');
  });

  testWidgets('settings', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/settings',
      mobileData: _nearLimit,
      prefs: {'checkup_last_run': DateTime(2026, 9, 25, 19, 32).millisecondsSinceEpoch},
    );
    await snap(tester, 'settings');
  });

  testWidgets('checkup', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/checkup');
    await snap(tester, 'checkup');
  });

  /// A proxy in use that answered quickly, and a SOCKS5 one that didn't.
  Override savedProxies() => proxiesProvider.overrideWith(
    () => _Proxies([
      ProxyEntry(
        id: 2,
        server: '185.76.9.14',
        port: 443,
        kind: ProxyKind.mtproto,
        enabled: true,
        lastUsed: DateTime.now(),
        latency: const LatencyMeasured(Duration(milliseconds: 240)),
      ),
      const ProxyEntry(
        id: 1,
        server: 'socks.example.org',
        port: 1080,
        kind: ProxyKind.socks5,
        enabled: false,
        lastUsed: null,
        latency: LatencyFailed(),
      ),
    ]),
  );

  Future<void> scrollToProxy(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Proxy'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('settings connection', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/settings', overrides: [savedProxies()]);
    await scrollToProxy(tester);
    // On to where Connection sits between Security and This phone.
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await snap(tester, 'settings_connection');
  });

  testWidgets('settings about', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/settings');
    await tester.scrollUntilVisible(
      find.text('Sign out'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await snap(tester, 'settings_about');
  });

  testWidgets('proxy sheet', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/settings',
      overrides: [
        connectionStateProvider.overrideWith(
          (ref) => Stream.value(const td.ConnectionStateReady()),
        ),
        savedProxies(),
      ],
    );
    await scrollToProxy(tester);
    await tester.tap(find.text('Proxy'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'proxy_sheet');
  });

  testWidgets('settings notifications off', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/settings', notificationsEnabled: false);
    await snap(tester, 'settings_notifications_off');
  });

  testWidgets('data limit sheet', (tester) async {
    await prepareData(tester);
    // One of the limits the sheet offers, so it shows as chosen.
    await pumpApp(
      tester,
      location: '/settings',
      mobileData: MobileDataState(
        metered: false,
        limit: 500 * _mb,
        renewDay: 3,
        periodStart: DateTime(2026, 9, 3),
        periodEnd: DateTime(2026, 10, 3),
        mobileBytes: 380 * _mb,
        measured: true,
      ),
    );
    await tester.tap(find.text('Monthly limit'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'data_limit_sheet');
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
          needRoom: 0,
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
          needRoom: 0,
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
          needRoom: 0,
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
      needRoom: 0,
      needRoomLeft: 0,
      paused: 0,
      pausedLeft: 0,
      progress: 0.24,
    );
  }

  /// Space with the sample files placed in folders, nothing transferring,
  /// and what the phone holds measured.
  List<Override> spaceData() {
    DriveFile placed(DriveFile file, String? folderId) => DriveFile(
      id: file.id,
      folderId: folderId,
      name: file.name,
      mimeType: file.mimeType,
      kind: file.kind,
      size: file.size,
      createdAt: file.createdAt,
      modifiedAt: file.modifiedAt,
      partCount: file.partCount,
      starred: file.starred,
      minithumbnail: file.minithumbnail,
      thumbnailFileId: file.thumbnailFileId,
    );
    const homes = {
      'Wedding highlights 4K.mp4': 'Trips',
      'Project backup.zip': 'Work',
      'gramx-release.apk': 'Work',
      'Budget 2026.xlsx': 'Work',
      'Simien trek.png': 'Photos',
      'Lalibela sunrise.jpg': 'Photos',
      'Tax return 2025.pdf': 'Documents',
    };
    final largest = [for (final file in files) placed(file, homes[file.name])]
      ..sort((a, b) => b.size.compareTo(a.size));
    FolderSize sum(String? id, String name) {
      final inside = largest.where(
        (f) => id == 'Videos' ? f.folderId == 'Trips' : f.folderId == id,
      );
      return FolderSize(
        id,
        name,
        inside.length,
        inside.fold(0, (s, f) => s + f.size),
      );
    }

    return [
      largestFilesProvider.overrideWith((ref) => Stream.value(largest)),
      folderIndexProvider.overrideWith(
        (ref) => Stream.value({
          for (final folder in [
            ...folders,
            _folder('Videos', 40),
            _folder('Trips', 20, parentId: 'Videos'),
          ])
            folder.id: folder,
        }),
      ),
      folderSizesProvider.overrideWith(
        (ref) => Stream.value([
          sum('Videos', 'Videos'),
          sum('Work', 'Work'),
          sum('Photos', 'Photos'),
          sum('Documents', 'Documents'),
          sum(null, ''),
        ]),
      ),
      trashTotalsProvider.overrideWith(
        (ref) => Stream.value((3, (85.2 * _mb).round())),
      ),
      phoneUsageProvider.overrideWith(
        (ref) async => PhoneUsage(
          openedFiles: 420 * _mb,
          thumbnails: 310 * _mb,
          leftovers: 95 * _mb,
          offline: (1.1 * _gb).round(),
          index: 38 * _mb,
          telegramDatabase: 120 * _mb,
          budget: _gb,
        ),
      ),
      offlineUsageProvider.overrideWith(
        (ref) => Stream.value((19, (1.1 * _gb).round())),
      ),
    ];
  }

  testWidgets('space', (tester) async {
    await prepareData(tester);
    transfers = TransfersState.empty;
    await pumpApp(
      tester,
      location: '/space',
      overrides: spaceData(),
      freeable: _backedUp(1240, (6.77 * _mb).round()),
    );
    await snap(tester, 'space');
  });

  testWidgets('space on this phone', (tester) async {
    await prepareData(tester);
    transfers = TransfersState.empty;
    await pumpApp(
      tester,
      location: '/space?focus=phone',
      overrides: spaceData(),
      freeable: _backedUp(1240, (6.77 * _mb).round()),
    );
    expect(find.text('Telegram\'s records'), findsOneWidget);
    await snap(tester, 'space_phone');
  });

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
          (ref) => Stream.value({
            'Tax return 2025.pdf': '/offline/tax/Tax return 2025.pdf',
          }),
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
              needRoom: 0,
              needRoomLeft: 0,
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
  Future<void> keepOfflineSheet(
    WidgetTester tester,
    NetworkState network,
  ) async {
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

  testWidgets('clash sheet', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/files');
    // Budget 2026.xlsx is being uploaded into Work, which has one already,
    // as the first of three clashes in the batch.
    unawaited(
      showClashSheet(
        tester.element(find.byType(Scaffold).first),
        name: 'Budget 2026.xlsx',
        existing: files[5],
        newSize: 91000,
        folderName: 'Work',
        keepBothName: 'Budget 2026 (2).xlsx',
        clashesLeft: 3,
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'clash_sheet');
  });

  testWidgets('keep offline sheet on mobile data', (tester) async {
    await keepOfflineSheet(
      tester,
      const NetworkState(online: true, metered: true),
    );
    await snap(tester, 'keep_offline_sheet_mobile_data');
  });

  testWidgets('settings mobile data', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/settings');
    await tester.drag(find.byType(ListView).first, const Offset(0, -560));
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

  testWidgets('photos scrub', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/photos', backup: uploading);
    final grid = tester.getRect(find.byType(MediaGrid));
    // The handle shows once the grid has scrolled.
    await tester.dragFrom(grid.center, const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 100));
    final gesture = await tester.startGesture(
      Offset(grid.right - 12, grid.top + 160),
    );
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveTo(
      Offset(grid.right - 12, grid.top + grid.height * 0.85),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await snap(tester, 'photos_scrub');
    await gesture.up();
  });

  testWidgets('photos month select', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/photos', backup: uploading);
    final second = monthSections(photos)[1];
    // Long-press a photo of the second month, then take the rest of it.
    await tester.longPress(find.byType(FileThumbnail).at(second.start));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(InkWell, second.title));
    await tester.pump(const Duration(milliseconds: 300));
    await snap(tester, 'photos_month_select');
  });

  testWidgets('photos month', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/photos', backup: uploading);
    // A month's title selects the whole month, even with nothing selected.
    await tester.tap(find.widgetWithText(InkWell, 'This month'));
    await tester.pump(const Duration(milliseconds: 300));
    await snap(tester, 'photos_month');
  });

  /// Backup running on its own: it last ran overnight, the checks run, and
  /// battery saver may still stop it.
  Future<void> pumpBackupSettings(WidgetTester tester) async {
    final today = DateTime.now();
    final ran = DateTime(today.year, today.month, today.day, 2, 14);
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
        'backup_mobile_data': 'photos',
        'backup_excluded_folders': ['WhatsApp Images'],
        'photos_hidden_folders': ['Screenshots'],
        'backup_unattended': true,
        'backup_bg_last_run': ran.millisecondsSinceEpoch,
        'backup_bg_last_uploaded': 40,
      },
      mobileData: _nearLimit,
      background: BackgroundHealth(
        watching: true,
        batteryOk: false,
        lastChecked: DateTime(today.year, today.month, today.day, 7, 40),
        lastRun: ran,
        lastUploaded: 40,
      ),
    );
  }

  testWidgets('backup settings', (tester) async {
    await prepareData(tester);
    await pumpBackupSettings(tester);
    await snap(tester, 'backup_settings');
  });

  testWidgets('backup while the app is closed', (tester) async {
    await prepareData(tester);
    await pumpBackupSettings(tester);
    // Down to the group about the app being closed, its heading at the top.
    final heading = find.text('While the app is closed');
    await tester.scrollUntilVisible(
      heading,
      300,
      scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(heading);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Last ran 2:14\u202fAM · 40 items'), findsOneWidget);
    expect(find.text('Battery saver may stop backup'), findsOneWidget);
    await snap(tester, 'backup_while_closed');
  });

  testWidgets('backup folders', (tester) async {
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
      prefs: {'backup_enabled': true, 'backup_mobile_data': 'photos'},
    );
    // Down to Mobile data and the other folders on the phone.
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 300));
    await snap(tester, 'backup_folders');
  });

  testWidgets('google photos steps', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/takeout',
      overrides: [takeoutImportProvider.overrideWith(() => _Takeout(const TakeoutState()))],
    );
    await snap(tester, 'google_photos_steps');
  });

  testWidgets('google photos importing', (tester) async {
    await prepareData(tester);
    final added = DateTime(2026, 10, 6, 21);
    await pumpApp(
      tester,
      location: '/takeout',
      seed: (db) async {
        for (final (index, number) in [1, 2, 3, 5].indexed) {
          await db.saveTakeoutPart(
            TakeoutPartsCompanion.insert(
              id: 'part-$number',
              uri: 'content://downloads/$number',
              name: 'takeout-20261005T101010Z-00$number.zip',
              size: number == 5 ? 1340 * _mb : 2 << 30,
              addedAt: added.add(Duration(seconds: index)),
              readAt: Value(added),
            ),
          );
        }
      },
      overrides: [
        takeoutImportProvider.overrideWith(
          () => _Takeout(
            const TakeoutState(
              phase: TakeoutPhase.importing,
              running: true,
              current: 'PXL_20230612_183344512.jpg',
              working: true,
              speed: 2.4 * 1024 * 1024,
              timeLeft: Duration(minutes: 38),
              uploadedBytes: 2150 << 20,
              flights: [
                TakeoutFlight(
                  key: 'a',
                  name: 'PXL_20230612_183344512.jpg',
                  size: 4 << 20,
                  step: TakeoutStep.uploading,
                  transferId: 'none',
                ),
                TakeoutFlight(
                  key: 'b',
                  name: 'VID_20230613_090102.mp4',
                  size: 182 << 20,
                  step: TakeoutStep.extracting,
                  part: 'part 2',
                ),
              ],
              progress: TakeoutProgress(
                total: 12430,
                photos: 11220,
                videos: 1210,
                bytes: 7 << 30,
                albums: 41,
                sent: 3204,
                inDrive: 3120,
                leftBytes: 3 << 30,
                sentBytes: 2100 << 20,
                partsLeft: {'part-2': 812, 'part-3': 2340, 'part-5': 1406},
                partsTotal: {'part-1': 2100, 'part-2': 2210, 'part-3': 2340, 'part-5': 1406},
              ),
            ),
          ),
        ),
      ],
    );
    await snap(tester, 'google_photos_importing');
  });

  testWidgets('google photos done', (tester) async {
    await prepareData(tester);
    final added = DateTime(2026, 10, 9, 1);
    await pumpApp(
      tester,
      location: '/takeout',
      seed: (db) async {
        for (var number = 1; number <= 15; number++) {
          await db.saveTakeoutPart(
            TakeoutPartsCompanion.insert(
              id: 'part-$number',
              uri: 'content://downloads/$number',
              name: 'takeout-20261008T200000Z-${'$number'.padLeft(3, '0')}.zip',
              size: number == 15 ? 1900 * _mb : 2 << 30,
              addedAt: added.add(Duration(seconds: number)),
              readAt: Value(added),
              deletedAt: Value(added.add(const Duration(hours: 3))),
            ),
          );
        }
      },
      overrides: [
        takeoutImportProvider.overrideWith(
          () => _Takeout(
            const TakeoutState(
              uploadedBytes: 9100 << 20,
              progress: TakeoutProgress(total: 3349, photos: 2900, videos: 449, sent: 1232, inDrive: 2117, sentBytes: 9100 << 20),
            ),
          ),
        ),
      ],
    );
    await snap(tester, 'google_photos_done');
  });

  testWidgets('watched folder add', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/backup', watched: const []);
    await tester.tap(find.text('Add a folder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await snap(tester, 'watched_folder_add');
  });

  testWidgets('free up sheet', (tester) async {
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
      prefs: {'backup_enabled': true},
      freeable: _backedUp(2140, (4.45 * _mb).round(), fromDaysAgo: 40),
    );
    await tester.tap(find.text('Free up space on this phone'));
    await tester.pump(const Duration(milliseconds: 600));
    await snap(tester, 'free_up_sheet');
  });

  testWidgets('free up preview', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/free-up');
    await snap(tester, 'free_up_preview');
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
        for (final (index, MapEntry(key: id, value: name))
            in names.entries.indexed) ...[
          assetThumbnailProvider(id)
              .overrideWith((ref) async => scenes![index % 3]),
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

  /// Backup sending the newest of a few hundred photos: two going up, the
  /// rest in line, and the ones that went up since the app opened.
  Future<void> pumpQueue(WidgetTester tester) async {
    await prepareData(tester);
    final scenes = await tester.runAsync(
      () => Future.wait([
        _scene(const Color(0xFF7FB2E5), const Color(0xFF5E8C4A), 160),
        _scene(const Color(0xFFF2B880), const Color(0xFF8C5A3C), 160),
        _scene(const Color(0xFF9AA7C7), const Color(0xFF3F5A6B), 160),
      ]),
    );
    final names = [
      'IMG_20260925_181204.jpg',
      'VID_20260925_174412.mp4',
      'IMG_20260925_093058.jpg',
      'IMG_20260924_210731.jpg',
      'Screenshot_20260924_170322.png',
      'IMG_20260924_081945.jpg',
      'IMG_20260923_194410.jpg',
      'IMG_20260923_123517.jpg',
      'IMG_20260922_181150.jpg',
    ];
    final waiting = [
      for (var i = 0; i < names.length; i++)
        PendingAsset(
          assetId: 'queue-$i',
          takenAt: DateTime.now().subtract(Duration(hours: 2 + i * 9)),
          folder: names[i].startsWith('Screenshot') ? 'Screenshots' : 'Camera',
        ),
    ];
    TransferItem going(int i, {required int size, required int done, double speed = 0}) =>
        TransferItem(
          TransferRow(
            id: 'up-$i',
            kind: TransferKind.upload,
            status: TransferStatus.running,
            name: names[i],
            mimeType: mimeTypeFor(names[i]),
            fileId: 'file-up-$i',
            ownsSource: false,
            wifiOnly: false,
            totalBytes: size,
            doneBytes: done,
            partCount: 1,
            completedParts: 0,
            createdAt: DateTime.now(),
            origin: TransferOrigin.backup,
            assetId: 'queue-$i',
          ),
          bytesPerSecond: speed,
        );
    await pumpApp(
      tester,
      location: '/backup/queue',
      backup: BackupState(
        phase: BackupPhase.uploading,
        total: 4847,
        done: 4538,
        waiting: waiting,
        recent: [
          for (final photo in photos.take(12)) RecentBackup(assetId: photo.id, fileId: photo.id),
        ],
      ),
      overrides: [
        backupUploadsProvider.overrideWith(
          (ref) => [
            going(0, size: (4.2 * _mb).round(), done: (2.7 * _mb).round(), speed: 1.8 * _mb),
            going(1, size: 86 * _mb, done: (11.5 * _mb).round(), speed: 1.4 * _mb),
          ],
        ),
        recentBackupsProvider.overrideWith((ref) => Stream.value(photos.take(12).toList())),
        for (var i = 0; i < names.length; i++) ...[
          assetThumbnailProvider('queue-$i').overrideWith((ref) async => scenes![i % 3]),
          assetTitleProvider('queue-$i').overrideWith((ref) async => names[i]),
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
  }

  testWidgets('backup queue', (tester) async {
    await pumpQueue(tester);
    await snap(tester, 'backup_queue');
  });

  testWidgets('backup queue backed up', (tester) async {
    await pumpQueue(tester);
    await tester.tap(find.text('Backed up · 12'));
    await tester.pumpAndSettle();
    await snap(tester, 'backup_queue_backed_up');
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

  /// Small copies of the photos taken on mobile data are in; their
  /// originals wait for Wi-Fi.
  testWidgets('photos originals waiting', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/backup',
      backup: const BackupState(
        phase: BackupPhase.waitingForWifi,
        total: 4530,
        done: 3120,
        smallCopies: 1410,
      ),
      prefs: {'backup_enabled': true, 'backup_small_copies': true},
      overrides: [
        pendingOriginalsProvider.overrideWith(
          (ref) => Stream.value((count: 1410, bytes: (6.8 * 1024 * _mb).round())),
        ),
      ],
    );
    await snap(tester, 'photos_originals_waiting');
  });

  testWidgets('backup limit reached', (tester) async {
    await prepareData(tester);
    await pumpApp(
      tester,
      location: '/photos',
      backup: const BackupState(
        phase: BackupPhase.waitingForBudget,
        total: 4530,
        done: 4320,
        heldForBudget: 3,
      ),
      mobileData: _nearLimit,
    );
    await snap(tester, 'backup_limit_reached');
  });

  testWidgets('transfers with backup', (tester) async {
    await prepareData(tester);
    await pumpApp(tester, location: '/transfers', backup: uploading);
    await snap(tester, 'transfers_backup');
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    Map<String, Object> prefs = const {},
    List<Override> overrides = const [],
  }) async {
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          ...overrides,
        ],
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

  testWidgets('welcome after a session ended in Telegram', (tester) async {
    await pumpScreen(
      tester,
      const WelcomeScreen(),
      prefs: {'session_ended_at': DateTime(2026, 9, 29, 19, 32).millisecondsSinceEpoch},
    );
    await snap(tester, 'welcome_session_ended');
  });

  testWidgets('phone', (tester) async {
    await pumpScreen(tester, const PhoneScreen());
    await snap(tester, 'phone');
  });

  testWidgets('phone stuck', (tester) async {
    await pumpScreen(
      tester,
      const PhoneScreen(),
      overrides: [
        connectionHealthProvider.overrideWith(
          () => _Health(ConnectionHealth.stuck),
        ),
      ],
    );
    await snap(tester, 'phone_stuck');
  });

  testWidgets('photos before thumbnails arrive', (tester) async {
    await prepareData(tester);
    // Only Telegram's tiny inline previews: the state a fresh install sees
    // for a moment while thumbnails download.
    _thumbPaths.clear();
    await pumpApp(tester, location: '/photos', backup: uploading);
    await snap(tester, 'photos_loading');
  });

  testWidgets('photos save memory', (tester) async {
    await prepareData(tester);
    // The same moment on a phone saving memory: the previews drawn plain.
    _thumbPaths.clear();
    await pumpApp(
      tester,
      location: '/photos',
      backup: uploading,
      prefs: {'save_memory': true},
    );
    await snap(tester, 'photos_save_memory');
  });
}
