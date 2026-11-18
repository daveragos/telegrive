import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../../infrastructure/storage/app_dirs.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/domain/drive_models.dart';
import '../../player/data/stream_server.dart';
import '../../transfers/data/transfer_queue.dart';
import 'dav_tree.dart';
import 'dav_xml.dart';

/// The drive as a WebDAV server on this computer's loopback address, for
/// Finder, File Explorer or a Linux file manager to mount as a disk, and
/// for VLC, Kodi or rclone to read.
///
/// It listens on 127.0.0.1 alone, on a port kept from one start to the
/// next, and everything is under a random token kept with it, so a mount
/// or a saved address still works after a restart: the drive is
/// `/<token>/Telegrive/`, which the systems name the disk after. Paths are
/// read from the drive's index ([davEntries] names each folder's contents
/// uniquely); Private and Trash stay out.
///
/// * Reading goes through [StreamServer.serve], ranges and split files
///   included, fetched from Telegram as it is read.
/// * A file written in is kept in the app's scratch folder, shown where it
///   was put, and goes up as an ordinary upload once the system has
///   stopped writing it for a few seconds. One written over a drive file
///   replaces it, and the file before goes to Trash. An empty file is
///   shown but never sent.
/// * New folders, renames and moves become the drive's own; a delete
///   sends to Trash, where everything stays for 30 days.
/// * What the system and apps leave behind ([davJunk]) is kept here and
///   shown back to them, and never reaches the drive.
/// * Locks are kept in memory and bind nothing; they are there because
///   Finder and Explorer won't write without them. Copying within the
///   drive isn't offered.
class DavServer {
  DavServer(this._ref, {this.settleFor = const Duration(seconds: 3)});

  final Ref _ref;

  /// The disk's name, and the last part of its address.
  static const String volume = 'Telegrive';

  /// How long a written file stays still before it goes up: Explorer writes
  /// an empty file first and the bytes a moment later, and both systems
  /// set times and drop their lock after.
  final Duration settleFor;

  static const String _allow = 'OPTIONS, GET, HEAD, PUT, DELETE, MKCOL, MOVE, PROPFIND, PROPPATCH, LOCK, UNLOCK';
  static const Duration _lockTimeout = Duration(hours: 1);

  HttpServer? _server;
  String? _token;

  /// Files written in that haven't landed in the drive yet, by
  /// [_stagedKey].
  final Map<String, _Staged> _staged = {};

  /// What the system and apps left behind, by [_pathKey].
  final Map<String, _Junk> _junk = {};

  final Map<String, String> _locks = {};

  DriveRepository get _repository => _ref.read(driveRepositoryProvider);
  TransferQueue get _queue => _ref.read(transferQueueProvider.notifier);
  Preferences get _prefs => _ref.read(preferencesProvider);

  bool get running => _server != null;

