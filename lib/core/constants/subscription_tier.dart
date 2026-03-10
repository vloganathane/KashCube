/// Subscription tier for KashCube's freemium model.
///
/// Free     → All data features. PDFs carry a "Created with KashCube Free"
///            watermark banner. Reports export is gated.
/// Starter  → Watermark-free PDFs, report export, UPI QR on invoices,
///            5 industry templates.
/// Business → All Starter features + GSTR-1 JSON, Tally XML, inventory,
///            payroll, LAN sync.
enum SubscriptionTier { free, starter, business }

extension SubscriptionTierX on SubscriptionTier {
  /// Returns true for Starter **or** Business (anything above Free).
  bool get isStarter =>
      this == SubscriptionTier.starter || this == SubscriptionTier.business;

  /// Returns true only for Business tier.
  bool get isBusiness => this == SubscriptionTier.business;

  /// Returns true only for Free tier.
  bool get isFree => this == SubscriptionTier.free;

  /// The string value stored in the settings DB key.
  String get dbValue => name; // 'free', 'starter', 'business'

  /// Parse a DB value back to a [SubscriptionTier], defaulting to [free].
  static SubscriptionTier fromDb(String? value) {
    return SubscriptionTier.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SubscriptionTier.free,
    );
  }

  /// Human-readable display name.
  String get displayName {
    switch (this) {
      case SubscriptionTier.free:
        return 'Free';
      case SubscriptionTier.starter:
        return 'Starter';
      case SubscriptionTier.business:
        return 'Business';
    }
  }
}
