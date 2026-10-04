import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/infrastructure/telegram/td_ownership.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('td_owner');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('the first to ask owns TDLib, and a second engine does not', () async {
    final app = TdOwnership(dir);
    final job = TdOwnership(dir);
    addTearDown(app.release);

    expect(await app.isHeld(), isFalse);
    expect(await app.tryAcquire(), isTrue);
    expect(await job.tryAcquire(), isFalse);
    expect(await app.isHeld(), isTrue);
    expect(await job.isHeld(), isTrue);
  });

  test('asking to hand over reaches the owner', () async {
    final job = TdOwnership(dir);
    final app = TdOwnership(dir);
    addTearDown(job.release);
    expect(await job.tryAcquire(), isTrue);

    final asked = job.yieldRequests.first;
    expect(await app.requestYield(), isTrue);
    await asked.timeout(const Duration(seconds: 5));
  });

  test('a request made before the owner listens is kept for it', () async {
    final job = TdOwnership(dir);
    addTearDown(job.release);
    await job.tryAcquire();

    expect(await TdOwnership(dir).requestYield(), isTrue);
    await job.yieldRequests.first.timeout(const Duration(seconds: 5));
  });

  test('with nobody holding it, there is no one to ask', () async {
    expect(await TdOwnership(dir).requestYield(), isFalse);
  });

  test('once the owner lets go, the other engine takes over', () async {
    final job = TdOwnership(dir);
    final app = TdOwnership(dir);
    addTearDown(app.release);
    await job.tryAcquire();

    await job.release();
    expect(await app.isHeld(), isFalse);
    expect(await app.tryAcquire(), isTrue);
    expect(await job.isHeld(), isTrue);
    expect(await job.tryAcquire(), isFalse);
  });

  test('a socket file left behind with nobody listening is replaced', () async {
    // What an owner that went away without closing leaves: a file at the
    // socket's path that answers no one.
    await File('${dir.path}/owner.sock').writeAsString('');
    final app = TdOwnership(dir);
    addTearDown(app.release);

    expect(await app.isHeld(), isFalse);
    expect(await app.tryAcquire(), isTrue);
    expect(await TdOwnership(dir).isHeld(), isTrue);
  });
}
