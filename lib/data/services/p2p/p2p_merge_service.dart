import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../sync/sync_table_registry.dart';

/// Tables that participate in P2P LAN sync.
///
/// The merge service is table-agnostic for most operations; [_invoiceTable] is
/// special-cased because it uses the state-machine override for `status`.
const _invoiceTable = 'invoices';

/// Invoice status ordinal map used by the state machine.
///
/// Higher ordinal wins in a tie-break. `cancelled` is handled separately:
/// it always wins over any non-cancelled status (even `paid`).
const _invoiceStatusOrdinal = <String, int>{
  'draft':         0,
  'pendingNumber': 1,
  'sent':          2,
  'overdue':       2, // same "sent" tier — whichever is newer wins
  'viewed':        3,
  'partiallyPaid': 4,
  'paid':          5,
  'cancelled':     6, // special — beats everything
};

/// Merges remote rows into the local SQLite database using Last-Write-Wins
/// (LWW) semantics per row, keyed on `sync_id`.
///
/// Invoice `status` is additionally governed by a state machine:
///   `draft(0) → sent/overdue(2) → viewed(3) → partiallyPaid(4) → paid(5)`
///   `cancelled(6)` always wins regardless of `updated_at`.
///
/// Soft-delete: a remote row with `deleted_at` set wins if it is newer
/// than the local row, effectively marking the record as deleted locally.
///
/// Thread-safety: all public methods are async and must be called
/// on the same isolate as the [Database] instance.
///
/// No network calls — purely local, never transmits data.
class P2pMergeService {
  P2pMergeService._();
  static final P2pMergeService instance = P2pMergeService._();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Merges [remoteRows] into [table] within [db].
  ///
  /// Returns a [MergeResult] summarising how many rows were
  /// inserted, updated, or skipped.
  ///
  /// [deviceId] is this device's identity_id, written into
  /// `updated_by_device_id` on rows that are written locally so that
  /// the next outbound sync can detect which device last touched each row.
  Future<MergeResult> mergeTable({
    required Database db,
    required String table,
    required List<Map<String, dynamic>> remoteRows,
    required String deviceId,
    String keyColumn = 'sync_id',
    SyncMode mode = SyncMode.deltaTs,
  }) async {
    var inserted = 0;
    var updated  = 0;
    var skipped  = 0;

    for (final remote in remoteRows) {
      final keyValue = remote[keyColumn];
      if (keyValue == null) {
        debugPrint('[Merge] Skipping row with no $keyColumn in $table');
        skipped++;
        continue;
      }

      final existing = await _fetchByKey(
        db,
        table,
        keyColumn,
        keyValue,
      );
      if (existing == null) {
        // New row — insert it.
        await _insertRow(
          db,
          table,
          remote,
          deviceId,
          preserveId: keyColumn == 'id',
        );
        inserted++;
      } else {
        final shouldApply = _shouldApplyRemote(
          table:    table,
          local:    existing,
          remote:   remote,
          mode:     mode,
        );
        if (shouldApply) {
          await _updateRow(
            db,
            table,
            remote,
            existing['id'] as int,
            deviceId,
            keyColumn: keyColumn,
          );
          updated++;
        } else {
          skipped++;
        }
      }
    }

    debugPrint(
      '[Merge] $table → inserted=$inserted updated=$updated skipped=$skipped',
    );
    return MergeResult(
      table:    table,
      inserted: inserted,
      updated:  updated,
      skipped:  skipped,
    );
  }

  // ── Core LWW + state-machine decision ────────────────────────────────────

