import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/iap_service.dart';
import 'settings_provider.dart';

/// Initialises [IapService] once and exposes the singleton.
///
/// Watched from [KashCubeApp] so the billing client connects early.
/// Uses [keepAlive] so the subscription listener is never torn down.
final iapServiceProvider = FutureProvider<IapService>((ref) async {
  ref.keepAlive();
  final tierNotifier = ref.read(subscriptionTierProvider.notifier);
  final service = IapService.instance;
  await service.init(tierNotifier);
  return service;
});
