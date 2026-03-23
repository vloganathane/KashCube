import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../data/services/action_center_background_service.dart';
import '../../../data/services/backup_service.dart';
import '../../../data/services/encrypted_backup_service.dart';
import '../../../data/services/pdf_cache_manager.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transaction_provider.dart';

// ── Provider ─────────────────────────────────────────────────────────────────

final _storageStatsProvider = FutureProvider<_StorageStats>((ref) async {
  final stats = await Future.wait([
    _dbFileSize(),
    PdfCacheManager.instance.totalSize(),
    _billsSize(),
    BackupService.instance.getTotalBackupSize(),
    BackupService.instance.listBackups(),
  ]);
  return _StorageStats(
    dbBytes: stats[0] as int,
    pdfBytes: stats[1] as int,
    billsBytes: stats[2] as int,
    backupBytes: stats[3] as int,
    lastBackup: (stats[4] as List<BackupInfo>).firstOrNull?.createdAt,
  );
});

Future<int> _dbFileSize() async {
  try {
    final dbPath = await getDatabasesPath();
    final file = File(p.join(dbPath, AppConstants.dbName));
    return await file.exists() ? await file.length() : 0;
  } catch (_) {
    return 0;
  }
}

Future<int> _billsSize() async {
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final billsDir = Directory(p.join(appDir.path, 'bills'));
    if (!await billsDir.exists()) return 0;
    var total = 0;
    await for (final entity in billsDir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  } catch (_) {
    return 0;
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _StorageStats {
  const _StorageStats({
    required this.dbBytes,
    required this.pdfBytes,
    required this.billsBytes,
    required this.backupBytes,
    required this.lastBackup,
  });

  final int dbBytes;
  final int pdfBytes;
  final int billsBytes;
  final int backupBytes;
  final DateTime? lastBackup;

  int get totalBytes => dbBytes + pdfBytes + billsBytes + backupBytes;
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Shows a breakdown of on-device storage used by Kash Cube.
///
/// All data is local — nothing is sent to any server.
class StorageHealthScreen extends ConsumerStatefulWidget {
  const StorageHealthScreen({super.key});

  @override
  ConsumerState<StorageHealthScreen> createState() =>
      _StorageHealthScreenState();
}

class _StorageHealthScreenState extends ConsumerState<StorageHealthScreen> {
  bool _backingUp = false;
  bool _restoring = false;
  bool _exporting = false;
  bool _autoBackupEnabled = false;
  String _autoBackupInterval = 'weekly';

  @override
  void initState() {
    super.initState();
    _loadAutoBackupPrefs();
  }

  Future<void> _loadAutoBackupPrefs() async {
    final svc = EncryptedBackupService.instance;
    final enabled = await svc.autoBackupEnabled();
    final interval = await svc.autoBackupInterval();
    if (mounted) {
      setState(() {
        _autoBackupEnabled = enabled;
        _autoBackupInterval = interval;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(_storageStatsProvider);
    final colors = Theme.of(context).extension<KashCubeColors>()!;

    return Scaffold(
      appBar: AppBar(title: const Text('Storage & Backup')),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (stats) => _buildBody(context, ref, stats, colors),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    _StorageStats stats,
    KashCubeColors colors,
  ) {
    final dateFormat = DateFormat('d MMM yyyy, h:mm a');
    final daysSinceBackup = stats.lastBackup == null
        ? null
        : DateTime.now().difference(stats.lastBackup!).inDays;
    final backupWarning = stats.lastBackup == null || (daysSinceBackup != null && daysSinceBackup > 30);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_storageStatsProvider),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          // ── Storage Usage ────────────────────────────────────────────────
          Text(
            'Storage Usage',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                children: [
                  _StorageRow(
                    icon: Icons.storage_outlined,
                    label: 'Database',
                    bytes: stats.dbBytes,
                    total: stats.totalBytes,
                  ),
                  const Divider(height: 1, indent: AppSpacing.base),
                  _StorageRow(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'PDFs (cached)',
                    bytes: stats.pdfBytes,
                    total: stats.totalBytes,
                    trailing: TextButton(
                      onPressed: stats.pdfBytes == 0
                          ? null
                          : () async {
                              await PdfCacheManager.instance.clearAll();
                              ref.invalidate(_storageStatsProvider);
                              if (context.mounted) {
                                context.showSnackBar('PDF cache cleared');
                              }
                            },
                      child: const Text('Clear cache'),
                    ),
                  ),
                  const Divider(height: 1, indent: AppSpacing.base),
                  _StorageRow(
                    icon: Icons.attach_file_outlined,
                    label: 'Bills & Attachments',
                    bytes: stats.billsBytes,
                    total: stats.totalBytes,
                  ),
                  const Divider(height: 1, indent: AppSpacing.base),
                  _StorageRow(
                    icon: Icons.backup_outlined,
                    label: 'Backups',
                    bytes: stats.backupBytes,
                    total: stats.totalBytes,
                  ),
                  const Divider(height: 1, indent: AppSpacing.base),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        Text(
                          _formatBytes(stats.totalBytes),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Backup ────────────────────────────────────────────────────────
          Text(
            'Backup',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.history,
                        size: 18,
                        color: backupWarning ? colors.expense : null,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          stats.lastBackup == null
                              ? 'Last backup: Never'
                              : 'Last backup: ${dateFormat.format(stats.lastBackup!)}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: backupWarning ? colors.expense : null,
                              ),
                        ),
                      ),
                    ],
                  ),
                  if (backupWarning) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      stats.lastBackup == null
                          ? 'You have never backed up. Your data is only on this device.'
                          : 'Last backup was $daysSinceBackup days ago — back up regularly.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.expense,
                          ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.base),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _backingUp ? null : _createBackup,
                      icon: _backingUp
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.backup_outlined),
                      label: Text(_backingUp ? 'Backing up…' : 'Back Up Now'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _restoring
                              ? null
                              : _showRestoreDialog,
                          icon: const Icon(Icons.restore, size: 18),
                          label: const Text('Restore'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exporting
                              ? null
                              : _exportCsv,
                          icon: _exporting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.file_download_outlined,
                                  size: 18,
                                ),
                          label: const Text('Export CSV'),
                        ),
                      ),
                    ],
                  ),
                  // ── Auto Backup ──────────────────────────────────────────
                  const SizedBox(height: AppSpacing.sm),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto Backup'),
                    subtitle: const Text(
                        'Automatically back up in the background'),
                    value: _autoBackupEnabled,
                    onChanged: _toggleAutoBackup,
                  ),
                  if (_autoBackupEnabled) ...[
                    const SizedBox(height: AppSpacing.xs),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'daily', label: Text('Daily')),
                        ButtonSegment(value: 'weekly', label: Text('Weekly')),
                        ButtonSegment(
                            value: 'monthly', label: Text('Monthly')),
                      ],
                      selected: {_autoBackupInterval},
                      onSelectionChanged: (v) =>
                          _setAutoBackupInterval(v.first),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Keeps the last 3 auto-backups. '
                      'On iOS, timing is best-effort.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleAutoBackup(bool value) async {
    final svc = EncryptedBackupService.instance;
    await svc.setAutoBackupEnabled(value);
    if (value) {
      await registerAutoBackupTask(_autoBackupInterval);
    } else {
      await cancelAutoBackupTask();
    }
    if (mounted) setState(() => _autoBackupEnabled = value);
  }

  Future<void> _setAutoBackupInterval(String interval) async {
    final svc = EncryptedBackupService.instance;
    await svc.setAutoBackupInterval(interval);
    if (_autoBackupEnabled) {
      await registerAutoBackupTask(interval);
    }
    if (mounted) setState(() => _autoBackupInterval = interval);
  }

  Future<void> _createBackup() async {
    setState(() => _backingUp = true);
    try {
      await BackupService.instance.createBackup();
      ref.invalidate(_storageStatsProvider);
      if (mounted) context.showSnackBar('Backup created successfully');
    } catch (e) {
      if (mounted) context.showSnackBar('Backup failed: $e');
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _showRestoreDialog() async {
    final service = BackupService.instance;
    final backups = await service.listBackups();

    if (!mounted) return;

    if (backups.isEmpty) {
      context.showSnackBar('No backups found');
      return;
    }

    if (mounted) setState(() => _restoring = true);

    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    final selected = await showModalBottomSheet<BackupInfo>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Text(
                'Select Backup',
                style: ctx.textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: backups.length,
                itemBuilder: (_, i) {
                  final b = backups[i];
                  return ListTile(
                    leading: const Icon(Icons.folder_zip_outlined),
                    title: Text(dateFormat.format(b.createdAt)),
                    subtitle: Text(b.formattedSize),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await service.deleteBackup(b.path);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          _showRestoreDialog();
                        }
                      },
                    ),
                    onTap: () => Navigator.pop(ctx, b),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (!mounted) {
      setState(() => _restoring = false);
      return;
    }

    if (selected == null) {
      setState(() => _restoring = false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => AlertDialog(
        title: const Text('Restore Backup?'),
        content: const Text(
          'This will replace all current data with the backup.\n\n'
          'This action cannot be undone. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await service.restoreFromBackup(selected.path);
        if (mounted) {
          context.showSnackBar('Backup restored. Please restart the app.');
        }
      } catch (e) {
        if (mounted) {
          context.showSnackBar('Restore failed: $e', isError: true);
        }
      }
    }

    if (mounted) setState(() => _restoring = false);
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final repo = ref.read(transactionRepositoryProvider);
      final transactions = await repo.getAll();

      if (transactions.isEmpty) {
        if (mounted) context.showSnackBar('No transactions to export');
        return;
      }

      final csvService = ref.read(csvExportServiceProvider);
      final path = await csvService.exportTransactions(transactions);
      await Share.shareXFiles([XFile(path)]);
    } catch (e) {
      if (mounted) context.showSnackBar('Export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.icon,
    required this.label,
    required this.bytes,
    required this.total,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final int bytes;
  final int total;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : bytes / total;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label)),
              ?trailing,
              const SizedBox(width: AppSpacing.xs),
              Text(
                _formatBytes(bytes),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
