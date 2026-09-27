import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';

/// Asks before moving [count] files to the trash when [onPhone] of them are
/// photos or videos this phone still has, and whether the phone's copies
/// go too. [what] names the files, e.g. `"IMG_1.jpg"` or `5 items`. Over
/// 100 it also says what the confirm it stands in for says. Returns
/// whether to delete the phone's copies as well, or null to leave
/// everything where it is.
Future<bool?> showTrashSheet(
  BuildContext context, {
  required String what,
  required int count,
  required int onPhone,
  required bool initialAlsoPhone,
}) => showModalBottomSheet<bool>(
  context: context,
  useRootNavigator: true,
  builder: (_) => TrashSheet(
    what: what,
    count: count,
    onPhone: onPhone,
    initialAlsoPhone: initialAlsoPhone,
  ),
);

/// Whether the phone's copies go once the snack offering Undo has closed
/// for [reason]: only when [alsoPhone] asked for it and Undo wasn't tapped.
/// A snack pushed aside by another one counts as not undone, since the
/// drive copies are still in the Trash either way.
bool shouldDeletePhoneCopy(SnackBarClosedReason reason, {required bool alsoPhone}) =>
    alsoPhone && reason != SnackBarClosedReason.action;

/// The question [showTrashSheet] asks. Moving to the trash can be undone,
/// so nothing here is red; deleting from the phone is confirmed later by
/// the phone itself.
class TrashSheet extends StatefulWidget {
  const TrashSheet({
    super.key,
    required this.what,
    required this.count,
    required this.onPhone,
    required this.initialAlsoPhone,
  });

  final String what;
  final int count;
  final int onPhone;
  final bool initialAlsoPhone;

  @override
  State<TrashSheet> createState() => _TrashSheetState();
}

class _TrashSheetState extends State<TrashSheet> {
  late bool _alsoPhone = widget.initialAlsoPhone;

  @override
  Widget build(BuildContext context) {
    final single = widget.count == 1;
    final onPhone = widget.onPhone;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Move ${widget.what} to Trash?', style: context.text.titleMedium),
            const SizedBox(height: Space.s),
            Text(
              [
                single
                    ? 'It stays in the Trash for 30 days, where you can restore it.'
                    : 'They stay in the Trash for 30 days, where you can restore them.',
                if (widget.count > 100) 'Undo takes a while for this many, one edit per file.',
              ].join(' '),
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: Space.m),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Also delete from this phone'),
              subtitle: onPhone < widget.count
                  ? Text(
                      '${Formatters.number(onPhone)} of these '
                      '${onPhone == 1 ? 'is' : 'are'} on this phone',
                      style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                    )
                  : null,
              value: _alsoPhone,
              onChanged: (value) => setState(() => _alsoPhone = value ?? false),
            ),
            const SizedBox(height: Space.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _alsoPhone),
                    child: const Text('Move to Trash'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
