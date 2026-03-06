import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_config.dart';
import '../core/utils/deep_link_vcard.dart';
import '../core/utils/vcard_builder.dart' show parseVCard;
import '../data/models/parsed_sms.dart';
import '../data/models/party.dart';
import '../data/models/transaction.dart';
import '../data/services/sms_parser.dart';
import 'providers/deep_link_provider.dart';
import 'providers/party_provider.dart';
import 'providers/scheduled_payment_provider.dart';
import 'providers/sms_provider.dart';
import 'providers/transaction_provider.dart';
import 'screens/business/business_hub_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/parties/parties_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/transactions/add_edit_transaction_screen.dart';
import 'screens/transactions/transactions_hub_screen.dart';
import 'widgets/party_form_sheet.dart';
import 'widgets/speed_dial_fab.dart';
import 'widgets/sms_confirmation_sheet.dart';

/// Provider for the current bottom navigation tab index.
final currentTabIndexProvider = StateProvider<int>((ref) => 0);

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

    // Show Add-Party sheet whenever a contact arrives via deep link or
    // install referrer — one-shot, resets to null after handling.
    ref.listen<String?>(pendingDeepLinkVCardProvider, (_, vcard) {
      if (vcard != null && mounted) {
        ref.read(pendingDeepLinkVCardProvider.notifier).state = null;
        _showPartyFromVCard(vcard);
      }
    });

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (index) {
          ref.read(currentTabIndexProvider.notifier).state = index;
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Business',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
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

// Speed Dial FAB → see lib/presentation/widgets/speed_dial_fab.dart
