import '../../../infrastructure/storage/device_storage.dart';

/// How much free space the phone needs before Telegrive writes a big file,
/// and whether it has it. Every place that writes one asks here first, so a
/// transfer waits for room rather than fill the phone and fail halfway.
/// Pure arithmetic apart from [shortfall], so each sum is tested on its own.
abstract final class Room {
  /// Left free on top of every need, so a write never takes the phone to
  /// its last byte and small changes in between don't tip it over.
  static const int margin = 64 << 20;

  /// Copying a picked or shared file of [size] into staging.
  static int forStage(int size) => size + margin;

  /// Cutting one part of [partBytes] out of a split upload.
  static int forPart(int partBytes) => partBytes + margin;

  /// Downloading a file of [size] of which [alreadyHere] is on the phone.
  /// A [split] file is stitched together a part at a time, so its largest
  /// part sits in TDLib's cache next to the stitched copy. A save that
  /// [keepsCopy] copies the finished file into Download, the gallery or
  /// offline before the download is let go, so it is there twice.
  static int forDownload({
    required int size,
    required int alreadyHere,
    required bool split,
    required int largestPart,
    required bool keepsCopy,
  }) =>
      (size - alreadyHere) + (split ? largestPart : 0) + (keepsCopy ? size : 0) + margin;

  /// The bytes [needed] and those free when [storage] has less than that,
  /// or null when it has enough. A phone that can't say how much it has
  /// never holds anything back.
  static Future<(int needed, int free)?> shortfall(DeviceStorage storage, int needed) async {
    final free = await storage.freeBytes();
    if (free == null || free >= needed) return null;
    return (needed, free);
  }
}
