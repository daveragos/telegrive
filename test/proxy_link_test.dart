import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/network/domain/proxy_link.dart';

void main() {
  /// A fake-TLS secret: ee, sixteen bytes of key, then the domain in hex.
  const fakeTls = 'ee0123456789abcdef0123456789abcdef676f6f676c652e636f6d';

  test('a tg://proxy link with a fake-TLS secret', () {
    final link = ProxyLink.parse('tg://proxy?server=1.2.3.4&port=443&secret=$fakeTls')!;
    expect(link.server, '1.2.3.4');
    expect(link.port, 443);
    expect(link.kind, ProxyKind.mtproto);
    expect(link.secret, fakeTls);
    expect(link.username, isNull);
    expect(link.label, '1.2.3.4:443');
    final type = link.toTd();
    expect(type, isA<td.ProxyTypeMtproto>());
    expect((type as td.ProxyTypeMtproto).secret, fakeTls);
  });

  test('a tg://socks link, with and without a login', () {
    final withLogin = ProxyLink.parse('tg://socks?server=proxy.example.org&port=1080&user=ana&pass=s3cret')!;
    expect(withLogin.kind, ProxyKind.socks5);
    expect(withLogin.server, 'proxy.example.org');
    expect(withLogin.port, 1080);
    expect(withLogin.username, 'ana');
    expect(withLogin.password, 's3cret');
    expect(withLogin.secret, isNull);
    final type = withLogin.toTd() as td.ProxyTypeSocks5;
    expect(type.username, 'ana');
    expect(type.password, 's3cret');

    final open = ProxyLink.parse('tg://socks?server=10.0.0.2&port=9050')!;
    expect(open.kind, ProxyKind.socks5);
    expect(open.username, isNull);
    expect(open.password, isNull);
    final openType = open.toTd() as td.ProxyTypeSocks5;
    expect(openType.username, '');
    expect(openType.password, '');
    expect(open.label, '10.0.0.2:9050');
  });

  test('t.me links, with https or bare', () {
    final https = ProxyLink.parse('https://t.me/proxy?server=5.6.7.8&port=8443&secret=dd00ff')!;
    expect(https.kind, ProxyKind.mtproto);
    expect(https.label, '5.6.7.8:8443');
    expect(https.secret, 'dd00ff');

    final http = ProxyLink.parse('http://t.me/socks?server=5.6.7.8&port=1080')!;
    expect(http.kind, ProxyKind.socks5);

    final bare = ProxyLink.parse('t.me/socks?server=example.net&port=1080&user=me')!;
    expect(bare.kind, ProxyKind.socks5);
    expect(bare.server, 'example.net');
    expect(bare.username, 'me');
    expect(bare.password, isNull);
  });

  test('percent-encoded values are decoded, and a plus stays a plus', () {
    final link = ProxyLink.parse(
      'tg://socks?server=proxy%2Eexample%2Eorg&port=1080&user=ana%20b&pass=p%40ss+word%26',
    )!;
    expect(link.server, 'proxy.example.org');
    expect(link.username, 'ana b');
    expect(link.password, 'p@ss+word&');

    final secret = ProxyLink.parse('tg://proxy?server=1.2.3.4&port=443&secret=7gAA%2B%2Fab+cd')!;
    expect(secret.secret, '7gAA+/ab+cd');
  });

  test('whitespace around the link is ignored', () {
    final link = ProxyLink.parse('  \n tg://proxy?server=1.2.3.4&port=443&secret=$fakeTls \t')!;
    expect(link.label, '1.2.3.4:443');
  });

  test('a link without its secret, server or port is not a proxy', () {
    expect(ProxyLink.parse('tg://proxy?server=1.2.3.4&port=443'), isNull);
    expect(ProxyLink.parse('tg://proxy?server=1.2.3.4&port=443&secret='), isNull);
    expect(ProxyLink.parse('tg://proxy?server=1.2.3.4&secret=$fakeTls'), isNull);
    expect(ProxyLink.parse('tg://socks?port=1080'), isNull);
    expect(ProxyLink.parse('tg://socks?server=&port=1080'), isNull);
  });

  test('a port outside 1 to 65535 is not a port', () {
    expect(ProxyLink.parse('tg://socks?server=1.2.3.4&port=0'), isNull);
    expect(ProxyLink.parse('tg://socks?server=1.2.3.4&port=70000'), isNull);
    expect(ProxyLink.parse('tg://socks?server=1.2.3.4&port=-1'), isNull);
    expect(ProxyLink.parse('tg://socks?server=1.2.3.4&port=http'), isNull);
    expect(ProxyLink.parse('tg://socks?server=1.2.3.4&port=1'), isNotNull);
    expect(ProxyLink.parse('tg://socks?server=1.2.3.4&port=65535'), isNotNull);
  });

  test('other links and plain text are not proxies', () {
    expect(ProxyLink.parse(''), isNull);
    expect(ProxyLink.parse('hello'), isNull);
    expect(ProxyLink.parse('server=1.2.3.4&port=443&secret=$fakeTls'), isNull);
    expect(ProxyLink.parse('tg://resolve?domain=telegram'), isNull);
    expect(ProxyLink.parse('https://t.me/telegram'), isNull);
    expect(ProxyLink.parse('https://example.com/proxy?server=1.2.3.4&port=443&secret=ee'), isNull);
    expect(ProxyLink.parse('https://t.me/proxy/extra?server=1.2.3.4&port=443&secret=ee'), isNull);
    expect(ProxyLink.parse('tg://proxy?server=1.2.3.4&port=443&secret=%E2%82'), isNull);
  });

  test('typed details make the same proxy a link does', () {
    final typed = ProxyLink.from(
      kind: ProxyKind.mtproto,
      server: ' 1.2.3.4 ',
      port: '443',
      secret: fakeTls,
    )!;
    expect(typed.label, '1.2.3.4:443');
    expect(typed.secret, fakeTls);
    expect(
      ProxyLink.from(kind: ProxyKind.socks5, server: 'example.net', port: '1080', username: ' ', password: '')!
          .username,
      isNull,
    );
    expect(ProxyLink.from(kind: ProxyKind.mtproto, server: '1.2.3.4', port: '443'), isNull);
    expect(ProxyLink.from(kind: ProxyKind.socks5, server: '', port: '1080'), isNull);
  });

  test('an IPv6 server keeps its port apart in the label', () {
    final link = ProxyLink.parse('tg://socks?server=2001:db8::1&port=1080')!;
    expect(link.label, '[2001:db8::1]:1080');
  });
}
