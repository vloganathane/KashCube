import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../screens/bills/bills_and_payments_screen.dart';
import '../screens/bookings/create_booking_screen.dart';
import '../screens/invoices/quote_builder_screen.dart';
import '../screens/ledger/credits_screen.dart';
import '../screens/loans/loans_screen.dart';
import '../screens/invoices/item_catalog_screen.dart';
import '../screens/transactions/add_edit_transaction_screen.dart';

/// Shared speed-dial FAB used on the home shell, Invoices & Quotes screen,
/// and the Transactions tab.
///
/// Behaviour modes:
/// - [showAllOptions] = true, [transactionsTabOnly] = false → home shell
///   (all options: business + transaction + loan + bills in respective modes)
/// - [showAllOptions] = false → invoices/business screen (invoice + quote only)
/// - [transactionsTabOnly] = true → transactions tab (transaction + loan +
///   bills only; hides invoice / quote / booking even in business mode)
class SpeedDialFab extends ConsumerStatefulWidget {
  const SpeedDialFab({
    super.key,
    this.showAllOptions = true,
    this.transactionsTabOnly = false,
  });

  /// If true (default), shows Transaction / Loan / Bills options in addition
  /// to Invoice / Quote. Set to false when used inside the Invoices screen.
  final bool showAllOptions;

  /// When true, suppresses Invoice / Quote / Booking options so only the
  /// transaction-relevant actions (Transaction, Loan/Lend, Bills Payable)
  /// are shown. Takes precedence over [showAllOptions] for business items.
  final bool transactionsTabOnly;

  @override
  ConsumerState<SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends ConsumerState<SpeedDialFab>
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

  void _openLoan() {
    _close();
    Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddLedgerEntryScreen()),
    );
  }

  void _openUdhar() {
    _close();
    Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddCreditScreen()),
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

  void _openNewBooking() {
    _close();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CreateBookingScreen(),
      ),
    );
  }

  void _openAddItem() {
    _close();
    showAddItemSheet(context, ref);
  }

  Widget _animated(Widget child) => ScaleTransition(
        scale: _expandAnim,
        child: FadeTransition(opacity: _expandAnim, child: child),
      );

  @override
  Widget build(BuildContext context) {
    final isBusiness = ref.watch(businessModeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
// ── Invoice + Quote + Booking + Item (business mode, not on transactions tab) ──
        if (isBusiness && !widget.transactionsTabOnly) ...[          
          _animated(SpeedDialOption(
            icon: Icons.inventory_2_outlined,
            label: 'Add Item',
            onTap: _openAddItem,
          )),
          const SizedBox(height: 12),
          _animated(SpeedDialOption(
            icon: Icons.receipt_outlined,
            label: 'Invoice',
            onTap: _openNewInvoice,
          )),
          const SizedBox(height: 12),
          _animated(SpeedDialOption(
            icon: Icons.request_quote_outlined,
            label: 'Quote',
            onTap: _openNewQuote,
          )),
          const SizedBox(height: 12),
          _animated(SpeedDialOption(
            icon: Icons.calendar_month_outlined,
            label: 'Booking',
            onTap: _openNewBooking,
          )),
          const SizedBox(height: 12),
        ],

        // ── Transaction / Loan / Bills (home shell only) ────────────────
        if (widget.showAllOptions) ...[
          _animated(SpeedDialOption(
            icon: Icons.event_repeat,
            label: 'Bills Payable',
            onTap: _openBillsAndPayments,
          )),
          const SizedBox(height: 12),
          _animated(SpeedDialOption(
            icon: Icons.currency_rupee_outlined,
            label: 'Dues',
            onTap: _openUdhar,
          )),
          const SizedBox(height: 12),
          _animated(SpeedDialOption(
            icon: Icons.handshake_outlined,
            label: 'Loan / Lend',
            onTap: _openLoan,
          )),
          const SizedBox(height: 12),
          _animated(SpeedDialOption(
            icon: Icons.receipt_long_outlined,
            label: 'Transaction',
            onTap: _openTransaction,
          )),
          const SizedBox(height: 12),
        ],

        const SizedBox(height: 4),

        // ── Main FAB ───────────────────────────────────────────────────
        FloatingActionButton(
          heroTag: 'fab_speed_dial',
          onPressed: _toggle,
          child: AnimatedRotation(
            turns: _open ? 0.125 : 0,
            duration: const Duration(milliseconds: 220),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

class SpeedDialOption extends StatelessWidget {
  const SpeedDialOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                label,
                style: TextStyle(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.small(
          heroTag: 'fab_$label',
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }
}
