import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/file_style.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/widgets/file_visuals.dart';
import '../data/local_media.dart';

/// A photo on this phone as a row: its thumbnail, its file name, a second
/// line and the row's buttons, with a bar under the line while it goes up.
/// A photo the phone no longer has shows the kind glyph.
class PhoneAssetRow extends ConsumerWidget {
  const PhoneAssetRow({
    super.key,
    required this.assetId,
    required this.subtitle,
    this.trailing,
    this.subtitleLines = 1,
    this.progress,
    this.progressColor,
    this.onTap,
  });

  final String assetId;
  final String subtitle;
  final int subtitleLines;
  final Widget? trailing;

  /// 0..1 for a bar under the second line, negative for one that runs
  /// without a measure, null for none.
  final double? progress;

  /// The bar's colour when it isn't the accent: grey while it waits.
  final Color? progressColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnail = ref.watch(assetThumbnailProvider(assetId)).value;
    final title = ref.watch(assetTitleProvider(assetId));
    final name = title.isLoading ? '' : (title.value ?? 'Photo');
    final kind = FileKind.detect(fileName: name) == FileKind.video ? FileKind.video : FileKind.image;
    final bar = progress;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s + 2, Space.s, Space.s + 2),
        child: Row(
          children: [
            if (thumbnail != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.thumb),
                child: Image.memory(
                  thumbnail,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              )
            else
              FileIconTile(style: FileStyle.forKind(kind)),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: subtitleLines,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                  ),
                  if (bar != null) ...[
                    const SizedBox(height: Space.s),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: bar < 0 ? 0 : bar),
                        duration: const Duration(milliseconds: 250),
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: bar < 0 ? null : value,
                          minHeight: 4,
                          color: progressColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Space.s),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
