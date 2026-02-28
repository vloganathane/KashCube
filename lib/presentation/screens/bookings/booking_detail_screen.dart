import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/party.dart';
import '../../../data/services/invoice_number_service.dart';
import '../../providers/booking_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/party_provider.dart';
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
        child: FilledButton.icon(
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Complete & Create Invoice'),
          onPressed: () async {
            // Mark booking as completed first
            await ref.read(bookingsProvider.notifier).markAsCompleted(booking.id!);
            
            // Generate invoice from booking
            final invoiceNo = await InvoiceNumberService.instance.nextInvoiceNo();
            final now = DateTime.now();
            
            // Calculate amounts (subtract advance from total)
            final amountToInvoice = booking.totalAmount - booking.advanceAmount;
            
            // Create invoice
            final invoice = Invoice(
              invoiceNo: invoiceNo,
              businessId: booking.businessId,
              customerPartyId: booking.customerPartyId,
              customerName: booking.customerName,
              status: InvoiceStatus.draft,
              issueDate: now,
              dueDate: now,
              subtotal: amountToInvoice,
              taxTotal: 0,
              discountPct: 0,
              total: amountToInvoice,
              paidAmount: 0,
              notes: booking.notes != null && booking.notes!.isNotEmpty
                  ? 'Booking: ${booking.bookingRef}\n${booking.notes}'
                  : 'Booking: ${booking.bookingRef}',
              items: [],
              createdAt: now,
              updatedAt: now,
            );
            
            // Create invoice item from booking service
            final invoiceItem = InvoiceItem(
              invoiceId: 0, // Placeholder - will be set by repository
              itemName: booking.serviceName,
              description: 'Service completed on ${DateFormat('d MMM yyyy').format(booking.startDatetime)}${booking.advanceAmount > 0 ? ' (Advance paid: ${CurrencyFormatter.format(booking.advanceAmount)})' : ''}',
              qty: 1,
              unitPrice: amountToInvoice,
              discountPct: 0,
              lineTotal: amountToInvoice,
            );
            
            // Save invoice
            final invoiceId = await ref.read(invoicesProvider.notifier).add(
              invoice,
              [invoiceItem],
            );
            
            // Link invoice to booking
            await ref.read(bookingsProvider.notifier).linkInvoice(
              booking.id!,
              invoiceId,
            );
            
            if (context.mounted) {
              // Navigate to invoice detail for review/send
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => InvoiceDetailScreen(invoiceId: invoiceId),
                ),
              );
            }
          },
        ),
      );
    }
    return null;
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
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse(
      'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _buildConfirmationMessage() {
    final dateStr = DateFormat('d MMM').format(booking.startDatetime);
    final timeStr = DateFormat('h:mm a').format(booking.startDatetime);
    return "Hi ${booking.customerName}, your ${booking.serviceName} is confirmed for $dateStr at $timeStr. Amount: ${CurrencyFormatter.format(booking.totalAmount)}.";
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
    final balance = booking.totalAmount - booking.advanceAmount;

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
            if (booking.advanceAmount > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              _AmountRow(
                label: 'Advance Paid',
                amount: booking.advanceAmount,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(height: AppSpacing.sm),
              _AmountRow(
                label: 'Balance Due',
                amount: balance,
                color: colors.expense,
                isBold: true,
              ),
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
