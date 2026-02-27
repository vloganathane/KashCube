import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/item_catalog.dart';
import '../../providers/booking_provider.dart';
import '../../providers/invoice_provider.dart';
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

/// Full-screen form for creating a new booking
class CreateBookingScreen extends ConsumerStatefulWidget {
  const CreateBookingScreen({super.key});

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

  int? _selectedPartyId;  // Track selected party ID
  ItemCatalog? _selectedService;
  bool _isCustomService = false;  // Track if using custom service
  DateTime _startDate = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _startTime = TimeOfDay.now();
  DateTime? _endDate;
  TimeOfDay? _endTime;
  int? _customDuration;
  bool _hasEndTime = false;  // Simple toggle for end time

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
      _amountController.text = service.unitPrice.toStringAsFixed(0);
      
      // Set duration and smart end time handling
      if (service.durationMinutes != null) {
        _customDuration = service.durationMinutes;
        // Auto-enable end time for multi-day services
        if (service.durationMinutes! >= 1440) {
          _hasEndTime = true;
          final days = (service.durationMinutes! / 1440).ceil();
          _endDate = _startDate.add(Duration(days: days));
        }
      }
    });
  }

  void _onCustomServiceMode() {
    setState(() {
      _isCustomService = true;
      _selectedService = null;
      _amountController.clear();
    });
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
    
    // Validate service (catalog or custom)
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

    final booking = Booking(
      customerPartyId: _selectedPartyId,
      customerName: _customerController.text.trim(),
      serviceItemId: _isCustomService ? null : _selectedService!.id,
      serviceName: _isCustomService 
          ? _customServiceController.text.trim() 
          : _selectedService!.name,
      startDatetime: startDatetime,
      endDatetime: endDatetime,
      durationMinutes: _customDuration,
      status: BookingStatus.pending,
      totalAmount: double.tryParse(_amountController.text) ?? 0,
      advanceAmount: double.tryParse(_advanceController.text) ?? 0,
      notes: _notesController.text.trim().isEmpty 
          ? null 
          : _notesController.text.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await ref.read(bookingsProvider.notifier).add(booking);

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Booking'),
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
                // Customer Name (optional for walk-ins)
                PartyPickerField(
                  controller: _customerController,
                  labelText: 'Customer Name (optional)',
                  onPartySelected: (party) {
                    setState(() => _selectedPartyId = party.id);
                  },
                ),
                const SizedBox(height: AppSpacing.base),

                // Service Picker or Custom Input
                if (!_isCustomService) ...[
                  _ServicePickerField(
                    services: bookableServices,
                    selected: _selectedService,
                    onSelected: _onServiceSelected,
                    onCustomMode: _onCustomServiceMode,
                  ),
                  
                  // Show service info when catalog item selected
                  if (_selectedService != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        '${CurrencyFormatter.format(_selectedService!.unitPrice)}'
                        '${_selectedService!.durationMinutes != null ? ' • ${_formatDuration(_selectedService!.durationMinutes!)}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ),
                ] else ...[
                  // Custom Service Input
                  TextFormField(
                    controller: _customServiceController,
                    decoration: InputDecoration(
                      labelText: 'Service Name *',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _isCustomService = false;
                          _customServiceController.clear();
                        }),
                        tooltip: 'Use catalog',
                      ),
                    ),
                    validator: (v) => v?.isEmpty ?? true ? 'Service name required' : null,
                  ),
                ],
                const SizedBox(height: AppSpacing.base),

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
                  onChanged: (v) => setState(() {
                    _hasEndTime = v;
                    if (!v) {
                      _endDate = null;
                      _endTime = null;
                    }
                  }),
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

                // Amount
                TextFormField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    labelText: 'Total Amount *',
                    prefixText: '₹',
                    border: const OutlineInputBorder(),
                    helperText: _selectedService != null 
                        ? 'From catalog' 
                        : (_isCustomService ? 'Custom pricing' : null),
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

                // Advance Payment
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

// ── Service Picker Field ─────────────────────────────────────────────────────

class _ServicePickerField extends StatelessWidget {
  const _ServicePickerField({
    required this.services,
    required this.selected,
    required this.onSelected,
    required this.onCustomMode,
  });

  final List<ItemCatalog> services;
  final ItemCatalog? selected;
  final ValueChanged<ItemCatalog> onSelected;
  final VoidCallback onCustomMode;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showServicePicker(context),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Service *',
          border: const OutlineInputBorder(),
          suffixIcon: Icon(
            Icons.arrow_drop_down,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        child: Text(
          selected?.name ?? 'Select a service',
          style: selected != null
              ? null
              : TextStyle(color: Theme.of(context).hintColor),
        ),
      ),
    );
  }

  Future<void> _showServicePicker(BuildContext context) async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ServicePickerSheet(
        services: services, 
        selected: selected,
        onCustomMode: onCustomMode,
      ),
    );
    if (result != null && result is ItemCatalog) {
      onSelected(result);
    }
  }
}

// ── Service Picker Sheet ─────────────────────────────────────────────────────

class _ServicePickerSheet extends StatefulWidget {
  const _ServicePickerSheet({
    required this.services, 
    this.selected,
    required this.onCustomMode,
  });
  final List<ItemCatalog> services;
  final ItemCatalog? selected;
  final VoidCallback onCustomMode;

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
            
            // Custom Service Button
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onCustomMode();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Use custom service'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
