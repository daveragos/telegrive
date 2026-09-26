import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:pdfrx/pdfrx.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/files/file_kind.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/domain/drive_models.dart';
import '../../transfers/data/transfer_queue.dart';

@immutable
class IndexerState {
  const IndexerState({this.enabled = true, this.running = false, this.left = 0});

  final bool enabled;
  final bool running;

  /// Files still to read in the current pass.
  final int left;

  IndexerState copyWith({bool? enabled, bool? running, int? left}) => IndexerState(
    enabled: enabled ?? this.enabled,
    running: running ?? this.running,
    left: left ?? this.left,
  );
}

/// Reads what is in photos and documents so search can find them by it:
/// the text in a photo (a receipt, a sign, a screenshot), what a photo
/// shows ("dog", "beach"), and the words in PDFs and text files.
///
/// Everything happens on this phone with on-device models, a file at a
/// time while the app is open; nothing is sent anywhere. Photos are read
/// from the phone's own copy when there is one and otherwise from their
/// small preview (enough to say what is in them, not to read their text).
/// Anything not on the phone yet (previews, PDFs, text files) is fetched on
/// Wi-Fi only.
class ContentIndexer extends Notifier<IndexerState> {
  static const int version = 1;
  static const int _maxChars = 20000;
  static const int _pdfLimit = 25 * 1024 * 1024;
  static const int _textLimit = 1024 * 1024;
  static const int _pdfPages = 40;

  Timer? _start;
  bool _stop = false;

  /// Whether this pass may fetch previews and documents it doesn't have.
  bool _onWifi = false;
  ImageLabeler? _labeler;
  TextRecognizer? _recognizer;

  AppDatabase get _db => ref.read(appDatabaseProvider);
  TelegramClient get _client => ref.read(telegramClientProvider);

  static bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  IndexerState build() {
    final enabled = ref.watch(preferencesProvider).contentSearch;
    ref.onDispose(() {
      _stop = true;
      _start?.cancel();
      unawaited(_labeler?.close());
      unawaited(_recognizer?.close());
    });
    if (!_supported) return IndexerState(enabled: enabled);
    ref.listen<DriveSession?>(driveSessionProvider, (_, session) {
      if (session != null) _soon(const Duration(seconds: 20));
    }, fireImmediately: true);
    ref.listen<SyncState>(driveSyncProvider, (previous, next) {
      if ((previous?.running ?? false) && !next.running) _soon(const Duration(seconds: 5));
    });
    return IndexerState(enabled: enabled);
  }

  Future<void> setEnabled(bool enabled) async {
    await ref.read(preferencesProvider).setContentSearch(enabled);
    _stop = !enabled;
    state = state.copyWith(enabled: enabled);
    if (enabled) _soon(Duration.zero);
  }

  void _soon(Duration after) {
    _start?.cancel();
    _start = Timer(after, () => unawaited(_run()));
  }

