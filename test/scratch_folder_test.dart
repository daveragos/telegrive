import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:telegrive/core/platform/app_platform.dart';
import 'package:telegrive/features/transfers/data/leftovers.dart';
import 'package:telegrive/infrastructure/storage/app_dirs.dart';

/// A temporary folder shared with other apps, and a cache of the app's own.
class _Paths extends PathProviderPlatform {
  _Paths(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');

  @override
  Future<String?> getApplicationCachePath() async => p.join(root, 'cache');
}

void main() {
  late Directory root;
  late PathProviderPlatform paths;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desktop_platform_test');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
  });

  tearDown(() async {
    AppPlatform.debugDesktop = false;
    PathProviderPlatform.instance = paths;
    await root.delete(recursive: true);
  });

  group('AppPlatform', () {
    test('a phone is mobile and says phone', () {
      AppPlatform.debugDesktop = false;
      expect(AppPlatform.isMobile, isTrue);
      expect(AppPlatform.thisDevice, 'this phone');
    });

    test('a computer is a desktop and says computer', () {
      AppPlatform.debugDesktop = true;
      expect(AppPlatform.isMobile, isFalse);
      expect(AppPlatform.thisDevice, 'this computer');
    });
  });

  group('scratchDirectory', () {
    test('a phone uses its own temporary folder', () async {
      expect((await scratchDirectory()).path, p.join(root.path, 'tmp'));
    });

    test('a computer keeps its copies in its own cache, not the shared temp folder', () async {
      AppPlatform.debugDesktop = true;
      final scratch = await scratchDirectory();
      expect(scratch.path, p.join(root.path, 'cache', 'scratch'));
      expect(await scratch.exists(), isTrue);
    });

    test("a file the person keeps in the shared temp folder is not taken for the app's copy", () async {
      AppPlatform.debugDesktop = true;
      final folders = await CopyFolders.find();
      expect(folders.holds(p.join(root.path, 'tmp', 'movie.iso')), isFalse);
      expect(folders.holds(p.join(root.path, 'cache', 'scratch', 'telegrive-staging', 'a')), isTrue);
    });
  });
}
