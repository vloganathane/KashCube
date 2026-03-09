// ---------------------------------------------------------------------------
// homeWidgetProvider
// ---------------------------------------------------------------------------
// Manages the ordered + enabled list of home-screen sections.
// Config persisted as JSON in the local settings table under
// SettingsKeys.homeWidgetsConfig.
// ---------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/home_widget_config.dart';
import '../../domain/repositories/settings_repository.dart';
import 'settings_provider.dart';

// ─── Notifier ─────────────────────────────────────────────────────────────────

class HomeWidgetNotifier
    extends StateNotifier<List<HomeWidgetConfig>> {
  HomeWidgetNotifier(this._settings)
      : super(List.of(HomeWidgetId.defaults)) {
    _load();
  }

  final SettingsRepository _settings;

  Future<void> _load() async {
    final raw = await _settings.get(SettingsKeys.homeWidgetsConfig);
    state = HomeWidgetConfig.decodeList(raw);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Persist [configs] and update state.
  Future<void> save(List<HomeWidgetConfig> configs) async {
    state = List.of(configs);
    await _settings.set(
      SettingsKeys.homeWidgetsConfig,
      HomeWidgetConfig.encodeList(configs),
    );
  }

  /// Toggle the enabled flag for a single widget by [id].
  Future<void> toggle(String id) async {
    await save(
      state.map((c) => c.id == id ? c.copyWith(enabled: !c.enabled) : c).toList(),
    );
  }

  /// Handle a reorder drag: move item from [oldIndex] to [newIndex] and
  /// re-stamp order values.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    await save([
      for (int i = 0; i < list.length; i++) list[i].copyWith(order: i),
    ]);
  }

  /// Restore factory defaults.
  Future<void> resetToDefaults() async => save(List.of(HomeWidgetId.defaults));
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final homeWidgetProvider =
    StateNotifierProvider<HomeWidgetNotifier, List<HomeWidgetConfig>>(
  (ref) => HomeWidgetNotifier(ref.read(settingsRepositoryProvider)),
);
