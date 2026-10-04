import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../auth/presentation/auth_layout.dart';
import '../data/proxies.dart';
import '../domain/proxy_link.dart';

/// The proxy sheet: how Telegram is connected right now, a link or typed
/// details to connect through a new proxy, and the saved ones to switch
/// between. It opens on the root navigator, since the sign-in screens come
/// from the authorization state and can't be pushed to, and works there
/// before sign-in as well as after. With [prefill], a link someone tapped,
/// it first asks whether to connect through it; nothing connects without
/// that tap.
Future<void> showProxySheet(BuildContext context, {ProxyLink? prefill}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => ProxySheet(prefill: prefill),
    );

class ProxySheet extends ConsumerStatefulWidget {
  const ProxySheet({super.key, this.prefill});

  final ProxyLink? prefill;

  @override
  ConsumerState<ProxySheet> createState() => _ProxySheetState();
}

class _ProxySheetState extends ConsumerState<ProxySheet> {
  final _link = TextEditingController();
  final _server = TextEditingController();
  final _port = TextEditingController();
  final _secret = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  /// The tapped link still waiting for Connect or Not now.
  late ProxyLink? _offer = widget.prefill;
  bool _manual = false;
  ProxyKind _kind = ProxyKind.mtproto;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // After the first frame, once the list is being watched, so it is the
    // list the sheet shows that gets pinged.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(proxiesProvider.notifier).pingAll());
    });
  }

  @override
  void dispose() {
    for (final controller in [_link, _server, _port, _secret, _username, _password]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The proxy the typed details describe, or null while they are
  /// incomplete.
  ProxyLink? get _typed => ProxyLink.from(
    kind: _kind,
    server: _server.text,
    port: _port.text,
    secret: _secret.text,
    username: _username.text,
    password: _password.text,
  );

  /// A port that has been typed and can't be one.
  bool get _badPort {
    final port = int.tryParse(_port.text);
    return port != null && (port < 1 || port > 65535);
  }

  void _edited() => setState(() => _error = null);

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _link.text = text;
      _error = null;
    });
  }

  void _connectLink() {
    final link = ProxyLink.parse(_link.text);
    if (link == null) {
      setState(
        () => _error =
            'That isn\'t a proxy link. Proxy links start with tg://proxy, tg://socks '
            'or t.me/proxy.',
      );
      return;
    }
    unawaited(_connect(link));
  }

  Future<void> _connect(ProxyLink link) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(proxiesProvider.notifier).connect(link);
      if (!mounted) return;
      setState(() {
        _offer = null;
        for (final controller in [_link, _server, _port, _secret, _username, _password]) {
          controller.clear();
        }
      });
    } on TelegramException catch (e) {
      if (mounted) setState(() => _error = 'Telegram didn\'t accept this proxy: ${e.friendlyMessage}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Switches to the saved proxy [id], or to a direct connection for 0.
  Future<void> _switchTo(int id) => _change(() {
    final proxies = ref.read(proxiesProvider.notifier);
    return id == 0 ? proxies.useDirect() : proxies.enable(id);
  });

  Future<void> _change(Future<void> Function() change) async {
    setState(() => _error = null);
    try {
      await change();
    } on TelegramException catch (e) {
      if (mounted) setState(() => _error = e.friendlyMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    // TDLib answers nothing about proxies until it has its parameters.
    final ready = telegramConfigured(ref.watch(authStateProvider).value);
    final entries = ref.watch(proxiesProvider).value ?? const <ProxyEntry>[];
    final enabled = entries.where((p) => p.enabled).firstOrNull;
    final offer = _offer;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (offer != null) ...[
                _Offer(
                  link: offer,
                  busy: _busy,
                  error: _error,
                  onConnect: ready ? () => _connect(offer) : null,
                  onNotNow: () => Navigator.pop(context),
                ),
                const SizedBox(height: Space.xxl),
                const Divider(),
                const SizedBox(height: Space.l),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Proxy', style: context.text.titleMedium),
                    const SizedBox(height: Space.s),
                    Text(
                      'Connect through a proxy when Telegram is blocked or very slow here. '
                      'Telegram\'s encryption still applies; the proxy only passes '
                      'traffic along.',
                      style: context.text.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.s),
              _Status(connection: ref.watch(connectionStateProvider).value, proxy: enabled),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_manual) ..._details() else _linkField(),
                    if (offer == null) FormError(_error),
                    const SizedBox(height: Space.l),
                    BusyButton(
                      label: 'Connect',
                      busy: _busy && offer == null,
                      onPressed: !ready || _busy
                          ? null
                          : _manual
                          ? switch (_typed) {
                              final typed? => () => _connect(typed),
                              null => null,
                            }
                          : _link.text.trim().isEmpty
                          ? null
                          : _connectLink,
                    ),
                    const SizedBox(height: Space.xs),
                    TextButton(
                      onPressed: () => setState(() {
                        _manual = !_manual;
                        _error = null;
                      }),
                      child: Text(_manual ? 'Use a link instead' : 'Enter details instead'),
                    ),
                  ],
                ),
              ),
              const SectionHeader('Saved'),
              RadioGroup<int>(
                groupValue: enabled?.id ?? 0,
                onChanged: (id) {
                  if (id != null) unawaited(_switchTo(id));
                },
                child: ListGroup(
                  margin: EdgeInsets.zero,
                  children: [
                    const RadioListTile<int>(
                      value: 0,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text('Direct connection'),
                      subtitle: Text('No proxy'),
                    ),
                    for (final entry in entries)
                      RadioListTile<int>(
                        value: entry.id,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(entry.label),
                        subtitle: Text(
                          [entry.kind.label, ?_latency(entry.latency)].join(' · '),
                          style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                        ),
                        secondary: PopupMenuButton<void>(
                          tooltip: 'More',
                          icon: Icon(Icons.more_vert_rounded, color: context.colors.text3),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              onTap: () => _change(
                                () => ref.read(proxiesProvider.notifier).remove(entry.id),
                              ),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkField() => TextField(
    controller: _link,
    keyboardType: TextInputType.url,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: TextInputAction.go,
    onChanged: (_) => _edited(),
    onSubmitted: (_) => _connectLink(),
    decoration: InputDecoration(
      labelText: 'Proxy link',
      hintText: 'tg://proxy?server=…',
      suffixIcon: IconButton(
        onPressed: _paste,
        icon: const Icon(Icons.content_paste_rounded),
        tooltip: 'Paste',
      ),
    ),
  );

  List<Widget> _details() => [
    SegmentedButton<ProxyKind>(
      segments: [
        for (final kind in ProxyKind.values)
          ButtonSegment(value: kind, label: Text(kind.label)),
      ],
      selected: {_kind},
      showSelectedIcon: false,
      onSelectionChanged: (kinds) => setState(() {
        _kind = kinds.first;
        _error = null;
      }),
    ),
    const SizedBox(height: Space.m),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _server,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => _edited(),
            decoration: const InputDecoration(labelText: 'Server'),
          ),
        ),
        const SizedBox(width: Space.m),
        SizedBox(
          width: 112,
          child: TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => _edited(),
            style: const TextStyle(fontFeatures: tabularFigures),
            decoration: InputDecoration(
              labelText: 'Port',
              errorText: _badPort ? 'From 1 to 65535' : null,
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: Space.m),
    if (_kind == ProxyKind.mtproto)
      TextField(
        controller: _secret,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => _edited(),
        decoration: const InputDecoration(labelText: 'Secret'),
      )
    else ...[
      TextField(
        controller: _username,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => _edited(),
        decoration: const InputDecoration(labelText: 'Username (optional)'),
      ),
      const SizedBox(height: Space.m),
      TextField(
        controller: _password,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => _edited(),
        decoration: const InputDecoration(labelText: 'Password (optional)'),
      ),
    ],
  ];

  static String? _latency(ProxyLatency? latency) => switch (latency) {
    LatencyChecking() => 'Checking',
    LatencyMeasured(:final time) => Formatters.latency(time),
    LatencyFailed() => 'No answer',
    null => null,
  };
}

/// What a tapped link asks before anything connects: the proxy's address
/// and kind, Connect, and Not now, which closes the sheet.
class _Offer extends StatelessWidget {
  const _Offer({
    required this.link,
    required this.busy,
    required this.error,
    required this.onConnect,
    required this.onNotNow,
  });

  final ProxyLink link;
  final bool busy;
  final String? error;
  final VoidCallback? onConnect;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Connect through this proxy?', style: context.text.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            '${link.label} · ${link.kind.label}',
            style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
          ),
          FormError(error),
          const SizedBox(height: Space.l),
          BusyButton(label: 'Connect', busy: busy, onPressed: onConnect),
          const SizedBox(height: Space.xs),
          TextButton(onPressed: busy ? null : onNotNow, child: const Text('Not now')),
        ],
      ),
    );
  }
}

/// How Telegram is connected right now, live: the accent only while it is
/// connecting.
class _Status extends StatelessWidget {
  const _Status({required this.connection, required this.proxy});

  final td.ConnectionState? connection;

  /// The proxy in use, or null for a direct connection.
  final ProxyEntry? proxy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return switch (connection) {
      td.ConnectionStateReady() || td.ConnectionStateUpdating() => StatusLine(
        icon: Icons.check_circle_outline_rounded,
        color: colors.success,
        text: 'Connected',
        detail: proxy == null ? 'Directly' : 'Through ${proxy!.label}',
      ),
      td.ConnectionStateWaitingForNetwork() => const StatusLine(
        icon: Icons.wifi_off_rounded,
        text: 'No internet connection',
      ),
      td.ConnectionStateConnectingToProxy() => StatusLine(
        icon: Icons.sync_rounded,
        color: colors.accent,
        text: 'Connecting to the proxy',
        progress: -1,
      ),
      _ => StatusLine(
        icon: Icons.sync_rounded,
        color: colors.accent,
        text: 'Connecting',
        progress: -1,
      ),
    };
  }
}
