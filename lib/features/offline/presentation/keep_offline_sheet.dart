import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../drive/domain/drive_models.dart';
import '../../transfers/data/transfer_policy.dart';
import '../data/offline_sync.dart';

/// What keeping a folder offline takes, before anything downloads: how many
/// files, how big, the room that needs, and whether the phone has it.
@immutable
class KeepOfflineEstimate {
  const KeepOfflineEstimate({
    required this.count,
    required this.bytes,
    required this.largest,
    required this.freeBytes,
    required this.android,
  });

  /// [items], the folder's files as they are now, against [freeBytes].
  factory KeepOfflineEstimate.of(
    List<SaveItem> items, {
    required int? freeBytes,
    required bool android,
  }) {
    var bytes = 0;
    var largest = 0;
    for (final item in items) {
      bytes += item.file.size;
      if (item.file.size > largest) largest = item.file.size;
    }
    return KeepOfflineEstimate(
      count: items.length,
      bytes: bytes,
      largest: largest,
      freeBytes: freeBytes,
      android: android,
    );
  }

  final int count;
  final int bytes;

  /// The biggest of the files.
  final int largest;

  /// Free space on this phone, or null when the phone didn't say.
  final int? freeBytes;

  /// On Android a copy kept offline is made from TDLib's download, so the
  /// file being copied is on the phone twice for a moment.
  final bool android;

  /// The room keeping the folder takes.
  int get needed => bytes + (android ? largest : 0);

  /// The phone hasn't the room, so Keep is off. Free space the phone didn't
  /// report never stops it.
  bool get tooBig => freeBytes != null && needed > freeBytes!;
}

/// Asks before a folder is kept offline, and says what it costs: the files
/// and their size, the room on this phone, and on mobile data how much of
/// it this uses. Only over Wi-Fi is the Offline screen's switch, for
/// everything kept offline. Pops true for Keep.
class KeepOfflineSheet extends ConsumerWidget {
  const KeepOfflineSheet({
    super.key,
    required this.folderName,
    required this.count,
    required this.bytes,
    required this.largest,
    required this.freeBytes,
  });

  final String folderName;
  final int count;
  final int bytes;
  final int largest;
  final int? freeBytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final estimate = KeepOfflineEstimate(
      count: count,
      bytes: bytes,
      largest: largest,
      freeBytes: freeBytes,
      android: Platform.isAndroid,
    );
    final free = estimate.freeBytes;
    final wifiOnly = ref.watch(offlineSyncProvider);
    final network = ref.watch(networkStatusProvider);
    final String? onData;
    if (!network.metered) {
      onData = null;
    } else if (wifiOnly) {
      onData = 'You\'re on mobile data. It downloads once the phone is on Wi-Fi.';
    } else if (TransferPolicy.shouldAsk(network: network, bytes: bytes)) {
      onData = 'You\'re on mobile data. This uses ${Formatters.bytes(bytes)} of it.';
    } else {
      onData = null;
    }
    final small = context.text.bodySmall?.copyWith(fontFeatures: tabularFigures);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Keep "$folderName" on this phone?', style: context.text.titleMedium),
            const SizedBox(height: 2),
            Text(
              '${Formatters.count(count, 'file')} · ${Formatters.bytes(bytes)}',
              style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
            ),
            const SizedBox(height: Space.l),
            Text('New files added to it later follow on their own.', style: context.text.bodyMedium),
            const SizedBox(height: Space.s),
            if (free != null)
              Text(
                estimate.tooBig
                    ? 'Not enough space: this needs ${Formatters.bytes(estimate.needed)} '
                          'and the phone has ${Formatters.bytes(free)} free.'
                    : '${Formatters.bytes(free)} free on this phone',
                style: small?.copyWith(color: estimate.tooBig ? colors.danger : null),
              ),
            if (onData != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(onData, style: small?.copyWith(color: colors.text2)),
              ),
            const SizedBox(height: Space.s),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Only over Wi-Fi'),
              subtitle: const Text('For everything kept offline'),
              value: wifiOnly,
              onChanged: (on) => ref.read(offlineSyncProvider.notifier).setWifiOnly(on),
            ),
            const SizedBox(height: Space.l),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: FilledButton(
                    onPressed: estimate.tooBig ? null : () => Navigator.pop(context, true),
                    child: const Text('Keep'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
