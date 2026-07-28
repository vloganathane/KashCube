// ---------------------------------------------------------------------------
// BulkReminderService — P2.5
// ---------------------------------------------------------------------------
// Sends WhatsApp reminders for selected ActionItems.
// Groups items by party name so each party gets a single consolidated message.
//
// Uses url_launcher to open WhatsApp with a pre-filled message.
// 100% on-device — no network calls.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/action_item.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final bulkReminderServiceProvider = Provider<BulkReminderService>(
  (_) => const BulkReminderService(),
);

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class BulkReminderService {
  const BulkReminderService();

  /// Opens WhatsApp reminders for each party represented in [items].
  ///
  /// Items are grouped by [ActionItem.title] (party name). One WhatsApp
  /// message is sent per party. If WhatsApp is not installed the device
  /// falls back to SMS.
  Future<void> remindAll(BuildContext context, List<ActionItem> items) async {
    if (items.isEmpty) return;

    // Group by party title (= party name in ActionItem)
    final groups = <String, List<ActionItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.title, () => []).add(item);
    }

    int sent = 0;
    int failed = 0;

    for (final entry in groups.entries) {
      final party = entry.key;
      final partyItems = entry.value;
      final message = _buildMessage(party, partyItems);

      final launched = await _launchWhatsApp(message);
      if (launched) {
        sent++;
      } else {
        failed++;
      }
    }

    if (context.mounted) {
      _showResult(context, sent: sent, failed: failed);
    }
  }

  // ── Message builder ────────────────────────────────────────────────────────

  String _buildMessage(String partyName, List<ActionItem> items) {
    final buf = StringBuffer();
    buf.writeln('Dear $partyName,');
    buf.writeln();
    buf.writeln(
      'This is a gentle reminder for the following outstanding item(s):',
    );
    buf.writeln();

    for (final item in items) {
      final sign = item.direction == ActionItemDirection.toCollect
          ? ''
          : '(to pay) ';
      final amountStr = '₹${_formatAmount(item.amount)}';
      buf.write('  \u2022 $sign$amountStr');
      if (item.subtitle != null && item.subtitle!.isNotEmpty) {
        buf.write(' — ${item.subtitle}');
      }
      if (item.dueDate != null) {
        buf.write(' (due ${DateFormat('d MMM yyyy').format(item.dueDate!)})');
      }
      buf.writeln();
    }

    buf.writeln();
    buf.write('Please arrange payment at your earliest convenience.');
    buf.writeln(' Thank you!');

    return buf.toString();
  }

  String _formatAmount(double amount) {
    // Simple Indian number formatting without external formatter dependency
    final intPart = amount.toInt();
    if (intPart >= 10000000) {
      return '${(amount / 10000000).toStringAsFixed(2)}Cr';
    } else if (intPart >= 100000) {
      return '${(amount / 100000).toStringAsFixed(2)}L';
    }
    // Format with Indian commas: last 3 then groups of 2
    final s = intPart.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    final rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    for (int i = rest.length; i > 0; i -= 2) {
      parts.insert(
        0,
        rest.substring(i.clamp(0, rest.length) - 2.clamp(0, i), i),
      );
    }
    return '${parts.join(',')},$last3';
  }

  // ── URL launcher ──────────────────────────────────────────────────────────

  Future<bool> _launchWhatsApp(String message) async {
    final encoded = Uri.encodeComponent(message);
    // WhatsApp without phone number opens contact picker
    final waUri = Uri.parse('https://wa.me/?text=$encoded');

    if (await canLaunchUrl(waUri)) {
      return launchUrl(waUri, mode: LaunchMode.externalApplication);
    }

    // Fallback: SMS without number
    final smsUri = Uri.parse('sms:?body=$encoded');
    if (await canLaunchUrl(smsUri)) {
      return launchUrl(smsUri, mode: LaunchMode.externalApplication);
    }

    return false;
  }

  // ── Toast ─────────────────────────────────────────────────────────────────

  void _showResult(
    BuildContext context, {
    required int sent,
    required int failed,
  }) {
    final msg = sent > 0 && failed == 0
        ? 'Reminder${sent > 1 ? 's' : ''} sent for $sent part${sent > 1 ? 'ies' : 'y'}'
        : failed > 0 && sent == 0
        ? 'Could not open WhatsApp. Is it installed?'
        : '$sent sent, $failed failed to open';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
