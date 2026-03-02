import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/repositories/settings_repository.dart';
import '../repositories/settings_repository_impl.dart';
import 'database_helper.dart';
import 'fiscal_year_service.dart';

// ---------------------------------------------------------------------------
// FyArchiveService
// ---------------------------------------------------------------------------
// Handles year-end closing for Kash Cube:
//
//  1. Queries the FY summary (income, expense, invoice stats) for display in
//     the closing wizard.
//  2. Archives the live DB as `kash_cube_archive_FY{YYYY}-{YY+1}.db` so it
//     can be kept as a read-only historical reference.
//  3. Updates `last_fy_close_date` and `current_fy_start` in settings so the
//     year-end banner disappears and invoice sequences reset to 0001.
//
// Archiving is a safe copy-then-update flow:
//   close DB → copy file → update settings → reopen DB
//
// The live DB is NOT modified — all historical records remain accessible.
// Invoice numbering resets automatically because the next FY prefix (e.g.,
// "INV-26-27-") does not match any existing row in the DB.
// ---------------------------------------------------------------------------

/// Immutable FY financial summary used by the closing wizard.
class FYSummary {
  const FYSummary({
    required this.fyLabel,
    required this.fyRange,
    required this.income,
    required this.expense,
    required this.invoiceCount,
    required this.outstanding,
    required this.openCreditCount,
  });

  final String fyLabel;
  final DateRange fyRange;

  /// Total income transactions in this FY.
  final double income;

  /// Total expense transactions in this FY.
  final double expense;

  /// Number of invoices issued in this FY.
  final int invoiceCount;

  /// Sum of unpaid amounts on sent/partial/overdue invoices in this FY.
  final double outstanding;

  /// Number of open (uncleared) credits/udhar at FY close.
  final int openCreditCount;

  double get netPnL => income - expense;
}

class FyArchiveService {
  FyArchiveService._({
    required SettingsRepository settings,
    required DatabaseHelper dbHelper,
    required FiscalYearService fyService,
  })  : _settings = settings,
        _dbHelper = dbHelper,
        _fyService = fyService;

  static final FyArchiveService instance = FyArchiveService._(
    settings: SettingsRepositoryImpl(),
    dbHelper: DatabaseHelper.instance,
    fyService: FiscalYearService.instance,
  );

  final SettingsRepository _settings;
  final DatabaseHelper _dbHelper;
  final FiscalYearService _fyService;

  // ── Summary ─────────────────────────────────────────────────────────────

  /// Returns the financial summary for the FY currently being closed.
  ///
  /// If [isResetDue] is true (FY has already flipped), this queries the
  /// OLD FY that is stored in `current_fy_start`.  Otherwise queries the
  /// current (still-open) FY.
  Future<FYSummary> getFYSummary() async {
    final fyRange = await _getFYBeingClosed();
    final fyLabel = await _fyService.getFYLabel(fyRange);
    final db = await _dbHelper.database;

    final startISO = fyRange.start.toIso8601String().substring(0, 10);
    final endISO = fyRange.end.toIso8601String().substring(0, 10);

    // ── Income / Expense ─────────────────────────────────────────────────
    final txRows = await db.rawQuery(
      '''
      SELECT type, COALESCE(SUM(amount), 0.0) AS total
      FROM transactions
      WHERE date >= ? AND date <= ? AND deleted_at IS NULL
        AND type IN ('income', 'expense')
      GROUP BY type
      ''',
      [startISO, endISO],
    );
    double income = 0, expense = 0;
    for (final row in txRows) {
      final t = row['type'] as String;
      final v = (row['total'] as num).toDouble();
      if (t == 'income') income = v;
      if (t == 'expense') expense = v;
    }

    // ── Invoice Stats ────────────────────────────────────────────────────
    final invCountRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM invoices WHERE issue_date >= ? AND issue_date <= ?',
      [startISO, endISO],
    );
    final invoiceCount = (invCountRows.first['cnt'] as int?) ?? 0;

