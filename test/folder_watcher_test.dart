import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telegrive/features/backup/data/folder_watcher.dart';

/// A watcher on a folder, with the changes it has told of since [reset].
class _Watched {
  _Watched(String root, {required bool perFolder}) {
    watcher = FolderWatcher(root, recursive: true, perFolder: perFolder, onChange: _changed);
  }

  late final FolderWatcher watcher;
  int changes = 0;
  Completer<void> _next = Completer<void>();

  void _changed() {
    changes++;
    if (!_next.isCompleted) _next.complete();
  }

  /// Starts watching, and lets the system's reports of what happened just
  /// before the watch began, which macOS may still send, go by.
  Future<void> start() async {
    await watcher.start();
    await Future<void>.delayed(const Duration(seconds: 1));
    reset();
  }

  void reset() {
    changes = 0;
    _next = Completer<void>();
  }

  Future<void> get nextChange => _next.future.timeout(const Duration(seconds: 10));
}

void main() {
  late Directory root;

  setUp(() async {
    // Resolved, since macOS reports changes under /private/var for /var.
    root = Directory((await Directory.systemTemp.createTemp('folder_watcher_test')).resolveSymbolicLinksSync());
    Directory(p.join(root.path, 'Trip')).createSync();
  });

  tearDown(() => root.delete(recursive: true));

  Future<_Watched> watch({bool perFolder = false}) async {
    final watched = _Watched(root.path, perFolder: perFolder);
    addTearDown(watched.watcher.stop);
    await watched.start();
    return watched;
  }

  for (final perFolder in [false, true]) {
    final how = perFolder ? 'folder by folder, as on Linux' : 'all at once';
    test('a file saved in a subfolder is noticed, watching $how', () async {
      final watched = await watch(perFolder: perFolder);
      File(p.join(root.path, 'Trip', 'map.pdf')).writeAsStringSync('map');
      await watched.nextChange;
    });
  }

  test('a folder made after the watch started is watched too, folder by folder', () async {
    final watched = await watch(perFolder: true);
    final made = Directory(p.join(root.path, 'New'))..createSync();
    await watched.nextChange;
    await Future<void>.delayed(const Duration(seconds: 1));
    watched.reset();
    File(p.join(made.path, 'notes.txt')).writeAsStringSync('notes');
    await watched.nextChange;
  });

  test('clutter and hidden files say nothing', () async {
    final watched = await watch();
    File(p.join(root.path, '.DS_Store')).writeAsStringSync('x');
    File(p.join(root.path, 'Trip', 'Thumbs.db')).writeAsStringSync('x');
    Directory(p.join(root.path, '.git')).createSync();
    File(p.join(root.path, '.git', 'index')).writeAsStringSync('x');
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(watched.changes, 0);
  });

  test('a stopped watcher says nothing', () async {
    final watched = await watch();
    watched.watcher.stop();
    File(p.join(root.path, 'Trip', 'map.pdf')).writeAsStringSync('map');
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(watched.changes, 0);
  });
}