  /// Where the drive is served, while the server runs.
  Uri? get address {
    final server = _server;
    final token = _token;
    if (server == null || token == null) return null;
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: [token, volume, ''],
    );
  }

  /// Starts serving, on the port and under the token of last time when the
  /// port is free, and answers the drive's address.
  Future<Uri> start() async {
    if (_server == null) {
      final token = _token = _prefs.davToken ?? _randomToken();
      if (_prefs.davToken == null) await _prefs.setDavToken(token);
      final kept = _prefs.davPort;
      HttpServer server;
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, kept ?? 0);
      } on SocketException {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      }
      if (server.port != kept) await _prefs.setDavPort(server.port);
      server.autoCompress = false;
      server.listen((request) => unawaited(_handle(request)));
      _server = server;
    }
    return address!;
  }

  /// Stops serving. Files written in and not yet sent are dropped.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    for (final staged in [..._staged.values]) {
      if (staged.transferId == null) await _drop(staged);
    }
    await server?.close(force: true);
  }

  // ---------------------------------------------------------------------------
  // Requests
  // ---------------------------------------------------------------------------

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers
      ..set('DAV', '1, 2')
      ..set('MS-Author-Via', 'DAV');
    var closed = false;
    try {
      if (request.method == 'OPTIONS') {
        response.headers.set('Allow', _allow);
        return;
      }
      final segments = [for (final s in request.uri.pathSegments) if (s.isNotEmpty) s];
      // Explorer looks at the levels above the drive before mounting it;
      // they hold nothing but the way down, and the top not even that.
      if (segments.length < 2) {
        if (request.method != 'PROPFIND' || (segments.isNotEmpty && segments.first != _token)) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        final top = segments.isEmpty ? '/' : '/$_token/';
        final now = DateTime.now();
        return await _multistatus(response, [
          DavResource(href: top, name: '', collection: true, modified: now, created: now),
          if (segments.isNotEmpty && request.headers.value('depth') != '0')
            DavResource(href: '$top$volume/', name: volume, collection: true, modified: now, created: now),
        ]);
      }
      if (segments[0] != _token || segments[1] != volume) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (_ref.read(driveSessionProvider) == null) {
        response
          ..statusCode = HttpStatus.serviceUnavailable
          ..headers.set(HttpHeaders.retryAfterHeader, '10');
        return;
      }
      final path = segments.sublist(2);
      switch (request.method) {
        case 'PROPFIND':
          await _propfind(request, path);
        case 'GET' || 'HEAD':
          closed = await _get(request, path);
        case 'PUT':
          await _put(request, path);
        case 'MKCOL':
          await _mkcol(request, path);
        case 'DELETE':
          await _delete(request, path);
        case 'MOVE':
          await _move(request, path);
        case 'LOCK':
          await _lock(request, path);
        case 'UNLOCK':
          await _unlock(request, path);
        case 'PROPPATCH':
          await _proppatch(request, path);
        default:
          response
            ..statusCode = HttpStatus.notImplemented
            ..headers.set('Allow', _allow);
      }
    } on DriveException catch (e) {
      response.statusCode = HttpStatus.conflict;
      response.write(e.message);
    } catch (e, stack) {
      if (e is! HttpException && e is! SocketException) {
        debugPrint('[Dav] ${request.method} ${request.uri.path}: $e\n$stack');
        try {
          response.statusCode = HttpStatus.internalServerError;
        } catch (_) {}
      }
    } finally {
      if (!closed) {
        try {
          await response.close();
        } catch (_) {}
      }
    }
  }

  Future<void> _propfind(HttpRequest request, List<String> path) async {
    final node = await _resolve(path);
    if (node is _Absent) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    final resources = [_resource(node, path)];
    if (request.headers.value('depth') != '0' && _isFolder(node)) {
      resources.addAll(await _children(node, path));
    }
    await _multistatus(request.response, resources);
  }

  /// Answers [path] as a file, or a folder's listing as a page; true when
  /// the stream server has closed the response itself.
  Future<bool> _get(HttpRequest request, List<String> path) async {
    final node = await _resolve(path);
    switch (node) {
      case _FileNode(:final file):
        await _ref.read(streamServerProvider).serve(request, file);
        return true;
      case _StagedNode(:final staged):
        await _serveLocal(request, staged.file, lookupMimeType(staged.name));
      case _JunkNode(:final junk) when junk.file != null:
        await _serveLocal(request, junk.file!, null);
      case _Absent():
        request.response.statusCode = HttpStatus.notFound;
      default:
        await _index(request, node, path);
    }
    return false;
  }

  Future<void> _put(HttpRequest request, List<String> path) async {
    final response = request.response;
    final node = await _resolve(path);
    switch (node) {
      case _Absent(parentMissing: true):
        response.statusCode = HttpStatus.conflict;
      case _Top() || _FolderNode() || _JunkNode(junk: _Junk(file: null)):
        response.statusCode = HttpStatus.methodNotAllowed;
      case _Absent(junk: true) || _JunkNode():
        final file = await _scratchFile(path.last);
        await request.cast<List<int>>().pipe(file.openWrite());
        final key = _pathKey(path);
        final old = _junk[key];
        _junk[key] = _Junk(path.last, file, modified: DateTime.now());
        await _deleteQuietly(old?.file);
        response.statusCode = node is _Absent ? HttpStatus.created : HttpStatus.noContent;
      case _FileNode(:final file, :final parentId):
        // Written over: the new bytes go up in the drive file's place.
        await _stage(request, parentId: parentId, name: file.name, replaces: file.id);
        response.statusCode = HttpStatus.noContent;
      case _StagedNode(:final staged):
        await _stage(request, parentId: staged.parentId, name: staged.name, replaces: staged.replaces);
        response.statusCode = HttpStatus.noContent;
      case _Absent(:final parentId, :final name):
        await _stage(request, parentId: parentId, name: name);
        response.statusCode = HttpStatus.created;
    }
  }

  Future<void> _mkcol(HttpRequest request, List<String> path) async {
    final response = request.response;
    final node = await _resolve(path);
    switch (node) {
      case _Absent(parentMissing: true):
        response.statusCode = HttpStatus.conflict;
      case _Absent(junk: true):
        _junk[_pathKey(path)] = _Junk(path.last, null, modified: DateTime.now());
        response.statusCode = HttpStatus.created;
      case _Absent(:final parentId, :final name):
        await _repository.createFolder(name, parentId: parentId);
        response.statusCode = HttpStatus.created;
      default:
        response.statusCode = HttpStatus.methodNotAllowed;
    }
  }

  Future<void> _delete(HttpRequest request, List<String> path) async {
    final node = await _resolve(path);
    final response = request.response;
    if (node is _Absent) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    if (node is _Top) {
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    await _remove(node, path);
    response.statusCode = HttpStatus.noContent;
  }

  /// Takes [node] away: to Trash from the drive, and for good from here.
  Future<void> _remove(_Node node, List<String> path) async {
    switch (node) {
      case _FileNode(:final file):
        await _repository.trash(files: [file]);
      case _FolderNode(:final folder):
        await _repository.trash(folders: [folder]);
      case _StagedNode(:final staged):
        _staged.remove(staged.key);
        await _drop(staged);
      case _JunkNode():
        final key = _pathKey(path);
        for (final k in [..._junk.keys]) {
          if (k == key || k.startsWith('$key/')) await _deleteQuietly(_junk.remove(k)?.file);
        }
      case _Top() || _Absent():
    }
  }

  Future<void> _move(HttpRequest request, List<String> path) async {
    final response = request.response;
    final destination = _destinationOf(request);
    if (destination == null) {
      response.statusCode = HttpStatus.badGateway;
      return;
    }
    final source = await _resolve(path);
    if (source is _Absent) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    if (source is _Top || destination.isEmpty) {
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    var target = await _resolve(destination);
    if (target is _Absent && target.parentMissing) {
      response.statusCode = HttpStatus.conflict;
      return;
    }
    final existed = target is! _Absent && !_same(source, target);
    if (existed) {
      if (request.headers.value('overwrite')?.toUpperCase() == 'F') {
        response.statusCode = HttpStatus.preconditionFailed;
        return;
      }
      await _remove(target, destination);
      target = await _resolve(destination);
    }
    final name = destination.last;
    final parentId = switch (target) {
      _Absent(:final parentId) => parentId,
      _FileNode(:final parentId) || _FolderNode(:final parentId) => parentId,
      _StagedNode(:final staged) => staged.parentId,
      _ => null,
    };
    final intoJunk = target is _JunkNode || (target is _Absent && target.junk);
    switch (source) {
      case _FileNode(:final file, parentId: final from):
        if (target is _Absent && target.parentIsJunk) return _forbid(response);
        if (from == parentId) {
          await _repository.renameFile(file, name);
        } else {
          await _repository.moveFiles([file], parentId, renames: name == file.name ? const {} : {file.id: name});
        }
      case _FolderNode(:final folder, parentId: final from):
        if (intoJunk) return _forbid(response);
        if (from != parentId) await _repository.moveFolder(folder, parentId);
        if (name != folder.name) {
          final moved = await _repository.folderById(folder.id) ?? folder;
          await _repository.renameFolder(moved, name);
        }
      case _StagedNode(:final staged):
        if (staged.transferId != null) {
          response.statusCode = HttpStatus.locked;
          return;
        }
        _staged.remove(staged.key);
        if (intoJunk) {
          staged.timer?.cancel();
          _junk[_pathKey(destination)] = _Junk(name, staged.file, modified: staged.modified);
        } else {
          staged
            ..parentId = parentId
            ..name = name;
          _staged[staged.key] = staged;
          _settle(staged);
        }
      case _JunkNode(:final junk):
        final from = _pathKey(path);
        if (intoJunk) {
          final to = _pathKey(destination);
          for (final k in [..._junk.keys]) {
            if (k != from && !k.startsWith('$from/')) continue;
            final moved = _junk.remove(k)!;
            _junk['$to${k.substring(from.length)}'] = k == from ? _Junk(name, moved.file, modified: moved.modified) : moved;
          }
        } else if (junk.file case final file?) {
          // An app saving through a temporary file renames it into place,
          // which is when it becomes the person's.
          _junk.remove(from);
          final staged = _Staged(parentId: parentId, name: name, file: file, size: await file.length(), modified: DateTime.now());
          _staged[staged.key] = staged;
          _settle(staged);
        } else {
          return _forbid(response);
        }
      case _Top() || _Absent():
    }
    response.statusCode = existed ? HttpStatus.noContent : HttpStatus.created;
  }

  Future<void> _lock(HttpRequest request, List<String> path) async {
    final response = request.response;
    final body = await utf8.decoder.bind(request).join();
    final key = _pathKey(path);
    var node = await _resolve(path);
    var created = false;
    if (node is _Absent) {
      if (node.parentMissing) {
        response.statusCode = HttpStatus.conflict;
        return;
      }
      // Locking a name that isn't there yet makes an empty file of it,
      // which the write that follows fills.
      if (node.junk) {
        _junk[key] = _Junk(path.last, await _scratchFile(path.last, create: true), modified: DateTime.now());
      } else {
        final file = await _scratchFile(node.name, create: true);
        final staged = _Staged(parentId: node.parentId, name: node.name, file: file, size: 0, modified: DateTime.now());
        _staged[staged.key] = staged;
      }
      created = true;
      node = await _resolve(path);
    }
    if (node is _StagedNode) node.staged.timer?.cancel();
    final token = body.trim().isEmpty && _locks[key] != null ? _locks[key]! : 'opaquelocktoken:${_repository.newId()}';
    _locks[key] = token;
    response
      ..statusCode = created ? HttpStatus.created : HttpStatus.ok
      ..headers.set('Lock-Token', '<$token>')
      ..headers.contentType = ContentType('application', 'xml', charset: 'utf-8')
      ..write(davLock(href: _href(path, folder: _isFolder(node)), token: token, timeout: _lockTimeout, owner: davLockOwner(body)));
  }

  Future<void> _unlock(HttpRequest request, List<String> path) async {
    _locks.remove(_pathKey(path));
    final node = await _resolve(path);
    if (node is _StagedNode) _settle(node.staged);
    request.response.statusCode = HttpStatus.noContent;
  }

  Future<void> _proppatch(HttpRequest request, List<String> path) async {
    final body = await utf8.decoder.bind(request).join();
    final node = await _resolve(path);
    if (node is _Absent) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    if (node is _StagedNode) _settle(node.staged);
    request.response
      ..statusCode = 207
      ..headers.contentType = ContentType('application', 'xml', charset: 'utf-8')
      ..write(davProppatch(_href(path, folder: _isFolder(node)), body));
  }

  // ---------------------------------------------------------------------------
  // Files written in
  // ---------------------------------------------------------------------------

  /// Keeps what [request] writes as [name] in [parentId], the top of the
  /// drive when null, in place of anything written there before, and sends
  /// it up once it settles, in place of drive file [replaces] when given.
  Future<void> _stage(HttpRequest request, {required String? parentId, required String name, String? replaces}) async {
    final file = await _scratchFile(name);
    await request.cast<List<int>>().pipe(file.openWrite());
    final staged = _Staged(parentId: parentId, name: name, file: file, size: await file.length(), modified: DateTime.now(), replaces: replaces);
    final old = _staged[staged.key];
    _staged[staged.key] = staged;
    if (old != null) await _drop(old);
    _settle(staged);
  }

  void _settle(_Staged staged) {
    staged.timer?.cancel();
    if (staged.transferId != null) return;
    staged.timer = Timer(settleFor, () => unawaited(_send(staged)));
  }

  /// Sends [staged] up, and lets go of it once its upload has ended, by
  /// when the drive shows the file, or Transfers says why it couldn't.
  Future<void> _send(_Staged staged) async {
    if (staged.size == 0 || staged.transferId != null || !identical(_staged[staged.key], staged)) return;
    try {
      final ids = await _queue.enqueueUploads([
        UploadRequest(
          name: staged.name,
          path: staged.file.path,
          size: staged.size,
          ownsSource: true,
          replacesFileId: staged.replaces,
        ),
      ], folderId: staged.parentId);
      if (ids.isEmpty) return;
      staged.transferId = ids.single;
      await _queue.whenFinished(ids.single);
    } catch (e) {
      debugPrint('[Dav] ${staged.name}: $e');
    }
    if (identical(_staged[staged.key], staged)) _staged.remove(staged.key);
    await _deleteDir(staged.file.parent);
  }

  /// Forgets [staged]: its upload is cancelled, and its copy deleted.
  Future<void> _drop(_Staged staged) async {
    staged.timer?.cancel();
    if (staged.transferId case final id?) {
      await _queue.cancel(id);
    } else {
      await _deleteDir(staged.file.parent);
    }
  }

  /// A new file in a folder of its own in the scratch folder, named
  /// [name], so a copy that goes up shows that name in Telegram too.
  Future<File> _scratchFile(String name, {bool create = false}) async {
    final dir = Directory(p.join((await scratchDirectory()).path, 'dav', _repository.newId()));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, DeviceStorage.safeName(name)));
    if (create) await file.create();
    return file;
  }

  static Future<void> _deleteQuietly(File? file) async {
    try {
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> _deleteDir(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Paths
  // ---------------------------------------------------------------------------

  /// What [path] below the drive's top is, walking down the index by the
  /// names [davEntries] gives.
  Future<_Node> _resolve(List<String> path) async {
    String? folderId;
    var inJunk = false;
    for (var i = 0; i < path.length; i++) {
      final name = path[i];
      final last = i == path.length - 1;
      final key = _pathKey(path.sublist(0, i + 1));
      if (inJunk || davJunk(name)) {
        final junk = _junk[key];
        if (last) {
          return junk == null
              ? _Absent(parentId: folderId, name: name, junk: true, parentIsJunk: inJunk)
              : _JunkNode(junk);
        }
        if (junk == null || junk.file != null) return _Absent(parentId: folderId, name: name, parentMissing: true);
        inJunk = true;
        continue;
      }
      final entries = await _entries(folderId);
      final lower = name.toLowerCase();
      final entry = entries.where((e) => e.name.toLowerCase() == lower).firstOrNull;
      if (last) {
        if (entry?.folder case final folder?) return _FolderNode(folder, parentId: folderId);
        if (entry?.file case final file?) return _FileNode(file, parentId: folderId);
        final staged = _staged[_Staged.keyOf(folderId, name)];
        if (staged != null) return _StagedNode(staged);
        return _Absent(parentId: folderId, name: name);
      }
      final folder = entry?.folder;
      if (folder == null) return _Absent(parentId: folderId, name: name, parentMissing: true);
      folderId = folder.id;
    }
    return const _Top();
  }

  Future<List<DavEntry>> _entries(String? folderId) async {
    final contents = await _repository.watchFolder(folderId).first;
    return davEntries(contents.folders, contents.files);
  }

  /// What a PROPFIND of a folder lists below it: its drive entries, files
  /// written in that haven't landed, and what the system left there.
  Future<List<DavResource>> _children(_Node node, List<String> path) async {
    final resources = <DavResource>[];
    final key = _pathKey(path);
    final names = <String>{};
    if (node case _Top() || _FolderNode()) {
      final folderId = node is _FolderNode ? node.folder.id : null;
      for (final entry in await _entries(folderId)) {
        names.add(entry.name.toLowerCase());
        final child = [...path, entry.name];
        resources.add(_resource(entry.isFolder ? _FolderNode(entry.folder!) : _FileNode(entry.file!), child));
      }
      for (final staged in _staged.values) {
        if (staged.parentId != folderId || !names.add(staged.name.toLowerCase())) continue;
        resources.add(_resource(_StagedNode(staged), [...path, staged.name]));
      }
    }
    for (final MapEntry(key: k, value: junk) in _junk.entries) {
      final parent = k.contains('/') ? k.substring(0, k.lastIndexOf('/')) : '';
      if (parent != key) continue;
      resources.add(_resource(_JunkNode(junk), [...path, junk.name]));
    }
    return resources;
  }

  DavResource _resource(_Node node, List<String> path) {
    final href = _href(path, folder: _isFolder(node));
    final name = path.isEmpty ? volume : path.last;
    return switch (node) {
      _Top() => DavResource(
        href: href,
        name: name,
        collection: true,
        modified: DateTime.now(),
        created: DateTime.now(),
        quota: true,
      ),
      _FolderNode(:final folder) => DavResource(
        href: href,
        name: name,
        collection: true,
        modified: folder.modifiedAt,
        created: folder.createdAt,
        etag: 'd-${folder.id}-${folder.modifiedAt.millisecondsSinceEpoch}',
      ),
      _FileNode(:final file) => DavResource(
        href: href,
        name: name,
        collection: false,
        size: file.size,
        modified: file.modifiedAt,
        created: file.createdAt,
        contentType: file.mimeType,
        etag: 'f-${file.id}-${file.modifiedAt.millisecondsSinceEpoch}',
      ),
      _StagedNode(:final staged) => DavResource(
        href: href,
        name: name,
        collection: false,
        size: staged.size,
        modified: staged.modified,
        created: staged.modified,
        contentType: lookupMimeType(staged.name),
        etag: 's-${staged.modified.microsecondsSinceEpoch}',
      ),
      _JunkNode(:final junk) => DavResource(
        href: href,
        name: name,
        collection: junk.file == null,
        size: junk.file?.lengthSync() ?? 0,
        modified: junk.modified,
        created: junk.modified,
      ),
      _Absent() => DavResource(href: href, name: name, collection: false, modified: DateTime.now(), created: DateTime.now()),
    };
  }

  static bool _isFolder(_Node node) => switch (node) {
    _Top() || _FolderNode() => true,
    _JunkNode(:final junk) => junk.file == null,
    _ => false,
  };

  static bool _same(_Node a, _Node b) => switch ((a, b)) {
    (_FileNode(file: final x), _FileNode(file: final y)) => x.id == y.id,
    (_FolderNode(folder: final x), _FolderNode(folder: final y)) => x.id == y.id,
    (_StagedNode(staged: final x), _StagedNode(staged: final y)) => identical(x, y),
    (_JunkNode(junk: final x), _JunkNode(junk: final y)) => identical(x, y),
    _ => false,
  };

  String _href(List<String> path, {required bool folder}) {
    final segments = [_token!, volume, ...path];
    return '/${segments.map(Uri.encodeComponent).join('/')}${folder ? '/' : ''}';
  }

  /// The path below the drive's top that a MOVE's Destination names, or
  /// null for one on another server or outside the drive.
  List<String>? _destinationOf(HttpRequest request) {
    final header = request.headers.value('destination');
    if (header == null) return null;
    final uri = Uri.tryParse(header);
    if (uri == null) return null;
    if (uri.hasAuthority && uri.port != _server?.port) return null;
    final segments = [for (final s in uri.pathSegments) if (s.isNotEmpty) s];
    if (segments.length < 2 || segments[0] != _token || segments[1] != volume) return null;
    return segments.sublist(2);
  }

  static String _pathKey(List<String> path) => path.map((s) => s.toLowerCase()).join('/');

  // ---------------------------------------------------------------------------
  // Answers
  // ---------------------------------------------------------------------------

  static Future<void> _multistatus(HttpResponse response, List<DavResource> resources) async {
    response
      ..statusCode = 207
      ..headers.contentType = ContentType('application', 'xml', charset: 'utf-8')
      ..write(davMultistatus(resources));
  }

  static void _forbid(HttpResponse response) => response.statusCode = HttpStatus.forbidden;

  /// Answers a GET or HEAD for [file] on this computer, a range of it when
  /// one is asked for.
  static Future<void> _serveLocal(HttpRequest request, File file, String? contentType) async {
    final response = request.response;
    final total = await file.length();
    var start = 0;
    var end = total - 1;
    final range = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    if (range != null && total > 0) {
      final from = int.tryParse(range[1]!);
      final to = int.tryParse(range[2]!);
      if (from != null) {
        start = from;
        if (to != null) end = math.min(to, total - 1);
      } else if (to != null) {
        start = math.max(0, total - to);
      }
      if (start > end) {
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        return;
      }
      response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
    }
    response.headers
      ..contentType = ContentType.parse(contentType ?? 'application/octet-stream')
      ..contentLength = total == 0 ? 0 : end - start + 1
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (request.method == 'HEAD' || total == 0) return;
    await response.addStream(file.openRead(start, end + 1));
  }

  /// A plain page listing a folder, for a browser pointed at the address.
  Future<void> _index(HttpRequest request, _Node node, List<String> path) async {
    final children = await _children(node, path);
    const escape = HtmlEscape();
    final title = escape.convert(path.isEmpty ? volume : path.last);
    final items = [
      for (final r in children)
        '<li><a href="${escape.convert(r.href)}">${escape.convert(r.name)}${r.collection ? '/' : ''}</a></li>',
    ];
    request.response
      ..headers.contentType = ContentType.html
      ..write('<!doctype html><meta charset="utf-8"><title>$title</title><h1>$title</h1><ul>${items.join()}</ul>');
  }

  static String _randomToken() {
    final random = math.Random.secure();
    return base64Url.encode(List.generate(18, (_) => random.nextInt(256))).replaceAll('=', '');
  }
}

final davServerProvider = Provider<DavServer>((ref) {
  final server = DavServer(ref);
  ref.onDispose(() => unawaited(server.stop()));
  return server;
});

/// A file written in that hasn't landed in the drive yet.
class _Staged {
  _Staged({
    required this.parentId,
    required this.name,
    required this.file,
    required this.size,
    required this.modified,
    this.replaces,
  });

  String? parentId;
  String name;
  final File file;
  final int size;
  final DateTime modified;

  /// The drive file it goes up in place of.
  final String? replaces;
  Timer? timer;

  /// Its upload, once queued.
  String? transferId;

  String get key => keyOf(parentId, name);
  static String keyOf(String? parentId, String name) => '${parentId ?? ''}/${name.toLowerCase()}';
}

/// What the system or an app left behind, under [name]: a file, or a
/// folder when [file] is null.
class _Junk {
  _Junk(this.name, this.file, {required this.modified});

  final String name;
  final File? file;
  final DateTime modified;
}

sealed class _Node {
  const _Node();
}

class _Top extends _Node {
  const _Top();
}

class _FolderNode extends _Node {
  const _FolderNode(this.folder, {this.parentId});
  final DriveFolder folder;

  /// The folder it shows in, which may not be the one it names when that
  /// one is gone.
  final String? parentId;
}

class _FileNode extends _Node {
  const _FileNode(this.file, {this.parentId});
  final DriveFile file;
  final String? parentId;
}

class _StagedNode extends _Node {
  const _StagedNode(this.staged);
  final _Staged staged;
}

class _JunkNode extends _Node {
  const _JunkNode(this.junk);
  final _Junk junk;
}

/// Nothing at a path whose folder [parentId] is there, unless
/// [parentMissing]; [junk] when the name, or a folder above it, is one
/// [davJunk] keeps here.
class _Absent extends _Node {
  const _Absent({
    required this.parentId,
    required this.name,
    this.junk = false,
    this.parentIsJunk = false,
    this.parentMissing = false,
  });

  final String? parentId;
  final String name;
  final bool junk;
  final bool parentIsJunk;
  final bool parentMissing;
}
