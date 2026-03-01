import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/parsed_sms.dart';
import '../data/models/transaction.dart';
import '../data/services/sms_parser.dart';
import 'providers/scheduled_payment_provider.dart';
import 'providers/sms_provider.dart';
import 'providers/transaction_provider.dart';
import 'screens/business/business_hub_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/parties/parties_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/transactions/add_edit_transaction_screen.dart';
import 'screens/transactions/transactions_hub_screen.dart';
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
    });
  }

  Future<void> _processRecurringTransactions() async {
    await processScheduledAutoCreations(ref);
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
    final showFab = currentIndex == 0 || currentIndex == 1;

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
      floatingActionButton: showFab ? const SpeedDialFab() : null,
    );
  }
}

// Speed Dial FAB → see lib/presentation/widgets/speed_dial_fab.dart
