import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/permission.dart';
import '../data/models/user_permission.dart';
import 'providers/sync_provider.dart';
import 'widgets/read_only_mode_banner.dart';
import '../core/constants/app_config.dart';
import '../core/utils/deep_link_vcard.dart';
import '../core/utils/vcard_builder.dart' show parseVCard;
import '../data/models/parsed_sms.dart';
import '../data/models/party.dart';
import '../data/models/transaction.dart';
import '../data/services/sms_parser.dart';
import 'providers/app_user_provider.dart';
import 'providers/deep_link_provider.dart';
import 'providers/party_provider.dart';
import 'providers/scheduled_payment_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/sms_provider.dart';
import 'providers/transaction_provider.dart';
import 'screens/business/business_hub_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/parties/parties_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/transactions/add_edit_transaction_screen.dart';
import 'screens/transactions/transactions_hub_screen.dart';
import 'widgets/context_banner_widget.dart';
import 'widgets/party_form_sheet.dart';
import 'widgets/speed_dial_fab.dart';
import 'widgets/sms_confirmation_sheet.dart';

/// Provider for the current bottom navigation tab index.
final currentTabIndexProvider = StateProvider<int>((ref) => 0);

// ---------------------------------------------------------------------------
// Tab spec helpers
// ---------------------------------------------------------------------------

/// Maps a screen index (0–4 in [IndexedStack]) to its [NavigationDestination].
class _TabSpec {
  const _TabSpec(this.screenIndex, this.destination);
  final int                 screenIndex;
  final NavigationDestination destination;
}

