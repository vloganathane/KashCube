import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/iap_service.dart';
import 'settings_provider.dart';

/// Set to `true` when Play Console products are live and ready for billing.
/// When `false`, IAP is completely skipped and all users stay on the free tier.
const bool _kIapEnabled = false;

/// Initialises [IapService] once and exposes the singleton.
///
/// Watched from [KashCubeApp] so the billing client connects early.
/// Uses [keepAlive] so the subscription listener is never torn down.
final iapServiceProvider = FutureProvider<IapService>((ref) async {
  ref.keepAlive();
  if (!_kIapEnabled) return IapService.instance; // IAP disabled — skip init
  final tierNotifier = ref.read(subscriptionTierProvider.notifier);
  final service = IapService.instance;
  await service.init(tierNotifier);
  return service;
});
