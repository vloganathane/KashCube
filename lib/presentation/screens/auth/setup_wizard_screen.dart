import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/gstin_validator.dart';
import '../../../data/models/account.dart';
import '../../../data/services/pincode_lookup_service.dart';
import '../../../data/models/business.dart';
import '../../providers/account_provider.dart';
import '../../providers/business_provider.dart';
import '../../providers/settings_provider.dart';

// ---------------------------------------------------------------------------
// App mode selection
// ---------------------------------------------------------------------------

enum _AppMode { personal, business, both }

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------

/// First-run setup wizard shown after T&C acceptance, before the main shell.
///
/// Guides the user through 4 steps:
///   1. Mode selection (personal / business / both)
///   2. Profile (owner name, phone, personal UPI)
///   3. Business setup (name, GSTIN, address) — only for business / both
///   4. Financial setup (fiscal year start, opening balances)
///
/// All steps are skippable with "Skip for now". Tapping "Finish" on the last
/// step calls [onComplete] which invalidates [setupWizardDoneProvider] in
/// [SetupWizardNotifier.markDone].
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // ── Shared state ────────────────────────────────────────────────────────
  _AppMode _mode = _AppMode.personal;

  // Step 2 – Profile
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _personalUpiCtrl = TextEditingController();

  // Step 3 – Business
  final _bizNameCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  final _bizAddressCtrl = TextEditingController();
  final _bizPincodeCtrl = TextEditingController();
  final _bizCityCtrl = TextEditingController();
  final _bizStateCtrl = TextEditingController();
  bool _bizPincodeAutoFilled = false;
  String? _gstinError;

  // Step 4 – Financial
  int _fyStartMonth = 4; // April = Indian default
  final _cashCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    PincodeLookupService.ensureLoaded();
    _bizPincodeCtrl.addListener(_onBizPincodeChanged);
    // Trigger rebuilds so _canContinue re-evaluates on required field changes.
    _nameCtrl.addListener(_onRequiredFieldChanged);
    _bizNameCtrl.addListener(_onRequiredFieldChanged);
  }

  void _onRequiredFieldChanged() => setState(() {});

  void _onBizPincodeChanged() {
    final pin = _bizPincodeCtrl.text.trim();
    if (pin.length != 6 || !RegExp(r'^\d{6}$').hasMatch(pin)) {
      if (_bizPincodeAutoFilled) setState(() => _bizPincodeAutoFilled = false);
      return;
    }
    final result = PincodeLookupService.lookup(pin);
    if (result == null) {
      if (_bizPincodeAutoFilled) setState(() => _bizPincodeAutoFilled = false);
      return;
    }
    setState(() {
      if (_bizCityCtrl.text.isEmpty) _bizCityCtrl.text = result.city;
      _bizStateCtrl.text = result.state;
      _bizPincodeAutoFilled = true;
    });
  }

  // Whether business step is needed given current mode.
  bool get _hasBizStep => _mode == _AppMode.business || _mode == _AppMode.both;

  // Total number of pages for the current mode.
  int get _totalPages => _hasBizStep ? 4 : 3;

  /// Whether the Continue/Finish button should be enabled on the current page.
  bool get _canContinue {
    switch (_currentPage) {
      case 1:
        return _nameCtrl.text.trim().isNotEmpty;
      case 2:
        return _bizNameCtrl.text.trim().isNotEmpty && _gstinError == null;
      default:
        return true;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _personalUpiCtrl.dispose();
    _bizNameCtrl.dispose();
    _gstinCtrl.dispose();
    _bizAddressCtrl.dispose();
    _bizPincodeCtrl.dispose();
    _bizCityCtrl.dispose();
    _bizStateCtrl.dispose();
    _cashCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  // ── Navigation helpers ─────────────────────────────────────────────────

  void _nextPage() {
    // Skip business page when not needed.
    int next = _currentPage + 1;
    if (next == 2 && !_hasBizStep) next = 3;
    if (next > 3) {
      // Handled via _finish.
      return;
    }
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentPage = next);
  }

  void _prevPage() {
    int prev = _currentPage - 1;
    if (prev == 2 && !_hasBizStep) prev = 1;
    if (prev < 0) return;
    _pageController.animateToPage(
      prev,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentPage = prev);
  }

  bool get _isLastPage => _currentPage == 3; // Financial is always page 3

  // ── Save logic ─────────────────────────────────────────────────────────

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final settings = ref.read(settingsRepositoryProvider);

      // ── Mode ──────────────────────────────────────────────────────────
      final bizEnabled = _mode != _AppMode.personal;
      await ref.read(businessModeProvider.notifier).setEnabled(bizEnabled);

      // ── Profile ──────────────────────────────────────────────────────
      final name = _nameCtrl.text.trim();
      if (name.isNotEmpty) {
        await settings.set(SettingsKeys.ownerName, name);
      }
      final phone = _phoneCtrl.text.trim();
      if (phone.isNotEmpty) {
        await settings.set(SettingsKeys.personalPhone, phone);
      }

      // ── Business ──────────────────────────────────────────────────────
      if (_hasBizStep) {
        final bizName = _bizNameCtrl.text.trim();
        if (bizName.isNotEmpty) {
          String? nullIfEmpty(String s) => s.isEmpty ? null : s;
          final now = DateTime.now();
          final biz = Business(
            name: bizName,
            ownerName: name.isNotEmpty ? name : null,
            gstNo: nullIfEmpty(_gstinCtrl.text.trim())?.toUpperCase(),
            address: nullIfEmpty(_bizAddressCtrl.text.trim()),
            pincode: nullIfEmpty(_bizPincodeCtrl.text.trim()),
            city: nullIfEmpty(_bizCityCtrl.text.trim()),
            state: nullIfEmpty(_bizStateCtrl.text.trim()),
            upiId: nullIfEmpty(_personalUpiCtrl.text.trim()),
            isActive: true,
            createdAt: now,
            updatedAt: now,
          );
          await ref.read(businessesProvider.notifier).add(biz, setActive: true);
        }
      }

      // ── Fiscal year ───────────────────────────────────────────────────
      await settings.set('fiscal_year_start_month', _fyStartMonth.toString());
      await settings.set('fiscal_year_start_day', '1');

      // ── Opening balances ──────────────────────────────────────────────
      final cashAmt = double.tryParse(_cashCtrl.text.trim());
      if (cashAmt != null && cashAmt > 0) {
        await ref
            .read(accountsProvider.notifier)
            .addAccount(
              Account(
                accountName: 'Cash',
                accountType: AccountType.cash,
                openingBalance: cashAmt,
                isActive: true,
                isPrimary: true,
              ),
            );
      }

      final bankAmt = double.tryParse(_bankCtrl.text.trim());
      if (bankAmt != null && bankAmt > 0) {
        await ref
            .read(accountsProvider.notifier)
            .addAccount(
              Account(
                accountName: 'Bank Account',
                accountType: AccountType.savings,
                openingBalance: bankAmt,
                isActive: true,
                isPrimary: cashAmt == null || cashAmt <= 0,
              ),
            );
      }

      // ── Mark wizard complete ──────────────────────────────────────────
      await ref.read(setupWizardDoneProvider.notifier).markDone();
      widget.onComplete();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            _WizardHeader(
              currentPage: _currentPage,
              totalPages: _totalPages,
              hasBizStep: _hasBizStep,
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Page 0 – Mode
                  _ModePage(
                    selectedMode: _mode,
                    onModeChanged: (m) => setState(() {
                      _mode = m;
                      // Reset page count based on new mode selection
                    }),
                  ),
                  // Page 1 – Profile
                  _ProfilePage(
                    nameCtrl: _nameCtrl,
                    phoneCtrl: _phoneCtrl,
                    upiCtrl: _personalUpiCtrl,
                    mode: _mode,
                  ),
                  // Page 2 – Business (always rendered, controlled by skip)
                  _BusinessPage(
                    bizNameCtrl: _bizNameCtrl,
                    gstinCtrl: _gstinCtrl,
                    addressCtrl: _bizAddressCtrl,
                    pincodeCtrl: _bizPincodeCtrl,
                    cityCtrl: _bizCityCtrl,
                    stateCtrl: _bizStateCtrl,
                    pincodeAutoFilled: _bizPincodeAutoFilled,
                    gstinError: _gstinError,
                    onGstinChanged: (v) {
                      setState(() {
                        if (v.isEmpty) {
                          _gstinError = null;
                        } else if (!GstinValidator.isValid(v)) {
                          _gstinError = 'Invalid GSTIN format';
                        } else {
                          _gstinError = null;
                        }
                      });
                    },
                  ),
                  // Page 3 – Financial
                  _FinancialPage(
                    fyStartMonth: _fyStartMonth,
                    onFyMonthChanged: (m) => setState(() => _fyStartMonth = m),
                    cashCtrl: _cashCtrl,
                    bankCtrl: _bankCtrl,
                  ),
                ],
              ),
            ),
            _WizardFooter(
              currentPage: _currentPage,
              isLastPage: _isLastPage,
              saving: _saving,
              canGoBack: _currentPage > 0,
              canContinue: _canContinue,
              onBack: _prevPage,
              onNext: _nextPage,
              onFinish: _finish,
              tt: tt,
              cs: cs,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — step indicators
// ---------------------------------------------------------------------------

class _WizardHeader extends StatelessWidget {
  const _WizardHeader({
    required this.currentPage,
    required this.totalPages,
    required this.hasBizStep,
  });

  final int currentPage;
  final int totalPages;
  final bool hasBizStep;

  static const _stepLabels = ['Mode', 'Profile', 'Business', 'Finances'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final visibleSteps = hasBizStep
        ? _stepLabels
        : [_stepLabels[0], _stepLabels[1], _stepLabels[3]];

    // Map real page index to visible-step index.
    final visibleIndex = hasBizStep
        ? currentPage
        : (currentPage == 3 ? 2 : currentPage);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.lg,
        AppSpacing.base,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
            children: List.generate(visibleSteps.length, (i) {
              final isActive = i == visibleIndex;
              final isDone = i < visibleIndex;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: isDone || isActive
                              ? cs.primary
                              : cs.outlineVariant.withValues(alpha: 1),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        visibleSteps[i],
                        style: tt.labelSmall?.copyWith(
                          color: isActive
                              ? cs.primary
                              : isDone
                              ? cs.primary.withValues(alpha: 0.7)
                              : cs.outline,
                          fontWeight: isActive ? FontWeight.bold : null,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer — navigation buttons
// ---------------------------------------------------------------------------

class _WizardFooter extends StatelessWidget {
  const _WizardFooter({
    required this.currentPage,
    required this.isLastPage,
    required this.saving,
    required this.canGoBack,
    required this.canContinue,
    required this.onBack,
    required this.onNext,
    required this.onFinish,
    required this.tt,
    required this.cs,
  });

  final int currentPage;
  final bool isLastPage;
  final bool saving;
  final bool canGoBack;
  final bool canContinue;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onFinish;
  final TextTheme tt;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          if (canGoBack)
            OutlinedButton(onPressed: onBack, child: const Text('Back'))
          else
            const SizedBox.shrink(),
          const Spacer(),
          if (!isLastPage && currentPage > 2)
            TextButton(
              onPressed: isLastPage ? null : onNext,
              child: const Text('Skip for now'),
            ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: saving
                ? null
                : (canContinue ? (isLastPage ? onFinish : onNext) : null),
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isLastPage ? 'Finish' : 'Continue'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 0 — Mode selection
// ---------------------------------------------------------------------------

class _ModePage extends StatelessWidget {
  const _ModePage({required this.selectedMode, required this.onModeChanged});

  final _AppMode selectedMode;
  final ValueChanged<_AppMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Image.asset(
            isDark ? 'assets/logo-white.png' : 'assets/logo.png',
            width: 56,
            height: 56,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Welcome to Kash Cube', style: tt.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'How are you planning to use this app?',
            style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _ModeCard(
            icon: Icons.person_outline,
            title: 'Personal',
            subtitle: 'Track your own expenses, income and credits',
            selected: selectedMode == _AppMode.personal,
            onTap: () => onModeChanged(_AppMode.personal),
          ),
          const SizedBox(height: AppSpacing.md),
          _ModeCard(
            icon: Icons.business_outlined,
            title: 'My Business',
            subtitle: 'Manage invoices, GST, parties and business finances',
            selected: selectedMode == _AppMode.business,
            onTap: () => onModeChanged(_AppMode.business),
          ),
          const SizedBox(height: AppSpacing.md),
          _ModeCard(
            icon: Icons.people_outline,
            title: 'Both',
            subtitle: 'Keep personal and business finances separate in one app',
            selected: selectedMode == _AppMode.both,
            onTap: () => onModeChanged(_AppMode.both),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'You can change this anytime from Settings.',
            style: tt.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? cs.primary.withValues(alpha: 0.08)
              : cs.surfaceContainerHighest,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? cs.primary : cs.onSurfaceVariant,
              size: 28,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleMedium?.copyWith(
                      color: selected ? cs.primary : cs.onSurface,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: cs.primary)
            else
              Icon(Icons.radio_button_unchecked, color: cs.outlineVariant),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 1 — Profile
// ---------------------------------------------------------------------------

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.upiCtrl,
    required this.mode,
  });

  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController upiCtrl;
  final _AppMode mode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Text('Your Profile', style: tt.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This appears on invoices and reports.',
            style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Your name *',
              hintText: 'e.g. Ravi Kumar',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Phone number (optional)',
              hintText: '10-digit mobile number',
              prefixIcon: Icon(Icons.phone_outlined),
              prefixText: '+91 ',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: upiCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: mode == _AppMode.personal
                  ? 'Your UPI ID (optional)'
                  : 'Business UPI ID (optional)',
              hintText: 'yourname@upi',
              prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'All details are stored only on this device.',
            style: tt.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 2 — Business setup
// ---------------------------------------------------------------------------

class _BusinessPage extends StatelessWidget {
  const _BusinessPage({
    required this.bizNameCtrl,
    required this.gstinCtrl,
    required this.addressCtrl,
    required this.pincodeCtrl,
    required this.cityCtrl,
    required this.stateCtrl,
    required this.pincodeAutoFilled,
    required this.gstinError,
    required this.onGstinChanged,
  });

  final TextEditingController bizNameCtrl;
  final TextEditingController gstinCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController pincodeCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController stateCtrl;
  final bool pincodeAutoFilled;
  final String? gstinError;
  final ValueChanged<String> onGstinChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Text('Business Setup', style: tt.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Used on invoices, quotes and delivery challans.',
            style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: bizNameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Business name *',
              hintText: 'e.g. Kumar Traders',
              prefixIcon: Icon(Icons.business_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: gstinCtrl,
            textCapitalization: TextCapitalization.characters,
            maxLength: 15,
            decoration: InputDecoration(
              labelText: 'GSTIN (optional)',
              hintText: '15-character GSTIN',
              prefixIcon: const Icon(Icons.receipt_long_outlined),
              errorText: gstinError,
              counterText: '',
            ),
            onChanged: onGstinChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: addressCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Street address (optional)',
              hintText: 'Building, street, area',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: pincodeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'PIN code (optional)',
              hintText: '6-digit PIN code',
              prefixIcon: const Icon(Icons.pin_drop_outlined),
              counterText: '',
              suffixIcon: pincodeAutoFilled
                  ? const Icon(
                      Icons.check_circle_outline,
                      color: Colors.green,
                      size: 18,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: cityCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    hintText: 'e.g. Mumbai',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: stateCtrl,
                  textCapitalization: TextCapitalization.words,
                  readOnly: pincodeAutoFilled,
                  decoration: InputDecoration(
                    labelText: 'State',
                    hintText: 'e.g. Maharashtra',
                    prefixIcon: const Icon(Icons.map_outlined),
                    filled: pincodeAutoFilled,
                    fillColor: pincodeAutoFilled
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'You can add logo, bank details and more in Settings.',
            style: tt.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 3 — Financial setup
// ---------------------------------------------------------------------------

class _FinancialPage extends StatelessWidget {
  const _FinancialPage({
    required this.fyStartMonth,
    required this.onFyMonthChanged,
    required this.cashCtrl,
    required this.bankCtrl,
  });

  final int fyStartMonth;
  final ValueChanged<int> onFyMonthChanged;
  final TextEditingController cashCtrl;
  final TextEditingController bankCtrl;

  static const _fyOptions = [
    (month: 4, label: 'April (Indian FY — default)'),
    (month: 1, label: 'January (Calendar year)'),
    (month: 10, label: 'October'),
    (month: 7, label: 'July'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Text('Financial Setup', style: tt.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Set your fiscal year and opening balances.',
            style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Fiscal year ─────────────────────────────────────────────
          Text('Fiscal year starts in', style: tt.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          DropdownButton<int>(
            value: fyStartMonth,
            isExpanded: true,
            items: _fyOptions
                .map(
                  (o) => DropdownMenuItem(value: o.month, child: Text(o.label)),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) onFyMonthChanged(v);
            },
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Opening balances ─────────────────────────────────────────
          Text('Opening balances (optional)', style: tt.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Enter what you already have in hand / in the bank.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: cashCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: const InputDecoration(
              labelText: 'Cash in hand',
              prefixIcon: Icon(Icons.money_outlined),
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: bankCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: const InputDecoration(
              labelText: 'Bank account balance',
              prefixIcon: Icon(Icons.account_balance_outlined),
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'You can add more accounts any time from Settings → Accounts.',
            style: tt.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}
