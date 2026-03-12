import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/party.dart';
import '../../providers/party_provider.dart';
import '../../widgets/party_form_sheet.dart';
import 'staff_detail_screen.dart';

/// Displays all staff members for the active business.
///
/// Active tab shows parties with deletedAt == null;
/// Inactive tab shows soft-deleted ones.
class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addStaff() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PartyFormSheet(
        existing: const Party(name: '', partyType: PartyType.staff),
        onSave: (_) {
          ref.invalidate(staffMembersProvider);
        },
      ),
    );
  }

  Future<void> _openDetail(Party staff) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StaffDetailScreen(staffPartyId: staff.id!),
      ),
    );
    ref.invalidate(staffMembersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffMembersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff & Payroll'),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Inactive'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.sm, AppSpacing.base, 0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search staff…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _StaffList(
                  staffAsync: staffAsync,
                  query: _query,
                  showActive: true,
                  onTap: _openDetail,
                ),
                _StaffList(
                  staffAsync: staffAsync,
                  query: _query,
                  showActive: false,
                  onTap: _openDetail,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addStaff,
        tooltip: 'Add Staff',
        child: const Icon(Icons.person_add_outlined),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Staff list widget (used for both tabs)
// ---------------------------------------------------------------------------

class _StaffList extends StatelessWidget {
  const _StaffList({
    required this.staffAsync,
    required this.query,
    required this.showActive,
    required this.onTap,
  });

  final AsyncValue<List<Party>> staffAsync;
  final String query;
  final bool showActive;
  final void Function(Party) onTap;

  @override
  Widget build(BuildContext context) {
    return staffAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (all) {
        final filtered = all.where((s) {
          final isActive = s.deletedAt == null;
          if (showActive != isActive) return false;
          if (query.isEmpty) return true;
          return s.name.toLowerCase().contains(query) ||
              (s.staffRole?.toLowerCase().contains(query) ?? false) ||
              (s.phoneNumber?.contains(query) ?? false);
        }).toList();

        if (filtered.isEmpty) {
          return _EmptyState(showActive: showActive);
        }

        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.base),
          itemCount: filtered.length,
          separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) => _StaffCard(
            staff: filtered[i],
            onTap: () => onTap(filtered[i]),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Staff card
// ---------------------------------------------------------------------------

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.staff, required this.onTap});

  final Party staff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final role = staff.staffRole?.isNotEmpty == true ? staff.staffRole! : 'Staff';
    final salaryText = staff.staffSalary != null
        ? CurrencyFormatter.format(staff.staffSalary!)
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: context.colorScheme.primaryContainer,
          child: Text(
            staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?',
            style: TextStyle(
              color: context.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          staff.name,
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(role, style: context.textTheme.bodySmall),
            if (salaryText != null)
              Text(
                '$salaryText / ${_salaryTypeLabel(staff.staffSalaryType)}',
                style: context.textTheme.bodySmall?.copyWith(
                  color: colors.income,
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        isThreeLine: salaryText != null,
      ),
    );
  }

  String _salaryTypeLabel(String? type) {
    switch (type) {
      case 'daily':
        return 'day';
      case 'hourly':
        return 'hr';
      default:
        return 'month';
    }
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.showActive});

  final bool showActive;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              showActive ? Icons.badge_outlined : Icons.person_off_outlined,
              size: 64,
              color: context.colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              showActive ? 'No staff yet' : 'No inactive staff',
              style: context.textTheme.titleMedium?.copyWith(
                color: context.colorScheme.outline,
              ),
            ),
            if (showActive) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Tap + to add your first employee or contractor',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
