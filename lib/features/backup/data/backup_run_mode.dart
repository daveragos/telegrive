import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where photo backup runs: in the app, or in the background job that
/// backs up while the phone charges with the app closed.
enum BackupRunMode {
  app,

  /// The job's own engine. Backup runs the one pass the job asks for and
  /// no other, and the transfer queue sends only backup's own uploads,
  /// leaving the person's transfers for the app.
  background,
}

/// The mode this container runs backup in. The background job overrides
/// it with [BackupRunMode.background].
final backupRunModeProvider = Provider<BackupRunMode>((ref) => BackupRunMode.app);
