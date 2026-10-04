import 'package:flutter/foundation.dart';
import 'package:handy_tdlib/api.dart' as td;

/// The two kinds of proxy Telegram links carry.
enum ProxyKind {
  mtproto('MTProto'),
  socks5('SOCKS5');

  const ProxyKind(this.label);

  final String label;
}

/// A proxy as a link or the manual form describes it, before Telegram has
/// seen it. Its secret and password are passed on to TDLib and nowhere
/// else: nothing here prints them.
@immutable
class ProxyLink {
  const ProxyLink(
    this.server,
    this.port,
    this.kind, {
    this.secret,
    this.username,
    this.password,
  });

  final String server;
  final int port;
  final ProxyKind kind;

  /// MTProto only, and required there. TDLib checks its format, so any
  /// encoding Telegram accepts goes through as it was given.
  final String? secret;

  /// SOCKS5 only, and optional.
  final String? username;
  final String? password;

  /// A proxy from typed details, or null when they don't describe one: no
  /// server, a port outside 1 to 65535, or an MTProto proxy without its
  /// secret. Surrounding spaces are dropped; empty optional fields are
  /// left out.
  static ProxyLink? from({
    required ProxyKind kind,
    required String? server,
    required String? port,
    String? secret,
    String? username,
    String? password,
  }) {
    final host = server?.trim() ?? '';
    final number = int.tryParse(port?.trim() ?? '');
    if (host.isEmpty || number == null || number < 1 || number > 65535) return null;
    String? present(String? value) {
      final trimmed = value?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    }

    switch (kind) {
      case ProxyKind.mtproto:
        final key = present(secret);
        if (key == null) return null;
        return ProxyLink(host, number, kind, secret: key);
      case ProxyKind.socks5:
        return ProxyLink(
          host,
          number,
          kind,
          username: present(username),
          password: present(password),
        );
    }
  }

  /// Reads a tg://proxy, tg://socks, t.me/proxy or t.me/socks link, with or
  /// without http(s) in front of t.me, or returns null for anything else.
  /// Values are percent-decoded the way Telegram decodes them, so a plus
  /// sign in a secret stays a plus sign.
  static ProxyLink? parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final withScheme = trimmed.toLowerCase().startsWith('t.me/') ? 'https://$trimmed' : trimmed;
    final Uri uri;
    try {
      uri = Uri.parse(withScheme);
    } on FormatException {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final String? place = switch (scheme) {
      'tg' when uri.path.isEmpty || uri.path == '/' => host,
      'http' || 'https' when host == 't.me' => uri.path.toLowerCase().replaceAll('/', ''),
      _ => null,
    };
    final kind = switch (place) {
      'proxy' => ProxyKind.mtproto,
      'socks' => ProxyKind.socks5,
      _ => null,
    };
    if (kind == null) return null;
    final values = _query(uri.query);
    if (values == null) return null;
    return from(
      kind: kind,
      server: values['server'],
      port: values['port'],
      secret: values['secret'],
      username: values['user'],
      password: values['pass'],
    );
  }

  /// The query's values, decoded without turning a plus into a space, or
  /// null when one of them is badly encoded. The first of a repeated key
  /// counts.
  static Map<String, String>? _query(String query) {
    final values = <String, String>{};
    for (final pair in query.split('&')) {
      if (pair.isEmpty) continue;
      final at = pair.indexOf('=');
      final key = at < 0 ? pair : pair.substring(0, at);
      final value = at < 0 ? '' : pair.substring(at + 1);
      try {
        values.putIfAbsent(Uri.decodeComponent(key), () => Uri.decodeComponent(value));
      } on ArgumentError {
        return null;
      } on FormatException {
        return null;
      }
    }
    return values;
  }

  /// How the proxy is shown: its server and port.
  String get label => proxyLabel(server, port);

  /// What TDLib's AddProxy takes for this proxy.
  td.ProxyType toTd() => switch (kind) {
    ProxyKind.mtproto => td.ProxyTypeMtproto(secret: secret!),
    ProxyKind.socks5 => td.ProxyTypeSocks5(
      username: username ?? '',
      password: password ?? '',
    ),
  };
}

/// 'host:port', with an IPv6 address in brackets so the port stays apart.
String proxyLabel(String server, int port) =>
    server.contains(':') ? '[$server]:$port' : '$server:$port';
