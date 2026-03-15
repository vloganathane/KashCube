import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'fiscal_year_service.dart';

// ---------------------------------------------------------------------------
// NumberReservationService
// ---------------------------------------------------------------------------
// Provides atomic, conflict-free document-number reservation backed by the
// `invoice_number_cursors` table (added in DB v67).
//
// One cursor row per document type. The cursor stores the *prefix* (all
// format tokens resolved except {SEQ}). When the FY rolls over the prefix
// changes, triggering an automatic reset of last_seq to 0.
//
// Supported doc types:
//   'invoice'     → invoices  (INV-25-26-0001, CN-25-26-0001, DN-25-26-0001)
//   'quote'       → quotes    (QT-25-26-0001)
//   'dc'          → delivery_challans (DC-25-26-0001)
//
// Deferred path (offline secondary):
//   Rows saved with invoice_no = NULL and status = 'pending_number'.
//   When the primary receives a delta-upload from a secondary it calls
//   assignPendingNumbers() which processes them in created_at order.
// ---------------------------------------------------------------------------

class NumberReservationService {
  const NumberReservationService._();

  static const NumberReservationService instance = NumberReservationService._();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Atomically reserves [count] sequential numbers for [docType] under the
  /// given [prefix] (the part of the format string before `{SEQ}`).
  ///
  /// Runs inside a `BEGIN EXCLUSIVE` transaction so concurrent calls on the
  /// same SQLite connection are safe.
  ///
  /// [prefix]  — e.g. `"INV-25-26-"` (already has trailing separator)
  /// Returns   — e.g. `["INV-25-26-0042"]` for count=1
  Future<List<String>> reserveNext(
    Database db, {
    required String docType,
    required String prefix,
    int count = 1,
    int padWidth = 4,
  }) async {
    assert(count >= 1);

    List<String> assigned = [];

    await db.transaction((txn) async {
      final rows = await txn.query(
        'invoice_number_cursors',
        where: 'doc_type = ?',
        whereArgs: [docType],
        limit: 1,
      );

      int startSeq;

      if (rows.isEmpty || rows.first['prefix'] as String != prefix) {
        // First use in this FY or FY rollover → start fresh at 1.
        startSeq = 1;
        final now = DateTime.now().toIso8601String();
        await txn.insert(
          'invoice_number_cursors',
          {
            'doc_type': docType,
            'prefix': prefix,
            'last_seq': startSeq + count - 1,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        final lastSeq = rows.first['last_seq'] as int;
        startSeq = lastSeq + 1;
        await txn.update(
          'invoice_number_cursors',
          {
            'prefix': prefix,
            'last_seq': lastSeq + count,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'doc_type = ?',
          whereArgs: [docType],
        );
      }

      for (int i = 0; i < count; i++) {
        assigned.add('$prefix${(startSeq + i).toString().padLeft(padWidth, '0')}');
      }
    });

    return assigned;
  }

  // ── Deferred path ─────────────────────────────────────────────────────────

  /// Assigns real numbers to all rows that were saved with a NULL number
  /// (status = 'pending_number') on any secondary device and then uploaded
  /// to the primary via delta-upload.
  ///
  /// Processes rows in `created_at ASC` order to preserve chronological
  /// sequence. Updates the number column and clears `pending_number_since`.
  /// Returns the number of rows that received a number.
  Future<int> assignPendingNumbers(
    Database db,
    FiscalYearService fyService,
  ) async {
    int assigned = 0;
    assigned += await _assignPendingForTable(
      db,
      fyService,
      table: 'invoices',
      numberColumn: 'invoice_no',
      docTypeForFormat: 'invoice',
      invoiceTypeFilter: null,
    );
    assigned += await _assignPendingForTable(
      db,
      fyService,
      table: 'quotes',
      numberColumn: 'quote_no',
      docTypeForFormat: 'quote',
      invoiceTypeFilter: null,
    );
    assigned += await _assignPendingForTable(
      db,
      fyService,
      table: 'delivery_challans',
      numberColumn: 'challan_no',
      docTypeForFormat: 'dc',
      invoiceTypeFilter: null,
    );
    return assigned;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<int> _assignPendingForTable(
    Database db,
    FiscalYearService fyService, {
    required String table,
    required String numberColumn,
    required String docTypeForFormat,
    String? invoiceTypeFilter,
  }) async {
    String whereClause = '$numberColumn IS NULL AND pending_number_since IS NOT NULL';
    List<dynamic> whereArgs = [];
    if (invoiceTypeFilter != null) {
      whereClause += ' AND invoice_type = ?';
      whereArgs.add(invoiceTypeFilter);
    }

    final pending = await db.query(
      table,
      where: whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at ASC',
    );

    if (pending.isEmpty) return 0;

    int count = 0;
    for (final row in pending) {
      final id = row['id'];
      final createdAt = row['created_at'] as String?;
      final date = createdAt != null
          ? DateTime.tryParse(createdAt) ?? DateTime.now()
          : DateTime.now();

      final fy = await fyService.getFiscalYearFor(date);
      final format = await _formatForDocType(fyService, docTypeForFormat);
      final prefix = fyService.computePrefix(format, fy);

      final numbers = await reserveNext(
        db,
        docType: docTypeForFormat,
        prefix: prefix,
      );
      final number = numbers.first;

      await db.update(
        table,
        {
          numberColumn: number,
          'pending_number_since': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      count++;
    }

    debugPrint('[NumberReservation] assigned $count pending numbers in $table');
    return count;
  }

  Future<String> _formatForDocType(
    FiscalYearService fyService,
    String docType,
  ) async {
    switch (docType) {
      case 'invoice':
        return await fyService.invoiceNoFormat;
      case 'quote':
        return await fyService.quoteNoFormat;
      case 'dc':
        return await fyService.challanNoFormat;
      default:
        return 'DOC-{YY}-{YY+1}-{SEQ}';
    }
  }
}
