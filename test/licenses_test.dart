import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Telegrive, the typeface, TDLib and OpenSSL come with their licenses', () async {
    final entries = await readBundledLicenses().toList();
    String text(String package) => entries
        .singleWhere((entry) => entry.packages.contains(package))
        .paragraphs
        .map((paragraph) => paragraph.text)
        .join('\n');

    expect(text('Telegrive'), contains('GNU GENERAL PUBLIC LICENSE'));
    expect(text('Telegrive'), contains('Version 3, 29 June 2007'));
    expect(text('IBM Plex Sans'), contains('SIL OPEN FONT LICENSE Version 1.1'));
    expect(text('TDLib'), contains('Boost Software License - Version 1.0'));
    expect(text('OpenSSL'), contains('Apache License'));
    expect(text('OpenSSL'), contains('Version 2.0, January 2004'));
  });

  test('they join the licenses Flutter lists', () async {
    registerBundledLicenses();
    final packages = await LicenseRegistry.licenses.expand((entry) => entry.packages).toSet();
    expect(packages, containsAll(['Telegrive', 'IBM Plex Sans', 'TDLib', 'OpenSSL']));
  });
}
