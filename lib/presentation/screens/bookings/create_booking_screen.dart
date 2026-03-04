import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/item_catalog.dart';
import '../../providers/booking_provider.dart';
import '../../providers/business_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/party_picker_field.dart';
import '../../../data/models/booking_item.dart';

/// Helper function to format duration in minutes to readable text
String _formatDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  if (minutes < 1440) {
    final hours = minutes / 60;
    return hours == hours.toInt() 
        ? '${hours.toInt()} hrs' 
        : '${hours.toStringAsFixed(1)} hrs';
  }
  final days = minutes / 1440;
  return days == days.toInt() 
      ? '${days.toInt()} days' 
      : '${days.toStringAsFixed(1)} days';
}

/// Full-screen form for creating or editing a booking
class CreateBookingScreen extends ConsumerStatefulWidget {
  const CreateBookingScreen({
    super.key,
    this.booking,
    this.defaultBookingType = BookingType.business,
  });

  final Booking? booking;  // If provided, we're editing
  final BookingType defaultBookingType;

  @override
  ConsumerState<CreateBookingScreen> createState() => _CreateBookingScreenState();
}

class _CreateBookingScreenState extends ConsumerState<CreateBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _notesController = TextEditingController();
  final _advanceController = TextEditingController();
  // Used for Schedule (personal) title field only
  final _customServiceController = TextEditingController();

  int? _selectedBusinessId;
  int? _selectedPartyId;

  /// Line items for business bookings. Empty for Schedule / personal.
  final List<_ItemDraft> _items = [];
  bool _itemsLoaded = false;

  DateTime _startDate = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _startTime = TimeOfDay.now();
  DateTime? _endDate;
  TimeOfDay? _endTime;
  int? _customDuration;
  bool _hasEndTime = false;
  BookingType _bookingType = BookingType.business;

  @override
  void initState() {
    super.initState();
    _bookingType = widget.booking?.bookingType ?? widget.defaultBookingType;
    if (widget.booking != null) {
      _loadBookingData();
      // Load items after first frame so ref is available
      if (_bookingType == BookingType.business && widget.booking!.id != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadItemsForEdit(widget.booking!.id!),
        );
      }
    } else if (_bookingType == BookingType.business) {
      // New business booking: start with one empty item row
      _items.add(_ItemDraft());
    }
  }

  void _loadBookingData() {
    final booking = widget.booking!;
    _customerController.text = booking.customerName;
    _selectedBusinessId = booking.businessId;
    _selectedPartyId = booking.customerPartyId;
    _startDate = booking.startDatetime;
    _startTime = TimeOfDay.fromDateTime(booking.startDatetime);
    if (booking.endDatetime != null) {
      _hasEndTime = true;
      _endDate = booking.endDatetime;
      _endTime = TimeOfDay.fromDateTime(booking.endDatetime!);
    }
    _customDuration = booking.durationMinutes;
    _advanceController.text = booking.advanceAmount.toStringAsFixed(0);
    if (booking.notes != null) _notesController.text = booking.notes!;
    // Schedule (personal) stores its title in serviceName
    if (booking.bookingType == BookingType.personal) {
      _customServiceController.text = booking.serviceName;
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _notesController.dispose();
    _advanceController.dispose();
    _customServiceController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  // ── Item management ──────────────────────────────────────────────────────

  /// Applies a catalog selection to an existing [draft] row.
  void _applyServiceToItem(_ItemDraft draft, ItemCatalog service) {
    final isDayBased = (service.durationMinutes ?? 0) >= 1440;
    // Update controllers OUTSIDE setState to avoid notifyListeners re-entrancy
    draft.nameCtrl.text = service.name;
    draft.priceCtrl.text = service.unitPrice.toStringAsFixed(0);
    draft.sacCtrl.text = service.hsnCode ?? '';
    setState(() {
      draft.serviceItemId = service.id;
      draft.isDayBased = isDayBased;
      draft.taxPct = service.taxPct;
      draft.unit = isDayBased
          ? 'days'
          : ((service.durationMinutes ?? 0) >= 60 ? 'hrs' : 'session');
      _customDuration = service.durationMinutes;
      if (isDayBased) {
        _hasEndTime = true;
        final days = ((service.durationMinutes ?? 1440) / 1440).ceil();
        _endDate ??= _startDate.add(Duration(days: days));
      }
    });
    _recalcDayBasedItems();
  }

  void _addItem() => setState(() => _items.add(_ItemDraft()));

  void _removeItem(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  /// Updates qty on every day-based row using the current start/end date diff.
  void _recalcDayBasedItems() {
    if (!_hasEndTime || _endDate == null) return;
    final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
    final days = end.difference(start).inDays;
    if (days <= 0) return;
    // Update controllers OUTSIDE setState to avoid notifyListeners re-entrancy
    for (final item in _items) {
      if (item.isDayBased) item.qtyCtrl.text = days.toString();
    }
    setState(() {}); // trigger rebuild so lineTotal chips recalculate
  }

  /// Loads existing booking items from DB when editing.
  /// Falls back to a single synthetic item for legacy bookings with no items.
  Future<void> _loadItemsForEdit(int bookingId) async {
    final repo = ref.read(bookingRepositoryProvider);
    final existing = await repo.getItems(bookingId);
    if (!mounted) return;
    setState(() {
      for (final d in _items) {
        d.dispose();
      }
      _items.clear();
      if (existing.isEmpty) {
        // Legacy booking: synthesise one row from scalar fields
        final b = widget.booking!;
        _items.add(_ItemDraft(
          itemName: b.serviceName,
          qty: '1',
          unitPrice: b.totalAmount.toStringAsFixed(0),
          unit: 'session',
        ));
      } else {
        _items.addAll(existing.map((item) => _ItemDraft(
              id: item.id,
              itemName: item.itemName,
              qty: item.qty == item.qty.roundToDouble()
                  ? item.qty.toStringAsFixed(0)
                  : item.qty.toString(),
              unitPrice: item.unitPrice.toStringAsFixed(0),
              unit: item.unit,
              taxPct: item.taxPct,
              discountPct: item.discountPct,
              sacCode: item.sacCode,
              serviceItemId: item.serviceItemId,
              isDayBased: item.unit == 'days',
            )));
      }
      _itemsLoaded = true;
    });
  }

  Future<void> _showCatalogPickerForItem(
    BuildContext context,
    _ItemDraft draft,
    List<ItemCatalog> services,
  ) async {
    final result = await showModalBottomSheet<ItemCatalog>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ServicePickerSheet(services: services),
    );
    if (result != null) _applyServiceToItem(draft, result);
  }

  Future<void> _selectStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _startDate = date);
      _recalcDayBasedItems();
    }
  }

  Future<void> _selectStartTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (time != null) {
      setState(() => _startTime = time);
    }
  }

  Future<void> _selectEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 1)),
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _endDate = date);
      _recalcDayBasedItems();
    }
  }

  Future<void> _selectEndTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _endTime ?? TimeOfDay.now(),
    );
    if (time != null) {
      setState(() => _endTime = time);
    }
  }

  Future<void> _saveBooking() async {
    if (!_formKey.currentState!.validate()) return;

    if (_bookingType == BookingType.business) {
      final named = _items.where((d) => d.nameCtrl.text.trim().isNotEmpty).toList();
      if (named.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one service')),
        );
        return;
      }
    } else {
      if (_customServiceController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a title')),
        );
        return;
      }
    }

    final startDatetime = DateTime(
      _startDate.year, _startDate.month, _startDate.day,
      _startTime.hour, _startTime.minute,
    );
    DateTime? endDatetime;
    if (_hasEndTime && _endDate != null) {
      final t = _endTime ?? const TimeOfDay(hour: 18, minute: 0);
      endDatetime = DateTime(
        _endDate!.year, _endDate!.month, _endDate!.day, t.hour, t.minute,
      );
    }

    final customerName = _customerController.text.trim().isEmpty
        ? 'Walk-in Customer'
        : _customerController.text.trim();

    // Derive totals and summary fields from items
    final validItems = _bookingType == BookingType.business
        ? _items.where((d) => d.nameCtrl.text.trim().isNotEmpty).toList()
        : <_ItemDraft>[];
    final totalAmount = validItems.fold(0.0, (s, d) => s + d.lineTotal);
    final advanceAmount = _bookingType == BookingType.business
        ? (double.tryParse(_advanceController.text) ?? 0)
        : 0.0;
    final firstName =
        validItems.isNotEmpty ? validItems.first.nameCtrl.text.trim() : '';
    final serviceName = _bookingType == BookingType.personal
        ? _customServiceController.text.trim()
        : (validItems.length > 1
            ? '$firstName +${validItems.length - 1} more'
            : firstName);

    final bookingData = Booking(
      id: widget.booking?.id,
      customerPartyId:
          _bookingType == BookingType.business ? _selectedPartyId : null,
      customerName:
          _bookingType == BookingType.business ? customerName : '',
      serviceItemId:
          validItems.isNotEmpty ? validItems.first.serviceItemId : null,
      serviceName: serviceName,
      startDatetime: startDatetime,
      endDatetime: endDatetime,
      durationMinutes: _customDuration,
      status: widget.booking?.status ?? BookingStatus.pending,
      totalAmount: totalAmount,
      advanceAmount: advanceAmount,
      // On first save, paidAmount = advance; on edit, keep existing paidAmount
      paidAmount: widget.booking?.paidAmount ?? advanceAmount,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      invoiceId: widget.booking?.invoiceId,
      bookingRef: widget.booking?.bookingRef,
      bookingType: _bookingType,
      businessId: _bookingType == BookingType.business
          ? (_selectedBusinessId ?? ref.read(activeBusinessProvider)?.id)
          : null,
      createdAt: widget.booking?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final itemsToSave = validItems
        .asMap()
        .entries
        .map((e) => e.value.toBookingItem(sortOrder: e.key))
        .toList();

    await ref
        .read(bookingsProvider.notifier)
        .saveWithItems(bookingData, itemsToSave);

    // Keep linked invoice customer info in sync
    if (widget.booking?.invoiceId != null) {
      final invoice =
          await ref.read(invoiceByIdProvider(widget.booking!.invoiceId!).future);
      if (invoice != null) {
        await ref.read(invoicesProvider.notifier).edit(
          invoice.copyWith(
            customerName: customerName,
            customerPartyId: _selectedPartyId,
          ),
          invoice.items,
        );
      }
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.booking != null ? 'Booking updated' : 'Booking created',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookableServices = ref.watch(catalogProvider).valueOrNull?.where(
      (item) => item.isBookable && item.isActive,
    ).toList() ?? [];
    final businessEnabled = ref.watch(businessModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.booking != null
              ? (_bookingType == BookingType.personal ? 'Edit Schedule' : 'Edit Booking')
              : (_bookingType == BookingType.personal ? 'New Schedule' : 'New Booking'),
        ),
        actions: [
          TextButton(
            onPressed: _saveBooking,
            child: const Text('SAVE'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                // Booking Type selector (only when business mode is on)
                if (businessEnabled) ...[  
                  SegmentedButton<BookingType>(
                    segments: const [
                      ButtonSegment(
                        value: BookingType.business,
                        icon: Icon(Icons.storefront_outlined, size: 18),
                        label: Text('Booking'),
                      ),
                      ButtonSegment(
                        value: BookingType.personal,
                        icon: Icon(Icons.person_outline, size: 18),
                        label: Text('Schedule'),
                      ),
                    ],
                    selected: {_bookingType},
                    onSelectionChanged: (sel) => setState(() => _bookingType = sel.first),
                  ),
                  const SizedBox(height: AppSpacing.base),
                ],

                // ── Business-only fields ────────────────────────────────────
                if (_bookingType == BookingType.business) ...[
                  // Business selector (hidden when only 1 business)
                  Consumer(
                    builder: (context, ref, _) {
                      final businessesAsync = ref.watch(businessesProvider);
                      return businessesAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (businesses) {
                          if (businesses.isEmpty) return const SizedBox.shrink();
                          if (businesses.length == 1) {
                            // Auto-select single business silently
                            if (_selectedBusinessId == null) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) setState(() => _selectedBusinessId = businesses.first.id);
                              });
                            }
                            return const SizedBox.shrink();
                          }
                          final activeBusiness = ref.watch(activeBusinessProvider);
                          final selectedId = _selectedBusinessId ?? activeBusiness?.id;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<int>(
                                initialValue: selectedId,
                                decoration: const InputDecoration(
                                  labelText: 'Business',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.business_outlined),
                                ),
                                items: businesses.map((biz) {
                                  return DropdownMenuItem(
                                    value: biz.id,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          biz.name,
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        if (biz.gstNo != null)
                                          Text(
                                            'GST: ${biz.gstNo}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) => setState(() => _selectedBusinessId = value),
                                validator: (value) =>
                                    value == null ? 'Please select a business' : null,
                              ),
                              const SizedBox(height: AppSpacing.base),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  // Customer Name (optional for walk-ins)
                  PartyPickerField(
                    controller: _customerController,
                    labelText: 'Customer Name (optional)',
                    onPartySelected: (party) {
                      setState(() => _selectedPartyId = party.id);
                    },
                  ),
                  const SizedBox(height: AppSpacing.base),

                  // ── Services / Items ─────────────────────────────────────
                  Text(
                    'Services',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildItemsSection(context, bookableServices),
                  const SizedBox(height: AppSpacing.base),
                ],

                // ── Personal-only fields ─────────────────────────────────────
                if (_bookingType == BookingType.personal) ...[
                  TextFormField(
                    controller: _customServiceController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'e.g., Doctor appointment, Gym, Study session',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.event_note_outlined),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Title required' : null,
                  ),
                  const SizedBox(height: AppSpacing.base),
                ],

                // Start Date & Time
                Text(
                  'Start Date & Time *',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today),
                        label: Text(DateFormat('d MMM yyyy').format(_startDate)),
                        onPressed: _selectStartDate,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time),
                        label: Text(_startTime.format(context)),
                        onPressed: _selectStartTime,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.base),

                // End Time Toggle
                SwitchListTile(
                  title: const Text('Has end time'),
                  subtitle: const Text('For multi-hour or multi-day services'),
                  value: _hasEndTime,
                  onChanged: (v) {
                    setState(() {
                      _hasEndTime = v;
                      if (!v) {
                        _endDate = null;
                        _endTime = null;
                      }
                    });
                    if (v) _recalcDayBasedItems();
                  },
                  contentPadding: EdgeInsets.zero,
                ),

                // End Date & Time (when enabled)
                if (_hasEndTime) ...[
                  Text(
                    'End Date & Time',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            _endDate != null 
                                ? DateFormat('d MMM yyyy').format(_endDate!)
                                : 'Select date',
                          ),
                          onPressed: _selectEndDate,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time),
                          label: Text(
                            _endTime != null 
                                ? _endTime!.format(context)
                                : 'Select time',
                          ),
                          onPressed: _selectEndTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.base),
                ],

                // Payment summary (business only)
                if (_bookingType == BookingType.business && _items.isNotEmpty) ...[
                  _buildPaymentSummary(context),
                  const SizedBox(height: AppSpacing.base),
                ],

                // Notes
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        );
  }

  // ── Build helpers ──────────────────────────────────────────────────────────

  Widget _buildItemsSection(BuildContext context, List<ItemCatalog> services) {
    // Show spinner while loading existing items in edit mode
    if (widget.booking?.id != null && !_itemsLoaded && _items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.base),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < _items.length; i++) ...[
          _buildItemRow(context, i, services),
          if (i < _items.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _addItem,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Service'),
        ),
      ],
    );
  }

  Widget _buildItemRow(
      BuildContext context, int index, List<ItemCatalog> services) {
    final draft = _items[index];
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          // ── Name row ────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.nameCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Service name',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical: 14,
                    ),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Name required' : null,
                ),
              ),
              if (services.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.list_alt, size: 20),
                  tooltip: 'Pick from catalog',
                  onPressed: () =>
                      _showCatalogPickerForItem(context, draft, services),
                ),
              if (_items.length > 1)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: cs.error,
                  tooltip: 'Remove',
                  onPressed: () => _removeItem(index),
                ),
            ],
          ),
          const Divider(height: 1),
          // ── Qty × Rate = Total ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: TextFormField(
                    controller: draft.qtyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: Text(
                    draft.unit,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Text('×'),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: TextFormField(
                    controller: draft.priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Rate',
                      prefixText: '₹',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: Text('='),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    CurrencyFormatter.format(draft.lineTotal),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── SAC & GST (collapsed by default) ────────────────────────────
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                _sacGstLabel(draft),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              tilePadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                0,
                AppSpacing.base,
                AppSpacing.sm,
              ),
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: draft.sacCtrl,
                        decoration: const InputDecoration(
                          labelText: 'SAC Code',
                          border: OutlineInputBorder(),
                          hintText: '998311',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        decoration: const InputDecoration(
                          labelText: 'GST %',
                          border: OutlineInputBorder(),
                        ),
                        items: const [0.0, 5.0, 12.0, 18.0, 28.0]
                            .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text('${v.toStringAsFixed(0)}%'),
                                ))
                            .toList(),
                        initialValue: draft.taxPct,
                        onChanged: (v) =>
                            setState(() => draft.taxPct = v ?? 0),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _sacGstLabel(_ItemDraft draft) {
    final hasSac = draft.sacCtrl.text.isNotEmpty;
    final hasGst = draft.taxPct > 0;
    if (hasSac && hasGst) {
      return 'SAC: ${draft.sacCtrl.text}  •  GST ${draft.taxPct.toStringAsFixed(0)}%';
    } else if (hasSac) {
      return 'SAC: ${draft.sacCtrl.text}';
    } else if (hasGst) {
      return 'GST ${draft.taxPct.toStringAsFixed(0)}%';
    }
    return 'SAC & GST (optional)';
  }

  Widget _buildPaymentSummary(BuildContext context) {
    final subtotal = _items.fold(0.0, (s, d) => s + d.lineTotal);
    final advance = double.tryParse(_advanceController.text) ?? 0;
    final balance = (subtotal - advance).clamp(0.0, double.infinity);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Subtotal', style: Theme.of(context).textTheme.bodyMedium),
            Text(
              CurrencyFormatter.format(subtotal),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const Divider(height: AppSpacing.xl),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _advanceController,
          decoration: const InputDecoration(
            labelText: 'Advance Paid (optional)',
            prefixText: '₹',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
        ),
        if (advance > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Balance Due',
                  style: Theme.of(context).textTheme.bodyMedium),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: balance > 0 ? cs.errorContainer : cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  CurrencyFormatter.format(balance),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: balance > 0
                        ? cs.onErrorContainer
                        : cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── _ItemDraft ─────────────────────────────────────────────────────────────────

/// Mutable UI-layer draft for a single booking line item.
/// Not an Equatable model — converted to [BookingItem] on save via [toBookingItem].
class _ItemDraft {
  _ItemDraft({
    this.id,
    String itemName = '',
    String qty = '1',
    String unitPrice = '0',
    this.unit = 'session',
    this.taxPct = 0,
    this.discountPct = 0,
    this.sacCode,
    this.serviceItemId,
    this.isDayBased = false,
  })  : nameCtrl = TextEditingController(text: itemName),
        qtyCtrl = TextEditingController(text: qty),
        priceCtrl = TextEditingController(text: unitPrice),
        sacCtrl = TextEditingController() {
    if (sacCode != null) sacCtrl.text = sacCode!;
  }

  /// Non-null when editing an existing [BookingItem] row.
  final int? id;
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController sacCtrl;

  String unit;
  double taxPct;
  double discountPct;
  String? sacCode;
  int? serviceItemId;

  /// True when this row is priced per calendar day.
  /// [qtyCtrl] is auto-updated by [_recalcDayBasedItems] when dates change.
  bool isDayBased;

  double get qty => double.tryParse(qtyCtrl.text) ?? 0;
  double get unitPrice => double.tryParse(priceCtrl.text) ?? 0;
  double get lineTotal => qty * unitPrice;

  /// Build a [BookingItem] for persistence.
  /// [bookingId] is overwritten by [BookingRepositoryImpl.saveItems]; pass 0.
  BookingItem toBookingItem({int bookingId = 0, int sortOrder = 0}) =>
      BookingItem(
        id: id,
        bookingId: bookingId,
        itemName: nameCtrl.text.trim(),
        qty: qty,
        unit: unit,
        unitPrice: unitPrice,
        taxPct: taxPct,
        discountPct: discountPct,
        lineTotal: lineTotal,
        sacCode: sacCtrl.text.trim().isEmpty ? null : sacCtrl.text.trim(),
        sortOrder: sortOrder,
        serviceItemId: serviceItemId,
      );

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
    sacCtrl.dispose();
  }
}

// ── Service Picker Sheet ─────────────────────────────────────────────────────

class _ServicePickerSheet extends StatefulWidget {
  const _ServicePickerSheet({
    required this.services,
  });
  final List<ItemCatalog> services;

  @override
  State<_ServicePickerSheet> createState() => _ServicePickerSheetState();
}

class _ServicePickerSheetState extends State<_ServicePickerSheet> {
  final _searchController = TextEditingController();
  List<ItemCatalog> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.services;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? widget.services
          : widget.services
              .where((s) =>
                  s.name.toLowerCase().contains(query) ||
                  (s.description?.toLowerCase().contains(query) ?? false))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Header
            AppBar(
              title: const Text('Select Service'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search services',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),

            // Services list
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('No bookable services found'),
                          const SizedBox(height: AppSpacing.base),
                          Text(
                            'Add services to catalog with "Enable bookings" checked',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final service = _filtered[index];
                        return ListTile(
                          title: Text(service.name),
                          subtitle: Text(
                            service.durationMinutes != null
                                ? '${CurrencyFormatter.format(service.unitPrice)} • ${_formatDuration(service.durationMinutes!)}'
                                : CurrencyFormatter.format(service.unitPrice),
                          ),
                          onTap: () => Navigator.pop(context, service),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
