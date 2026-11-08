import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../infrastructure/media/media_probe.dart';

/// A photo the app's own decoder couldn't read, a RAW file say, decoded by
/// the phone instead into a JPEG no side over [side] pixels and shown in
/// its place. While that is made nothing shows, so what sits behind it
/// stays in view; when the phone can't make one either, [fallback] shows.
class DecodedByPhone extends StatefulWidget {
  const DecodedByPhone({
    super.key,
    required this.source,
    required this.side,
    required this.fallback,
  });

  /// The photo on the phone.
  final String source;
  final int side;
  final Widget fallback;

  /// The copies made in this run, by photo and size, so swiping back to a
  /// photo doesn't decode it again.
  static final Map<String, String> _made = {};

  @override
  State<DecodedByPhone> createState() => _DecodedByPhoneState();
}

class _DecodedByPhoneState extends State<DecodedByPhone> {
  late Future<String?> _copy = _make();

  @override
  void didUpdateWidget(DecodedByPhone old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source || old.side != widget.side) _copy = _make();
  }

  Future<String?> _make() async {
    final key = '${widget.source}|${widget.side}';
    final made = DecodedByPhone._made[key];
    if (made != null && File(made).existsSync()) return made;
    // In the cache's previews folder, which is swept like the other
    // leftovers once nothing has used it for a while.
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'previews', 'viewer'));
    await dir.create(recursive: true);
    final out = p.join(dir.path, '${key.hashCode.toUnsigned(32)}.jpg');
    final copy = await MediaProbe.picture(widget.source, side: widget.side, out: out);
    if (copy != null) DecodedByPhone._made[key] = copy;
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _copy,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const SizedBox.shrink();
        final copy = snapshot.data;
        if (copy == null) return widget.fallback;
        return Image.file(
          File(copy),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => widget.fallback,
        );
      },
    );
  }
}
