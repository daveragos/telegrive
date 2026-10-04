import 'dart:collection';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/format/formatters.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/backup/presentation/backup_card.dart';

void main() {
  group('orderPending', () {
    String id(String item) => item;

    test('puts Back up now requests first, in the order they were asked for', () {
      expect(
        BackupController.orderPending(['a', 'b', 'c', 'd', 'e'], {'d', 'b'}, id),
        ['d', 'b', 'a', 'c', 'e'],
      );
    });

    test('keeps the order when nothing was asked for', () {
      expect(BackupController.orderPending(['a', 'b', 'c'], {}, id), ['a', 'b', 'c']);
    });

    test('leaves out requests for photos that are not waiting', () {
      expect(BackupController.orderPending(['a', 'b'], {'x', 'b'}, id), ['b', 'a']);
    });
  });

  group('nextInLine', () {
    late Queue<String> priority;
    late Set<String> started;
    late Iterator<String> queue;

    setUp(() {
      priority = Queue();
      started = {};
      queue = ['a', 'b', 'c'].iterator;
    });

    // The pass found a to d; a, b and c were waiting, d had failed before.
    String? next({Set<String> active = const {}}) => BackupController.nextInLine(
      priority: priority,
      inScope: {for (final id in ['a', 'b', 'c', 'd']) id: id},
      active: active,
      queue: queue,
      started: started,
      idOf: (item) => item,
    );

    test('a request made during the pass goes next, and only once', () {
      expect(next(), 'a');
      priority.add('c');
      expect(next(), 'c');
      expect(next(), 'b');
      expect(next(), isNull);
      expect(priority, isEmpty);
    });

    test('a photo retried after failing in this pass goes again', () {
      expect(next(), 'a');
      priority.add('a');
      expect(next(), 'a');
      expect(next(), 'b');
    });

    test('a photo retried from an earlier pass goes ahead of the rest', () {
      expect(next(), 'a');
      priority.add('d');
      expect(next(), 'd');
      expect(next(), 'b');
    });

    test('a request for a photo the pass did not find stays for the next pass', () {
      priority.add('x');
      expect(next(), 'a');
      expect(priority, ['x']);
    });

    test('a request for a photo going up right now waits until it is done', () {
      expect(next(), 'a');
      priority.add('a');
      expect(next(active: {'a'}), 'b');
      expect(priority, ['a']);
      expect(next(), 'a');
    });
  });

  test('the waiting list is carried through copyWith until replaced', () {
    final waiting = [
      PendingAsset(assetId: '1', takenAt: DateTime(2026, 9, 25), folder: 'Camera'),
    ];
    final state = const BackupState(phase: BackupPhase.waitingForWifi, total: 4).copyWith(
      waiting: waiting,
    );
    expect(state.waiting, waiting);
    expect(state.copyWith(done: 1).waiting, waiting);
    expect(state.copyWith(waiting: const []).waiting, isEmpty);
    expect(const BackupState(phase: BackupPhase.off).waiting, isEmpty);
  });

  test('backup held by the monthly data limit says when it carries on', () {
    final status = describeBackup(
      const BackupState(phase: BackupPhase.waitingForBudget, total: 4530, done: 4320),
      renewDay: 3,
    );
    expect(status.icon, Icons.data_usage_rounded);
    expect(status.title, 'Monthly data limit reached');
    expect(status.detail, '210 items left. Backup carries on over Wi-Fi, or on the 3rd.');
  });

  test('with mobile data for photos only, the videos are what waits', () {
    const held = BackupState(
      phase: BackupPhase.waitingForWifi,
      total: 300,
      done: 262,
      heldVideos: 38,
    );
    expect(describeBackup(held).title, 'Videos wait for Wi-Fi');
    expect(describeBackup(held).detail, '38 videos left. Photos are backed up.');

    final waiting = describeBackup(const BackupState(phase: BackupPhase.waitingForWifi, total: 4));
    expect(waiting.title, 'Waiting for Wi-Fi');
    expect(waiting.detail, '4 items left. Backup uses Wi-Fi only.');

    final uploading = describeBackup(
      const BackupState(phase: BackupPhase.uploading, total: 300, done: 90, heldVideos: 38),
      speed: 2.1 * 1024 * 1024,
    );
    expect(uploading.detail, '210 items left · 2.1 MB/s · videos wait for Wi-Fi');
  });

  test('backup paused for a wait Telegram asked for says when it carries on', () {
    final until = DateTime.now().add(const Duration(days: 3));
    final paused = BackupState(
      phase: BackupPhase.uploading,
      total: 300,
      done: 90,
      pausedUntil: until,
    );
    final status = describeBackup(paused);
    expect(status.icon, Icons.hourglass_empty_rounded);
    expect(status.title, 'Telegram asked us to wait');
    expect(
      status.detail,
      '210 items left. Backup carries on by itself on ${Formatters.date(until)}.',
    );
    expect(status.progress, isNull);
    expect(paused.isWorking, isFalse);
    expect(paused.copyWith(clearPaused: true).isWorking, isTrue);
  });

  test('a stopped backup says so, with the reason as the detail', () {
    final status = describeBackup(
      const BackupState(
        phase: BackupPhase.stopped,
        error: 'Lost the connection to Telegram. Retry when you\'re back online.',
      ),
    );
    expect(status.title, 'Backup stopped');
    expect(status.detail, 'Lost the connection to Telegram. Retry when you\'re back online.');
  });
}
