import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/tutorial_mixin.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/bill_attachment.dart';
import '../../../data/models/account.dart';
import '../../../data/models/party.dart';
import '../../../data/models/transaction.dart';
import '../../../data/services/suggestion_service.dart';
import '../../providers/account_provider.dart';
import '../../providers/bill_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/suggestion_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/tutorial_flow_provider.dart';
import '../../widgets/party_picker_field.dart';
import '../../widgets/account_picker_sheet.dart';
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
    this.initialCategory,
    this.initialAmount,
    this.initialDescription,
  });

  /// If non-null, we're editing this transaction.
  final Transaction? transaction;

  /// Pre-select this type when creating a new transaction.
  final TransactionType? initialType;

  /// Pre-fill the party name field when creating a new transaction.
  final String? initialPartyName;

  /// Pre-select this category when creating a new transaction.
  final String? initialCategory;

  /// Pre-fill the amount field when creating a new transaction.
  final double? initialAmount;

  /// Pre-fill the description/notes field when creating a new transaction.
  final String? initialDescription;

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

  // Keys used by the guided Add Transaction tutorial flow (Quick mode).
  final _amountFieldKey   = GlobalKey();
  final _categoryFieldKey = GlobalKey();
  final _saveButtonKey    = GlobalKey();

  // Keys used by the Detail field-reference mode (all form fields).
  final _typeChipsKey     = GlobalKey();
  final _accountFieldKey  = GlobalKey();
  final _partyFieldKey    = GlobalKey();
  final _dateTimeKey      = GlobalKey();
  final _paymentMethodKey = GlobalKey();
  final _modeKey          = GlobalKey();
  final _notesKey         = GlobalKey();
  final _addCategoryKey   = GlobalKey();
  final _billAttachKey    = GlobalKey();

  late TransactionType _type;
  late TransactionMode _mode;
  late String _category;
  late PaymentMethod _paymentMethod;
  late DateTime _date;
  late TimeOfDay _time;

  // Lending / investment extra fields
  DateTime? _dueDate;
  InterestType _interestType = InterestType.none;

  // Transfer fields
  int? _fromAccountId;
  int? _toAccountId;

  // Account for non-transfer types
  int? _accountId;

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
      final rawAmount = txn.amount.toStringAsFixed(
        txn.amount == txn.amount.roundToDouble() ? 0 : 2,
      );
      _amountController.text = IndianCurrencyInputFormatter.format(rawAmount);
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
      _fromAccountId = txn.accountId;
      _toAccountId = txn.toAccountId;
      _accountId = txn.accountId;
      if (txn.interestRate != null) {
        _interestRateController.text = txn.interestRate!.toStringAsFixed(1);
      }
      // Load existing bill for this transaction
      _loadExistingBill(txn.id!);
    } else {
      _type = widget.initialType ?? TransactionType.expense;
      _mode = TransactionMode.personal;
      _category = widget.initialCategory ?? AppConstants.defaultCategories.first;
      _paymentMethod = PaymentMethod.upi;
      _date = DateTime.now();
      _time = TimeOfDay.now();
      if (widget.initialPartyName != null) {
        _partyNameController.text = widget.initialPartyName!;
      }
      if (widget.initialAmount != null) {
        final rawAmount = widget.initialAmount!.toStringAsFixed(
          widget.initialAmount! == widget.initialAmount!.roundToDouble() ? 0 : 2,
        );
        _amountController.text = IndianCurrencyInputFormatter.format(rawAmount);
      }
      if (widget.initialDescription != null) {
        _notesController.text = widget.initialDescription!;
      }
    }

    // If the Add Transaction tutorial flow is active, show the form guide
    // after the first frame so all keys are mounted.
    if (!widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final step = ref.read(tutorialFlowProvider);
        if (step == TutorialFlowStep.addTxAmount) _showFormFlowMark();
      });
    }
  }

  void _restartFormTutorial() => _showFormFlowMark();

  /// Detail mode — standalone field-by-field reference. Not connected to
  /// TutorialFlowNotifier; no done-flag; always replayable.
  void _showDetailModeMark() {
    // Only include targets whose keys are currently mounted (some fields are
    // conditionally rendered based on transaction type).
    final targets = <TargetFocus>[
      TargetFocus(
        identify: 'type_chips',
        keyTarget: _typeChipsKey,
        shape: ShapeLightFocus.RRect,
        radius: 8,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: tutorialContentCard(
              title: 'What happened?',
              message: 'Spent / Earned for everyday money.\n'
                  'Lent / Borrowed for money between people.\n'
                  'Invested / Redeemed for savings & MF.',
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'amount',
        keyTarget: _amountFieldKey,
        shape: ShapeLightFocus.RRect,
        radius: 8,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: tutorialContentCard(
              title: 'Amount',
              message: 'Enter in rupees. Indian comma formatting\n'
                  'is applied automatically — ₹1,23,456.',
            ),
          ),
        ],
      ),
      if (_accountFieldKey.currentContext != null)
        TargetFocus(
          identify: 'account',
          keyTarget: _accountFieldKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Account',
                message: 'Which bank or wallet this came from or\n'
                    'went to. Leave blank to record without\n'
                    'account tracking.',
              ),
            ),
          ],
        ),
      if (_categoryFieldKey.currentContext != null)
        TargetFocus(
          identify: 'category',
          keyTarget: _categoryFieldKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Category',
                message: 'Affects your Reports breakdown.\n'
                    'Tap "+ Add custom category" to create\n'
                    'your own.',
              ),
            ),
          ],
        ),
      if (_addCategoryKey.currentContext != null)
        TargetFocus(
          identify: 'add_category',
          keyTarget: _addCategoryKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: '+ Add custom category',
                message: 'Create categories that don\'t exist yet —\n'
                    'e.g. Pet Care, Side Hustle, School Fees.\n'
                    'They appear in Reports immediately.',
              ),
            ),
          ],
        ),
      if (_partyFieldKey.currentContext != null)
        TargetFocus(
          identify: 'party',
          keyTarget: _partyFieldKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Party / Merchant',
                message: 'Who you paid or received from.\n'
                    'Tap the contacts icon to pick from\n'
                    'your saved parties.',
              ),
            ),
          ],
        ),
      TargetFocus(
        identify: 'datetime',
        keyTarget: _dateTimeKey,
        shape: ShapeLightFocus.RRect,
        radius: 8,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: tutorialContentCard(
              title: 'Date & Time',
              message: 'Defaults to now. Tap either field\n'
                  'to change for past or future transactions.',
            ),
          ),
        ],
      ),
      if (_paymentMethodKey.currentContext != null)
        TargetFocus(
          identify: 'payment_method',
          keyTarget: _paymentMethodKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Payment Method',
                message: 'UPI, Cash, Card, Net Banking, or Wallet.\n'
                    'Auto-updates when you pick an Account.',
              ),
            ),
          ],
        ),
      if (_modeKey.currentContext != null)
        TargetFocus(
          identify: 'mode',
          keyTarget: _modeKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Personal / Business',
                message: 'Personal: your own ledger.\n'
                    'Business: records in P&L and can\n'
                    'appear on invoices.',
              ),
            ),
          ],
        ),
      if (_notesKey.currentContext != null)
        TargetFocus(
          identify: 'notes',
          keyTarget: _notesKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Notes (optional)',
                message: 'Add context — ref numbers, descriptions,\n'
                    'or reminders. Optional but fully\n'
                    'searchable in Transactions.',
              ),
            ),
          ],
        ),
      if (_billAttachKey.currentContext != null)
        TargetFocus(
          identify: 'bill_attach',
          keyTarget: _billAttachKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Attach Bill / Receipt',
                message: 'Photo or PDF of the bill. Stored\n'
                    'locally — viewable from the transaction\n'
                    'detail screen anytime.',
              ),
            ),
          ],
        ),
      TargetFocus(
        identify: 'save',
        keyTarget: _saveButtonKey,
        shape: ShapeLightFocus.RRect,
        radius: 8,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: tutorialContentCard(
              title: 'Save',
              message: 'Saves and returns. Balance, reports,\n'
                  'and party ledger update instantly.',
            ),
          ),
        ],
      ),
    ];

    // Scroll the target's widget into view ahead of the spotlight arriving.
    // alignment: 0.2 places the widget ~20% from the top so content above
    // it remains visible and the spotlight isn't clipped by the AppBar.
    void scrollTo(TargetFocus? target) {
      final key = target?.keyTarget;
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.2,
      );
    }

    // When the user taps the current spotlight (target or overlay), scroll
    // to the next field before the focus animation completes (400 ms).
    void scrollToNext(TargetFocus current) {
      final idx = targets.indexWhere((t) => t.identify == current.identify);
      if (idx + 1 < targets.length) scrollTo(targets[idx + 1]);
    }

    // Ensure the first field is visible before the overlay renders.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scrollTo(targets.isEmpty ? null : targets.first),
    );

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      textSkip: 'CLOSE',
      textStyleSkip: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        letterSpacing: 0.5,
      ),
      alignSkip: Alignment.topRight,
      paddingFocus: 8,
      pulseEnable: false, // reference mode — no pulsing, calmer UX
      focusAnimationDuration: const Duration(milliseconds: 400),
      onClickTarget: scrollToNext,
      onClickOverlay: scrollToNext,
      onSkip: () { return true; },
      onFinish: () {},
    ).show(context: context);
  }

  void _showFormFlowMark() {
    // Capture refs before showing overlay — avoids "ref after dispose" crash.
    final flowNotifier = ref.read(tutorialFlowProvider.notifier);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: 'amount',
          keyTarget: _amountFieldKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              // Amount field is near the top; putting content below keeps it
              // clear of the type-selector chips that sit above the field.
              align: ContentAlign.bottom,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Enter the amount',
                message: 'Type the amount in rupees — income,\n'
                    'expense, cash, UPI, anything.',
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'category',
          keyTarget: _categoryFieldKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Pick a category',
                message: 'Categorise the transaction so your\n'
                    'reports stay meaningful.',
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'save',
          keyTarget: _saveButtonKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Save your transaction',
                message: 'Tap here when you\'re done — your\n'
                    'balance updates instantly.',
              ),
            ),
          ],
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      textSkip: 'SKIP',
      textStyleSkip: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        letterSpacing: 0.5,
      ),
      alignSkip: Alignment.topRight,
      paddingFocus: 8,
      pulseEnable: true,
      onFinish: () {}, // user still fills and saves; orchestrator advances in _save()
      onSkip: () {
        Future(() {
          flowNotifier.abandon();
          settingsRepo.set(SettingsKeys.tutorialTxFlowDone, 'true');
        });
        return true;
      },
    ).show(context: context);
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

  Future<void> _syncPaymentMethodForAccount(int accountId) async {
    final cachedAccounts = ref.read(accountsProvider).valueOrNull;
    final List<Account> accounts =
        (cachedAccounts == null || cachedAccounts.isEmpty)
            ? await ref.read(accountRepositoryProvider).getAll()
            : cachedAccounts;
    final matchIndex = accounts.indexWhere((a) => a.id == accountId);
    if (matchIndex < 0 || !mounted || _accountId != accountId) return;
    setState(() {
      _paymentMethod = accounts[matchIndex].accountType.representativeMethod;
    });
  }

  List<String> _categoriesForType(CustomCategoriesState custom) {
    if (_type.isTransfer) return ['Transfer'];
    if (_type.isLending || _type.isSettlement || _type.isInvestment) {
      return ['Lending / Credit', 'Investment', 'Other'];
    }
    final typeKey = _type == TransactionType.income ? 'income' : 'expense';
    return buildCategoryList(custom, typeKey)
        .where((c) => c != kAddCustomCategorysentinel)
        .toList();
  }

  Widget _buildCategoryDropdown() {
    final custom = ref.watch(customCategoriesProvider);
    final cats = _categoriesForType(custom);

    // If the transaction's current category was a custom one that has since
    // been deleted, it won't appear in `cats`. Preserve it as an "orphaned"
    // option so editing the transaction never silently re-categorises it.
    final isOrphaned = _category.isNotEmpty && !cats.contains(_category);
    final allCats = isOrphaned ? [_category, ...cats] : cats;
    final safeCategory = _category.isNotEmpty && allCats.contains(_category)
        ? _category
        : allCats.first;
    // Use plain DropdownButton + InputDecorator instead of DropdownButtonFormField
    // to avoid registering with the parent Form's _FormScope InheritedWidget.
    // DropdownButtonFormField's _FormScope dependency causes _dependents.isEmpty
    // assertion when the dialog's TextFormField opens the IME, which triggers a
    // viewport-metrics rebuild on the underlying screen mid-animation.
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Category',
        prefixIcon: Icon(Icons.category_outlined),
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButton<String>(
        value: safeCategory,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        isDense: true,
        items: allCats.map((cat) {
          if (cat == _category && isOrphaned) {
            return DropdownMenuItem<String>(
              value: cat,
              child: Row(
                children: [
                  Icon(Icons.label_off_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      cat,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'deleted',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ),
            );
          }
          return DropdownMenuItem<String>(value: cat, child: Text(cat));
        }).toList(),
        onChanged: (value) {
          if (value != null) setState(() => _category = value);
        },
      ),
    );
  }

  Future<void> _showAddCategoryDialog() async {
    final typeKey = _type == TransactionType.income ? 'income' : 'expense';
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('New category'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Category name',
              hintText: 'e.g. Pets, Gym, Charity',
              prefixIcon: Icon(Icons.label_outline),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter a name';
              if (v.trim().length > 40) return 'Too long (max 40 chars)';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    // Defer disposal to the next frame so the IME hide animation can complete
    // without hitting a disposed controller.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());

    if (result == null || !mounted) return;

    // Defer setState + provider update to the next frame.
    // This ensures the IME hide / viewport-metrics rebuild triggered by the
    // dialog closing has fully settled before we mutate state, avoiding the
    // _dependents.isEmpty assertion caused by two simultaneous rebuilds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _category = result);
      // ignore: discarded_futures
      ref.read(customCategoriesProvider.notifier).addCategory(result, typeKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEditing ? 'Edit Transaction' : 'Add Transaction';

    // Loan-linked transactions are managed via the Loans screen — show read-only.
    if (widget.isEditing && (widget.transaction?.isLoanLinked ?? false)) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Managed by Loan contract',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'This transaction was auto-created from a Loan. Edit it from the Loans screen instead.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Pre-fill default account for new transactions once the provider loads.
    if (!widget.isEditing) {
      ref.listen<int?>(defaultAccountIdProvider, (_, next) {
        if (next != null && _accountId == null) {
          setState(() => _accountId = next);
          // ignore: discarded_futures
          _syncPaymentMethodForAccount(next);
        }
      });
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          final step = ref.read(tutorialFlowProvider);
          if (step.isAddTxFlow) {
            ref.read(tutorialFlowProvider.notifier).abandon();
            ref.read(settingsRepositoryProvider)
                .set(SettingsKeys.tutorialTxFlowDone, 'true');
          }
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          // ? help button — Quick + Detail on new, Detail only on edit
          if (widget.isEditing)
            IconButton(
              icon: const Icon(Icons.help_outline_rounded),
              tooltip: 'Field reference',
              onPressed: _showDetailModeMark,
            )
          else
            PopupMenuButton<int>(
              icon: const Icon(Icons.help_outline_rounded),
              tooltip: 'Help guides',
              itemBuilder: (_) => const [
                PopupMenuItem(value: 0, child: Text('Quick guide')),
                PopupMenuItem(value: 1, child: Text('Field reference')),
              ],
              onSelected: (v) =>
                  v == 0 ? _restartFormTutorial() : _showDetailModeMark(),
            ),
          if (widget.isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.base),
          child: FilledButton.icon(
            key: _saveButtonKey,
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(widget.isEditing ? Icons.check : Icons.add),
            label: Text(
                widget.isEditing ? 'Update Transaction' : 'Add Transaction'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // Transaction type selector — progressive disclosure chips
            KeyedSubtree(
              key: _typeChipsKey,
              child: _TypeSelector(
                selected: _type,
                onChanged: (type) {
                  setState(() {
                    _type = type;
                    // Reset category when type group changes
                    final custom = ref.read(customCategoriesProvider);
                    final cats = _categoriesForType(custom)
                        .where((c) => c != kAddCustomCategorysentinel)
                        .toList();
                    if (!cats.contains(_category)) {
                      _category = cats.first;
                    }
                    // Reset mode — only personal/business apply to income/expense
                    if (!type.isIncome && !type.isExpense) {
                      _mode = TransactionMode.personal;
                    }
                    // Transfer accounts reset
                    if (!type.isTransfer) {
                      _fromAccountId = null;
                      _toAccountId = null;
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Amount Field
            TextFormField(
              key: _amountFieldKey,
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
              inputFormatters: [IndianCurrencyInputFormatter()],
              validator: Validators.validateAmount,
              // Disable autofocus when the tutorial is guiding through this form;
              // opening the keyboard shifts the ListView layout before the coach
              // mark captures the widget position, making the spotlight miss.
              autofocus: !widget.isEditing &&
                  ref.watch(tutorialFlowProvider) != TutorialFlowStep.addTxAmount,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Transfer: From / To account pickers
            if (_type.isTransfer) ...[  
              _TransferAccountRow(
                fromAccountId: _fromAccountId,
                toAccountId: _toAccountId,
                onFromChanged: (id) => setState(() => _fromAccountId = id),
                onToChanged: (id) => setState(() => _toAccountId = id),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Account picker — for all non-transfer types
            if (!_type.isTransfer) ...[  
              KeyedSubtree(
                key: _accountFieldKey,
                child: _AccountRow(
                  accountId: _accountId,
                  onChanged: (id) {
                    setState(() => _accountId = id);
                    // Auto-set payment method based on account type.
                    if (id != null) {
                      // ignore: discarded_futures
                      _syncPaymentMethodForAccount(id);
                    }
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Category — only for income / expense
            if (_type.isIncome || _type.isExpense) ...[
              KeyedSubtree(
                key: _categoryFieldKey,
                child: _buildCategoryDropdown(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: _addCategoryKey,
                  onPressed: _showAddCategoryDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add custom category'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ),
              if (_type.isExpense)
                _BudgetHintRow(category: _category),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Party Name — not for transfer
            if (!_type.isTransfer) ...[  
              KeyedSubtree(
                key: _partyFieldKey,
                child: _buildPartyNameField(),
              ),
              if (_activeSuggestion != null && !_suggestionApplied)
                _buildSuggestionChip(),
              const SizedBox(height: AppSpacing.lg),
            ],

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
              key: _dateTimeKey,
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
              Builder(
                builder: (_) {
                  final selectedAccount =
                      (ref.watch(accountsProvider).valueOrNull ?? const <Account>[])
                          .where((a) => a.id == _accountId)
                          .firstOrNull;
                  final effectivePaymentMethod =
                      selectedAccount?.accountType.representativeMethod ??
                          _paymentMethod;

                  // Filter payment methods based on selected account type
                  final availableMethods = selectedAccount != null
                      ? selectedAccount.accountType.validPaymentMethods
                      : PaymentMethod.values;

                  return DropdownButtonFormField<PaymentMethod>(
                    key: _paymentMethodKey,
                    initialValue: effectivePaymentMethod,
                    decoration: InputDecoration(
                      labelText: 'Payment Method',
                      prefixIcon: const Icon(Icons.payment_outlined),
                      helperText: _accountId != null
                          ? 'Filtered by account type'
                          : null,
                      helperStyle: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    items: availableMethods
                        .map((method) => DropdownMenuItem(
                              value: method,
                              child: Text(method.label),
                            ))
                        .toList(),
                    onChanged: _accountId != null
                        ? null // Disabled when account is selected
                        : (value) {
                            if (value != null) {
                              setState(() => _paymentMethod = value);
                            }
                          },
                    disabledHint: Text(effectivePaymentMethod.label),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Mode Toggle — only relevant for income / expense
            if (_type.isIncome || _type.isExpense) ...[  
              KeyedSubtree(
                key: _modeKey,
                child: _ModeChips(
                  selected: _mode,
                  onChanged: (mode) => setState(() => _mode = mode),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Notes
            TextFormField(
              key: _notesKey,
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
              KeyedSubtree(
                key: _billAttachKey,
                child: _buildBillSection(),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ] else
              const SizedBox(height: AppSpacing.xxl),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    ), // Scaffold
    ); // PopScope
  }

  Widget _buildPartyNameField() {
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
    return PartyPickerField(
      controller: _partyNameController,
      labelText: partyLabel,
      hintText: partyHint,
      onSelected: _fetchSuggestionForParty,
      onPartySelected: (party) {
        // Auto-set mode from party type — only meaningful for income/expense.
        if (_type == TransactionType.income ||
            _type == TransactionType.expense) {
          final autoMode = switch ((party.partyType, party.partyContext)) {
            (PartyType.vendor, _) ||
            (PartyType.customer, _) ||
            (_, 'business') =>
              TransactionMode.business,
            _ => TransactionMode.personal,
          };
          setState(() => _mode = autoMode);
        }
      },
      validator: partyRequired
          ? (v) => v == null || v.trim().isEmpty ? 'Required' : null
          : null,
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
      final custom = ref.read(customCategoriesProvider);
      final cats = _categoriesForType(custom)
          .where((c) => c != kAddCustomCategorysentinel)
          .toList();
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

    var paymentMethodToSave = _paymentMethod;
    if (_accountId != null) {
      final cachedAccounts = ref.read(accountsProvider).valueOrNull;
      final List<Account> accounts =
          (cachedAccounts == null || cachedAccounts.isEmpty)
              ? await ref.read(accountRepositoryProvider).getAll()
              : cachedAccounts;
      final matchIndex = accounts.indexWhere((a) => a.id == _accountId);
      if (matchIndex >= 0) {
        paymentMethodToSave =
            accounts[matchIndex].accountType.representativeMethod;
      }
    }

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
      accountId: _type.isTransfer ? _fromAccountId : _accountId,
      toAccountId: _type.isTransfer ? _toAccountId : widget.transaction?.toAccountId,
        paymentMethod: paymentMethodToSave,
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
      smsBody: widget.transaction?.smsBody,
      smsSender: widget.transaction?.smsSender,
      upiApp: widget.transaction?.upiApp,
      upiRefNo: widget.transaction?.upiRefNo,
      referenceId: widget.transaction?.referenceId,
      autoDetected: widget.transaction?.autoDetected ?? false,
      verified: true,
      linkedTransactionId: widget.transaction?.linkedTransactionId,
      parentTransactionId: widget.transaction?.parentTransactionId,
      loanId: widget.transaction?.loanId,
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
        // Advance the tutorial flow to the result step (if active) before
        // popping, so TransactionsScreen sees the state when it resumes.
        if (!widget.isEditing) {
          final step = ref.read(tutorialFlowProvider);
          if (step.isAddTxFlow) {
            ref.read(tutorialFlowProvider.notifier)
                .advance(TutorialFlowStep.addTxResult);
          }
        }
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
      useRootNavigator: false,
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
      (TransactionType.transfer, Icons.swap_horiz, 'Transfer'),
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

/// From / To account pickers for the Transfer transaction type.
class _TransferAccountRow extends ConsumerWidget {
  const _TransferAccountRow({
    required this.fromAccountId,
    required this.toAccountId,
    required this.onFromChanged,
    required this.onToChanged,
  });

  final int? fromAccountId;
  final int? toAccountId;
  final ValueChanged<int?> onFromChanged;
  final ValueChanged<int?> onToChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    return accountsAsync.when(
      data: (accounts) {
        String nameFor(int? id) {
          if (id == null) return 'Select account';
          return accounts.firstWhere((a) => a.id == id,
              orElse: () => accounts.first).accountName;
        }

        return Column(
          children: [
            _AccountTile(
              label: 'From',
              accountName: nameFor(fromAccountId),
              onTap: () async {
                final picked = await showAccountPicker(
                  context,
                  excludeId: toAccountId,
                  title: 'From Account',
                );
                if (picked != null) onFromChanged(picked.id);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            const Icon(Icons.arrow_downward, size: 20),
            const SizedBox(height: AppSpacing.sm),
            _AccountTile(
              label: 'To',
              accountName: nameFor(toAccountId),
              onTap: () async {
                final picked = await showAccountPicker(
                  context,
                  excludeId: fromAccountId,
                  title: 'To Account',
                );
                if (picked != null) onToChanged(picked.id);
              },
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
    );
  }
}

/// Single account picker row — used for income, expense, and other non-transfer types.
class _AccountRow extends ConsumerWidget {
  const _AccountRow({
    required this.accountId,
    required this.onChanged,
  });

  final int? accountId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);

    return accountsAsync.when(
      data: (accounts) {
        String accountName() {
          if (accountId == null) return 'Select account (optional)';
          return accounts
              .where((a) => a.id == accountId)
              .map((a) => a.accountName)
              .firstOrNull ?? 'Select account (optional)';
        }

        return _AccountTile(
          label: 'Account',
          accountName: accountName(),
          accountId: accountId,
          onTap: () async {
            final picked = await showAccountPicker(
              context,
              title: 'Account',
            );
            if (picked != null) onChanged(picked.id);
          },
          onClear: accountId != null ? () => onChanged(null) : null,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.label,
    required this.accountName,
    required this.onTap,
    this.accountId,
    this.onClear,
  });

  final String label;
  final String accountName;
  final VoidCallback onTap;
  final int? accountId;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
          suffixIcon: onClear != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: onClear,
                )
              : const Icon(Icons.expand_more),
        ),
        child: Text(accountName),
      ),
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

/// Formats amount input with Indian comma grouping (e.g. 1,23,456.78)
class IndianCurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    // Strip commas to get the raw string
    final stripped = text.replaceAll(',', '');

    // Reject anything that isn't digits + optional single dot
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(stripped)) return oldValue;

    final dotIndex = stripped.indexOf('.');
    final intPart = dotIndex == -1 ? stripped : stripped.substring(0, dotIndex);
    final decPart = dotIndex == -1 ? '' : stripped.substring(dotIndex + 1);
    final hasDot = dotIndex != -1;

    final formattedInt = _formatInteger(intPart);
    final result = hasDot ? '$formattedInt.$decPart' : formattedInt;

    // Preserve cursor: count non-comma chars after cursor in the pre-format text
    final cursorPos = newValue.selection.end.clamp(0, text.length);
    final sigCharsAfterCursor = text.substring(cursorPos).replaceAll(',', '').length;

    // Find matching position in formatted result by counting back
    int newCursor = result.length;
    if (sigCharsAfterCursor > 0) {
      int count = 0;
      for (int i = result.length - 1; i >= 0; i--) {
        if (result[i] != ',') count++;
        if (count == sigCharsAfterCursor) {
          newCursor = i;
          break;
        }
      }
    }

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(
        offset: newCursor.clamp(0, result.length),
      ),
    );
  }

  static String _formatInteger(String digits) {
    if (digits.length <= 3) return digits;
    final lastThree = digits.substring(digits.length - 3);
    final remaining = digits.substring(0, digits.length - 3);
    final buffer = StringBuffer();
    // First group: remaining.length % 2 chars (1 or 2), then groups of 2
    int idx = remaining.length % 2;
    if (idx > 0) buffer.write(remaining.substring(0, idx));
    while (idx < remaining.length) {
      if (buffer.isNotEmpty) buffer.write(',');
      buffer.write(remaining.substring(idx, idx + 2));
      idx += 2;
    }
    buffer.write(',');
    buffer.write(lastThree);
    return buffer.toString();
  }

  /// Format a plain numeric string with Indian commas (for initial values).
  static String format(String raw) {
    final stripped = raw.replaceAll(',', '');
    final dotIndex = stripped.indexOf('.');
    final intPart = dotIndex == -1 ? stripped : stripped.substring(0, dotIndex);
    final decPart = dotIndex == -1 ? '' : stripped.substring(dotIndex + 1);
    final formatted = _formatInteger(intPart);
    return decPart.isEmpty ? formatted : '$formatted.$decPart';
  }
}

// ---------------------------------------------------------------------------
// Budget hint row — shown below the category dropdown for expense transactions
// ---------------------------------------------------------------------------

/// Displays the current month's budget status for [category] inline on the
/// add/edit transaction form. Hidden when no budget is set.
class _BudgetHintRow extends ConsumerWidget {
  const _BudgetHintRow({required this.category});
  final String category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets =
        ref.watch(currentMonthBudgetsProvider).valueOrNull ?? const [];
    final budget = budgets.where((b) => b.category == category).firstOrNull;

    if (budget == null) return const SizedBox.shrink();

    final pct = budget.spentPercentage;
    final isOver = budget.isOverBudget;
    final isNear = budget.isNearLimit;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isOver) {
      statusColor = context.colorScheme.error;
      statusIcon = Icons.warning_amber_rounded;
      statusText =
          'Over budget by ₹${(budget.spentAmount - budget.budgetAmount).toStringAsFixed(0)}';
    } else if (isNear) {
      statusColor = Colors.orange;
      statusIcon = Icons.info_outline;
      statusText =
          '${(pct * 100).toStringAsFixed(0)}% of budget used — nearing limit';
    } else {
      statusColor = context.colorScheme.outline;
      statusIcon = Icons.savings_outlined;
      statusText =
          '₹${budget.spentAmount.toStringAsFixed(0)} of ₹${budget.budgetAmount.toStringAsFixed(0)} used (${(pct * 100).toStringAsFixed(0)}%)';
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(statusIcon, size: AppSpacing.iconSm, color: statusColor),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              statusText,
              style: context.textTheme.labelSmall
                  ?.copyWith(color: statusColor),
            ),
          ),
          // Mini progress bar
          SizedBox(
            width: 60,
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(AppSpacing.radiusFull),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor:
                    context.colorScheme.surfaceContainerHighest,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