/// Returns the visible tab specs for the given device session [preset].
/// Cashier devices only see Home, Transactions, and Business.
List<_TabSpec> _computeVisibleTabs(String? preset) {
  const tabs = [
    _TabSpec(0, NavigationDestination(icon: Icon(Icons.home_outlined),         selectedIcon: Icon(Icons.home),         label: 'Home')),
    _TabSpec(1, NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Transactions')),
    _TabSpec(2, NavigationDestination(icon: Icon(Icons.storefront_outlined),   selectedIcon: Icon(Icons.storefront),   label: 'Business')),
    _TabSpec(3, NavigationDestination(icon: Icon(Icons.people_outline),        selectedIcon: Icon(Icons.people),       label: 'Contacts')),
    _TabSpec(4, NavigationDestination(icon: Icon(Icons.settings_outlined),     selectedIcon: Icon(Icons.settings),     label: 'Settings')),
  ];
  if (preset == 'cashier') {
    return tabs.sublist(0, 3); // Home, Transactions, Business only
  }
  return tabs.toList();
}

/// App shell with bottom navigation bar, FAB, and SMS listener.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _smsListenerStarted = false;
  bool _deepLinksStarted  = false;
  final _appLinks = AppLinks();

  static const _screens = [
    HomeScreen(),
    TransactionsHubScreen(),
    BusinessHubScreen(),
    PartiesScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Kick off SMS listener after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSmsListener();
      _processRecurringTransactions();
      _initDeepLinks();
    });
  }

  Future<void> _processRecurringTransactions() async {
    await processScheduledAutoCreations(ref);
  }

  // ── Deep Link & Install Referrer ─────────────────────────────────────────

  Future<void> _initDeepLinks() async {
    if (_deepLinksStarted) return;
    _deepLinksStarted = true;

    // 1️⃣  Install Referrer — runs once on first cold start after install.
    //     Delivers the vCard that the kashcube.com landing page embedded in
    //     the Play Store URL before the user tapped "Install".
    if (Platform.isAndroid) {
      await _checkInstallReferrer();
    }

    // 2️⃣  Initial link — app was cold-started by tapping a link.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleIncomingUri(initial);
    } catch (_) {}

    // 3️⃣  Stream — link arrives while app is already running.
    _appLinks.uriLinkStream.listen(_handleIncomingUri, onError: (_) {});
  }

  void _handleIncomingUri(Uri uri) {
    final vcard = decodeVCardUri(uri);
    if (vcard != null && mounted) {
      ref.read(pendingDeepLinkVCardProvider.notifier).state = vcard;
    }
  }

  /// Reads the Play Store install referrer via a MethodChannel bridged in
  /// MainActivity.kt.  Only runs once per device (flag stored in prefs).
  Future<void> _checkInstallReferrer() async {
    const prefKey = 'install_referrer_checked';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(prefKey) == true) return;   // already consumed
    await prefs.setBool(prefKey, true);

    try {
      const channel = MethodChannel(AppConfig.installReferrerChannel);
      final referrer = await channel.invokeMethod<String>('getReferrer');
      if (referrer != null && referrer.isNotEmpty) {
        final vcard = decodeInstallReferrer(referrer);
        if (vcard != null && mounted) {
          ref.read(pendingDeepLinkVCardProvider.notifier).state = vcard;
        }
      }
    } catch (_) {
      // Play Store not available (sideload / emulator) — ignore silently.
    }
  }

  /// Shows the Add-Party bottom sheet pre-filled with data from [vcard].
  void _showPartyFromVCard(String vcard) {
    final fields = parseVCard(vcard);
    final name = (fields['name'] ?? '').trim();
    if (name.isEmpty) return;

    // Build a Party skeleton — id is null so the form creates a new record.
    final prefilled = Party(
      name: name,
      phoneNumber: fields['phone'],
      email: fields['email'],
      address: fields['address'],
      city: fields['city'],
      state: fields['state'],
      pincode: fields['pincode'],
      website: fields['website'],
      whatsapp: fields['whatsapp'],
      linkedin: fields['linkedin'],
      instagram: fields['instagram'],
      gstin: fields['gstin'],
      partyType: PartyType.personal,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PartyFormSheet(
        existing: prefilled,
        onSave: (saved) {
          // id is null → create; non-null would be an update (shouldn't happen
          // here, but is safe to handle).
          if (saved.id == null) {
            ref.read(partiesProvider.notifier).add(saved);
          } else {
            ref.read(partiesProvider.notifier).update(saved);
          }
        },
      ),
    );
  }

  Future<void> _initSmsListener() async {
    if (_smsListenerStarted) return;

    final smsService = ref.read(smsServiceProvider);
    final hasPermission = await smsService.hasPermission;
    if (!hasPermission) return;

    // Only start real-time listening if auto-detect is enabled.
    final autoDetect = ref.read(smsAutoDetectEnabledProvider);
    if (!autoDetect) return;

    _smsListenerStarted = true;
    smsService.startListening(
      onTransactionDetected: _onSmsTransactionDetected,
    );
  }

  void _onSmsTransactionDetected(ParsedSms parsed) {
    // Check for duplicate before showing confirmation
    final dedupeHash = SmsParser.generateDedupeHash(parsed);

    // Add to pending list (provider handles dedup by smsBody)
    ref.read(pendingSmsConfirmationsProvider.notifier).addPending(parsed);

    // Show confirmation sheet if the app is in foreground
    if (mounted) {
      _showSmsConfirmation(parsed, dedupeHash);
    }
  }

  Future<void> _showSmsConfirmation(
    ParsedSms parsed,
    String dedupeHash,
  ) async {
    // Check if already saved (by dedupe hash)
    final repo = ref.read(transactionRepositoryProvider);
    final exists = await repo.existsByDedupeHash(dedupeHash);
    if (exists) {
      ref.read(pendingSmsConfirmationsProvider.notifier).removePending(parsed);
      return;
    }

    if (!mounted) return;

    final action = await showSmsConfirmationSheet(context, ref, parsed);

    if (action == SmsConfirmAction.editManually && mounted) {
      // Open Add screen pre-filled with parsed data
      Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => AddEditTransactionScreen(
            transaction: Transaction(
              amount: parsed.amount,
              date: parsed.date ?? DateTime.now(),
              type: parsed.isCredit
                  ? TransactionType.income
                  : TransactionType.expense,
              category: '',
              partyName: parsed.partyName,
              smsBody: parsed.smsBody,
              smsSender: parsed.smsSender,
              upiApp: parsed.upiApp,
              upiRefNo: parsed.upiRefNo,
              referenceId: parsed.referenceId,
              autoDetected: true,
            ),
          ),
        ),
      );
      ref.read(pendingSmsConfirmationsProvider.notifier).removePending(parsed);
    } else if (action == SmsConfirmAction.dismissed) {
      ref.read(pendingSmsConfirmationsProvider.notifier).removePending(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(currentTabIndexProvider);
    final showFab = currentIndex == 0 || currentIndex == 1 || currentIndex == 2;
    final activeUser = ref.watch(activeAppUserProvider);

    // Web: activate the live-sync WS listener (no-op on Android).
    final webLiveState = kIsWeb ? ref.watch(webLiveSyncProvider) : null;

    // Device session: null = primary; non-null = secondary.
    final sessionAsync   = ref.watch(activeDeviceSessionProvider);
    final session        = sessionAsync.valueOrNull;
    final sessionPreset  = session?.token.preset;
    final isStaffTerminal = sessionPreset != null && sessionPreset != 'owner_mirror';

    final visibleTabs = _computeVisibleTabs(sessionPreset);

    // If the current screen index is hidden for this preset, reset to 0.
    if (!visibleTabs.any((t) => t.screenIndex == currentIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(currentTabIndexProvider.notifier).state = 0;
      });
    }

    // Map actual screen index -> nav bar index (clamp for safety).
    final navBarIndex = visibleTabs
        .indexWhere((t) => t.screenIndex == currentIndex)
        .clamp(0, visibleTabs.length - 1);

    // Layer 1: module required per bottom-nav tab index.
    // Owner (activeUser == null) bypasses all checks.
    const tabModules = [
      PermissionModule.transactions, // 0: Home
      PermissionModule.transactions, // 1: Transactions
      PermissionModule.invoices,     // 2: Business
      PermissionModule.credits,      // 3: Contacts
      null,                          // 4: Settings — always visible
    ];

    Future<void> handleTabSelected(int screenIndex) async {
      if (activeUser == null) {
        ref.read(currentTabIndexProvider.notifier).state = screenIndex;
        return;
      }
      final module = tabModules[screenIndex];
      if (module == null) {
        ref.read(currentTabIndexProvider.notifier).state = screenIndex;
        return;
      }
      final perm = await ref.read(permissionProvider(
        (module: module, businessId: UserPermission.kPersonalScope),
      ));
      if (!perm.canView) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("You don't have access to this section.")),
          );
        }
        return;
      }
      ref.read(currentTabIndexProvider.notifier).state = screenIndex;
    }

    // Show Add-Party sheet whenever a contact arrives via deep link or
    // install referrer — one-shot, resets to null after handling.
    ref.listen<String?>(pendingDeepLinkVCardProvider, (_, vcard) {
      if (vcard != null && mounted) {
        ref.read(pendingDeepLinkVCardProvider.notifier).state = null;
        _showPartyFromVCard(vcard);
      }
    });

    // Dynamically start/stop real-time SMS listener when the toggle changes.
    ref.listen<bool>(smsAutoDetectEnabledProvider, (_, next) {
      if (next) {
        if (!_smsListenerStarted) {
          final smsService = ref.read(smsServiceProvider);
          smsService.hasPermission.then((granted) {
            if (!granted) return; // permission not available — don't set flag
            if (!mounted) return;
            _smsListenerStarted = true;
            smsService.startListening(
              onTransactionDetected: _onSmsTransactionDetected,
            );
          });
        }
      } else {
        _smsListenerStarted = false;
        ref.read(smsServiceProvider).stopListening();
      }
    });

    // Badge count for pending SMS confirmations.
    final pendingCount = ref.watch(pendingSmsConfirmationsProvider).length;

    // Overlay a badge on the Home destination when there are pending SMS.
    final displayedTabs = pendingCount > 0
        ? [
            for (final tab in visibleTabs)
              if (tab.screenIndex == 0)
                _TabSpec(
                  0,
                  NavigationDestination(
                    icon: Badge(
                      label: Text(pendingCount > 9 ? '9+' : '$pendingCount'),
                      child: const Icon(Icons.home_outlined),
                    ),
                    selectedIcon: Badge(
                      label: Text(pendingCount > 9 ? '9+' : '$pendingCount'),
                      child: const Icon(Icons.home),
                    ),
                    label: 'Home',
                  ),
                )
              else
                tab,
          ]
        : visibleTabs;

    return Scaffold(
      body: Column(
        children: [
          // Read-only banner: shown when grace period exceeded on a secondary.
          const ReadOnlyModeBanner(),
          // Web: persistent banner when the live WS connection to the phone is down.
          if (kIsWeb && webLiveState != null && !webLiveState.isConnected)
            const _WebDisconnectedBanner(),
          // Staff mode indicator: subtle top bar for non-owner-mirror secondaries.
          if (isStaffTerminal) _StaffModeBanner(session: session!),
          // Context banner: shown when viewing a linked business session.
          const ContextBannerWidget(),
          Expanded(
            child: IndexedStack(
              index: currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navBarIndex,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (navIdx) {
          handleTabSelected(visibleTabs[navIdx].screenIndex);
        },
        destinations: displayedTabs.map((t) => t.destination).toList(),
      ),
      floatingActionButton: showFab
          ? SpeedDialFab(
              transactionsTabOnly: currentIndex == 1,
              showAllOptions: currentIndex != 2,
            )
          : null,
    );
  }
}

/// Thin banner shown below the status bar when the current device is a linked
/// secondary (non-owner-mirror).  Reminds the user they are in staff mode.
class _StaffModeBanner extends StatelessWidget {
  const _StaffModeBanner({required this.session});

  final dynamic session; // DeviceSessionToken host object

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.secondary.withAlpha(26),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Row(
          children: [
            Icon(
              Icons.store_outlined,
              size: 14,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 6),
            Text(
              'Staff Mode',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Speed Dial FAB → see lib/presentation/widgets/speed_dial_fab.dart

// ---------------------------------------------------------------------------
// Web disconnected banner
// ---------------------------------------------------------------------------

/// Shown on the browser companion when the live WS connection to the phone
/// has dropped.  Data is read-only and may be stale until reconnected.
class _WebDisconnectedBanner extends StatelessWidget {
  const _WebDisconnectedBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 16, color: cs.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Disconnected from phone — showing last synced data.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
