import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/launch_action.dart';
import 'package:telegrive/features/transfers/data/transfer_keep_alive.dart';

void main() {
  group('LaunchAction.fromRoute', () {
    test('the transfer notification\'s route opens Transfers', () {
      expect(
        LaunchAction.fromRoute(TransferKeepAlive.notificationRoute),
        LaunchAction.transfers,
      );
    });

    test('the default route, which a reopened app gets, is a plain launch', () {
      expect(LaunchAction.fromRoute('/'), isNull);
      expect(LaunchAction.fromRoute(''), isNull);
    });

    test('no other route is an action', () {
      expect(LaunchAction.fromRoute('/home'), isNull);
      expect(LaunchAction.fromRoute('/transfers/'), isNull);
    });
  });
}
