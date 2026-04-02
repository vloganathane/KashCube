/// Single source of truth for every SQLite table name in the app.
///
/// Use these constants everywhere a table name is needed (repositories,
/// sync registry, auto-refresh provider, migrations, tests) so that a rename
/// is a one-line change and a typo produces a compile error rather than a
/// silent runtime miss.
abstract final class AppTables {
  // ── Core finance ──────────────────────────────────────────────────────────
  static const String transactions        = 'transactions';
  static const String credits             = 'credits';
  static const String creditPayments      = 'credit_payments';
  static const String loans               = 'loans';
  static const String loanPayments        = 'loan_payments';
  static const String scheduledPayments   = 'scheduled_payments';
  static const String recurringTransactions = 'recurring_transactions';

  // ── Parties & accounts ────────────────────────────────────────────────────
  static const String parties             = 'parties';
  static const String partyAddresses      = 'party_addresses';
  static const String partyReminders      = 'party_reminders';
  static const String accounts            = 'accounts';

  // ── Categorisation & budgets ──────────────────────────────────────────────
  static const String categories          = 'categories';
  static const String budgets             = 'budgets';

  // ── Invoicing & quotes ────────────────────────────────────────────────────
  static const String invoices            = 'invoices';
  static const String invoiceItems        = 'invoice_items';
  static const String invoiceNumberCursors = 'invoice_number_cursors';
  static const String quotes              = 'quotes';
  static const String quoteItems          = 'quote_items';
  static const String documentTemplates   = 'document_templates';

  // ── Purchase & inventory ──────────────────────────────────────────────────
  static const String purchaseBills       = 'purchase_bills';
  static const String purchaseBillItems   = 'purchase_bill_items';
  static const String itemCatalog         = 'item_catalog';
  static const String itemStock           = 'item_stock';
  static const String stockMovements      = 'stock_movements';
  static const String unitTypes           = 'unit_types';
  static const String hsnMaster           = 'hsn_master';

  // ── Delivery challans ─────────────────────────────────────────────────────
  static const String deliveryChallans    = 'delivery_challans';
  static const String deliveryChallanItems = 'delivery_challan_items';
  static const String transporters        = 'transporters';

  // ── Bookings ──────────────────────────────────────────────────────────────
  static const String bookings            = 'bookings';
  static const String bookingItems        = 'booking_items';

  // ── Staff & payroll ───────────────────────────────────────────────────────
  static const String staff               = 'staff';
  static const String salaryPayments      = 'salary_payments';

  // ── Bills (recurring) ────────────────────────────────────────────────────
  static const String bills               = 'bills';
  static const String billAttachments     = 'bill_attachments';

  // ── Business & settings ───────────────────────────────────────────────────
  static const String businesses          = 'businesses';
  static const String mediaAssets         = 'media_assets';
  static const String settings            = 'settings';

  // ── Users, RBAC & subscription ────────────────────────────────────────────
  static const String appUsers            = 'app_users';
  static const String userPermissions     = 'user_permissions';
  static const String subscription        = 'subscription';
  static const String planFeatures        = 'plan_features';

  // ── P2P / sync engine (local-only — never leave this device) ─────────────
  static const String linkedDevices           = 'linked_devices';
  static const String linkedBusinessSessions  = 'linked_business_sessions';
  static const String deviceSession           = 'device_session';
  static const String deviceRecovery          = 'device_recovery';
  static const String pairingHistory          = 'pairing_history';
  static const String trustedPeers            = 'trusted_peers';
  static const String myIdentity              = 'my_identity';
  static const String syncOutbox              = 'sync_outbox';
  static const String syncWatermarks          = 'sync_watermarks';
  static const String syncTableState          = 'sync_table_state';
  static const String schemaVersion           = 'schema_version';
  static const String payrollNotifications    = 'payroll_notifications';
}
