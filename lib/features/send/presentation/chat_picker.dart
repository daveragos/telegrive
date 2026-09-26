import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/common.dart';
import '../../drive/data/previews.dart';
import '../data/telegram_chats.dart';

/// Picks one or more Telegram chats. Pops with them, or null.
Future<List<TelegramChat>?> showChatPicker(
  BuildContext context, {
  required String title,
  String? note,
}) {
  return showModalBottomSheet<List<TelegramChat>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _ChatPicker(title: title, note: note),
  );
}

class _ChatPicker extends ConsumerStatefulWidget {
  const _ChatPicker({required this.title, this.note});

  final String title;
  final String? note;

  @override
  ConsumerState<_ChatPicker> createState() => _ChatPickerState();
}

class _ChatPickerState extends ConsumerState<_ChatPicker> {
  final Map<int, TelegramChat> _picked = {};
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chats = _query.isEmpty
        ? ref.watch(recentChatsProvider)
        : ref.watch(chatSearchProvider(_query));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.s),
              child: Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium,
              ),
            ),
            if (widget.note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.s),
                child: Text(widget.note!, style: context.text.bodySmall),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.s),
              child: TextField(
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search chats',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 250), () {
                    if (mounted) setState(() => _query = value.trim());
                  });
                },
              ),
            ),
            Expanded(
              child: AsyncView(
                value: chats,
                data: (chats) => chats.isEmpty
                    ? const EmptyState(title: 'No chats found', compact: true)
                    : ListView.builder(
                        controller: scroll,
                        itemCount: chats.length,
                        itemBuilder: (context, i) {
                          final chat = chats[i];
                          final picked = _picked.containsKey(chat.id);
                          return ListTile(
                            leading: ChatAvatar(chat: chat),
                            title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Icon(
                              picked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              color: picked ? context.colors.accent : context.colors.text3,
                            ),
                            onTap: () => setState(
                              () => picked ? _picked.remove(chat.id) : _picked[chat.id] = chat,
                            ),
                          );
                        },
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, Space.l),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _picked.isEmpty
                      ? null
                      : () => Navigator.pop(context, _picked.values.toList()),
                  child: Text(
                    _picked.length <= 1 ? 'Send' : 'Send to ${_picked.length} chats',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A chat's photo, its blurred preview while that loads, or its initial.
class ChatAvatar extends ConsumerWidget {
  const ChatAvatar({super.key, required this.chat, this.radius = 22});

  final TelegramChat chat;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    if (chat.isSelf) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: colors.accent,
        child: Icon(Icons.bookmark_rounded, color: Colors.white, size: radius),
      );
    }
    final photoId = chat.photoFileId;
    final path = photoId == null ? null : ref.watch(thumbnailPathProvider(photoId)).value;
    ImageProvider? image;
    if (path != null) {
      image = FileImage(File(path));
    } else if (chat.minithumbnail case final data?) {
      try {
        image = MemoryImage(base64Decode(data));
      } catch (_) {}
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.surface2,
      foregroundImage: image,
      child: Text(
        chat.title.isEmpty ? '?' : chat.title.characters.first.toUpperCase(),
        style: context.text.titleSmall?.copyWith(color: colors.text2),
      ),
    );
  }
}
