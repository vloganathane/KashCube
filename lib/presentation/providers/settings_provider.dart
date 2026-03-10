import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/subscription_tier.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../data/services/backup_service.dart';
import '../../data/services/csv_export_service.dart';
import '../../data/services/pdf_document_data.dart';
import '../../domain/repositories/settings_repository.dart';

// ---------------------------------------------------------------------------
// Settings repository
// ---------------------------------------------------------------------------

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (_) => SettingsRepositoryImpl(),
);

// ---------------------------------------------------------------------------
// App lock settings
// ---------------------------------------------------------------------------

/// Keys used in the settings table.
class SettingsKeys {
  SettingsKeys._();
  static const pinHash = 'pin_hash';
  static const appLockEnabled = 'app_lock_enabled';
  static const biometricEnabled = 'biometric_enabled';
  static const themeMode = 'theme_mode';
  static const defaultAccountId = 'default_account_id';
  static const businessModeEnabled = 'business_mode_enabled';
  static const businessName = 'business_name';

  // Personal vCard / My Card fields
  static const ownerName        = 'owner_name';
  static const personalPhone    = 'personal_phone';
  static const personalEmail    = 'personal_email';
  static const personalWebsite  = 'personal_website';
  static const personalWhatsapp = 'personal_whatsapp';
  static const personalLinkedin = 'personal_linkedin';
  static const personalInstagram= 'personal_instagram';
  static const personalPhotoPath = 'personal_photo_path';
  static const personalAddress  = 'personal_address';
  static const personalCity     = 'personal_city';
  static const personalState    = 'personal_state';
  static const personalPincode  = 'personal_pincode';
  static const personalCountry  = 'personal_country';
  static const personalDialCode = 'personal_dial_code';

  // Default T&C shown in PDF footers
  static const invoiceTerms = 'invoice_terms';
  static const quoteTerms   = 'quote_terms';
  static const bookingTerms = 'booking_terms';
  static const challanTerms = 'challan_terms';

  // Built-in fallback T&C used when the user has not yet customised them
  static const defaultInvoiceTerms =
      '1. Payment is due on or before the due date mentioned on this invoice.\n'
      '2. Goods once sold cannot be returned without prior written approval.\n'
      '3. All disputes are subject to local jurisdiction only.\n'
      '4. E. & O.E.';

  static const defaultQuoteTerms =
      '1. This quotation is valid for 30 days from the date of issue.\n'
      '2. Prices are subject to revision without notice after the validity period.\n'
      '3. Taxes applicable as per prevailing government norms.\n'
      '4. E. & O.E.';

  static const defaultBookingTerms =
      '1. Advance paid is non-refundable if cancelled within 48 hours of the service date.\n'
      '2. Rescheduling is subject to availability and must be requested at least 24 hours in advance.\n'
      '3. Service will be provided as per the booking details mentioned above.';

  static const defaultChallanTerms =
      '1. This delivery challan is not a tax invoice.\n'
      '2. Please verify goods on receipt. Any discrepancy must be reported within 24 hours.\n'
      '3. Signed copy to be returned as acknowledgement of delivery.';

  // PDF document template
  static const documentTemplate = 'document_template';

  // Subscription tier: 'free' | 'starter' | 'business'
  static const subscriptionTier = 'subscription_tier';

  // Home screen widget layout (JSON-encoded list of HomeWidgetConfig)
  static const homeWidgetsConfig = 'home_widgets_config';
}

// ---------------------------------------------------------------------------
// Theme mode
// ---------------------------------------------------------------------------

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._repo) : super(ThemeMode.system) {
    _load();
  }

  final SettingsRepository _repo;

  Future<void> _load() async {
    final value = await _repo.get(SettingsKeys.themeMode);
    state = _fromString(value);
  }

  Future<void> setTheme(ThemeMode mode) async {
    await _repo.set(SettingsKeys.themeMode, _toDbString(mode));
    state = mode;
  }

  static ThemeMode _fromString(String? v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _toDbString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(ref.read(settingsRepositoryProvider)),
);

// ---------------------------------------------------------------------------
// Default account
// ---------------------------------------------------------------------------

class DefaultAccountNotifier extends StateNotifier<int?> {
  DefaultAccountNotifier(this._repo) : super(null) {
    _load();
  }

  final SettingsRepository _repo;

  Future<void> _load() async {
    final value = await _repo.get(SettingsKeys.defaultAccountId);
    if (value != null) state = int.tryParse(value);
  }

  Future<void> setDefault(int? accountId) async {
    if (accountId == null) {
      await _repo.set(SettingsKeys.defaultAccountId, '');
    } else {
      await _repo.set(SettingsKeys.defaultAccountId, accountId.toString());
    }
    state = accountId;
  }
}

final defaultAccountIdProvider =
    StateNotifierProvider<DefaultAccountNotifier, int?>(
  (ref) => DefaultAccountNotifier(ref.read(settingsRepositoryProvider)),
);

/// Whether app lock (PIN) is enabled.
final appLockEnabledProvider = FutureProvider<bool>((ref) async {
  final repo = ref.read(settingsRepositoryProvider);
  final value = await repo.get(SettingsKeys.appLockEnabled);
  return value == 'true';
});

/// Whether biometric unlock is enabled.
final biometricEnabledProvider = FutureProvider<bool>((ref) async {
  final repo = ref.read(settingsRepositoryProvider);
  final value = await repo.get(SettingsKeys.biometricEnabled);
  return value == 'true';
});

// ---------------------------------------------------------------------------
// Backup
// ---------------------------------------------------------------------------

final backupServiceProvider = Provider<BackupService>(
  (_) => BackupService.instance,
);

final backupListProvider = FutureProvider<List<BackupInfo>>((ref) async {
  final service = ref.read(backupServiceProvider);
  return service.listBackups();
});

