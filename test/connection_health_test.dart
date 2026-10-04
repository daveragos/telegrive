import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/network/data/connection_health.dart';

void main() {
  const after = Duration(milliseconds: 50);
  late StreamController<td.ConnectionState> states;
  late StreamController<bool> network;
  late ConnectionHealthTracker tracker;
  late List<ConnectionHealth> seen;

  setUp(() {
    states = StreamController<td.ConnectionState>();
    network = StreamController<bool>();
    tracker = ConnectionHealthTracker(
      states: states.stream,
      hasNetwork: network.stream,
      after: after,
    );
    seen = [];
    tracker.changes.listen(seen.add);
  });

  tearDown(() async {
    await tracker.dispose();
    await states.close();
    await network.close();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);
  Future<void> wait() => Future<void>.delayed(after * 2);

  test('connecting with a network becomes stuck after the delay', () async {
    network.add(true);
    states.add(const td.ConnectionStateConnecting());
    await settle();
    expect(tracker.health, ConnectionHealth.ok);

    await wait();
    expect(tracker.health, ConnectionHealth.stuck);
    expect(seen, [ConnectionHealth.stuck]);
  });

  test('ready before the delay stays ok', () async {
    states.add(const td.ConnectionStateConnecting());
    await settle();
    states.add(const td.ConnectionStateReady());
    await wait();
    expect(tracker.health, ConnectionHealth.ok);
    expect(seen, isEmpty);
  });

  test('ready or updating clears a stuck connection at once', () async {
    states.add(const td.ConnectionStateConnecting());
    await wait();
    expect(tracker.health, ConnectionHealth.stuck);

    states.add(const td.ConnectionStateUpdating());
    await settle();
    expect(tracker.health, ConnectionHealth.ok);
    expect(seen, [ConnectionHealth.stuck, ConnectionHealth.ok]);
  });

  test('connecting to a proxy becomes proxyStuck', () async {
    states.add(const td.ConnectionStateConnectingToProxy());
    await wait();
    expect(tracker.health, ConnectionHealth.proxyStuck);
  });

  test('switching to a proxy starts the clock again', () async {
    states.add(const td.ConnectionStateConnecting());
    await wait();
    expect(tracker.health, ConnectionHealth.stuck);

    states.add(const td.ConnectionStateConnectingToProxy());
    await settle();
    expect(tracker.health, ConnectionHealth.ok);
    await wait();
    expect(tracker.health, ConnectionHealth.proxyStuck);
  });

  test('waiting for a network is no network, not stuck', () async {
    states.add(const td.ConnectionStateWaitingForNetwork());
    await wait();
    expect(tracker.health, ConnectionHealth.noNetwork);
    expect(seen, [ConnectionHealth.noNetwork]);
  });

  test('losing the network cancels the timer', () async {
    network.add(true);
    states.add(const td.ConnectionStateConnecting());
    await settle();
    network.add(false);
    await wait();
    expect(tracker.health, ConnectionHealth.noNetwork);
    expect(seen, isNot(contains(ConnectionHealth.stuck)));

    // Back on a network, the clock starts over.
    network.add(true);
    await settle();
    expect(tracker.health, ConnectionHealth.ok);
    await wait();
    expect(tracker.health, ConnectionHealth.stuck);
  });

  test('a request that already timed out has waited long enough', () {
    expect(healthAfterWaiting(const td.ConnectionStateConnecting()), ConnectionHealth.stuck);
    expect(
      healthAfterWaiting(const td.ConnectionStateConnectingToProxy()),
      ConnectionHealth.proxyStuck,
    );
    expect(
      healthAfterWaiting(const td.ConnectionStateWaitingForNetwork()),
      ConnectionHealth.noNetwork,
    );
    expect(healthAfterWaiting(const td.ConnectionStateReady()), ConnectionHealth.ok);
    expect(healthAfterWaiting(null), ConnectionHealth.ok);
  });
}
