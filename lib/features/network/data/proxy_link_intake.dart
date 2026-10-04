import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/proxy_link.dart';

/// A tg://proxy or tg://socks link tapped in another app (Android). The
/// activity holds it until Dart takes it, whether the tap started the app
/// or reached it while open; the app then offers it in the proxy sheet and
/// clears it. A link that isn't a usable proxy is dropped.
class ProxyLinkIntake extends Notifier<ProxyLink?> {
  static const _channel = MethodChannel('telegrive/links');

  @override
  ProxyLink? build() {
    if (kIsWeb || !Platform.isAndroid) return null;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'linkAvailable') await _take();
    });
    ref.onDispose(() => _channel.setMethodCallHandler(null));
    unawaited(_take());
    return null;
  }

  Future<void> _take() async {
    try {
      final text = await _channel.invokeMethod<String>('takeLink');
      final link = text == null ? null : ProxyLink.parse(text);
      if (link != null) state = link;
    } on PlatformException catch (e) {
      // Only the code: the link, secret included, stays out of the log.
      debugPrint('[Links] ${e.code}');
    }
  }

  /// Forgets the link once the sheet has it.
  void clear() => state = null;
}

final proxyLinkIntakeProvider = NotifierProvider<ProxyLinkIntake, ProxyLink?>(
  ProxyLinkIntake.new,
);
