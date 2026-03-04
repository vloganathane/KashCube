import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/party.dart';
import '../../../data/services/booking_confirmation_pdf_service.dart';
import '../../../data/services/invoice_number_service.dart';
import '../../providers/booking_provider.dart';
import '../../providers/business_provider.dart';
import '../../widgets/reminder_bottom_sheet.dart';
import '../../../data/models/reminder_item.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/party_provider.dart';
import '../../providers/settings_provider.dart';
import '../invoices/invoice_detail_screen.dart';
import 'create_booking_screen.dart';

class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({super.key, required this.bookingId});
  final int bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingAsync = ref.watch(bookingByIdProvider(bookingId));
    return bookingAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          appBar: AppBar(), body: Center(child: Text('Error: $e'))),
      data: (booking) {
        if (booking == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('Booking not found')));
        }
        return _BookingDetailView(booking: booking);
      },
    );
  }
}

class _BookingDetailView extends ConsumerWidget {
  const _BookingDetailView({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(booking.serviceName),
        actions: [
          // View / Share PDF — business bookings only
          if (booking.bookingType == BookingType.business) ...[  
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Preview PDF',
              onPressed: () => _viewBookingPdf(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share PDF',
              onPressed: () => _shareBookingPdf(context, ref),
            ),
          ],
          // Send Reminder — for active/upcoming bookings
          if (booking.status == BookingStatus.pending ||
              booking.status == BookingStatus.confirmed)
            IconButton(
              icon: const Icon(Icons.send_outlined),
              tooltip: 'Send Reminder',
              onPressed: () => _showReminderSheet(context, ref),
            ),
          if (booking.status != BookingStatus.completed &&
              booking.status != BookingStatus.cancelled &&
              booking.status != BookingStatus.noShow)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: booking.bookingType == BookingType.personal
                  ? 'Edit Schedule'
                  : 'Edit Booking',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateBookingScreen(booking: booking),
                ),
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'cancel':
                  await _cancelBooking(context, ref);
                case 'no-show':
                  await _markAsNoShow(context, ref);
              }
            },
            itemBuilder: (context) => [
              if (booking.status == BookingStatus.pending ||
                  booking.status == BookingStatus.confirmed)
                PopupMenuItem(
                  value: 'cancel',
                  child: Row(
                    children: [
                      const Icon(Icons.cancel_outlined),
                      const SizedBox(width: 12),
                      Text(booking.bookingType == BookingType.personal
                          ? 'Cancel Schedule'
                          : 'Cancel Booking'),
                    ],
                  ),
                ),
              if (booking.bookingType == BookingType.business &&
                  booking.status == BookingStatus.confirmed &&
                  booking.startDatetime.isBefore(DateTime.now()))
                const PopupMenuItem(
                  value: 'no-show',
                  child: Row(
                    children: [
                      Icon(Icons.person_off_outlined),
                      SizedBox(width: 12),
                      Text('Mark No-show'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _HeaderCard(booking: booking),
          const SizedBox(height: AppSpacing.base),
          if (booking.bookingType == BookingType.business) ...[    
            _CustomerCard(booking: booking),
            const SizedBox(height: AppSpacing.base),
          ],
          if (booking.bookingType == BookingType.business)
            _ServiceItemsCard(booking: booking)
          else
            _ServiceCard(booking: booking),
          const SizedBox(height: AppSpacing.base),
          if (booking.bookingType == BookingType.business)
            _AmountCard(booking: booking),
          if (booking.notes != null && booking.notes!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            _NotesCard(notes: booking.notes!),
          ],
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context, ref),
    );
  }

  Widget? _buildBottomBar(BuildContext context, WidgetRef ref) {
    // Schedule: simple Mark Done button
    if (booking.bookingType == BookingType.personal) {
      if (booking.status == BookingStatus.pending ||
          booking.status == BookingStatus.confirmed) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            AppSpacing.sm,
            AppSpacing.base,
            AppSpacing.xl,
          ),
          child: FilledButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Mark Done'),
            onPressed: () async {
              await ref.read(bookingsProvider.notifier).markAsCompleted(booking.id!);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Marked as done')),
                );
              }
            },
          ),
        );
      }
      return null;
    }

    if (booking.status == BookingStatus.pending) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.sm,
          AppSpacing.base,
          AppSpacing.xl,
        ),
        child: FilledButton.icon(
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Confirm Booking'),
          onPressed: () async {
            await ref.read(bookingsProvider.notifier).markAsConfirmed(booking.id!);
            if (!context.mounted) return;
            await _sendWhatsAppConfirmation(ref);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Booking confirmed')),
            );
          },
        ),
      );
    } else if (booking.status == BookingStatus.confirmed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.sm,
          AppSpacing.base,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Record partial payment before invoicing
            if (booking.bookingType == BookingType.business &&
                !booking.isFullyPaid)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Record Payment'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  onPressed: () => _showRecordPaymentDialog(context, ref),
                ),
              ),
            FilledButton.icon(
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Complete & Create Invoice'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () async {
                // Mark booking as completed
                await ref
                    .read(bookingsProvider.notifier)
                    .markAsCompleted(booking.id!);

                final invoiceNo =
                    await InvoiceNumberService.instance.nextInvoiceNo();
                final now = DateTime.now();

                // Load booking line items (multi-service support)
                final bookingItems = await ref
                    .read(bookingRepositoryProvider)
                    .getItems(booking.id!);

                // Tax total derived from items
                final taxTotal = bookingItems.fold(
                  0.0,
                  (sum, bi) => sum + bi.taxAmount,
                );

                // Invoice carries FULL booking amount; advance already paid
                final invoice = Invoice(
                  invoiceNo: invoiceNo,
                  businessId: booking.businessId,
                  customerPartyId: booking.customerPartyId,
                  customerName: booking.customerName,
                  status: booking.paidAmount > 0
                      ? InvoiceStatus.partiallyPaid
                      : InvoiceStatus.draft,
                  issueDate: now,
                  dueDate: now,
                  subtotal: booking.totalAmount,
                  taxTotal: taxTotal,
                  discountPct: 0,
                  total: booking.totalAmount,
                  paidAmount: booking.paidAmount,
                  notes: booking.notes != null && booking.notes!.isNotEmpty
                      ? 'Booking: ${booking.bookingRef}\n${booking.notes}'
                      : 'Booking: ${booking.bookingRef}',
                  items: [],
                  createdAt: now,
                  updatedAt: now,
                );

                // Map items 1:1 — preserves SAC code, taxPct, discountPct
                final List<InvoiceItem> invoiceItems;
                if (bookingItems.isNotEmpty) {
                  invoiceItems =
                      bookingItems.map((bi) => bi.toInvoiceItem(0)).toList();
                } else {
                  // Legacy fallback for bookings with no line items
                  invoiceItems = [
                    InvoiceItem(
                      invoiceId: 0,
                      itemName: booking.serviceName,
                      description:
                          'Service completed on ${DateFormat('d MMM yyyy').format(booking.startDatetime)}',
                      qty: 1,
                      unitPrice: booking.totalAmount,
                      discountPct: 0,
                      lineTotal: booking.totalAmount,
                    ),
                  ];
                }

                final invoiceId = await ref
                    .read(invoicesProvider.notifier)
                    .add(invoice, invoiceItems);

                await ref
                    .read(bookingsProvider.notifier)
                    .linkInvoice(booking.id!, invoiceId);

                if (!context.mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => InvoiceDetailScreen(invoiceId: invoiceId),
                  ),
                );
              },
            ),
          ],
        ),
      );
    } else if (booking.status == BookingStatus.completed &&
        booking.invoiceId != null) {
      // Booking is done — show a shortcut to the linked invoice
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.sm,
          AppSpacing.base,
          AppSpacing.xl,
        ),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('View Invoice'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => InvoiceDetailScreen(invoiceId: booking.invoiceId!),
              ),
            );
          },
        ),
      );
    }
    return null;
  }

  Future<void> _viewBookingPdf(BuildContext context, WidgetRef ref) async {
    try {
      final business = booking.businessId != null
          ? await ref.read(businessRepositoryProvider).getById(booking.businessId!)
          : ref.read(activeBusinessProvider);
      final customerParty = booking.customerPartyId != null
          ? await ref.read(partyRepositoryProvider).getById(booking.customerPartyId!)
          : null;
      final terms = await ref.read(settingsRepositoryProvider).get(SettingsKeys.bookingTerms);
      final bookingItems =
          await ref.read(bookingRepositoryProvider).getItems(booking.id!);
      final file = await BookingConfirmationPdfService.instance.generateBookingPdf(
        booking,
        business: business,
        customerParty: customerParty,
        termsAndConditions: terms ?? SettingsKeys.defaultBookingTerms,
        items: bookingItems.isNotEmpty ? bookingItems : null,
      );
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open PDF: ${result.message}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    }
  }

  Future<void> _shareBookingPdf(BuildContext context, WidgetRef ref) async {
    try {
      final business = booking.businessId != null
          ? await ref.read(businessRepositoryProvider).getById(booking.businessId!)
          : ref.read(activeBusinessProvider);
      final customerParty = booking.customerPartyId != null
          ? await ref.read(partyRepositoryProvider).getById(booking.customerPartyId!)
          : null;
      final terms = await ref.read(settingsRepositoryProvider).get(SettingsKeys.bookingTerms);
      final bookingItems =
          await ref.read(bookingRepositoryProvider).getItems(booking.id!);
      final file = await BookingConfirmationPdfService.instance.generateBookingPdf(
        booking,
        business: business,
        customerParty: customerParty,
        termsAndConditions: terms ?? SettingsKeys.defaultBookingTerms,
        items: bookingItems.isNotEmpty ? bookingItems : null,
      );
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Booking Confirmation - ${booking.bookingRef ?? booking.serviceName}',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share PDF: $e')),
        );
      }
    }
  }

  Future<void> _sendWhatsAppConfirmation(WidgetRef ref) async {
    // Look up party phone from customerPartyId or by name
    final parties = ref.read(partiesProvider).valueOrNull ?? [];
    Party? party;
    if (booking.customerPartyId != null) {
      party = parties.cast<Party?>().firstWhere(
        (p) => p?.id == booking.customerPartyId,
        orElse: () => null,
      );
    }
    party ??= parties.cast<Party?>().firstWhere(
      (p) => p?.name == booking.customerName,
      orElse: () => null,
    );

    final phone = party?.phoneNumber;
    if (phone == null || phone.isEmpty) return; // No phone — skip silently

    final message = _buildConfirmationMessage();
    final uri = PhoneUtils.waUri(phone, dialCode: party?.dialCode ?? '91', message: message);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _buildConfirmationMessage() {
    final dateStr = DateFormat('d MMM').format(booking.startDatetime);
    final timeStr = DateFormat('h:mm a').format(booking.startDatetime);
    return "Hi ${booking.customerName}, your ${booking.serviceName} is confirmed for $dateStr at $timeStr. Amount: ${CurrencyFormatter.format(booking.totalAmount)}.";
  }

  void _showReminderSheet(BuildContext context, WidgetRef ref) {
    // Look up party contact details asynchronously
    Future<void> open() async {
      String? phone;
      String? email;
      if (booking.customerPartyId != null) {
        final party =
            await ref.read(partyRepositoryProvider).getById(booking.customerPartyId!);
        phone = party?.phoneNumber;
        email = party?.email;
      }
      if (!context.mounted) return;

      final item = ReminderItem.fromBooking(
        booking,
        partyPhone: phone,
        partyEmail: email,
      );

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ReminderBottomSheet(
          item: item,
          onReminderSent: () {
            ref.read(bookingsProvider.notifier).markReminderSent(booking.id!);
          },
        ),
      );
    }

    open();
  }

  Future<void> _cancelBooking(BuildContext context, WidgetRef ref) async {
    final isSchedule = booking.bookingType == BookingType.personal;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isSchedule ? 'Cancel Schedule?' : 'Cancel Booking?'),
        content: Text(isSchedule
            ? 'Are you sure you want to cancel this schedule?'
            : 'Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(bookingsProvider.notifier).markAsCancelled(booking.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isSchedule ? 'Schedule cancelled' : 'Booking cancelled')),
        );
      }
    }
  }

  Future<void> _markAsNoShow(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as No-show?'),
        content: const Text('Customer did not show up for this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, No-show'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(bookingsProvider.notifier).markAsNoShow(booking.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked as no-show')),
        );
      }
    }
  }

  Future<void> _showRecordPaymentDialog(
      BuildContext context, WidgetRef ref) async {
    final amountCtrl = TextEditingController(
      text: booking.balanceDue > 0
          ? booking.balanceDue.toStringAsFixed(0)
          : '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Payment'),
        content: TextField(
          controller: amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount received',
            prefixText: '₹ ',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount =
                  double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
              if (amount > 0) Navigator.pop(ctx, amount);
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
    amountCtrl.dispose();
    if (result == null || result <= 0 || !context.mounted) return;
    await ref.read(bookingsProvider.notifier).recordPayment(
          bookingId: booking.id!,
          amount: result,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment of ${CurrencyFormatter.format(result)} recorded'),
      ),
    );
  }
}

