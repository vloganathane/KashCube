/// Canonical event names for KashCube analytics.
///
/// Use these constants at every call site — never inline raw strings.
/// Only feature/interaction events — NO financial values, NO names.
abstract final class AnalyticsEvents {
  // ── Screens ────────────────────────────────────────────────────────────────
  static const screenHome            = 'screen_home';
  static const screenTransactions    = 'screen_transactions';
  static const screenCredits         = 'screen_credits';
  static const screenReports         = 'screen_reports';
  static const screenInvoices        = 'screen_invoices';
  static const screenQuotes          = 'screen_quotes';
  static const screenDeliveryChallan = 'screen_delivery_challan';
  static const screenSettings        = 'screen_settings';
  static const screenParties         = 'screen_parties';
  static const screenInventory       = 'screen_inventory';
  static const screenBookings        = 'screen_bookings';
  static const screenGst             = 'screen_gst';

  // ── Transactions ───────────────────────────────────────────────────────────
  static const transactionAdded     = 'transaction_added';
  static const transactionEdited    = 'transaction_edited';
  static const transactionDeleted   = 'transaction_deleted';
  static const smsCaptureUsed       = 'sms_capture_used';

  // ── Invoices ───────────────────────────────────────────────────────────────
  static const invoiceCreated       = 'invoice_created';
  static const invoiceShared        = 'invoice_shared';
  static const invoicePdfOpened     = 'invoice_pdf_opened';
  static const quoteCreated         = 'quote_created';
  static const quoteShared          = 'quote_shared';
  static const challanCreated       = 'challan_created';

  // ── Credits ────────────────────────────────────────────────────────────────
  static const creditAdded          = 'credit_added';
  static const creditSettled        = 'credit_settled';

  // ── Backup / Export ────────────────────────────────────────────────────────
  static const backupCreated        = 'backup_created';
  static const backupRestored       = 'backup_restored';
  static const csvExported          = 'csv_exported';

  // ── Onboarding ─────────────────────────────────────────────────────────────
  static const onboardingCompleted  = 'onboarding_completed';
  static const analyticsConsentGiven   = 'analytics_consent_given';
  static const analyticsConsentRevoked = 'analytics_consent_revoked';

  // ── Web Companion ───────────────────────────────────────────────────────────
  /// Phone shows QR code for "Open on Laptop".
  static const webCompanionQrShown             = 'web_companion_qr_shown';
  /// User copies the URL chip on the "Open on Laptop" screen.
  static const webCompanionUrlCopied           = 'web_companion_url_copied';
  /// Browser successfully authenticates — AUTH_OK sent by phone server.
  static const webCompanionBrowserConnected    = 'web_companion_browser_connected';
  /// User manually taps "Disconnect browser" on the phone.
  static const webCompanionDisconnectedManually = 'web_companion_disconnected_manually';
}
