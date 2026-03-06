/// Riverpod providers for deep link / install-referrer state.
///
/// Flow:
///   1. App Link (installed app) OR install referrer (first launch) delivers
///      a raw vCard string.
///   2. That string is stored in [pendingDeepLinkVCardProvider].
///   3. [AppShell] listens to this provider and presents the Add-Party sheet
///      with pre-filled contact data.
///   4. Once consumed, the provider is reset to null.
///
/// Privacy: vCard data never leaves the device — it is decoded locally from
/// the URL/referrer and immediately discarded after the user acts on it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the raw vCard string decoded from an incoming deep link or the
/// Play Store install referrer.
///
/// Null means no pending link. Non-null means a contact is waiting to be added.
final pendingDeepLinkVCardProvider = StateProvider<String?>((ref) => null);

/// Tracks whether the install referrer has been checked on this device.
/// Prevents re-showing the party form on every cold start.
final installReferrerCheckedProvider = StateProvider<bool>((ref) => false);
