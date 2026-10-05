/// Telegram numbers a channel's messages 1, 2, 3 and on, as their t.me links
/// show. TDLib's id for message number n is n × 2^20, which only TDLib
/// knows, so what the drive writes into the channel uses the numbers.
abstract final class MessageNumber {
  static const int _shift = 20;

  /// The number of the message TDLib calls [messageId].
  static int of(int messageId) => messageId >> _shift;

  /// TDLib's id for message [number].
  static int idOf(int number) => number << _shift;
}
