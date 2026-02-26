import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/parsed_sms.dart';
import '../data/models/transaction.dart';
import '../data/services/sms_parser.dart';
import 'providers/scheduled_payment_provider.dart';
import 'providers/report_provider.dart';
import 'providers/sms_provider.dart';
import 'providers/transaction_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/bills/bills_and_payments_screen.dart';
import 'screens/invoices/quote_builder_screen.dart';
import 'screens/ledger/ledger_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/loans/loans_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/transactions/add_edit_transaction_screen.dart';
import 'screens/transactions/transactions_screen.dart';
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
    TransactionsScreen(),
    LedgerScreen(),
    ReportsScreen(),
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
    final showFab = currentIndex == 0 || currentIndex == 1 || currentIndex == 2;

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          if (index == 3) {
            ref.invalidate(monthlyPnLProvider);
            ref.invalidate(monthlyTotalsProvider);
            ref.invalidate(dailyTotalsProvider);
          }
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
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Ledger',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Reports',
          ),
        ],
      ),
      floatingActionButton: showFab ? const _SpeedDialFab() : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Speed Dial FAB
// ---------------------------------------------------------------------------

class _SpeedDialFab extends ConsumerStatefulWidget {
  const _SpeedDialFab();

  @override
  ConsumerState<_SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends ConsumerState<_SpeedDialFab>
    with SingleTickerProviderStateMixin {

  bool _open = false;
  late final AnimationController _ctrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  void _close() {
    setState(() => _open = false);
    _ctrl.reverse();
  }

  void _openTransaction() {
    _close();
    Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddEditTransactionScreen()),
    );
  }

  void _openLoan() async {
    _close();
    Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddLedgerEntryScreen()),
    );
  }

  void _openBillsAndPayments() {
    _close();
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => const AddEditScheduledPaymentScreen()),
    );
  }

  void _openNewInvoice() {
    _close();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const QuoteBuilderScreen(docType: DocumentType.invoice),
      ),
    );
  }

  void _openNewQuote() {
    _close();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QuoteBuilderScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ── Option: Invoice (business mode only) ──────────────────────────
        if (ref.watch(businessModeProvider)) ...[  
          ScaleTransition(
            scale: _expandAnim,
            child: FadeTransition(
              opacity: _expandAnim,
              child: _SpeedDialOption(
                icon: Icons.receipt_outlined,
                label: 'Invoice',
                onTap: _openNewInvoice,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ScaleTransition(
            scale: _expandAnim,
            child: FadeTransition(
              opacity: _expandAnim,
              child: _SpeedDialOption(
                icon: Icons.request_quote_outlined,
                label: 'Quote',
                onTap: _openNewQuote,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Option: Bills & Payments ───────────────────────────────────────
        ScaleTransition(
          scale: _expandAnim,
          child: FadeTransition(
            opacity: _expandAnim,
            child: _SpeedDialOption(
              icon: Icons.event_repeat,
              label: 'Bills & Pay',
              onTap: _openBillsAndPayments,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Option: Loan / Lend ────────────────────────────────────────
        ScaleTransition(
          scale: _expandAnim,
          child: FadeTransition(
            opacity: _expandAnim,
            child: _SpeedDialOption(
              icon: Icons.handshake_outlined,
              label: 'Loan / Lend',
              onTap: _openLoan,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Option: Transaction ────────────────────────────────────────
        ScaleTransition(
          scale: _expandAnim,
          child: FadeTransition(
            opacity: _expandAnim,
            child: _SpeedDialOption(
              icon: Icons.receipt_long_outlined,
              label: 'Transaction',
              onTap: _openTransaction,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Main FAB ───────────────────────────────────────────────────
        FloatingActionButton(
          heroTag: 'fab_speed_dial',
          onPressed: _toggle,
          child: AnimatedRotation(
            turns: _open ? 0.125 : 0, // 45° when open → × icon feel
            duration: const Duration(milliseconds: 220),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

class _SpeedDialOption extends StatelessWidget {
  const _SpeedDialOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label pill
        Material(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Mini FAB
        FloatingActionButton.small(
          heroTag: 'fab_$label',
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }
}
