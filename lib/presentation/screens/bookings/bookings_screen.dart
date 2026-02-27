import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/booking.dart';
import '../../providers/booking_provider.dart';
import '../../providers/settings_provider.dart';
import 'booking_detail_screen.dart';
import 'create_booking_screen.dart';

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        ref.read(bookingSearchQueryProvider.notifier).state = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final businessEnabled = ref.watch(businessModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search bookings...',
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  ref.read(bookingSearchQueryProvider.notifier).state = value;
                },
              )
            : const Text('Bookings'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
            tooltip: _isSearching ? 'Close search' : 'Search',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Booking'),
        onPressed: () {
          if (businessEnabled) {
            _showBookingTypeSheet(context);
          } else {
            // Business mode OFF → always personal
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const CreateBookingScreen(
                defaultBookingType: BookingType.personal,
              ),
            ));
          }
        },
      ),
      body: Column(
        children: [
          // Type filter only shown when business mode is ON
          if (businessEnabled)
            _TypeFilterBar(
              selected: ref.watch(bookingTypeFilterProvider),
              onSelected: (t) =>
                  ref.read(bookingTypeFilterProvider.notifier).state = t,
            ),
          _StatusFilterBar(
            selected: ref.watch(bookingFilterProvider),
            onSelected: (s) =>
                ref.read(bookingFilterProvider.notifier).state = s,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await ref.read(bookingsProvider.notifier).load();
              },
              child: const _BookingsList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showBookingTypeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New Booking',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.base),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.storefront_outlined),
                ),
                title: const Text('Business Booking'),
                subtitle: const Text('Customer appointment, invoice, payment'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const CreateBookingScreen(
                      defaultBookingType: BookingType.business,
                    ),
                  ));
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_outline),
                ),
                title: const Text('Personal Schedule'),
                subtitle: const Text('Reminder, appointment, personal event'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const CreateBookingScreen(
                      defaultBookingType: BookingType.personal,
                    ),
                  ));
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Type Filter Bar ──────────────────────────────────────────────────────────

class _TypeFilterBar extends StatelessWidget {
  const _TypeFilterBar({required this.selected, required this.onSelected});
  final BookingType? selected;
  final ValueChanged<BookingType?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.xs,
        ),
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          const SizedBox(width: AppSpacing.sm),
          ChoiceChip(
            avatar: const Icon(Icons.storefront_outlined, size: 16),
            label: const Text('Business'),
            selected: selected == BookingType.business,
            onSelected: (_) => onSelected(BookingType.business),
          ),
          const SizedBox(width: AppSpacing.sm),
          ChoiceChip(
            avatar: const Icon(Icons.person_outline, size: 16),
            label: const Text('Personal'),
            selected: selected == BookingType.personal,
            onSelected: (_) => onSelected(BookingType.personal),
          ),
        ],
      ),
    );
  }
}

// ── Status Filter Bar ────────────────────────────────────────────────────────

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.selected, required this.onSelected});
  final BookingStatus? selected;
  final ValueChanged<BookingStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    // All, Today, Upcoming, Confirmed, Pending
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        children: [
          FilterChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilterChip(
            label: const Text('Confirmed'),
            selected: selected == BookingStatus.confirmed,
            onSelected: (_) => onSelected(BookingStatus.confirmed),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilterChip(
            label: const Text('Pending'),
            selected: selected == BookingStatus.pending,
            onSelected: (_) => onSelected(BookingStatus.pending),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilterChip(
            label: const Text('Completed'),
            selected: selected == BookingStatus.completed,
            onSelected: (_) => onSelected(BookingStatus.completed),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilterChip(
            label: const Text('Cancelled'),
            selected: selected == BookingStatus.cancelled,
            onSelected: (_) => onSelected(BookingStatus.cancelled),
          ),
        ],
      ),
    );
  }
}

// ── Bookings List with Date Grouping ─────────────────────────────────────────

class _BookingsList extends ConsumerWidget {
  const _BookingsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(filteredBookingsProvider);

