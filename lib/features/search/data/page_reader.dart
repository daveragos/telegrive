import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads the words on PDF pages that are pictures, such as scans, with the
/// text recognition on the phone (Android's, through Play services). Nothing
/// is sent anywhere.
class PageReader {
  const PageReader();

  static const _channel = MethodChannel('telegrive/text');

  /// The text on [pages] (counted from 0) of the PDF at [path], at most
  /// about [maxChars] of it. Null when the phone can't read pages yet, as
  /// while Play services is still bringing the recognizer, so the document
  /// is tried again later. Empty when it never will: no recognizer on this
  /// phone, or a PDF it can't open.
  Future<String?> read(String path, List<int> pages, {required int maxChars}) async {
    try {
      return await _channel.invokeMethod<String>('readPdfPages', {
            'path': path,
            'pages': pages,
            'maxChars': maxChars,
          }) ??
          '';
    } on MissingPluginException {
      return '';
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') return null;
      debugPrint('[PageReader] $path: ${e.message}');
      return '';
    }
  }

  /// Whether a page's own text says it is a picture of a page: no words a
  /// search could find, or only a stray few.
  static bool isPicture(String pageText) => pageText.trim().length < 16;
}

final pageReaderProvider = Provider<PageReader>((ref) => const PageReader());