    final outstandingRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total - paid_amount), 0.0) AS owed
      FROM invoices
      WHERE issue_date >= ? AND issue_date <= ?
        AND status IN ('sent', 'partial', 'overdue')
      ''',
      [startISO, endISO],
    );
    final outstanding =
        (outstandingRows.first['owed'] as num?)?.toDouble() ?? 0.0;

    // ── Open Credits ─────────────────────────────────────────────────────
    final creditRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS cnt FROM credits
      WHERE is_cleared = 0 AND deleted_at IS NULL
      ''',
    );
    final openCreditCount = (creditRows.first['cnt'] as int?) ?? 0;

    return FYSummary(
      fyLabel: fyLabel,
      fyRange: fyRange,
      income: income,
      expense: expense,
      invoiceCount: invoiceCount,
      outstanding: outstanding,
      openCreditCount: openCreditCount,
    );
  }

  // ── Archive ──────────────────────────────────────────────────────────────

  /// Archives the live DB and marks the FY as closed.
  ///
  /// Steps:
  ///   1. Determine FY range being closed → compute archive filename.
  ///   2. Flush WAL to main DB (PRAGMA wal_checkpoint(TRUNCATE)).
  ///   3. Close DB connection.
  ///   4. Copy `kash_cube.db` → `kash_cube_archive_FY{YYYY}-{YY+1}.db`.
  ///   5. Write `last_fy_close_date` and `current_fy_start` to settings.
  ///   6. Reopen DB (next `get database` call auto-initialises).
  ///
  /// Returns the archive [File] path on success.
  Future<File> archiveCurrentFY() async {
    final closingRange = await _getFYBeingClosed();
    final archiveFilename = _archiveName(closingRange);

    debugPrint('[FY] Archiving to $archiveFilename');

    // 1. Flush WAL so the copy is fully consistent.
    final db = await _dbHelper.database;
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');

    // 2. Get live DB path before closing.
    final dbDir = await getDatabasesPath();
    final livePath = join(dbDir, AppConstants.dbName);
    final archivePath = join(dbDir, archiveFilename);

    // 3. Close connection.
    await _dbHelper.close();

    // 4. Copy file.
    final liveFile = File(livePath);
    if (!liveFile.existsSync()) {
      throw StateError('Live DB not found at $livePath');
    }
    final archiveFile = await liveFile.copy(archivePath);

    // 5. Update settings.
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _settings.set('last_fy_close_date', today);

    // Update current_fy_start to the NEW FY start so isResetDue() → false.
    final newFyStart =
        (await _fyService.currentFiscalYear).start.toIso8601String().substring(0, 10);
    await _settings.set('current_fy_start', newFyStart);

    debugPrint('[FY] Closed. last_fy_close_date=$today, current_fy_start=$newFyStart');

    // 6. Reopen DB (triggers integrity check + snapshot pipeline).
    await _dbHelper.database;

    return archiveFile;
  }

  /// Returns true if the current FY has already been closed (wizard was
  /// completed for the current FY period).
  Future<bool> isFYAlreadyClosed() async {
    final closedStr = await _settings.get('last_fy_close_date') ?? '';
    if (closedStr.isEmpty) return false;
    final closed = DateTime.tryParse(closedStr);
    if (closed == null) return false;
    // Check if the close date falls within the FY being closed right now.
    final closingRange = await _getFYBeingClosed();
    return closingRange.contains(closed) || closed.isAfter(closingRange.end);
  }

  /// Returns the list of existing archive DB files, sorted oldest-first.
  Future<List<File>> listArchives() async {
    final dbDir = await getDatabasesPath();
    final dir = Directory(dbDir);
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            basename(f.path).startsWith('kash_cube_archive_FY') &&
            f.path.endsWith('.db'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  // ── Private ──────────────────────────────────────────────────────────────

  /// The FY range being closed (old FY when reset is due; current FY otherwise).
  Future<DateRange> _getFYBeingClosed() async {
    final isResetDue = await _fyService.isResetDue();
    if (isResetDue) {
      // current_fy_start still points to the OLD FY start — use it.
      final storedStr = await _settings.get('current_fy_start') ?? '';
      final storedStart =
          DateTime.tryParse(storedStr) ?? DateTime.now().subtract(const Duration(days: 366));
      return _fyService.getFiscalYearFor(storedStart);
    }
    return _fyService.currentFiscalYear;
  }

  /// e.g. "kash_cube_archive_FY2025-26.db" for FY Apr 2025–Mar 2026.
  String _archiveName(DateRange fy) {
    final startYear = fy.start.year.toString();
    final endYY = (fy.end.year % 100).toString().padLeft(2, '0');
    return 'kash_cube_archive_FY$startYear-$endYY.db';
  }
}
