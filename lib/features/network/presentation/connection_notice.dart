import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../home/presentation/drive_health.dart';
import '../data/connection_health.dart';
import '../data/proxies.dart';
import 'proxy_sheet.dart';

/// Says that Telegram can't be reached on this network and offers a proxy,
/// on the screens before the drive opens; Home says the same in its own
/// first line. It is a state rather than a failure, so it is grey, and it
/// goes the moment Telegram connects.
class ConnectionNotice extends ConsumerWidget {
  const ConnectionNotice({super.key, this.margin = EdgeInsets.zero, this.timedOut = false});

  /// Space around the notice while it shows; none is taken while it doesn't.
  final EdgeInsetsGeometry margin;

  /// The screen's own request to Telegram already timed out, which is
  /// waiting enough, so the notice shows while Telegram is still connecting
  /// without waiting out the tracker's clock.
  final bool timedOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracked = ref.watch(connectionHealthProvider);
    final health = timedOut && tracked == ConnectionHealth.ok
        ? healthAfterWaiting(ref.watch(connectionStateProvider).value)
        : tracked;
    final line = describeConnection(
      health,
      proxy: health == ConnectionHealth.proxyStuck ? ref.watch(enabledProxyProvider)?.label : null,
    );
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: line == null
          ? const SizedBox(width: double.infinity)
          : ListGroup(
              margin: margin,
              children: [
                StatusLine(
                  icon: line.icon,
                  text: line.text,
                  detail: line.detail,
                  trailing: TextButton(
                    onPressed: () => showProxySheet(context),
                    child: Text(
                      line.action == HealthAction.changeProxy ? 'Change proxy' : 'Use a proxy',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
