import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/storage/preferences.dart';
import '../../space/data/phone_usage.dart';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(preferencesProvider).themeMode;

  void set(ThemeMode mode) {
    state = mode;
    ref.read(preferencesProvider).setThemeMode(mode);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Everything Telegrive keeps on this phone, as Space adds it up.
final cacheSizeProvider = FutureProvider.autoDispose<int>(
  (ref) async => (await ref.watch(phoneUsageProvider.future)).total,
);
