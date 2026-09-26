import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/storage/preferences.dart';
import '../../drive/domain/drive_models.dart';

@immutable
class BrowsePreferences {
  const BrowsePreferences({required this.viewMode, required this.sort});

  final ViewMode viewMode;
  final SortOrder sort;

  BrowsePreferences copyWith({ViewMode? viewMode, SortOrder? sort}) =>
      BrowsePreferences(viewMode: viewMode ?? this.viewMode, sort: sort ?? this.sort);
}

/// How folders are shown and ordered, remembered across launches.
class BrowsePreferencesNotifier extends Notifier<BrowsePreferences> {
  Preferences get _prefs => ref.read(preferencesProvider);

  @override
  BrowsePreferences build() {
    final prefs = ref.watch(preferencesProvider);
    return BrowsePreferences(
      viewMode: prefs.viewMode,
      sort: SortOrder(
        SortField.fromName(prefs.sortField),
        descending: prefs.sortDescending,
      ),
    );
  }

  void toggleViewMode() {
    final next = state.viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list;
    state = state.copyWith(viewMode: next);
    _prefs.setViewMode(next);
  }

  /// Picking the active field again flips its direction.
  void sortBy(SortField field) {
    final descending = state.sort.field == field
        ? !state.sort.descending
        : field == SortField.modified || field == SortField.size;
    state = state.copyWith(sort: SortOrder(field, descending: descending));
    _prefs.setSort(field.name, descending: descending);
  }
}

final browsePreferencesProvider =
    NotifierProvider<BrowsePreferencesNotifier, BrowsePreferences>(
      BrowsePreferencesNotifier.new,
    );
