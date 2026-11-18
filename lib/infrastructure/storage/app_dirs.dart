import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/platform/app_platform.dart';

/// Where the app makes its own short-lived copies: files staged for an
/// upload, split parts, thumbnails and the like, which the leftover sweep
/// clears when nothing needs them any more.
///
/// A phone gives each app a temporary folder of its own. A computer's
/// temporary folder is shared with every other app, and with files the
/// person keeps there, so the app keeps its copies in a folder inside its
/// own cache instead.
Future<Directory> scratchDirectory() async {
  if (!AppPlatform.isDesktop) return getTemporaryDirectory();
  final dir = Directory(p.join((await getApplicationCacheDirectory()).path, 'scratch'));
  await dir.create(recursive: true);
  return dir;
}