  Future<void> _run() async {
    if (state.running || !state.enabled || !_supported) return;
    _stop = false;
    state = state.copyWith(running: true);
    try {
      final done = await _db.indexedFileIds(version);
      final todo = [
        for (final row in await _db.completeFiles())
          if (!done.contains(row.id) && _readable(DriveFile.fromRow(row)))
            DriveFile.fromRow(row),
      ]..sort((a, b) => b.momentAt.compareTo(a.momentAt));

      _onWifi = await _wifi();
      for (final (index, file) in todo.indexed) {
        if (_stop) break;
        state = state.copyWith(left: todo.length - index);
        final content = await _read(file);
        if (content != null) {
          await _db.saveContent(file.id, _clean(content), version);
        }
        // Leave room for everything else the app is doing.
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    } catch (e) {
      debugPrint('[Indexer] $e');
    } finally {
      state = state.copyWith(running: false, left: 0);
    }
  }

  static bool _readable(DriveFile file) =>
      (file.fitsGallery && file.kind == FileKind.image) ||
      switch (_preview(file)) {
        Preview.pdf => file.size <= _pdfLimit,
        Preview.text => file.size <= _textLimit,
        _ => false,
      };

  static Preview _preview(DriveFile file) => Preview.of(
    name: file.name,
    mimeType: file.mimeType,
    kind: file.kind,
    size: file.size,
    isSplit: file.isSplit,
  );

  /// What [file] contains, or null to try again on a later pass.
  Future<String?> _read(DriveFile file) async {
    try {
      if (file.kind == FileKind.image) return await _readPhoto(file);
      final path = await _documentPath(file);
      if (path == null) return null;
      return _preview(file) == Preview.pdf ? await _readPdf(path) : await _readText(path);
    } catch (e) {
      debugPrint('[Indexer] ${file.name}: $e');
      // Unreadable files are recorded as empty so they aren't retried
      // forever.
      return '';
    }
  }

  Future<String?> _readPhoto(DriveFile file) async {
    final original = await _originalOnPhone(file);
    final path = original ?? await _thumbnail(file);
    if (path == null) return null;
    final image = InputImage.fromFilePath(path);
    final labels = await (_labeler ??= ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.7),
    )).processImage(image);
    final words = [for (final label in labels) label.label];
    // A 320 px preview is too small for reading text.
    if (original != null) {
      final text = await (_recognizer ??= TextRecognizer()).processImage(image);
      words.add(text.text);
    }
    return words.join(' · ');
  }

  /// The phone's own copy (backed up from here), or one already downloaded.
  Future<String?> _originalOnPhone(DriveFile file) async {
    final assetId = await _db.localAssetOf(file.id);
    if (assetId != null) {
      try {
        final asset = await AssetEntity.fromId(assetId);
        final local = await asset?.file;
        if (local != null && await local.exists()) return local.path;
      } catch (_) {}
    }
    return ref.read(transferQueueProvider.notifier).localPathIfAvailable(file);
  }

  /// The file's small preview; fetched only on Wi-Fi, since a whole drive
  /// of them adds up.
  Future<String?> _thumbnail(DriveFile file) async {
    final id = file.thumbnailFileId;
    if (id == null) return null;
    final known = await _client.send<td.File>(td.GetFile(fileId: id));
    if (known.local.isDownloadingCompleted) return known.local.path;
    if (!_onWifi) return null;
    final thumb = await _client.send<td.File>(
      td.DownloadFile(fileId: id, priority: 1, offset: 0, limit: 0, synchronous: true),
      timeout: const Duration(minutes: 1),
    );
    return thumb.local.isDownloadingCompleted ? thumb.local.path : null;
  }

  /// A document's path, fetching it only on Wi-Fi.
  Future<String?> _documentPath(DriveFile file) async {
    final local = await ref.read(transferQueueProvider.notifier).localPathIfAvailable(file);
    if (local != null) return local;
    if (!_onWifi) return null;
    final parts = await ref.read(driveRepositoryProvider).partsOf(file.id);
    if (parts.length != 1) return '';
    final tdFile = await ref.read(driveRepositoryProvider).resolveTdFile(parts.single);
    final fetched = await _client.send<td.File>(
      td.DownloadFile(fileId: tdFile.id, priority: 1, offset: 0, limit: 0, synchronous: true),
      timeout: const Duration(minutes: 10),
    );
    return fetched.local.isDownloadingCompleted ? fetched.local.path : null;
  }

  Future<String> _readPdf(String path) async {
    if (path.isEmpty) return '';
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(path);
    try {
      final buffer = StringBuffer();
      for (final page in document.pages.take(_pdfPages)) {
        final text = await page.loadText();
        if (text != null) buffer.writeln(text.fullText);
        if (buffer.length > _maxChars) break;
      }
      return buffer.toString();
    } finally {
      await document.dispose();
    }
  }

  Future<String> _readText(String path) async {
    if (path.isEmpty) return '';
    final bytes = await File(path).openRead(0, _maxChars * 2).fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<bool> _wifi() async {
    final network = await Connectivity().checkConnectivity();
    return network.contains(ConnectivityResult.wifi) ||
        network.contains(ConnectivityResult.ethernet);
  }

  static String _clean(String text) {
    final flat = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length > _maxChars ? flat.substring(0, _maxChars) : flat;
  }
}

final contentIndexerProvider = NotifierProvider<ContentIndexer, IndexerState>(
  ContentIndexer.new,
);

/// How many files have been read so far.
final indexedCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(appDatabaseProvider).watchIndexedCount(),
);
