import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/previews.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../player/data/stream_server.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/pdf_block_cache.dart';

/// Reads a PDF or a text file inside the app, and nothing leaves the app.
/// A PDF is read from the drive a range at a time, so its first page shows
/// after a few megabytes however big it is, and one stored in parts opens
/// the same way. A text file comes down into the app's cache whole, as it
/// would for opening it.
class DocumentPreviewScreen extends ConsumerWidget {
  const DocumentPreviewScreen({super.key, required this.fileId});

  final String fileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(fileInfoProvider(fileId)).value;
    final localCopy = ref.watch(_localCopyProvider(fileId));
    final local = localCopy.value;
    final pdf = file != null && _preview(file) == Preview.pdf;
    // A PDF the phone doesn't have is read by range, once it is clear the
    // phone doesn't have it.
    final streamed = pdf && local == null && !localCopy.isLoading
        ? ref.watch(_streamUrlProvider(fileId))
        : null;
    final fetched = file != null && !pdf && local == null
        ? ref.watch(filePreviewProvider(fileId))
        : null;
    final path = local ?? fetched?.value?.path;

    final Widget body;
    if (file == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (pdf) {
      final url = streamed?.value;
      if (local != null) {
        body = PdfViewer.file(local, params: _pdfParams(context, file));
      } else if (streamed case AsyncError(:final error)) {
        body = _CantShow(file: file, message: _pdfTrouble(error));
      } else if (url != null) {
        body = PdfViewer.uri(
          url,
          // Without it pdfrx fetches the whole file before the first page.
          preferRangeAccess: true,
          // Telegram can take a while to start on a slow network; the
          // stream server gives up on its own after two minutes of nothing.
          timeout: const Duration(minutes: 2),
          params: _pdfParams(context, file),
        );
      } else {
        body = const _Opening();
      }
    } else if (path != null) {
      body = _TextView(path: path, file: file);
    } else if (fetched is AsyncError) {
      body = _CantShow(file: file, message: '${fetched!.error}');
    } else {
      final progress = fetched?.value;
      body = _Opening(received: progress?.received, total: progress?.total ?? 0);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(file?.name ?? '', overflow: TextOverflow.ellipsis),
        actions: [
          if (file != null) ...[
            IconButton(
              onPressed: () => FileActions.openExternally(context, ref, file),
              icon: const Icon(Icons.open_in_new_rounded),
              tooltip: 'Open with another app',
            ),
            IconButton(
              onPressed: () => FileActions.showFileSheet(context, ref, file, fromViewer: true),
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'More',
            ),
          ],
        ],
      ),
      body: body,
    );
  }

  static PdfViewerParams _pdfParams(BuildContext context, DriveFile file) =>
      PdfViewerParams(
        backgroundColor: context.colors.bg,
        pageDropShadow: null,
        margin: Space.s,
        // Shown until the document has opened; pages then appear as they
        // arrive.
        loadingBannerBuilder: (context, received, total) => _Opening(
          received: received == 0 ? null : received,
          total: total ?? file.size,
        ),
        errorBannerBuilder: (context, error, _, _) =>
            _CantShow(file: file, message: _pdfTrouble(error)),
      );

  /// Why a PDF didn't open, in words. The reader's own errors are written
  /// for developers, so only the drive's reasons are shown as they are.
  static String _pdfTrouble(Object error) => switch (error) {
    DriveException(:final message) => message,
    PdfPasswordException() => 'This PDF is locked with a password.',
    TimeoutException() => 'Telegram took too long to send it.',
    _ => 'This PDF couldn\'t be read here.',
  };

  static Preview _preview(DriveFile file) => Preview.of(
    name: file.name,
    mimeType: file.mimeType,
    kind: file.kind,
    size: file.size,
    isSplit: file.isSplit,
  );
}

/// A copy already on the phone (offline, or downloaded before), so the
/// preview opens with no fetch.
final _localCopyProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  fileId,
) async {
  final file = await ref.watch(driveRepositoryProvider).fileById(fileId);
  if (file == null) return null;
  return ref.read(transferQueueProvider.notifier).localPathIfAvailable(file);
});

/// Where the PDF reader reads [fileId] from: the stream server, which
/// fetches from Telegram only the ranges the reader asks for.
final _streamUrlProvider = FutureProvider.autoDispose.family<Uri, String>((
  ref,
  fileId,
) async {
  final file = await ref.watch(driveRepositoryProvider).fileById(fileId);
  if (file == null) {
    throw const DriveException('This file is no longer in your drive.');
  }
  await (_pdfCacheSwept ??= deletePdfBlockCache());
  return ref.read(streamServerProvider).urlFor(file);
});

/// Set once this launch has emptied pdfrx's block cache. pdfrx keeps the
/// ranges it reads by URL, and stream URLs carry a token made fresh each
/// launch, so blocks from an earlier launch are never read again; they go
/// before the first PDF opens.
Future<void>? _pdfCacheSwept;

/// A document on its way: 'Opening' until its first bytes arrive, then
/// how much of [total] is here.
class _Opening extends StatelessWidget {
  const _Opening({this.received, this.total = 0});

  final int? received;
  final int total;

  @override
  Widget build(BuildContext context) {
    final received = this.received;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 160,
            child: LinearProgressIndicator(
              value: received == null || total <= 0
                  ? null
                  : (received / total).clamp(0.0, 1.0),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: Space.m),
          Text(
            received == null
                ? 'Opening'
                : '${Formatters.bytes(received)} of ${Formatters.bytes(total)}',
            style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
          ),
        ],
      ),
    );
  }
}

/// The document can't be shown here; another app may manage.
class _CantShow extends ConsumerWidget {
  const _CantShow({required this.file, required this.message});

  final DriveFile file;
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) => EmptyState(
    title: 'Can\'t show this here',
    message: message,
    action: FilledButton.tonal(
      onPressed: () => FileActions.openExternally(context, ref, file),
      child: const Text('Open with another app'),
    ),
  );
}

class _TextView extends StatelessWidget {
  const _TextView({required this.path, required this.file});

  final String path;
  final DriveFile file;

  static const _codeExtensions = {'json', 'xml', 'yaml', 'yml', 'csv', 'tsv', 'log', 'sql'};

  Future<String> _read() async {
    final bytes = await File(path).readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Widget build(BuildContext context) {
    final monospace = _codeExtensions.contains(file.extension.toLowerCase()) ||
        !{'txt', 'md', 'markdown', 'srt', 'vtt'}.contains(file.extension.toLowerCase());
    return FutureBuilder<String>(
      future: _read(),
      builder: (context, snapshot) {
        final text = snapshot.data;
        if (text == null) return const Center(child: CircularProgressIndicator());
        return Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.gutter, Space.x4),
            child: SelectableText(
              text,
              style: monospace
                  ? context.text.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.45,
                      color: context.colors.text,
                    )
                  : context.text.bodyLarge?.copyWith(color: context.colors.text),
            ),
          ),
        );
      },
    );
  }
}
