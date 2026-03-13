import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import '../services/database_helper.dart';

/// All REST route handlers for KashCube Web.
///
/// Handlers are pure functions (Request → Response).
/// They query [DatabaseHelper.instance] directly — same DB the app uses.
/// All queries are parameterized. context_id IS NULL = personal data.
///
/// Note: auth token validation is done in [WebServerService] before these
/// handlers are called.
class WebApiRoutes {
  WebApiRoutes._();

  static final DatabaseHelper _db = DatabaseHelper.instance;

  // ── helpers ────────────────────────────────────────────────────────────────

  static Response _json(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );

  static Response _err(String msg, {int status = 400}) =>
      _json({'error': msg}, status: status);

  static int _parseInt(String? v, int fallback) {
    if (v == null) return fallback;
    return int.tryParse(v) ?? fallback;
  }

  // ── Dashboard ──────────────────────────────────────────────────────────────

  static Future<Response> dashboard(Request req) async {
    try {
      final db = await _db.database;
      final now = DateTime.now();
      final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final monthEnd =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-31';

      final incomeResult = await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS v FROM transactions "
        "WHERE deleted_at IS NULL AND context_id IS NULL "
        "AND type IN ('income','received_back') AND date >= ? AND date <= ?",
        [monthStart, monthEnd],
      );
      final expenseResult = await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS v FROM transactions "
        "WHERE deleted_at IS NULL AND context_id IS NULL "
        "AND type IN ('expense','paid_back') AND date >= ? AND date <= ?",
        [monthStart, monthEnd],
      );
      final creditsResult = await db.rawQuery(
        "SELECT COALESCE(SUM(amount - COALESCE(paid_amount,0)),0) AS v "
        "FROM credits WHERE deleted_at IS NULL AND context_id IS NULL "
        "AND status != 'settled'",
        [],
      );
      final recentRows = await db.rawQuery(
        "SELECT id, amount, type, notes, category, party_name, date, payment_method "
        "FROM transactions WHERE deleted_at IS NULL AND context_id IS NULL "
        "ORDER BY date DESC, id DESC LIMIT 10",
      );

      final income = (incomeResult.first['v'] as num).toDouble();
      final expense = (expenseResult.first['v'] as num).toDouble();
      final credits = (creditsResult.first['v'] as num).toDouble();

