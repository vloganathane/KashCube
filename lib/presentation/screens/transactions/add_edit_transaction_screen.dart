import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/bill_attachment.dart';
import '../../../data/models/transaction.dart';
import '../../../data/services/suggestion_service.dart';
import '../../providers/bill_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/suggestion_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/bill_picker.dart';

/// Screen for adding or editing a transaction.
///
/// Pass [transaction] to edit an existing one; omit for new entry.
/// Use [initialType] to pre-select the transaction type (e.g., from Ledger screen).
/// Use [initialPartyName] to pre-fill the party name field.
class AddEditTransactionScreen extends ConsumerStatefulWidget {
  const AddEditTransactionScreen({
    super.key,
    this.transaction,
    this.initialType,
    this.initialPartyName,
  });

  /// If non-null, we're editing this transaction.
  final Transaction? transaction;

  /// Pre-select this type when creating a new transaction.
  final TransactionType? initialType;

  /// Pre-fill the party name field when creating a new transaction.
  final String? initialPartyName;

  bool get isEditing => transaction != null;

  @override
  ConsumerState<AddEditTransactionScreen> createState() =>
      _AddEditTransactionScreenState();
}

class _AddEditTransactionScreenState
    extends ConsumerState<AddEditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _partyNameController = TextEditingController();
  final _notesController = TextEditingController();
  final _interestRateController = TextEditingController();

  late TransactionType _type;
  late TransactionMode _mode;
  late String _category;
  late PaymentMethod _paymentMethod;
  late DateTime _date;
  late TimeOfDay _time;

  // Lending / investment extra fields
  DateTime? _dueDate;
  InterestType _interestType = InterestType.none;

  bool _isSaving = false;

  // Bill attachment state
  BillPickerResult? _pendingBill;
  BillAttachment? _existingBill;
  bool _billRemoved = false;

  // Smart suggestion state
  TransactionSuggestion? _activeSuggestion;
  bool _suggestionApplied = false;

  @override
  void initState() {
    super.initState();
    final txn = widget.transaction;
    if (txn != null) {
      _amountController.text = txn.amount.toStringAsFixed(
        txn.amount == txn.amount.roundToDouble() ? 0 : 2,
      );
      _partyNameController.text = txn.partyName ?? '';
      _notesController.text = txn.notes ?? '';
      _type = txn.type;
      _mode = txn.mode;
      _category = txn.category;
      _paymentMethod = txn.paymentMethod;
      _date = txn.date;
      _time = TimeOfDay.fromDateTime(txn.date);
      _dueDate = txn.dueDate;
      _interestType = txn.interestType ?? InterestType.none;
      if (txn.interestRate != null) {
        _interestRateController.text = txn.interestRate!.toStringAsFixed(1);
      }
      // Load existing bill for this transaction
      _loadExistingBill(txn.id!);
    } else {
      _type = widget.initialType ?? TransactionType.expense;
      _mode = TransactionMode.personal;
      _category = AppConstants.defaultCategories.first;
      _paymentMethod = PaymentMethod.upi;
      _date = DateTime.now();
      _time = TimeOfDay.now();
      if (widget.initialPartyName != null) {
        _partyNameController.text = widget.initialPartyName!;
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _partyNameController.dispose();
    _notesController.dispose();
    _interestRateController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingBill(int transactionId) async {
    final repo = ref.read(billRepositoryProvider);
    final bill = await repo.getByTransactionId(transactionId);
    if (mounted && bill != null) {
      setState(() => _existingBill = bill);
    }
  }

  List<String> get _categoriesForType {
    if (_type == TransactionType.income) {
      return AppConstants.incomeCategories;
    }
    if (_type.isLending || _type.isSettlement || _type.isInvestment) {
      return ['Lending / Credit', 'Investment', 'Other'];
    }
    return AppConstants.defaultCategories;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEditing ? 'Edit Transaction' : 'Add Transaction';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // Transaction type selector — progressive disclosure chips
            _TypeSelector(
              selected: _type,
              onChanged: (type) {
                setState(() {
                  _type = type;
                  // Reset category when type group changes
                  final cats = _categoriesForType;
                  if (!cats.contains(_category)) {
                    _category = cats.first;
                  }
                });
              },
            ),
            const SizedBox(height: AppSpacing.xl),

            // Amount Field
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                prefixStyle: TextStyle(
                  color: context.colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                hintText: '0',
              ),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                fontFamily: 'RobotoMono',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              validator: Validators.validateAmount,
              autofocus: !widget.isEditing,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Category — only for income / expense
            if (_type.isIncome || _type.isExpense) ...[
              DropdownButtonFormField<String>(
                initialValue: _categoriesForType.contains(_category)
                    ? _category
                    : _categoriesForType.first,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _categoriesForType
                    .map((cat) => DropdownMenuItem(
                          value: cat,
                          child: Text(cat),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Party Name with Autocomplete
            _buildPartyNameField(),

            // Smart suggestion chip
            if (_activeSuggestion != null && !_suggestionApplied)
              _buildSuggestionChip(),
            const SizedBox(height: AppSpacing.lg),

            // Due date — for lent / borrowed
            if (_type == TransactionType.lent || _type == TransactionType.borrowed) ...[
              _DueDateField(
                dueDate: _dueDate,
                onChanged: (d) => setState(() => _dueDate = d),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Interest section
              _InterestSection(
                selectedType: _interestType,
                rateController: _interestRateController,
                onTypeChanged: (t) => setState(() => _interestType = t),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Date & Time Row
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    date: _date,
                    onChanged: (date) => setState(() => _date = date),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _TimeField(
                    time: _time,
                    onChanged: (time) => setState(() => _time = time),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Payment Method — for income / expense / settlement only
            if (_type.isIncome ||
                _type.isExpense ||
                _type.isSettlement) ...[
              DropdownButtonFormField<PaymentMethod>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  prefixIcon: Icon(Icons.payment_outlined),
                ),
                items: PaymentMethod.values
                    .map((method) => DropdownMenuItem(
                          value: method,
                          child: Text(method.label),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _paymentMethod = value);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Mode Toggle
            _ModeChips(
              selected: _mode,
              onChanged: (mode) => setState(() => _mode = mode),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: Icon(Icons.note_outlined),
                hintText: 'Add a note...',
              ),
              maxLines: 2,
              maxLength: 500,
              validator: Validators.validateNotes,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Bill Attachment — only for income / expense
            if (_type.isIncome || _type.isExpense) ...[
              _buildBillSection(),
              const SizedBox(height: AppSpacing.xxl),
            ] else
              const SizedBox(height: AppSpacing.xxl),

            // Save Button
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(widget.isEditing ? Icons.check : Icons.add),
              label: Text(widget.isEditing ? 'Update Transaction' : 'Add Transaction'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildPartyNameField() {
    final knownNamesAsync = ref.watch(knownPartyNamesProvider);
    final knownNames = knownNamesAsync.valueOrNull ?? [];

    return Autocomplete<String>(
      initialValue: _partyNameController.value,
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return const [];
        final query = textEditingValue.text.toLowerCase();
        return knownNames
            .where((name) => name.toLowerCase().contains(query))
            .take(5);
      },
      onSelected: (selected) {
        _partyNameController.text = selected;
        _fetchSuggestionForParty(selected);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        // Sync the external controller
        controller.text = _partyNameController.text;
        controller.addListener(() {
          if (_partyNameController.text != controller.text) {
            _partyNameController.text = controller.text;
          }
        });

        final partyRequired = _type.requiresParty;
        final partyLabel = switch (_type) {
          TransactionType.lent => 'Borrower Name *',
          TransactionType.borrowed => 'Lender Name *',
          TransactionType.invested => 'Institution / Fund *',
          TransactionType.redeemed => 'Institution / Fund *',
          TransactionType.receivedBack => 'Party Name *',
          TransactionType.paidBack => 'Party Name *',
          _ => 'Party / Merchant (optional)',
        };
        final partyHint = switch (_type) {
          TransactionType.lent => 'e.g. Ramesh, Priya',
          TransactionType.borrowed => 'e.g. Bank, Friend',
          TransactionType.invested => 'e.g. Zerodha, SBI MF',
          _ => 'e.g. Swiggy, Ramesh',
        };
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: partyLabel,
            prefixIcon: const Icon(Icons.person_outline),
            hintText: partyHint,
          ),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: partyRequired
              ? (v) => v == null || v.trim().isEmpty ? 'Required' : null
              : null,
          onEditingComplete: () {
            onFieldSubmitted();
            if (controller.text.isNotEmpty) {
              _fetchSuggestionForParty(controller.text);
            }
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(option),
                    leading: const Icon(Icons.history, size: 18),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuggestionChip() {
    final suggestion = _activeSuggestion!;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Card(
        color: context.colorScheme.primaryContainer.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: context.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Previously: ${suggestion.category} via ${suggestion.paymentMethod.label}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: _applySuggestion,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Apply'),
              ),
              IconButton(
                onPressed: () => setState(() => _suggestionApplied = true),
                icon: const Icon(Icons.close, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fetchSuggestionForParty(String partyName) async {
    if (widget.isEditing) return; // Don't suggest when editing

    final service = ref.read(suggestionServiceProvider);
    final suggestion = await service.suggestForParty(partyName);
    if (mounted && suggestion != null) {
      setState(() {
        _activeSuggestion = suggestion;
        _suggestionApplied = false;
      });
    }
  }

  void _applySuggestion() {
    final suggestion = _activeSuggestion;
    if (suggestion == null) return;

    setState(() {
      // Apply category if it exists in current type's list
      final cats = _categoriesForType;
      if (cats.contains(suggestion.category)) {
        _category = suggestion.category;
      }
      _paymentMethod = suggestion.paymentMethod;
      _mode = suggestion.mode;
      _suggestionApplied = true;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final dateTime = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );

    final amount = double.parse(
      _amountController.text.replaceAll(',', ''),
    );

    final transaction = Transaction(
      id: widget.transaction?.id,
      amount: amount,
      date: dateTime,
      type: _type,
      mode: _mode,
      category: _category,
      partyName: _partyNameController.text.trim().isNotEmpty
          ? _partyNameController.text.trim()
          : null,
      paymentMethod: _paymentMethod,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      // Lending / investment fields
      dueDate: _dueDate,
      interestType: _interestType,
      interestRate: _interestRateController.text.isNotEmpty
          ? double.tryParse(_interestRateController.text)
          : null,
      // Preserve existing fields when editing
      partyId: widget.transaction?.partyId,
      phoneNumber: widget.transaction?.phoneNumber,
      accountId: widget.transaction?.accountId,
      smsBody: widget.transaction?.smsBody,
      smsSender: widget.transaction?.smsSender,
      upiApp: widget.transaction?.upiApp,
      upiRefNo: widget.transaction?.upiRefNo,
      referenceId: widget.transaction?.referenceId,
      autoDetected: widget.transaction?.autoDetected ?? false,
      verified: true,
      linkedTransactionId: widget.transaction?.linkedTransactionId,
      parentTransactionId: widget.transaction?.parentTransactionId,
      dedupeHash: widget.transaction?.dedupeHash,
      tags: widget.transaction?.tags,
      createdAt: widget.transaction?.createdAt,
    );

    try {
      if (widget.isEditing) {
        await ref
            .read(transactionsProvider.notifier)
            .updateTransaction(transaction);
      } else {
        await ref
            .read(transactionsProvider.notifier)
            .addTransaction(transaction);
      }

      if (mounted) {
        // Save bill attachment if one was picked
        final txnId = widget.isEditing
            ? widget.transaction!.id!
            : await _getLastInsertedTransactionId();
        if (txnId != null) {
          await _saveBillAttachment(txnId);
        }

        // Refresh dashboard
        ref.read(dashboardSummaryProvider.notifier).loadSummary();
        ref.read(recentTransactionsProvider.notifier).loadRecent();
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        context.showSnackBar('Error saving transaction: $e', isError: true);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text(
          'Are you sure you want to delete this transaction? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(transactionsProvider.notifier)
          .deleteTransaction(widget.transaction!.id!);
      ref.read(dashboardSummaryProvider.notifier).loadSummary();
      ref.read(recentTransactionsProvider.notifier).loadRecent();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Widget _buildBillSection() {
    // Show existing bill (from DB) unless removed
    if (_existingBill != null && !_billRemoved && _pendingBill == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bill / Receipt',
            style: context.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          BillPreviewCard(
            filePath: _existingBill!.filePath,
            fileName: _existingBill!.fileName,
            isPdf: _existingBill!.isPdf,
            fileSize: _existingBill!.fileSize,
            onRemove: () => setState(() => _billRemoved = true),
          ),
        ],
      );
    }

    // Show pending bill (just picked, not yet saved)
    if (_pendingBill != null) {
      final isPdf = _pendingBill!.fileName.toLowerCase().endsWith('.pdf');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bill / Receipt',
            style: context.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          BillPreviewCard(
            filePath: _pendingBill!.filePath,
            fileName: _pendingBill!.fileName,
            isPdf: isPdf,
            onRemove: () => setState(() => _pendingBill = null),
          ),
        ],
      );
    }

    // Show attach button
    return OutlinedButton.icon(
      onPressed: _pickBill,
      icon: const Icon(Icons.receipt_long_outlined),
      label: const Text('Attach Bill / Receipt'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
      ),
    );
  }

  Future<void> _pickBill() async {
    final result = await showBillPicker(context);
    if (result != null) {
      setState(() {
        _pendingBill = result;
        _billRemoved = false;
      });
    }
  }

  Future<void> _saveBillAttachment(int transactionId) async {
    final billNotifier = ref.read(billNotifierProvider(transactionId).notifier);

    // If bill was removed and no new bill picked, delete existing
    if (_billRemoved && _pendingBill == null) {
      await billNotifier.removeBill();
      return;
    }

    // If a new bill was picked, save it
    if (_pendingBill != null) {
      await billNotifier.saveBill(
        sourcePath: _pendingBill!.filePath,
        originalFileName: _pendingBill!.fileName,
      );
    }
  }

  Future<int?> _getLastInsertedTransactionId() async {
    // After adding, refresh and get the latest transaction's ID
    final transactions = ref.read(transactionsProvider).valueOrNull;
    if (transactions != null && transactions.isNotEmpty) {
      return transactions.first.id;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

/// Progressive chip selector for all 8 transaction types.
class _TypeSelector extends StatelessWidget {
  final TransactionType selected;
  final ValueChanged<TransactionType> onChanged;

  const _TypeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Group definitions: label, icon, types
    final groups = [
      (TransactionType.expense, Icons.arrow_upward, 'Spent'),
      (TransactionType.income, Icons.arrow_downward, 'Earned'),
      (TransactionType.lent, Icons.person_add_alt_1, 'Lent'),
      (TransactionType.borrowed, Icons.person_remove_alt_1, 'Borrowed'),
      (TransactionType.invested, Icons.trending_up, 'Invested'),
      (TransactionType.redeemed, Icons.redeem, 'Redeemed'),
      (TransactionType.receivedBack, Icons.call_received, 'Got back'),
      (TransactionType.paidBack, Icons.call_made, 'Paid back'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What happened?',
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: groups.map((g) {
            final (type, icon, label) = g;
            final isSelected = selected == type;
            return ChoiceChip(
              label: Text(label),
              avatar: Icon(icon, size: 16),
              selected: isSelected,
              showCheckmark: false,
              onSelected: (_) => onChanged(type),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Chip-based mode selector (Personal / Business / Investment).
class _ModeChips extends StatelessWidget {
  final TransactionMode selected;
  final ValueChanged<TransactionMode> onChanged;

  const _ModeChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mode', style: context.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final mode in TransactionMode.values)
              ChoiceChip(
                label: Text(mode.label),
                selected: selected == mode,
                onSelected: (_) => onChanged(mode),
              ),
          ],
        ),
      ],
    );
  }
}

/// Tappable date field that opens a DatePicker.
class _DateField extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  const _DateField({required this.date, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date',
          prefixIcon: Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          DateFormat('d MMM yyyy').format(date),
          style: context.textTheme.bodyLarge,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Due date field
// ---------------------------------------------------------------------------

class _DueDateField extends StatelessWidget {
  const _DueDateField({required this.dueDate, required this.onChanged});

  final DateTime? dueDate;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate:
              dueDate ?? DateTime.now().add(const Duration(days: 30)),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        onChanged(picked);
      },
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Due Date (optional)',
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: dueDate != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => onChanged(null),
                )
              : null,
        ),
        child: Text(
          dueDate != null ? DateFormatter.format(dueDate!) : 'Not set',
          style: context.textTheme.bodyLarge,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interest section (for lent / borrowed)
// ---------------------------------------------------------------------------

class _InterestSection extends StatelessWidget {
  const _InterestSection({
    required this.selectedType,
    required this.rateController,
    required this.onTypeChanged,
  });

  final InterestType selectedType;
  final TextEditingController rateController;
  final ValueChanged<InterestType> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Interest',
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: InterestType.values.map((t) {
            return ChoiceChip(
              label: Text(t.label),
              selected: selectedType == t,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onTypeChanged(t),
            );
          }).toList(),
        ),
        if (selectedType != InterestType.none) ...[
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: rateController,
            decoration: const InputDecoration(
              labelText: 'Interest Rate (%)',
              prefixIcon: Icon(Icons.percent),
              suffixText: '%',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          ),
        ],
      ],
    );
  }
}/// Tappable time field that opens a TimePicker.
class _TimeField extends StatelessWidget {
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;

  const _TimeField({required this.time, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Time',
          prefixIcon: Icon(Icons.access_time_outlined),
        ),
        child: Text(
          time.format(context),
          style: context.textTheme.bodyLarge,
        ),
      ),
    );
  }
}
