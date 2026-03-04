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
  final _amountController = TextEditingController();
  final _advanceController = TextEditingController();
  final _customServiceController = TextEditingController();

  int? _selectedBusinessId;
  int? _selectedPartyId;  // Track selected party ID
  ItemCatalog? _selectedService;
  bool _isCustomService = false;  // Track if using custom service
  bool _serviceLoaded = false;  // Track if we've loaded service in edit mode
  DateTime _startDate = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _startTime = TimeOfDay.now();
  DateTime? _endDate;
  TimeOfDay? _endTime;
  int? _customDuration;
  bool _hasEndTime = false;  // Simple toggle for end time
  BookingType _bookingType = BookingType.business;

  @override
  void initState() {
    super.initState();
    _bookingType = widget.booking?.bookingType ?? widget.defaultBookingType;
    if (widget.booking != null) {
      _loadBookingData();
    }
  }

  void _loadBookingData() {
    final booking = widget.booking!;
    _customerController.text = booking.customerName;
    _selectedBusinessId = booking.businessId;
    _selectedPartyId = booking.customerPartyId;
    _isCustomService = booking.serviceItemId == null;
    if (_isCustomService) {
      _customServiceController.text = booking.serviceName;
    }
    // Note: _selectedService will be set from catalog if serviceItemId exists
    _startDate = booking.startDatetime;
    _startTime = TimeOfDay.fromDateTime(booking.startDatetime);
    if (booking.endDatetime != null) {
      _hasEndTime = true;
      _endDate = booking.endDatetime;
      _endTime = TimeOfDay.fromDateTime(booking.endDatetime!);
    }
    _customDuration = booking.durationMinutes;
    _amountController.text = booking.totalAmount.toStringAsFixed(0);
    _advanceController.text = booking.advanceAmount.toStringAsFixed(0);
    if (booking.notes != null) {
      _notesController.text = booking.notes!;
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _notesController.dispose();
    _amountController.dispose();
    _advanceController.dispose();
    _customServiceController.dispose();
    super.dispose();
  }

  void _onServiceSelected(ItemCatalog service) {
    setState(() {
      _selectedService = service;
      _isCustomService = false;
      _customServiceController.clear();

      // Set duration and smart end time handling
      if (service.durationMinutes != null) {
        _customDuration = service.durationMinutes;
        // Auto-enable end time for multi-day services
        if (service.durationMinutes! >= 1440) {
          _hasEndTime = true;
          final days = (service.durationMinutes! / 1440).ceil();
          _endDate ??= _startDate.add(Duration(days: days));
        }
      }

      // Set amount — will be recalculated below if day-based + end date set
      _amountController.text = service.unitPrice.toStringAsFixed(0);
    });
    // Recalc after setState so _endDate is updated
    _recalcAmount();
  }

  /// Recalculates [_amountController] based on date range when the active
  /// catalog service is day-based (durationMinutes ≥ 1440).
  ///
  /// No-op for custom services, hourly services, or when end date is not set.
  void _recalcAmount() {
    final service = _selectedService;
    if (service == null) return;
    if (!_hasEndTime || _endDate == null) return;
    if ((service.durationMinutes ?? 0) < 1440) return;

    final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final end   = DateTime(_endDate!.year,  _endDate!.month,  _endDate!.day);
    final days  = end.difference(start).inDays;
    if (days <= 0) return;

    final total = service.unitPrice * days;
    _amountController.text = total.toStringAsFixed(0);
  }

  void _onCustomServiceMode() {
    setState(() {
      _isCustomService = true;
      _selectedService = null;
      _amountController.clear();
    });
  }

  Future<void> _showCatalogPicker(BuildContext context, List<ItemCatalog> services) async {
    final result = await showModalBottomSheet<ItemCatalog>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ServicePickerSheet(services: services, selected: _selectedService),
    );
    if (result != null) {
      _onServiceSelected(result);
    }
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
      _recalcAmount();
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
      _recalcAmount();
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

    // For business bookings: validate service selection
    if (_bookingType == BookingType.business) {
      if (!_isCustomService && _selectedService == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a service')),
        );
        return;
      }
      if (_isCustomService && _customServiceController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter service name')),
        );
        return;
      }
    } else {
      // Personal: validate title field
      if (_customServiceController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a title')),
        );
        return;
      }
    }

    // Combine date and time
    final startDatetime = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );

    DateTime? endDatetime;
    if (_hasEndTime && _endDate != null) {
      final endTime = _endTime ?? const TimeOfDay(hour: 18, minute: 0);
      endDatetime = DateTime(
        _endDate!.year,
        _endDate!.month,
        _endDate!.day,
        endTime.hour,
        endTime.minute,
      );
    }

    final customerName = _customerController.text.trim().isEmpty
        ? 'Walk-in Customer'
        : _customerController.text.trim();

    final bookingData = Booking(
      id: widget.booking?.id,  // Preserve ID if editing
      customerPartyId: _bookingType == BookingType.business ? _selectedPartyId : null,
      customerName: _bookingType == BookingType.business ? customerName : '',
      serviceItemId: (_isCustomService || _bookingType == BookingType.personal) ? null : _selectedService!.id,
      serviceName: _bookingType == BookingType.personal
          ? _customServiceController.text.trim()
          : (_isCustomService
              ? _customServiceController.text.trim()
              : _selectedService!.name),
      startDatetime: startDatetime,
      endDatetime: endDatetime,
      durationMinutes: _customDuration,
      status: widget.booking?.status ?? BookingStatus.pending,
      totalAmount: _bookingType == BookingType.business
          ? (double.tryParse(_amountController.text) ?? 0)
          : 0,
      advanceAmount: _bookingType == BookingType.business
          ? (double.tryParse(_advanceController.text) ?? 0)
          : 0,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      invoiceId: widget.booking?.invoiceId,  // Preserve invoice link
      bookingRef: widget.booking?.bookingRef,  // Preserve booking reference
      bookingType: _bookingType,
      businessId: _bookingType == BookingType.business
          ? (_selectedBusinessId ?? ref.read(activeBusinessProvider)?.id)
          : null,
      createdAt: widget.booking?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    if (widget.booking != null) {
      // Update existing booking
      await ref.read(bookingsProvider.notifier).edit(bookingData);
      
      // Update linked invoice if exists
      if (widget.booking!.invoiceId != null) {
        final invoice = await ref.read(invoiceByIdProvider(widget.booking!.invoiceId!).future);
        if (invoice != null) {
          // Update invoice with new customer info
          await ref.read(invoicesProvider.notifier).edit(
            invoice.copyWith(
              customerName: customerName,
              customerPartyId: _selectedPartyId,
            ),
            invoice.items,  // Invoice already includes its items
          );
        }
      }
    } else {
      // Create new booking
      await ref.read(bookingsProvider.notifier).add(bookingData);
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking created')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookableServices = ref.watch(catalogProvider).valueOrNull?.where(
      (item) => item.isBookable && item.isActive,
    ).toList() ?? [];
    final businessEnabled = ref.watch(businessModeProvider);

    // Load selected service from catalog when editing (only once)
    if (widget.booking != null && 
        widget.booking!.serviceItemId != null && 
        !_serviceLoaded && 
        bookableServices.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final service = bookableServices.where((s) => s.id == widget.booking!.serviceItemId).firstOrNull;
        if (service != null && mounted) {
          setState(() {
            _selectedService = service;
            _serviceLoaded = true;
          });
        }
      });
    }

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
                                value: selectedId,
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

                  // Service Selection - Dual Buttons
                  Text(
                    'Service *',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showCatalogPicker(context, bookableServices),
                          icon: const Icon(Icons.list_alt),
                          label: const Text('From Catalog'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md,
                              horizontal: AppSpacing.sm,
                            ),
                            side: _selectedService != null
                                ? BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _onCustomServiceMode,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Custom'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md,
                              horizontal: AppSpacing.sm,
                            ),
                            side: _isCustomService
                                ? BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.base),

                  // Selected Service Display or Custom Input
                  if (_selectedService != null) ...[
                    Card(
                      child: ListTile(
                        title: Text(_selectedService!.name),
                        subtitle: Text(
                          '${CurrencyFormatter.format(_selectedService!.unitPrice)}'
                          '${_selectedService!.durationMinutes != null ? ' • ${_formatDuration(_selectedService!.durationMinutes!)}' : ''}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _selectedService = null;
                            _amountController.clear();
                          }),
                          tooltip: 'Remove service',
                        ),
                      ),
                    ),
                  ] else if (_isCustomService) ...[
                    TextFormField(
                      controller: _customServiceController,
                      decoration: const InputDecoration(
                        labelText: 'Service Name',
                        hintText: 'e.g., Emergency repair',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v?.isEmpty ?? true ? 'Service name required' : null,
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.arrow_upward,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Select from catalog or use custom service',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                        // Reset to single-unit price when end time is removed
                        if (_selectedService != null) {
                          _amountController.text =
                              _selectedService!.unitPrice.toStringAsFixed(0);
                        }
                      }
                    });
                    if (v) _recalcAmount();
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

                // Amount & Advance (business only)
                if (_bookingType == BookingType.business) ...[
                  TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: 'Total Amount *',
                      prefixText: '₹',
                      border: const OutlineInputBorder(),
                      helperText: () {
                          if (_selectedService == null) {
                            return _isCustomService ? 'Custom pricing' : null;
                          }
                          final svc = _selectedService!;
                          final isDayBased = (svc.durationMinutes ?? 0) >= 1440;
                          if (isDayBased && _hasEndTime && _endDate != null) {
                            final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
                            final end   = DateTime(_endDate!.year,  _endDate!.month,  _endDate!.day);
                            final days  = end.difference(start).inDays;
                            if (days > 0) {
                              return '₹${svc.unitPrice.toStringAsFixed(0)} × $days day${days == 1 ? '' : 's'}';
                            }
                          }
                          return 'From catalog';
                        }(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      if (v?.isEmpty ?? true) return 'Amount required';
                      if (double.tryParse(v!) == null) return 'Invalid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.base),

                  TextFormField(
                    controller: _advanceController,
                    decoration: const InputDecoration(
                      labelText: 'Advance Payment (optional)',
                      prefixText: '₹',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
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
}

// ── Service Picker Sheet ─────────────────────────────────────────────────────

class _ServicePickerSheet extends StatefulWidget {
  const _ServicePickerSheet({
    required this.services, 
    this.selected,
  });
  final List<ItemCatalog> services;
  final ItemCatalog? selected;

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
                        final isSelected = service.id == widget.selected?.id;
                        return ListTile(
                          title: Text(service.name),
                          subtitle: Text(
                            service.durationMinutes != null
                                ? '${CurrencyFormatter.format(service.unitPrice)} • ${_formatDuration(service.durationMinutes!)}'
                                : CurrencyFormatter.format(service.unitPrice),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
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
