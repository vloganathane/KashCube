import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/permission.dart';
import '../data/models/user_permission.dart';
import '../core/constants/app_config.dart';
import '../core/extensions/context_extensions.dart';
import '../core/utils/adaptive_sheet.dart';
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
import 'web/web_connection_banner.dart';

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

/// Returns the visible tab specs (all tabs — sync-based preset filtering removed).
List<_TabSpec> _computeVisibleTabs() {
  return const [
    _TabSpec(0, NavigationDestination(icon: Icon(Icons.home_outlined),         selectedIcon: Icon(Icons.home),         label: 'Home')),
    _TabSpec(1, NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Transactions')),
    _TabSpec(2, NavigationDestination(icon: Icon(Icons.storefront_outlined),   selectedIcon: Icon(Icons.storefront),   label: 'Business')),
    _TabSpec(3, NavigationDestination(icon: Icon(Icons.people_outline),        selectedIcon: Icon(Icons.people),       label: 'Contacts')),
    _TabSpec(4, NavigationDestination(icon: Icon(Icons.settings_outlined),     selectedIcon: Icon(Icons.settings),     label: 'Settings')),
  ];
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

  /// Per-tab [Navigator] keys — one per tab in [IndexedStack].
  /// Allows each tab to maintain its own push stack while the bottom nav
  /// bar remains visible at all depths.
  final List<GlobalKey<NavigatorState>> _tabNavKeys =
      List.generate(5, (_) => GlobalKey<NavigatorState>());

  /// Tab navigator widgets — created ONCE in [initState] and never rebuilt.
  /// Keeping stable widget objects prevents Flutter from briefly unmounting
  /// route elements on every [AppShell] rebuild (e.g. SMS badge changes),
  /// which would leave captured [BuildContext]s stale inside open dialogs.
  late final List<Widget> _tabScreens;

  /// One observer per tab — calls setState when the stack depth changes so
  /// [showFab] can hide the SpeedDial when a sub-screen is on top.
  late final List<_StackObserver> _tabObservers;

  @override
  void initState() {
    super.initState();
    _tabObservers = List.generate(
      5,
      (_) => _StackObserver(() { if (mounted) setState(() {}); }),
    );
    _tabScreens = [
      Navigator(key: _tabNavKeys[0], observers: [_tabObservers[0]], onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const HomeScreen())),
      Navigator(key: _tabNavKeys[1], observers: [_tabObservers[1]], onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const TransactionsHubScreen())),
      Navigator(key: _tabNavKeys[2], observers: [_tabObservers[2]], onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const BusinessHubScreen())),
      Navigator(key: _tabNavKeys[3], observers: [_tabObservers[3]], onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const PartiesScreen())),
      Navigator(key: _tabNavKeys[4], observers: [_tabObservers[4]], onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
    ];
    // Kick off SMS listener after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb) {
        _initSmsListener();
        _initDeepLinks();
      }
      _processRecurringTransactions();
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

    showAdaptiveSheet<void>(
      context,
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
    final subRouteActive = _tabNavKeys[currentIndex].currentState?.canPop() ?? false;
    final showFab = (currentIndex == 0 || currentIndex == 1 || currentIndex == 2)
        && !subRouteActive;
    final activeUser = ref.watch(activeAppUserProvider);
    final isWide = context.isExpanded; // ≥840 dp → NavigationRail layout

    final visibleTabs = _computeVisibleTabs();

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
      // Tapping the already-active tab pops to the root of that tab's stack.
      if (screenIndex == currentIndex) {
        _tabNavKeys[screenIndex].currentState?.popUntil((r) => r.isFirst);
        return;
      }
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

    // Build content stack once; wrap with web-disconnect banner when on web.
    Widget contentStack = IndexedStack(index: currentIndex, children: _tabScreens);
    if (kIsWeb) contentStack = WebConnectionBanner(child: contentStack);

    return PopScope(
      // Never pop the shell itself. Forward Android back to the active tab's
      // Navigator; if the tab is already at its root, minimize the app.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final tabNav = _tabNavKeys[currentIndex].currentState;
        if (tabNav != null && tabNav.canPop()) {
          tabNav.pop();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      body: Column(
        children: [
          // Context banner: shown when viewing a linked business session.
          const ContextBannerWidget(),
          if (isWide)
            // ── Expanded layout: NavigationRail + constrained content ─────
            Expanded(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: navBarIndex,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (navIdx) =>
                        handleTabSelected(visibleTabs[navIdx].screenIndex),
                    destinations: displayedTabs
                        .map(
                          (t) => NavigationRailDestination(
                            icon: t.destination.icon,
                            selectedIcon: t.destination.selectedIcon,
                            label: Text(t.destination.label),
                          ),
                        )
                        .toList(),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(child: contentStack),
                ],
              ),
            )
          else
            // ── Compact/medium layout: full-width content ─────────────────
            Expanded(child: contentStack),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: navBarIndex,
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
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
      ),
    );
  }
}

// Speed Dial FAB → see lib/presentation/widgets/speed_dial_fab.dart

/// Minimal [NavigatorObserver] that fires [onChanged] on every stack
/// mutation (push / pop / replace / remove), allowing [AppShell] to
/// rebuild and hide the global SpeedDial FAB when a sub-route is active.
class _StackObserver extends NavigatorObserver {
  _StackObserver(this.onChanged);
  final VoidCallback onChanged;

  @override void didPush(Route route, Route? previousRoute) => onChanged();
  @override void didPop(Route route, Route? previousRoute) => onChanged();
  @override void didRemove(Route route, Route? previousRoute) => onChanged();
  @override void didReplace({Route? newRoute, Route? oldRoute}) => onChanged();
}
