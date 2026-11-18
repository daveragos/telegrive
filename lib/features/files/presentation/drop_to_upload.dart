import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import 'file_actions.dart';
import 'phone_folder_upload.dart';

/// On a computer, files and folders dragged in from Finder, File Explorer
/// or a Linux file manager go up when dropped on the window: into the
/// folder [folderOf] names for where the app is, the one open in Files or
/// Private, or the top of the drive. A folder goes up with the folders
/// inside it, each file from where it is.
class DropToUpload extends ConsumerStatefulWidget {
  const DropToUpload({super.key, required this.folderOf, required this.child});

  /// The drive folder a drop goes into, for the router's current place.
  final String? Function(GoRouter router) folderOf;
  final Widget child;

  @override
  ConsumerState<DropToUpload> createState() => _DropToUploadState();
}

class _DropToUploadState extends ConsumerState<DropToUpload> {
  bool _over = false;

  void _hover(bool over) {
    if (over != _over) setState(() => _over = over);
  }

  Future<void> _dropped(DropDoneDetails details) async {
    _hover(false);
    final folderId = widget.folderOf(GoRouter.of(context));
    final files = <String>[];
    final folders = <String>[];
    for (final item in details.files) {
      if (item.path.isEmpty) continue;
      if (item is DropItemDirectory || FileSystemEntity.isDirectorySync(item.path)) {
        folders.add(item.path);
      } else {
        files.add(item.path);
      }
    }
    if (files.isNotEmpty) await FileActions.uploadPaths(context, ref, files, folderId: folderId);
    for (final folder in folders) {
      if (!mounted) return;
      await PhoneFolderUpload.uploadFrom(context, ref, folder, folderId: folderId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DropTarget(
      onDragEntered: (_) => _hover(true),
      onDragExited: (_) => _hover(false),
      onDragDone: _dropped,
      child: Stack(
        children: [
          widget.child,
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(Space.s),
                  decoration: BoxDecoration(
                    color: colors.accentSoft.withValues(alpha: 0.6),
                    border: Border.all(color: colors.accent, width: 2),
                    borderRadius: BorderRadius.circular(Radii.card),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.upload_rounded, size: 40, color: colors.accent),
                      const SizedBox(height: Space.s),
                      Text(
                        widget.folderOf(GoRouter.of(context)) == null
                            ? 'Drop to upload to Files'
                            : 'Drop to upload to this folder',
                        style: context.text.titleMedium?.copyWith(color: colors.accent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
