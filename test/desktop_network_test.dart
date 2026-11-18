import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';

void main() {
  test('a computer with any connection is online, and never metered', () {
    expect(NetworkStatus.desktopState([ConnectivityResult.wifi]), const NetworkState(online: true, metered: false));
    expect(NetworkStatus.desktopState([ConnectivityResult.ethernet, ConnectivityResult.vpn]).online, isTrue);
    expect(NetworkStatus.desktopState([ConnectivityResult.mobile]).metered, isFalse);
  });

  test('a computer with none is offline', () {
    expect(NetworkStatus.desktopState([ConnectivityResult.none]).online, isFalse);
    expect(NetworkStatus.desktopState(const []).online, isFalse);
  });
}