    return bookingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) {
          return const _EmptyState();
        }

        // Group bookings by date category
        final groups = _groupBookingsByDate(list);

        return ListView.builder(
          padding: const EdgeInsets.only(
            left: AppSpacing.base,
            right: AppSpacing.base,
            top: AppSpacing.sm,
            bottom: 80,
          ),
          itemCount: _calculateItemCount(groups),
          itemBuilder: (context, index) {
            return _buildItem(context, ref, groups, index);
          },
        );
      },
    );
  }

  Map<String, List<Booking>> _groupBookingsByDate(List<Booking> bookings) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final weekEnd = today.add(const Duration(days: 7));

    final groups = <String, List<Booking>>{
      'TODAY': [],
      'TOMORROW': [],
      'THIS WEEK': [],
      'PAST': [],
    };

    for (final booking in bookings) {
      final date = DateTime(
        booking.startDatetime.year,
        booking.startDatetime.month,
        booking.startDatetime.day,
      );

      if (date == today) {
        groups['TODAY']!.add(booking);
      } else if (date == tomorrow) {
        groups['TOMORROW']!.add(booking);
      } else if (date.isAfter(tomorrow) && date.isBefore(weekEnd)) {
        groups['THIS WEEK']!.add(booking);
      } else if (date.isBefore(today)) {
        groups['PAST']!.add(booking);
      } else {
        // Future bookings beyond this week also go into THIS WEEK for now
        groups['THIS WEEK']!.add(booking);
      }
    }

    // Remove empty groups
    groups.removeWhere((key, value) => value.isEmpty);

    return groups;
  }

  int _calculateItemCount(Map<String, List<Booking>> groups) {
    int count = 0;
    for (final entry in groups.entries) {
      count += 1 + entry.value.length; // header + bookings
    }
    return count;
  }

  Widget _buildItem(
    BuildContext context,
    WidgetRef ref,
    Map<String, List<Booking>> groups,
    int index,
  ) {
    int currentIndex = 0;
    for (final entry in groups.entries) {
      // Header
      if (currentIndex == index) {
        return _GroupHeader(label: entry.key);
      }
      currentIndex++;

      // Check if index is within this group's bookings
      if (index < currentIndex + entry.value.length) {
        final bookingIndex = index - currentIndex;
        return _BookingTile(booking: entry.value[bookingIndex]);
      }
      currentIndex += entry.value.length;
    }

    return const SizedBox.shrink();
  }
}

// ── Group Header ─────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.lg,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

// ── Booking Tile ─────────────────────────────────────────────────────────────

class _BookingTile extends ConsumerWidget {
  const _BookingTile({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookingDetailScreen(bookingId: booking.id!),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time and Status Row
              Row(
                children: [
                  Text(
                    _formatTime(booking),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  _StatusBadge(status: booking.status),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Customer and Service
              Text(
                '${booking.customerName} • ${booking.serviceName}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.xs),

              // Amount and Duration
              Row(
                children: [
                  Text(
                    CurrencyFormatter.format(booking.totalAmount),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.income,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (booking.durationMinutes != null) ...[
                    Text(
                      ' • ${booking.durationLabel}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),

              // Primary Action Button
              if (_shouldShowActionButton(booking)) ...[
                const SizedBox(height: AppSpacing.md),
                _ActionButton(booking: booking),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(Booking booking) {
    if (booking.isMultiDay && booking.endDatetime != null) {
      final start = DateFormat('d MMM').format(booking.startDatetime);
      final end = DateFormat('d MMM').format(booking.endDatetime!);
      return '$start - $end';
    }
    return DateFormat('h:mm a').format(booking.startDatetime);
  }

  bool _shouldShowActionButton(Booking booking) {
    return booking.status == BookingStatus.pending ||
        booking.status == BookingStatus.confirmed;
  }
}

// ── Status Badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;

    Color getColor() {
      switch (status) {
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

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: getColor().withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: getColor(),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Action Button ────────────────────────────────────────────────────────────

class _ActionButton extends ConsumerWidget {
  const _ActionButton({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = booking.status == BookingStatus.pending
        ? 'Send Confirmation'
        : 'Complete & Invoice';

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          if (booking.status == BookingStatus.pending) {
            await ref.read(bookingsProvider.notifier).markAsConfirmed(booking.id!);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Booking confirmed')),
              );
            }
          } else {
            // TODO: Create invoice and navigate
          }
        },
        icon: Icon(
          booking.status == BookingStatus.pending
              ? Icons.send_outlined
              : Icons.receipt_long_outlined,
        ),
        label: Text(label),
      ),
    );
  }
}

// ── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No bookings yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create your first booking to get started',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

