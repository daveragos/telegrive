import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/launch_action.dart';
import 'package:telegrive/features/transfers/data/transfer_keep_alive.dart';

void main() {
  group('LaunchRequest.fromRoute', () {
    test('the transfer notification\'s route opens Transfers', () {
      expect(
        LaunchRequest.fromRoute(TransferKeepAlive.notificationRoute),
        const LaunchRequest(LaunchAction.transfers),
      );
    });

    test('the default route, which a reopened app gets, is a plain launch', () {
      expect(LaunchRequest.fromRoute('/'), isNull);
      expect(LaunchRequest.fromRoute(''), isNull);
    });

    test('no other route is an action', () {
      expect(LaunchRequest.fromRoute('/home'), isNull);
      expect(LaunchRequest.fromRoute('/transfers/'), isNull);
    });
  });
}
