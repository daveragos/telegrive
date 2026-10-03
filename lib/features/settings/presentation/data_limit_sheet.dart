import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../backup/data/backup_controller.dart';
import '../../network/data/mobile_data.dart';
import '../../network/domain/data_period.dart';

/// The limits on offer, in bytes, with 0 for none. Binary multiples, so
/// each reads as a round number wherever sizes are shown.
const List<int> _presets = [0, 250 << 20, 500 << 20, 1 << 30, 2 << 30, 5 << 30];

/// Sets the monthly mobile data limit and the day the plan renews on.
/// Saving has backup look again at what the limit held back.
Future<void> showDataLimitSheet(BuildContext context, WidgetRef ref) {
  final current = ref.read(mobileDataProvider);
  var limit = current.limit ?? 0;
  var renewDay = current.renewDay;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Monthly mobile data limit', style: context.text.titleMedium),
              const SizedBox(height: Space.s),
              Text(
                'Photo backup stays inside it and carries on over Wi-Fi. Files you '
                'open yourself always load, and count toward it.',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: Space.m),
              RadioGroup<int>(
                groupValue: limit,
                onChanged: (value) => setState(() => limit = value ?? 0),
                child: Column(
                  children: [
                    for (final preset in _presets)
                      RadioListTile<int>(
                        value: preset,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          preset == 0 ? 'No limit' : Formatters.bytes(preset, decimals: 0),
                          style: context.text.bodyLarge?.copyWith(fontFeatures: tabularFigures),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.s),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Renews on'),
                trailing: DropdownButton<int>(
                  value: renewDay,
                  underline: const SizedBox.shrink(),
                  onChanged: (day) => setState(() => renewDay = day ?? renewDay),
                  items: [
                    for (var day = 1; day <= DataPeriod.lastRenewDay; day++)
                      DropdownMenuItem(
                        value: day,
                        child: Text(
                          'the ${Formatters.dayOfMonth(day)}',
                          style: context.text.bodyMedium?.copyWith(
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.xxl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final mobileData = ref.read(mobileDataProvider.notifier);
                    final backup = ref.read(backupControllerProvider.notifier);
                    Navigator.pop(context);
                    await mobileData.setLimit(limit == 0 ? null : limit, renewDay);
                    backup.schedule(immediate: true);
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
