import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/services/database_helper.dart';

class AppLogsScreen extends StatefulWidget {
  const AppLogsScreen({super.key});

  @override
  State<AppLogsScreen> createState() => _AppLogsScreenState();
}

class _AppLogsScreenState extends State<AppLogsScreen> {
  static const _limit = 250;
  static const _all = 'all';

  bool _loading = true;
  String _selectedLevel = _all;
  List<Map<String, dynamic>> _logs = const [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.getRecentAppLogs(
      limit: _limit,
      level: _selectedLevel == _all ? null : _selectedLevel,
    );
    if (!mounted) return;
    setState(() {
      _logs = rows;
      _loading = false;
    });
  }

  Future<void> _clearLogs() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear logs?'),
        content: const Text('This will remove all locally stored diagnostics logs.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await DatabaseHelper.instance.clearAppLogs();
    await _loadLogs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics logs cleared')),
    );
  }

  String _asShareText() {
    if (_logs.isEmpty) {
      return 'KashCube diagnostics logs\n(no entries)';
    }

    final buffer = StringBuffer();
    buffer.writeln('KashCube diagnostics logs');
    buffer.writeln('entries=${_logs.length} level=$_selectedLevel');
    buffer.writeln('generated_at=${DateTime.now().toIso8601String()}');
    buffer.writeln('---');
    for (final row in _logs) {
      final ts = row['timestamp']?.toString() ?? '';
      final level = row['level']?.toString() ?? '';
      final source = row['source']?.toString() ?? 'app';
      final category = row['category']?.toString() ?? 'app';
      final eventName = row['event_name']?.toString();
      final sessionId = row['session_id']?.toString();
      final message = row['message']?.toString() ?? '';
      final err = row['error']?.toString();
      final stack = row['stack_trace']?.toString();
      final ctx = row['context_json']?.toString();
      final header = StringBuffer()
        ..write('[$ts] [$level] [$source] [$category]');
      if (eventName != null && eventName.isNotEmpty) {
        header.write(' [$eventName]');
      }
      buffer.writeln('${header.toString()} $message');
      if (sessionId != null && sessionId.isNotEmpty) {
        buffer.writeln('session_id: $sessionId');
      }
      if (err != null && err.isNotEmpty) buffer.writeln('error: $err');
      if (stack != null && stack.isNotEmpty) buffer.writeln('stack: $stack');
      if (ctx != null && ctx.isNotEmpty) buffer.writeln('context: $ctx');
      buffer.writeln('---');
    }
    return buffer.toString();
  }

  Future<void> _copyLogs() async {
    final text = _asShareText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copied to clipboard')),
    );
  }

  Future<void> _shareLogs() async {
    final text = _asShareText();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/kashcube_diagnostics_logs.txt');
    await file.writeAsString(text, flush: true);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'KashCube diagnostics logs',
      subject: 'KashCube diagnostics logs',
    );
  }

  String _formatTimestamp(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    final hh = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final mm = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} $hh:$mm $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics Logs'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadLogs,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Clear logs',
            onPressed: _loading || _logs.isEmpty ? null : _clearLogs,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Row(
                    children: [
                      const Text('Level:'),
                      const SizedBox(width: AppSpacing.sm),
                      DropdownButton<String>(
                        value: _selectedLevel,
                        items: const [
                          DropdownMenuItem(value: _all, child: Text('All')),
                          DropdownMenuItem(value: 'fatal', child: Text('Fatal')),
                          DropdownMenuItem(value: 'error', child: Text('Error')),
                          DropdownMenuItem(value: 'warning', child: Text('Warning')),
                          DropdownMenuItem(value: 'info', child: Text('Info')),
                          DropdownMenuItem(value: 'debug', child: Text('Debug')),
                          DropdownMenuItem(value: 'trace', child: Text('Trace')),
                        ],
                        onChanged: (value) async {
                          if (value == null) return;
                          setState(() => _selectedLevel = value);
                          await _loadLogs();
                        },
                      ),
                      const Spacer(),
                      Text('Showing ${_logs.length}'),
                    ],
                  ),
                ),
                Expanded(
                  child: _logs.isEmpty
                      ? Center(
                          child: Text(
                            'No logs found for this filter',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.base,
                          ),
                          itemCount: _logs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final row = _logs[index];
                            final ts = _formatTimestamp(
                              row['timestamp']?.toString() ?? '',
                            );
                            final source = row['source']?.toString() ?? 'app';
                            final level = row['level']?.toString() ?? 'info';
                            final eventName = row['event_name']?.toString();
                            final message = row['message']?.toString() ?? '';
                            final category = row['category']?.toString() ?? 'app';
                            final error = row['error']?.toString();

                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  source == 'terminal' || source == 'debug_print'
                                      ? Icons.terminal_outlined
                                      : level == 'error' || level == 'fatal'
                                      ? Icons.error_outline
                                      : level == 'warning'
                                          ? Icons.warning_amber_outlined
                                          : Icons.info_outline,
                                ),
                                title: Text(message),
                                subtitle: Text(
                                  '$ts · $source · $level · $category'
                                  '${(eventName != null && eventName.isNotEmpty) ? ' · $eventName' : ''}'
                                  '${(error != null && error.isNotEmpty) ? '\n$error' : ''}',
                                ),
                                isThreeLine: error != null && error.isNotEmpty,
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _logs.isEmpty ? null : _copyLogs,
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('Copy'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _logs.isEmpty ? null : _shareLogs,
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Share'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
