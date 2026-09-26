import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in account and the channel its drive lives in. Null until
/// setup has found or created the channel.
@immutable
class DriveSession {
  const DriveSession({
    required this.userId,
    required this.chatId,
    required this.channelTitle,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.username,
    required this.isPremium,
  });

  final int userId;
  final int chatId;
  final String channelTitle;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String? username;
  final bool isPremium;

  String get displayName => [firstName, lastName]
      .where((s) => s.trim().isNotEmpty)
      .join(' ')
      .trim();

  String get initials {
    final parts = displayName.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

class DriveSessionNotifier extends Notifier<DriveSession?> {
  @override
  DriveSession? build() => null;

  // ignore: use_setters_to_change_properties
  void open(DriveSession session) => state = session;

  void close() => state = null;
}

final driveSessionProvider =
    NotifierProvider<DriveSessionNotifier, DriveSession?>(
      DriveSessionNotifier.new,
    );
