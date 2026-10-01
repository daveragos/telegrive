import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';

/// What someone chose when asked about starting a transfer on mobile data.
enum DataChoice {
  /// Go now, over mobile data.
  now,

  /// Wait for Wi-Fi and start on its own then.
  later,
}

/// Asks, before something of [bytes] starts on mobile data, whether it
/// should go now or wait for Wi-Fi. [doing] says what is about to happen
/// ('Uploading 3 files'), [files] how many files that is, and [nowLabel]
/// names the button that goes now ('Upload now'). Null when the dialog was
/// dismissed, which calls the whole thing off.
///
/// Only worth asking on a metered network and for something big; see
/// TransferPolicy.shouldAsk.
Future<DataChoice?> askAboutMobileData(
  BuildContext context, {
  required int bytes,
  required String doing,
  required int files,
  required String nowLabel,
}) => showDialog<DataChoice>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('You\'re on mobile data'),
    content: Text(
      '$doing uses ${Formatters.bytes(bytes)} of your data. '
      '${files == 1 ? 'It' : 'They'} can wait for Wi-Fi instead.',
      style: const TextStyle(fontFeatures: tabularFigures),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(DataChoice.later),
        child: const Text('Later, on Wi-Fi'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(DataChoice.now),
        child: Text(nowLabel),
      ),
    ],
  ),
);

/// Whether a transfer started after [choice] waits for Wi-Fi: it does after
/// [DataChoice.later] and not after [DataChoice.now]. Null when nobody was
/// asked, so the size rules decide.
bool? wifiOnlyFrom(DataChoice? choice) => switch (choice) {
  DataChoice.now => false,
  DataChoice.later => true,
  null => null,
};
