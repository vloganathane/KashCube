import 'package:flutter/foundation.dart';

import '../../domain/repositories/settings_repository.dart';
import '../repositories/settings_repository_impl.dart';
import 'database_helper.dart';

// ---------------------------------------------------------------------------
// FiscalYearService
// ---------------------------------------------------------------------------
// Handles all FY date arithmetic, label generation, and FY-aware invoice /
// quote sequence generation.
//
// Configuration is read from the `settings` table (seeded in DB v27):
//   fiscal_year_start_month  (default: 4 = April)
//   fiscal_year_start_day    (default: 1)
//   invoice_no_format        (default: 'INV-{YY}-{YY+1}-{SEQ}')
//   quote_no_format          (default: 'QT-{YY}-{YY+1}-{SEQ}')
//   auto_reset_invoice_no    (default: '1')
//   current_fy_start         (ISO8601 date — updated on FY flip)
//   last_fy_close_date       (ISO8601 date — set by year-end closing wizard)
//
// Format tokens:
//   {YYYY}  — 4-digit FY start year, e.g. "2025"
//   {YY}    — 2-digit FY start year, e.g. "25"
//   {YY+1}  — 2-digit FY end year,   e.g. "26"
//   {SEQ}   — zero-padded sequence,   e.g. "0042"
// ---------------------------------------------------------------------------

/// Immutable date range (both ends inclusive).
class DateRange {
  const DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  bool contains(DateTime date) =>
      !date.isBefore(start) && !date.isAfter(end);

  @override
  String toString() =>
      '${start.toIso8601String().substring(0, 10)} → ${end.toIso8601String().substring(0, 10)}';
}

class FiscalYearService {
  FiscalYearService._({
    required SettingsRepository settings,
    required DatabaseHelper dbHelper,
  })  : _settings = settings,
        _dbHelper = dbHelper;

  static final FiscalYearService instance = FiscalYearService._(
    settings: SettingsRepositoryImpl(),
    dbHelper: DatabaseHelper.instance,
  );

  final SettingsRepository _settings;
  final DatabaseHelper _dbHelper;

  // ── FY Date Arithmetic ──────────────────────────────────────────────────

  /// Returns the FY [DateRange] that contains [date], respecting the
  /// configured `fiscal_year_start_month` and `fiscal_year_start_day`.
  Future<DateRange> getFiscalYearFor(DateTime date) async {
    final startMonth =
        int.parse(await _settings.get('fiscal_year_start_month') ?? '4');
    final startDay =
        int.parse(await _settings.get('fiscal_year_start_day') ?? '1');

    final thisYearStart = DateTime(date.year, startMonth, startDay);

    if (!date.isBefore(thisYearStart)) {
      // date ≥ this year's FY start → FY spans date.year → date.year+1
      return DateRange(
        start: thisYearStart,
        end: DateTime(date.year + 1, startMonth, startDay)
            .subtract(const Duration(days: 1)),
      );
    } else {
      // date < this year's FY start → FY spans date.year-1 → date.year
      return DateRange(
        start: DateTime(date.year - 1, startMonth, startDay),
        end: thisYearStart.subtract(const Duration(days: 1)),
      );
    }
  }

  /// Returns the currently active FY [DateRange].
  Future<DateRange> get currentFiscalYear => getFiscalYearFor(DateTime.now());

  // ── Labels ──────────────────────────────────────────────────────────────

  /// Returns a display label such as "FY 2025–26" (April-start) or "CY 2025"
  /// (January-start / calendar year).
  Future<String> getFYLabel(DateRange range) async {
    final startMonth =
        int.parse(await _settings.get('fiscal_year_start_month') ?? '4');
    if (startMonth == 1) {
      return 'CY ${range.start.year}';
    }
    final endYY = (range.end.year % 100).toString().padLeft(2, '0');
    return 'FY ${range.start.year}–$endYY';
  }

