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
import '../../transfers/data/transfer_queue.dart';

/// Reads a PDF or a text file inside the app. The file comes down into the
/// app's cache as it would for opening it, but nothing leaves the app.
class DocumentPreviewScreen extends ConsumerWidget {
  const DocumentPreviewScreen({super.key, required this.fileId});

  final String fileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(fileInfoProvider(fileId)).value;
    final local = ref.watch(_localCopyProvider(fileId)).value;
    final fetched = local == null ? ref.watch(filePreviewProvider(fileId)) : null;
    final path = local ?? fetched?.value?.path;

    final Widget body;
    if (file == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (path != null) {
      body = _preview(file) == Preview.pdf
          ? PdfViewer.file(
              path,
              params: PdfViewerParams(
                backgroundColor: context.colors.bg,
                pageDropShadow: null,
                margin: Space.s,
              ),
            )
          : _TextView(path: path, file: file);
    } else if (fetched is AsyncError) {
      body = EmptyState(
        title: 'Can\'t show this here',
        message: '${fetched!.error}',
        action: FilledButton.tonal(
          onPressed: () => FileActions.openExternally(context, ref, file),
          child: const Text('Open with another app'),
        ),
      );
    } else {
      final progress = fetched?.value;
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                value: progress == null || progress.total == 0 ? null : progress.fraction,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: Space.m),
            Text(
              progress == null
                  ? 'Opening'
                  : '${Formatters.bytes(progress.received)} of ${Formatters.bytes(progress.total)}',
              style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
            ),
          ],
        ),
      );
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
              onPressed: () => FileActions.showFileSheet(context, ref, file),
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'More',
            ),
          ],
        ],
      ),
      body: body,
    );
  }

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
