import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/constants/subscription_tier.dart';
import '../../presentation/providers/settings_provider.dart';

/// Google Play product IDs for KashCube subscriptions.
///
/// These must match the product IDs configured in the Play Console.
class KashCubeProducts {
  KashCubeProducts._();

  static const starterMonthly  = 'com.kashcube.starter.monthly';
  static const starterAnnual   = 'com.kashcube.starter.annual';
  static const businessMonthly = 'com.kashcube.business.monthly';
  static const businessAnnual  = 'com.kashcube.business.annual';

  static const all = {
    starterMonthly,
    starterAnnual,
    businessMonthly,
    businessAnnual,
  };

  /// Maps a product ID back to the [SubscriptionTier] it grants.
  static SubscriptionTier tierForProduct(String productId) {
    if (productId == businessMonthly || productId == businessAnnual) {
      return SubscriptionTier.business;
    }
    if (productId == starterMonthly || productId == starterAnnual) {
      return SubscriptionTier.starter;
    }
    return SubscriptionTier.free;
  }
}

/// Manages subscription purchases via Google Play's billing library.
///
/// Privacy note: no purchase data ever leaves the device to a KashCube server.
/// Google Play validates the purchase on-device and reports PURCHASED status;
/// KashCube only reads that status.
///
/// Lifecycle:
/// 1. Call [init] once from app startup (after Riverpod is available).
/// 2. [products] exposes available product details for the UI.
/// 3. [buySubscription] initiates a Play Store purchase flow.
/// 4. [restorePurchases] re-applies active subscriptions after reinstall.
/// 5. Call [dispose] when the app processes are done (usually never in mobile).
class IapService {
  IapService._();
  static final IapService instance = IapService._();

  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  /// All available subscription [ProductDetails] fetched from Play Store.
  final List<ProductDetails> products = [];

  /// True when the Play Store billing service is available on this device.
  bool get isAvailable => _isAvailable;
  bool _isAvailable = false;

  /// Whether [init] has been called.
  bool _initialised = false;

  /// The Riverpod [SubscriptionTierNotifier] ref used to persist tier changes.
  SubscriptionTierNotifier? _tierNotifier;

  /// Initialises the billing client, loads product details, and starts
  /// listening to purchase updates.
  ///
  /// [tierNotifier] is the Riverpod notifier that persists the active tier to
  /// settings — pass `ref.read(subscriptionTierProvider.notifier)`.
  Future<void> init(SubscriptionTierNotifier tierNotifier) async {
    if (_initialised) return;
    _initialised = true;
    _tierNotifier = tierNotifier;

    // IAP uses Google Play Billing — only available on Android.
    // On macOS/iOS/web, StoreKit would fire storekit_no_response because
    // products are not registered in App Store Connect.
    if (!kIsWeb && !Platform.isAndroid) {
      debugPrint('[IAP] Skipping IAP init — Google Play only (current platform: ${Platform.operatingSystem})');
      return;
    }

    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      debugPrint('[IAP] Billing service not available on this device');
      return;
    }

    // Subscribe to purchase updates before loading products.
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object e) => debugPrint('[IAP] purchaseStream error: $e'),
    );

    // Fetch product details from Play Store.
    final response = await _iap.queryProductDetails(KashCubeProducts.all);
    if (response.error != null) {
      debugPrint('[IAP] queryProductDetails error: ${response.error}');
    }
    products
      ..clear()
      ..addAll(response.productDetails);
    debugPrint('[IAP] Loaded ${products.length} products');

    // Re-apply any active subscriptions from previous sessions.
    await _iap.restorePurchases();
  }

  /// Initiates a Play Store subscription purchase for [productId].
  ///
  /// Returns `true` if the purchase flow was launched successfully.
  Future<bool> buySubscription(String productId) async {
    if (!_isAvailable) {
      debugPrint('[IAP] Cannot purchase — billing not available');
      return false;
    }
    final product = products.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw StateError(
          '[IAP] Product not loaded: $productId. Call init() first.'),
    );
    final param = PurchaseParam(productDetails: product);
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Asks Play to restore all past purchases (useful after reinstall).
  Future<void> restorePurchases() async {
    if (!_isAvailable) return;
    await _iap.restorePurchases();
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        // Acknowledge the purchase so Play doesn't auto-refund it.
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        final tier = KashCubeProducts.tierForProduct(purchase.productID);
        await _tierNotifier?.setTier(tier);
        debugPrint('[IAP] Subscription active: ${purchase.productID} → $tier');
      } else if (purchase.status == PurchaseStatus.error) {
        debugPrint('[IAP] Purchase error: ${purchase.error}');
      } else if (purchase.status == PurchaseStatus.canceled) {
        debugPrint('[IAP] Purchase cancelled: ${purchase.productID}');
      }
    }
  }

  void dispose() {
    _purchaseSub?.cancel();
    _purchaseSub = null;
    _initialised = false;
  }
}
