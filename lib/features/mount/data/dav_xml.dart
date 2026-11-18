import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

/// What a PROPFIND says of one file or folder.
@immutable
class DavResource {
  const DavResource({
    required this.href,
    required this.name,
    required this.collection,
    this.size = 0,
    required this.modified,
    required this.created,
    this.contentType,
    this.etag,
    this.quota = false,
  });

  /// Its path on the server, percent-encoded, a folder's ending in `/`.
  final String href;
  final String name;
  final bool collection;
  final int size;
  final DateTime modified;
  final DateTime created;
  final String? contentType;
  final String? etag;

  /// Says how much room there is, as the drive's top folder does: Telegram
  /// sets no limit, so a petabyte free, which no copy runs into.
  final bool quota;
}

/// Room Finder and Explorer are told is free: Telegram keeps no count.
const int davFreeBytes = 1 << 50;

/// The multistatus answer to a PROPFIND for [resources].
String davMultistatus(Iterable<DavResource> resources) {
  final xml = XmlBuilder()..processing('xml', 'version="1.0" encoding="utf-8"');
  xml.element(
    'D:multistatus',
    namespaceUris: {'D': 'DAV:'},
    nest: () {
      for (final r in resources) {
        xml.element(
          'D:response',
          nest: () {
            xml.element('D:href', nest: r.href);
            xml.element(
              'D:propstat',
              nest: () {
                xml.element(
                  'D:prop',
                  nest: () {
                    xml.element('D:displayname', nest: r.name);
                    xml.element('D:resourcetype', nest: () {
                      if (r.collection) xml.element('D:collection');
                    });
                    xml.element('D:getlastmodified', nest: HttpDate.format(r.modified.toUtc()));
                    xml.element('D:creationdate', nest: r.created.toUtc().toIso8601String());
                    if (!r.collection) {
                      xml.element('D:getcontentlength', nest: '${r.size}');
                      xml.element('D:getcontenttype', nest: r.contentType ?? 'application/octet-stream');
                    }
                    if (r.etag case final etag?) xml.element('D:getetag', nest: '"$etag"');
                    if (r.quota) {
                      xml.element('D:quota-available-bytes', nest: '$davFreeBytes');
                      xml.element('D:quota-used-bytes', nest: '0');
                    }
                    xml.element('D:supportedlock', nest: () {
                      xml.element('D:lockentry', nest: () {
                        xml.element('D:lockscope', nest: () => xml.element('D:exclusive'));
                        xml.element('D:locktype', nest: () => xml.element('D:write'));
                      });
                    });
                  },
                );
                xml.element('D:status', nest: 'HTTP/1.1 200 OK');
              },
            );
          },
        );
      }
    },
  );
  return xml.buildDocument().toXmlString();
}

/// The answer to a LOCK of [href] as [token]: an exclusive write lock for
/// [timeout], as Finder and Explorer take before they write.
String davLock({required String href, required String token, required Duration timeout, String? owner}) {
  final xml = XmlBuilder()..processing('xml', 'version="1.0" encoding="utf-8"');
  xml.element(
    'D:prop',
    namespaceUris: {'D': 'DAV:'},
    nest: () {
      xml.element('D:lockdiscovery', nest: () {
        xml.element('D:activelock', nest: () {
          xml.element('D:locktype', nest: () => xml.element('D:write'));
          xml.element('D:lockscope', nest: () => xml.element('D:exclusive'));
          xml.element('D:depth', nest: '0');
          if (owner != null) xml.element('D:owner', nest: owner);
          xml.element('D:timeout', nest: 'Second-${timeout.inSeconds}');
          xml.element('D:locktoken', nest: () => xml.element('D:href', nest: token));
          xml.element('D:lockroot', nest: () => xml.element('D:href', nest: href));
        });
      });
    },
  );
  return xml.buildDocument().toXmlString();
}

/// Who a LOCK request names as the lock's owner, as text, or null.
String? davLockOwner(String body) {
  try {
    final owner = XmlDocument.parse(body).descendants.whereType<XmlElement>().where((e) => e.localName == 'owner');
    final text = owner.firstOrNull?.innerText.trim();
    return text == null || text.isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}

/// The answer to a PROPPATCH of [href]: every property [body] sets or
/// removes, as done. Finder and Explorer set times and attributes on what
/// they copy in; the drive keeps its own, so they are taken and dropped.
String davProppatch(String href, String body) {
  final props = <({String local, String? uri})>[];
  try {
    for (final prop in XmlDocument.parse(body).descendants.whereType<XmlElement>().where((e) => e.localName == 'prop')) {
      for (final child in prop.childElements) {
        props.add((local: child.localName, uri: child.namespaceUri));
      }
    }
  } catch (_) {}
  final namespaces = <String, String>{'DAV:': 'D'};
  for (final prop in props) {
    if (prop.uri case final uri? when !namespaces.containsKey(uri)) namespaces[uri] = 'n${namespaces.length}';
  }
  final xml = XmlBuilder()..processing('xml', 'version="1.0" encoding="utf-8"');
  xml.element(
    'D:multistatus',
    namespaceUris: {for (final MapEntry(key: uri, value: prefix) in namespaces.entries) prefix: uri},
    nest: () {
      xml.element('D:response', nest: () {
        xml.element('D:href', nest: href);
        xml.element('D:propstat', nest: () {
          xml.element('D:prop', nest: () {
            for (final prop in props) {
              final prefix = prop.uri == null ? null : namespaces[prop.uri];
              xml.element(prefix == null ? prop.local : '$prefix:${prop.local}');
            }
          });
          xml.element('D:status', nest: 'HTTP/1.1 200 OK');
        });
      });
    },
  );
  return xml.buildDocument().toXmlString();
}