  /// Returns true if the remote row should overwrite the local row.
  ///
  /// Rules (evaluated in order):
  ///   1. Remote `deleted_at` set + newer → apply (soft-delete wins).
  ///   2. Invoices: `status` state machine — higher ordinal wins;
  ///      if same ordinal, fall through to rule 3.
  ///   3. LWW: remote `updated_at` > local `updated_at` → apply.
  bool _shouldApplyRemote({
    required String table,
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
    required SyncMode mode,
  }) {
    final localTs  = _parseTs(local['updated_at']);
    final remoteTs = _parseTs(remote['updated_at']);

    // Rule 1 — soft-delete: a deleted remote wins if newer.
    final remoteDeleted = remote['deleted_at'] != null;
    final localDeleted  = local['deleted_at']  != null;
    if (remoteDeleted && !localDeleted) {
      return remoteTs != null && (localTs == null || remoteTs.isAfter(localTs));
    }

    // Rule 2 — invoice state machine.
    if (table == _invoiceTable) {
      final localStatus  = local['status']  as String? ?? 'draft';
      final remoteStatus = remote['status'] as String? ?? 'draft';
      final decision = _resolveInvoiceStatus(localStatus, remoteStatus);
      if (decision == _StatusDecision.remoteWins) return true;
      if (decision == _StatusDecision.localWins)  return false;
      // _StatusDecision.useLww → fall through to rule 3.
    }

    if (mode == SyncMode.deltaVersion) {
      return _remoteVersionIsNewer(local: local, remote: remote);
    }

    if (mode == SyncMode.snapshot) {
      return true;
    }

    // Rule 3 — LWW.
    if (remoteTs == null) return false;
    if (localTs  == null) return true;
    return remoteTs.isAfter(localTs);
  }

  bool _remoteVersionIsNewer({
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
  }) {
    final localVersion = _parseInt(local['version']);
    final remoteVersion = _parseInt(remote['version']);
    if (remoteVersion == null) return false;
    if (localVersion == null) return true;
    return remoteVersion > localVersion;
  }

  /// Resolves invoice status conflict.
  _StatusDecision _resolveInvoiceStatus(
    String localStatus,
    String remoteStatus,
  ) {
    if (localStatus == remoteStatus) return _StatusDecision.useLww;

    final localOrd  = _invoiceStatusOrdinal[localStatus]  ?? 0;
    final remoteOrd = _invoiceStatusOrdinal[remoteStatus] ?? 0;

    // `cancelled` (ordinal 6) always wins over everything else.
    if (remoteStatus == 'cancelled') return _StatusDecision.remoteWins;
    if (localStatus  == 'cancelled') return _StatusDecision.localWins;

    if (remoteOrd > localOrd) return _StatusDecision.remoteWins;
    if (remoteOrd < localOrd) return _StatusDecision.localWins;
    return _StatusDecision.useLww; // same tier → use timestamps
  }

  // ── DB helpers ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _fetchByKey(
    Database db,
    String table,
    String keyColumn,
    Object keyValue,
  ) async {
    final rows = await db.query(
      table,
      where: '$keyColumn = ?',
      whereArgs: [keyValue],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _insertRow(
    Database db,
    String table,
    Map<String, dynamic> remote,
    String deviceId, {
    required bool preserveId,
  }
  ) async {
    final row = _prepareRow(remote, deviceId);
    if (!preserveId) {
      // Remove integer PK so SQLite assigns its own.
      row.remove('id');
    }
    await db.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _updateRow(
    Database db,
    String table,
    Map<String, dynamic> remote,
    int localId,
    String deviceId, {
    required String keyColumn,
  }
  ) async {
    final row = _prepareRow(remote, deviceId);
    row.remove('id');      // don't overwrite PK
    row.remove(keyColumn); // immutable after creation
    await db.update(
      table,
      row,
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Cleans the remote row map before writing: strips unknown fields and
  /// stamps [deviceId] as the last writer.
  Map<String, dynamic> _prepareRow(
    Map<String, dynamic> remote,
    String deviceId,
  ) {
    final row = Map<String, dynamic>.from(remote);
    row['updated_by_device_id'] = deviceId;
    // Ensure any JSON sub-objects are serialised to strings.
    for (final key in row.keys.toList()) {
      final val = row[key];
      if (val is Map || val is List) {
        row[key] = jsonEncode(val);
      }
    }
    return row;
  }

  DateTime? _parseTs(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value as String).toUtc();
    } catch (_) {
      return null;
    }
  }

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

// ── Supporting types ─────────────────────────────────────────────────────────

enum _StatusDecision { remoteWins, localWins, useLww }

/// Summary of a single-table merge operation.
class MergeResult {
  const MergeResult({
    required this.table,
    required this.inserted,
    required this.updated,
    required this.skipped,
  });

  final String table;
  final int inserted;
  final int updated;
  final int skipped;

  int get total => inserted + updated + skipped;
  bool get hadChanges => inserted > 0 || updated > 0;

  @override
  String toString() =>
      'MergeResult($table: +$inserted ~$updated =$skipped)';
}