      return _json({
        'this_month_income': income,
        'this_month_expense': expense,
        'net': income - expense,
        'outstanding_credits': credits,
        'recent_transactions': recentRows.map(_txnRow).toList(),
      });
    } catch (e) {
      return _err('Dashboard error: $e', status: 500);
    }
  }

  // ── Transactions ───────────────────────────────────────────────────────────

  static Future<Response> listTransactions(Request req) async {
    try {
      final q = req.url.queryParameters;
      final page = _parseInt(q['page'], 1).clamp(1, 9999);
      final limit = _parseInt(q['limit'], 50).clamp(1, 200);
      final offset = (page - 1) * limit;
      final search = q['search']?.trim();
      final dateFrom = q['date_from'];
      final dateTo = q['date_to'];

      final db = await _db.database;

      final whereParts = <String>['deleted_at IS NULL', 'context_id IS NULL'];
      final args = <dynamic>[];

      if (search != null && search.isNotEmpty) {
        whereParts.add('(party_name LIKE ? OR notes LIKE ? OR category LIKE ?)');
        final p = '%$search%';
        args.addAll([p, p, p]);
      }
      if (dateFrom != null) {
        whereParts.add('date >= ?');
        args.add(dateFrom);
      }
      if (dateTo != null) {
        whereParts.add('date <= ?');
        args.add(dateTo);
      }

      final where = whereParts.join(' AND ');

      final countResult = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM transactions WHERE $where',
        args,
      );
      final total = (countResult.first['c'] as int?) ?? 0;

      final rows = await db.rawQuery(
        'SELECT id, amount, type, notes, category, party_name, date, '
        'payment_method, created_at FROM transactions '
        'WHERE $where ORDER BY date DESC, id DESC LIMIT ? OFFSET ?',
        [...args, limit, offset],
      );

      return _json({
        'page': page,
        'limit': limit,
        'total': total,
        'items': rows.map(_txnRow).toList(),
      });
    } catch (e) {
      return _err('List transactions error: $e', status: 500);
    }
  }

  static Future<Response> getTransaction(Request req, String id) async {
    final rowId = int.tryParse(id);
    if (rowId == null) return _err('Invalid id');
    try {
      final db = await _db.database;
      final rows = await db.rawQuery(
        'SELECT * FROM transactions WHERE id = ? AND deleted_at IS NULL '
        'AND context_id IS NULL',
        [rowId],
      );
      if (rows.isEmpty) return _err('Not found', status: 404);
      return _json(_txnRow(rows.first));
    } catch (e) {
      return _err('Get transaction error: $e', status: 500);
    }
  }

  static Future<Response> createTransaction(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;

      final amount = (body['amount'] as num?)?.toDouble();
      final type = body['type'] as String?;
      final date = body['date'] as String?;
      final paymentMethod = body['payment_method'] as String? ?? 'Cash';
      final notes = body['notes'] as String? ?? '';
      final category = body['category'] as String? ?? 'Other';
      final partyName = body['party_name'] as String?;

      if (amount == null || amount <= 0) return _err('amount must be > 0');
      if (type == null ||
          !{'income', 'expense', 'paid_back', 'received_back'}
              .contains(type)) {
        return _err('type must be income | expense | paid_back | received_back');
      }
      if (date == null) return _err('date is required (YYYY-MM-DD)');

      final db = await _db.database;
      final syncId = const Uuid().v4();
      final now = DateTime.now().toIso8601String();

      final rowId = await db.insert('transactions', {
        'amount': amount,
        'type': type,
        'date': date,
        'payment_method': paymentMethod,
        'notes': notes,
        'category': category,
        'party_name': partyName,
        'context_id': null,
        'sync_id': syncId,
        'version': 0,
        'created_at': now,
        'updated_at': now,
      });

      final row = await db.rawQuery(
        'SELECT * FROM transactions WHERE id = ?', [rowId],
      );

      return _json(_txnRow(row.first), status: 201);
    } catch (e) {
      return _err('Create transaction error: $e', status: 500);
    }
  }

  // ── Parties ────────────────────────────────────────────────────────────────

  static Future<Response> listParties(Request req) async {
    try {
      final search = req.url.queryParameters['search']?.trim();
      final db = await _db.database;

      List<Map<String, Object?>> rows;
      if (search != null && search.isNotEmpty) {
        rows = await db.rawQuery(
          'SELECT id, name, phone, type FROM parties '
          'WHERE deleted_at IS NULL AND context_id IS NULL '
          'AND name LIKE ? ORDER BY name ASC LIMIT 100',
          ['%$search%'],
        );
      } else {
        rows = await db.rawQuery(
          'SELECT id, name, phone, type FROM parties '
          'WHERE deleted_at IS NULL AND context_id IS NULL '
          'ORDER BY name ASC LIMIT 200',
        );
      }

      return _json({'items': rows.toList()});
    } catch (e) {
      return _err('List parties error: $e', status: 500);
    }
  }

  // ── Categories ─────────────────────────────────────────────────────────────

  static Future<Response> listCategories(Request req) async {
    try {
      final db = await _db.database;
      final rows = await db.rawQuery(
        'SELECT id, name, type, icon FROM categories '
        'WHERE deleted_at IS NULL AND context_id IS NULL '
        'ORDER BY name ASC',
      );
      return _json({'items': rows.toList()});
    } catch (e) {
      return _err('List categories error: $e', status: 500);
    }
  }

  // ── Invoices ────────────────────────────────────────────────────────────────

  static Future<Response> listInvoices(Request req) async {
    try {
      final q = req.url.queryParameters;
      final page = _parseInt(q['page'], 1).clamp(1, 9999);
      final limit = _parseInt(q['limit'], 50).clamp(1, 100);
      final offset = (page - 1) * limit;

      final db = await _db.database;
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM invoices WHERE deleted_at IS NULL',
      );
      final total = (countResult.first['c'] as int?) ?? 0;

      final rows = await db.rawQuery(
        'SELECT id, invoice_number, party_name, total_amount, status, '
        'invoice_date, due_date FROM invoices '
        'WHERE deleted_at IS NULL ORDER BY invoice_date DESC LIMIT ? OFFSET ?',
        [limit, offset],
      );

      return _json({'page': page, 'limit': limit, 'total': total, 'items': rows.toList()});
    } catch (e) {
      return _err('List invoices error: $e', status: 500);
    }
  }

  static Future<Response> getInvoicePdf(Request req, String id) async {
    // Sprint W2: generate PDF bytes and stream them for browser print.
    // In Sprint W1 return 501 so the browser can show a friendly message.
    return Response(
      501,
      body: jsonEncode({'error': 'PDF export available in KashCube Web v2'}),
      headers: {'content-type': 'application/json'},
    );
  }

  // ── Credits ────────────────────────────────────────────────────────────────

  static Future<Response> listCredits(Request req) async {
    try {
      final q = req.url.queryParameters;
      final limit = _parseInt(q['limit'], 50).clamp(1, 200);
      final db = await _db.database;

      final rows = await db.rawQuery(
        'SELECT id, party_name, amount, paid_amount, status, type, due_date, notes '
        'FROM credits WHERE deleted_at IS NULL AND context_id IS NULL '
        'ORDER BY created_at DESC LIMIT ?',
        [limit],
      );

      return _json({'items': rows.toList()});
    } catch (e) {
      return _err('List credits error: $e', status: 500);
    }
  }

  // ── Row mappers ────────────────────────────────────────────────────────────

  static Map<String, dynamic> _txnRow(Map<String, Object?> r) => {
        'id': r['id'],
        'amount': (r['amount'] as num?)?.toDouble() ?? 0.0,
        'type': r['type'],
        'note': r['notes'],
        'category': r['category'],
        'party': r['party_name'],
        'date': r['date'],
        'payment_method': r['payment_method'],
        'created_at': r['created_at'],
      };
}