// ── Header Card ──────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;

    Color getStatusColor() {
      switch (booking.status) {
        case BookingStatus.pending:
          return Colors.orange;
        case BookingStatus.confirmed:
          return colors.income;
        case BookingStatus.completed:
          return Colors.grey;
        case BookingStatus.cancelled:
          return Colors.grey;
        case BookingStatus.noShow:
          return colors.overdue;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  booking.bookingType == BookingType.personal
                      ? booking.serviceName
                      : (booking.bookingRef ?? 'No ref'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: getStatusColor().withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    booking.status.label,
                    style: TextStyle(
                      color: getStatusColor(),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            if (booking.bookingType == BookingType.personal &&
                booking.bookingRef != null) ...[  
              const SizedBox(height: AppSpacing.xs),
              Text(
                booking.bookingRef!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              _formatDateTime(),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            if (booking.durationMinutes != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Duration: ${booking.durationLabel}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDateTime() {
    if (booking.isMultiDay && booking.endDatetime != null) {
      final start = DateFormat('d MMM yyyy').format(booking.startDatetime);
      final end = DateFormat('d MMM yyyy').format(booking.endDatetime!);
      return '$start - $end';
    }
    final date = DateFormat('EEEE, d MMMM yyyy').format(booking.startDatetime);
    final time = DateFormat('h:mm a').format(booking.startDatetime);
    return '$date at $time';
  }
}

// ── Customer Card ────────────────────────────────────────────────────────────

class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fetch party details if linked
    final Party? party;
    if (booking.customerPartyId != null) {
      final partiesAsync = ref.watch(partiesProvider);
      party = partiesAsync.valueOrNull?.firstWhere(
        (p) => p.id == booking.customerPartyId,
        orElse: () => Party(
          name: booking.customerName,
          partyType: PartyType.customer,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    } else {
      party = null;
    }
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    booking.customerName[0].toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.customerName,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      if (party?.phoneNumber != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          party!.phoneNumber!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (party?.phoneNumber != null && party!.phoneNumber!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.phone, size: 18),
                    label: const Text('Call'),
                    onPressed: () => _makePhoneCall(party?.phoneNumber),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.message, size: 18),
                    label: const Text('WhatsApp'),
                    onPressed: () => _openWhatsApp(party?.phoneNumber, booking),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  void _makePhoneCall(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
  
  void _openWhatsApp(String? phone, Booking booking) async {
    if (phone == null || phone.isEmpty) return;
    // Format message for WhatsApp
    final dateStr = DateFormat('d MMM').format(booking.startDatetime);
    final timeStr = DateFormat('h:mm a').format(booking.startDatetime);
    final message = "Hi ${booking.customerName}, regarding your ${booking.serviceName} booking on $dateStr at $timeStr.";
    
    // Clean phone number (remove spaces, dashes, etc.)
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ── Service Items Card (business bookings) ──────────────────────────────────

class _ServiceItemsCard extends ConsumerWidget {
  const _ServiceItemsCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(bookingItemsProvider(booking.id!));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Services',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            itemsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, _) => Text(
                booking.serviceName,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Text(
                    booking.serviceName,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500),
                  );
                }
                return Column(
                  children: items.asMap().entries.map((e) {
                    final i = e.key;
                    final item = e.value;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (i > 0) const Divider(height: AppSpacing.base),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.itemName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w500),
                                  ),
                                  if (item.sacCode != null &&
                                      item.sacCode!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'SAC: ${item.sacCode}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  CurrencyFormatter.format(item.lineTotal),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                          fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${_fmtQty(item.qty)} ${item.unit} × ${CurrencyFormatter.format(item.unitPrice)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                                if (item.taxPct > 0)
                                  Text(
                                    'GST ${item.taxPct.toStringAsFixed(0)}%',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _fmtQty(double qty) => qty == qty.truncateToDouble()
      ? qty.toInt().toString()
      : qty.toStringAsFixed(2);
}

// ── Service Card ─────────────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              booking.bookingType == BookingType.personal ? 'Event' : 'Service',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              booking.serviceName,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Amount Card ──────────────────────────────────────────────────────────────

class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            _AmountRow(
              label: 'Total Amount',
              amount: booking.totalAmount,
              color: colors.income,
              isBold: true,
            ),
            if (booking.paidAmount > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              _AmountRow(
                label: booking.paidAmount > booking.advanceAmount
                    ? 'Total Paid'
                    : 'Advance Paid',
                amount: booking.paidAmount,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(height: AppSpacing.sm),
              _AmountRow(
                label: 'Balance Due',
                amount: booking.balanceDue,
                color: colors.expense,
                isBold: true,
              ),
            ],
            if (booking.invoiceId != null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(height: 1),
              ),
              _LinkedInvoiceRow(invoiceId: booking.invoiceId!),
            ],
          ],
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    required this.color,
    this.isBold = false,
  });
  final String label;
  final double amount;
  final Color color;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: isBold ? FontWeight.bold : null,
              ),
        ),
        Text(
          CurrencyFormatter.format(amount),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: color,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

// ── Linked Invoice Row ────────────────────────────────────────────────────────

class _LinkedInvoiceRow extends ConsumerWidget {
  const _LinkedInvoiceRow({required this.invoiceId});
  final int invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(invoiceByIdProvider(invoiceId));
    return invoiceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (invoice) {
        if (invoice == null) return const SizedBox.shrink();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Invoice',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => InvoiceDetailScreen(invoiceId: invoiceId),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    invoice.invoiceNo,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Notes Card ───────────────────────────────────────────────────────────────

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});
  final String notes;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notes',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              notes,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