  /// Convenience: label for the current FY, e.g. "FY 2025–26".
  Future<String> get currentFYLabel async {
    final fy = await currentFiscalYear;
    return getFYLabel(fy);
  }

  // ── Proximity & Reset Checks ────────────────────────────────────────────

  /// Returns true if today is within [daysBeforeEnd] of the FY end date.
  Future<bool> isApproachingYearEnd({int daysBeforeEnd = 30}) async {
    final fy = await currentFiscalYear;
    final daysLeft = fy.end.difference(DateTime.now()).inDays;
    return daysLeft >= 0 && daysLeft <= daysBeforeEnd;
  }

  /// Returns true if the current FY has started but `current_fy_start` in
  /// settings still points to the old FY — i.e., a sequence reset is due.
  Future<bool> isResetDue() async {
    final storedStr = await _settings.get('current_fy_start') ?? '';
    if (storedStr.isEmpty) return false;
    final stored = DateTime.tryParse(storedStr);
    if (stored == null) return false;
    final actualStart = (await currentFiscalYear).start;
    return actualStart.isAfter(stored);
  }

  // ── Invoice / Quote Numbering ───────────────────────────────────────────

  /// Generates the next invoice number for today's FY.
  ///
  /// Example with default format 'INV-{YY}-{YY+1}-{SEQ}':
  ///   → "INV-25-26-0001" on the first invoice of FY 2025-26.
  Future<String> nextInvoiceNo() async {
    final now = DateTime.now();
    final fy = await getFiscalYearFor(now);
    final format =
        await _settings.get('invoice_no_format') ?? 'INV-{YY}-{YY+1}-{SEQ}';
    final prefix = _fyPrefixFromRange(format, fy);
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT invoice_no FROM invoices WHERE invoice_no LIKE ? ORDER BY id DESC LIMIT 1',
      ['$prefix%'],
    );
    int seq = 1;
    if (result.isNotEmpty) {
      final last = result.first['invoice_no'] as String;
      final seqStr = last.substring(prefix.length);
      seq = (int.tryParse(seqStr) ?? 0) + 1;
    }
    return _applyTokens(format, fy, seq);
  }

  /// Generates the next quote number for today's FY.
  ///
  /// Example with default format 'QT-{YY}-{YY+1}-{SEQ}':
  ///   → "QT-25-26-0001" on the first quote of FY 2025-26.
  Future<String> nextQuoteNo() async {
    final now = DateTime.now();
    final fy = await getFiscalYearFor(now);
    final format =
        await _settings.get('quote_no_format') ?? 'QT-{YY}-{YY+1}-{SEQ}';
    final prefix = _fyPrefixFromRange(format, fy);
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT quote_no FROM quotes WHERE quote_no LIKE ? ORDER BY id DESC LIMIT 1',
      ['$prefix%'],
    );
    int seq = 1;
    if (result.isNotEmpty) {
      final last = result.first['quote_no'] as String;
      final seqStr = last.substring(prefix.length);
      seq = (int.tryParse(seqStr) ?? 0) + 1;
    }
    return _applyTokens(format, fy, seq);
  }

  /// Generates the next delivery challan number for today's FY.
  ///
  /// Default format: 'DC-{YY}-{YY+1}-{SEQ}' → "DC-25-26-0001"
  Future<String> nextChallanNo() async {
    final now = DateTime.now();
    final fy = await getFiscalYearFor(now);
    final format =
        await _settings.get('challan_no_format') ?? 'DC-{YY}-{YY+1}-{SEQ}';
    final prefix = _fyPrefixFromRange(format, fy);
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT challan_no FROM delivery_challans WHERE challan_no LIKE ? ORDER BY id DESC LIMIT 1',
      ['$prefix%'],
    );
    int seq = 1;
    if (result.isNotEmpty) {
      final last = result.first['challan_no'] as String;
      final seqStr = last.substring(prefix.length);
      seq = (int.tryParse(seqStr) ?? 0) + 1;
    }
    return _applyTokens(format, fy, seq);
  }

  /// Generates the next credit note number for today's FY.
  ///
  /// Default format: 'CN-{YY}-{YY+1}-{SEQ}' → "CN-25-26-0001"
  Future<String> nextCreditNoteNo() async {
    final now = DateTime.now();
    final fy = await getFiscalYearFor(now);
    const format = 'CN-{YY}-{YY+1}-{SEQ}';
    final prefix = _fyPrefixFromRange(format, fy);
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      "SELECT invoice_no FROM invoices WHERE invoice_no LIKE ? AND invoice_type = 'credit_note' ORDER BY id DESC LIMIT 1",
      ['$prefix%'],
    );
    int seq = 1;
    if (result.isNotEmpty) {
      final last = result.first['invoice_no'] as String;
      final seqStr = last.substring(prefix.length);
      seq = (int.tryParse(seqStr) ?? 0) + 1;
    }
    return _applyTokens(format, fy, seq);
  }

  /// Generates the next debit note number for today's FY.
  ///
  /// Default format: 'DN-{YY}-{YY+1}-{SEQ}' → "DN-25-26-0001"
  Future<String> nextDebitNoteNo() async {
    final now = DateTime.now();
    final fy = await getFiscalYearFor(now);
    const format = 'DN-{YY}-{YY+1}-{SEQ}';
    final prefix = _fyPrefixFromRange(format, fy);
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      "SELECT invoice_no FROM invoices WHERE invoice_no LIKE ? AND invoice_type = 'debit_note' ORDER BY id DESC LIMIT 1",
      ['$prefix%'],
    );
    int seq = 1;
    if (result.isNotEmpty) {
      final last = result.first['invoice_no'] as String;
      final seqStr = last.substring(prefix.length);
      seq = (int.tryParse(seqStr) ?? 0) + 1;
    }
    return _applyTokens(format, fy, seq);
  }

  // ── Startup Hook ────────────────────────────────────────────────────────

  /// Call once at app startup (after DB open) to keep `current_fy_start` in
  /// sync. If the FY has flipped since the last launch, this updates the
  /// stored value, making [isResetDue] return true.
  Future<void> ensureCurrentFYStart() async {
    final stored = await _settings.get('current_fy_start') ?? '';
    final actualStart = (await currentFiscalYear).start;
    final actualStr = actualStart.toIso8601String().substring(0, 10);
    if (stored != actualStr) {
      await _settings.set('current_fy_start', actualStr);
      debugPrint('[FY] current_fy_start updated → $actualStr');
    }
  }

  // ── Private Helpers ─────────────────────────────────────────────────────

  /// Expands all tokens except {SEQ} in [format] using [fy], then returns
  /// everything before {SEQ} as the SQL LIKE prefix.
  String _fyPrefixFromRange(String format, DateRange fy) {
    final seqIdx = format.indexOf('{SEQ}');
    // Take only the portion of the format before {SEQ}.
    final prefixTemplate =
        seqIdx >= 0 ? format.substring(0, seqIdx) : format;
    // _applyTokens is safe here: {SEQ} is absent from prefixTemplate,
    // so the seq argument (0) has no effect on the output.
    return _applyTokens(prefixTemplate, fy, 0);
  }

  /// Substitutes all format tokens in [format] using [fy] and [seq].
  String _applyTokens(String format, DateRange fy, int seq) {
    final yyyy = fy.start.year.toString();
    final yy = (fy.start.year % 100).toString().padLeft(2, '0');
    // end.year may be same as start.year for calendar-year configs;
    // use start.year+1 for the {YY+1} token.
    final yy1 = ((fy.start.year + 1) % 100).toString().padLeft(2, '0');
    final seqStr = seq.toString().padLeft(4, '0');
    return format
        .replaceAll('{YYYY}', yyyy)
        .replaceAll('{YY+1}', yy1) // must come before {YY}
        .replaceAll('{YY}', yy)
        .replaceAll('{SEQ}', seqStr);
  }
}
