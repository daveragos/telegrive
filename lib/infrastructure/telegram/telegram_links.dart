import 'message_number.dart';

/// Links into the Telegram app. They use the tg:// scheme, which any
/// Telegram app on the phone opens directly; a t.me link goes to the browser
/// on phones where no app has claimed it, and the browser can't show a
/// private channel.
abstract final class TelegramLinks {
  /// The message TDLib calls [messageId] in the channel [chatId].
  static Uri post(int chatId, int messageId) => Uri(
    scheme: 'tg',
    host: 'privatepost',
    queryParameters: {
      'channel': '${_channelOf(chatId)}',
      'post': '${MessageNumber.of(messageId)}',
    },
  );

  /// TDLib's chat id for a channel is -10^12 minus the channel's own id,
  /// which is the one links use.
  static int _channelOf(int chatId) => -chatId - 1000000000000;
}
