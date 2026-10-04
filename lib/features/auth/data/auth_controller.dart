import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../drive/data/drive_session.dart';
import '../../offline/data/offline_sync.dart';
import '../../photos/data/photos_visibility.dart';
import '../../preview/data/pdf_block_cache.dart';
import '../../share/data/recent_destinations.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../trash/data/pending_deletes.dart';

/// Choices the person made on the sign-in screens that TDLib's state alone
/// can't express.
@immutable
class AuthUiState {
  const AuthUiState({this.startedSignIn = false, this.editingPhone = false});

  /// Past the welcome screen in this run of the app.
  final bool startedSignIn;

  /// Wants to type a phone number even though TDLib is showing a QR code or
  /// waiting for a code (to fix a typo, say).
  final bool editingPhone;

  AuthUiState copyWith({bool? startedSignIn, bool? editingPhone}) =>
      AuthUiState(
        startedSignIn: startedSignIn ?? this.startedSignIn,
        editingPhone: editingPhone ?? this.editingPhone,
      );
}

/// Sign-in actions. Each throws a [TelegramException] whose
/// `friendlyMessage` the screen shows as-is.
class AuthController extends Notifier<AuthUiState> {
  TelegramClient get _client => ref.read(telegramClientProvider);

  @override
  AuthUiState build() => const AuthUiState();

  void startSignIn() => state = state.copyWith(startedSignIn: true);

  void editPhone() => state = state.copyWith(editingPhone: true);

  void cancelEditPhone() => state = state.copyWith(editingPhone: false);

  Future<void> submitPhone(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'[^\d+]'), '');
    await _client.send<td.Ok>(
      td.SetAuthenticationPhoneNumber(
        phoneNumber: normalized,
        settings: const td.PhoneNumberAuthenticationSettings(
          allowFlashCall: false,
          allowMissedCall: false,
          isCurrentPhoneNumber: false,
          hasUnknownPhoneNumber: false,
          allowSmsRetrieverApi: false,
          authenticationTokens: [],
        ),
      ),
    );
    state = state.copyWith(editingPhone: false);
  }

  Future<void> requestQrCode() async {
    await _client.send<td.Ok>(
      const td.RequestQrCodeAuthentication(otherUserIds: []),
    );
    state = state.copyWith(editingPhone: false);
  }

  Future<void> submitCode(String code) =>
      _client.send<td.Ok>(td.CheckAuthenticationCode(code: code.trim()));

  Future<void> resendCode() =>
      _client.send<td.Ok>(const td.ResendAuthenticationCode());

  Future<void> submitPassword(String password) =>
      _client.send<td.Ok>(td.CheckAuthenticationPassword(password: password));

  /// Signs out of Telegram and removes every local trace of the drive. The
  /// files themselves stay safe in the channel.
  Future<void> signOut() async {
    // Log out first: once TDLib leaves the ready state the app shows the
    // splash, so closing the drive afterwards can't bounce it back into
    // setup for the account that is leaving.
    await _client.logOut();
    await wipeDeviceState();
  }

  /// Forgets everything this phone keeps about the drive, while the files
  /// stay in the channel. Whatever has to forget a drive (signing out, a
  /// session ended from Telegram, another account signing in) calls this
  /// instead of clearing stores itself, so there is one list of what a drive
  /// leaves on the phone.
  ///
  /// The sync checkpoints go with the index. Kept on their own, they would
  /// tell the next sign-in that the channel was already read, and it would
  /// open an empty drive and back every photo up again. They are cleared
  /// before the index, so a wipe cut short still ends in a full read.
  ///
  /// Deletes still waiting out their Undo are dropped before anything
  /// else, so nothing is deleted once the drive has gone, from Telegram or
  /// from the phone over the Welcome screen. What they would have deleted is
  /// still in the channel for the next sign-in. Files kept available offline
  /// go with the index that knew about them, or nothing would find them
  /// again, and so do the pages of PDFs read in the app, which are pieces of
  /// the drive's documents.
  ///
  /// App settings (theme, app lock, Save memory, photo backup choices, the
  /// folders Photos keeps out) and the drive channel remembered per account
  /// stay, and so do whether Telegrive has asked to post notifications and
  /// when a swiped-away backup reminder may come back, which are about the
  /// phone. So do the
  /// monthly mobile data limit and what this period has used of it: they
  /// belong to the phone's data plan, and TDLib starts its counters over
  /// after a sign-out, so the use counted so far has to carry on. The 'Also
  /// delete from this phone' answer, Photos' Show for kept-out folders and
  /// Only over Wi-Fi for files kept offline don't: whoever signs in next
  /// starts with all three off. The chats files were
  /// last sent to go too, since they belong to the account that sent them,
  /// and so do the recent upload folders, and with them their targets in the
  /// system share sheet, so no folder name of this drive is left in other
  /// apps. When the phone's caches were last trimmed is forgotten as well,
  /// so the next drive to open trims them once straight away. Anything new
  /// that the phone keeps per drive, whether a table, a preference or a
  /// file, adds its cleanup here.
  Future<void> wipeDeviceState() async {
    ref.read(pendingDeletesProvider.notifier).discardAll();
    ref.read(driveSessionProvider.notifier).close();
    final prefs = ref.read(preferencesProvider);
    for (final chatId in prefs.syncedChatIds) {
      await prefs.clearSyncState(chatId);
    }
    await prefs.setDeletePhoneCopyToo(false);
    await prefs.setOfflineWifiOnly(false);
    await prefs.forgetRecentSendChats();
    await prefs.forgetCacheSweptAt();
    ref.invalidate(revealHiddenProvider);
    ref.invalidate(offlineSyncProvider);
    await ref.read(recentDestinationsProvider.notifier).clear();
    await ref.read(appDatabaseProvider).clearAll();
    await _deleteOfflineCopies();
    await deletePdfBlockCache();
    state = const AuthUiState();
  }

  /// A copy that can't be deleted now stays behind rather than stopping the
  /// rest of the sign-out.
  static Future<void> _deleteOfflineCopies() async {
    try {
      final offline = await TransferQueue.offlineDirectory();
      if (await offline.exists()) await offline.delete(recursive: true);
    } catch (e) {
      debugPrint('[Auth] Could not delete the offline copies: $e');
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthUiState>(
  AuthController.new,
);
