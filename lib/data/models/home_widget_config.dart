// ---------------------------------------------------------------------------
// HomeWidgetConfig
// ---------------------------------------------------------------------------
// Stores the user's home-screen layout: which sections are visible and in
// what order. Persisted as JSON in the local settings table — no network.
// ---------------------------------------------------------------------------

import 'dart:convert';

// ─── Widget IDs ──────────────────────────────────────────────────────────────

/// Stable string identifiers for every configurable home-screen section.
class HomeWidgetId {
  HomeWidgetId._();

  static const todayCashflow      = 'today_cashflow';
  static const upcoming           = 'upcoming';
  static const upcomingBookings   = 'upcoming_bookings';
  static const pendingSms         = 'pending_sms';
  static const alerts             = 'alerts';
  static const budgets            = 'budgets';
  static const reportsShortcut    = 'reports_shortcut';
  static const recentTransactions = 'recent_transactions';

  /// Human-readable labels used in the Customise Home screen.
  static const Map<String, String> labels = {
    todayCashflow:      "Today's Activity",
    upcoming:           'Upcoming Payments',
    upcomingBookings:   'Upcoming Bookings',
    pendingSms:         'Pending SMS Review',
    alerts:             'Alerts',
    budgets:            'Monthly Budgets',
    reportsShortcut:    'Reports Shortcut',
    recentTransactions: 'Recent Transactions',
  };

  /// Icon for each section (used in the Customise Home list).
  static const Map<String, String> iconKeys = {
    todayCashflow:      'today_cashflow',
    upcoming:           'upcoming',
    upcomingBookings:   'upcoming_bookings',
    pendingSms:         'pending_sms',
    alerts:             'alerts',
    budgets:            'budgets',
    reportsShortcut:    'reports_shortcut',
    recentTransactions: 'recent_transactions',
  };

  /// Factory-default config — all widgets enabled and ordered.
  static const List<HomeWidgetConfig> defaults = [
    HomeWidgetConfig(id: todayCashflow,      enabled: true,  order: 0),
    HomeWidgetConfig(id: upcoming,           enabled: true,  order: 1),
    HomeWidgetConfig(id: upcomingBookings,   enabled: true,  order: 2),
    HomeWidgetConfig(id: pendingSms,         enabled: true,  order: 3),
    HomeWidgetConfig(id: alerts,             enabled: true,  order: 4),
    HomeWidgetConfig(id: budgets,            enabled: true,  order: 5),
    HomeWidgetConfig(id: reportsShortcut,    enabled: true,  order: 6),
    HomeWidgetConfig(id: recentTransactions, enabled: true,  order: 7),
  ];

  /// Canonical ordering of all widget IDs (for merge / migration).
  static const List<String> all = [
    todayCashflow,
    upcoming,
    upcomingBookings,
    pendingSms,
    alerts,
    budgets,
    reportsShortcut,
    recentTransactions,
  ];
}

// ─── Model ───────────────────────────────────────────────────────────────────

/// Immutable configuration for one home-screen section.
class HomeWidgetConfig {
  final String id;
  final bool   enabled;
  final int    order;

  const HomeWidgetConfig({
    required this.id,
    required this.enabled,
    required this.order,
  });

  HomeWidgetConfig copyWith({bool? enabled, int? order}) => HomeWidgetConfig(
        id:      id,
        enabled: enabled ?? this.enabled,
        order:   order   ?? this.order,
      );

  Map<String, dynamic> toJson() => {
        'id':      id,
        'enabled': enabled,
        'order':   order,
      };

  factory HomeWidgetConfig.fromJson(Map<String, dynamic> json) =>
      HomeWidgetConfig(
        id:      json['id']      as String,
        enabled: json['enabled'] as bool?  ?? true,
        order:   json['order']   as int?   ?? 0,
      );

  // ── Codec helpers ──────────────────────────────────────────────────────────

  /// Encode a list to a single JSON string for the settings table.
  static String encodeList(List<HomeWidgetConfig> configs) =>
      jsonEncode(configs.map((c) => c.toJson()).toList());

  /// Decode a JSON string from the settings table, merging any new IDs that
  /// didn't exist when the user last customised (forward-migration).
  static List<HomeWidgetConfig> decodeList(String? json) {
    if (json == null || json.isEmpty) return List.of(HomeWidgetId.defaults);
    try {
      final raw     = jsonDecode(json) as List<dynamic>;
      final decoded = raw
          .map((e) =>
              HomeWidgetConfig.fromJson(e as Map<String, dynamic>))
          .toList();

      // Merge any IDs added since the user last saved preferences.
      final existingIds = decoded.map((c) => c.id).toSet();
      for (final id in HomeWidgetId.all) {
        if (!existingIds.contains(id)) {
          final def =
              HomeWidgetId.defaults.firstWhere((c) => c.id == id);
          decoded.add(HomeWidgetConfig(
              id: id, enabled: def.enabled, order: decoded.length));
        }
      }

      return decoded..sort((a, b) => a.order.compareTo(b.order));
    } catch (_) {
      return List.of(HomeWidgetId.defaults);
    }
  }
}