// ---------------------------------------------------------------------------
// CSV Export
// ---------------------------------------------------------------------------

final csvExportServiceProvider = Provider<CsvExportService>(
  (_) => CsvExportService.instance,
);

// ---------------------------------------------------------------------------
// Business Mode
// ---------------------------------------------------------------------------

class BusinessModeNotifier extends StateNotifier<bool> {
  BusinessModeNotifier(this._repo) : super(false) {
    _load();
  }

  final SettingsRepository _repo;

  Future<void> _load() async {
    final v = await _repo.get(SettingsKeys.businessModeEnabled);
    state = v == 'true';
  }

  Future<void> setEnabled(bool enabled) async {
    await _repo.set(SettingsKeys.businessModeEnabled, enabled.toString());
    state = enabled;
  }
}

final businessModeProvider =
    StateNotifierProvider<BusinessModeNotifier, bool>(
  (ref) => BusinessModeNotifier(ref.read(settingsRepositoryProvider)),
);

class BusinessNameNotifier extends StateNotifier<String> {
  BusinessNameNotifier(this._repo) : super('') {
    _load();
  }

  final SettingsRepository _repo;

  Future<void> _load() async {
    state = await _repo.get(SettingsKeys.businessName) ?? '';
  }

  Future<void> setName(String name) async {
    await _repo.set(SettingsKeys.businessName, name);
    state = name;
  }
}

final businessNameProvider =
    StateNotifierProvider<BusinessNameNotifier, String>(
  (ref) => BusinessNameNotifier(ref.read(settingsRepositoryProvider)),
);

// ---------------------------------------------------------------------------
// Document Template
// ---------------------------------------------------------------------------

class DocumentTemplateNotifier extends StateNotifier<DocumentTemplate> {
  DocumentTemplateNotifier(this._repo) : super(DocumentTemplate.modern) {
    _load();
  }

  final SettingsRepository _repo;

  Future<void> _load() async {
    final stored = await _repo.get(SettingsKeys.documentTemplate);
    final template = DocumentTemplate.fromId(stored ?? DocumentTemplate.modern.id);
    DocumentTemplate.setActive(template);
    state = template;
  }

  Future<void> setTemplate(DocumentTemplate template) async {
    await _repo.set(SettingsKeys.documentTemplate, template.id);
    DocumentTemplate.setActive(template);
    state = template;
  }
}

final documentTemplateProvider =
    StateNotifierProvider<DocumentTemplateNotifier, DocumentTemplate>(
  (ref) => DocumentTemplateNotifier(ref.read(settingsRepositoryProvider)),
);

// ---------------------------------------------------------------------------
// Notification Settings
// ---------------------------------------------------------------------------

/// Keys for notification settings stored in the generic [settings] table.
class NotificationKeys {
  NotificationKeys._();
  static const notificationsEnabled = 'notifications_enabled';
  static const invoicesNotifications = 'invoices_notifications';
  static const bookingsNotifications = 'bookings_notifications';
  static const creditsNotifications = 'credits_notifications';
  static const billsNotifications = 'bills_notifications';
  static const quietHoursStart = 'quiet_hours_start';
  static const quietHoursEnd = 'quiet_hours_end';
}

/// Holds all notification preference values as a flat map.
typedef NotificationSettings = Map<String, dynamic>;

class NotificationSettingsNotifier
    extends StateNotifier<AsyncValue<NotificationSettings>> {
  NotificationSettingsNotifier(this._repo)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final SettingsRepository _repo;

  static const _defaults = {
    NotificationKeys.notificationsEnabled: true,
    NotificationKeys.invoicesNotifications: true,
    NotificationKeys.bookingsNotifications: true,
    NotificationKeys.creditsNotifications: true,
    NotificationKeys.billsNotifications: true,
    NotificationKeys.quietHoursStart: '22:00',
    NotificationKeys.quietHoursEnd: '08:00',
  };

  Future<void> _load() async {
    final map = <String, dynamic>{};
    for (final entry in _defaults.entries) {
      final raw = await _repo.get(entry.key);
      if (raw == null) {
        map[entry.key] = entry.value;
      } else if (entry.value is bool) {
        map[entry.key] = raw == 'true';
      } else {
        map[entry.key] = raw;
      }
    }
    state = AsyncValue.data(map);
  }

  /// Update a single notification setting.
  Future<void> updateSetting(String key, dynamic value) async {
    await _repo.set(key, value.toString());
    final current = state.valueOrNull ?? {};
    state = AsyncValue.data({...current, key: value});
  }

  /// Reload all settings from DB (e.g. after restore).
  Future<void> reload() => _load();
}

final notificationSettingsProvider = StateNotifierProvider<
    NotificationSettingsNotifier, AsyncValue<NotificationSettings>>(
  (ref) => NotificationSettingsNotifier(ref.read(settingsRepositoryProvider)),
);

// ---------------------------------------------------------------------------
// Subscription Tier
// ---------------------------------------------------------------------------

class SubscriptionTierNotifier extends StateNotifier<SubscriptionTier> {
  SubscriptionTierNotifier(this._repo) : super(SubscriptionTier.free) {
    _load();
  }

  final SettingsRepository _repo;

  Future<void> _load() async {
    final value = await _repo.get(SettingsKeys.subscriptionTier);
    state = SubscriptionTierX.fromDb(value);
  }

  Future<void> setTier(SubscriptionTier tier) async {
    await _repo.set(SettingsKeys.subscriptionTier, tier.dbValue);
    state = tier;
  }
}

final subscriptionTierProvider =
    StateNotifierProvider<SubscriptionTierNotifier, SubscriptionTier>(
  (ref) => SubscriptionTierNotifier(ref.read(settingsRepositoryProvider)),
);


