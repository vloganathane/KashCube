import '../models/staff.dart';
import '../services/database_helper.dart';

/// CRUD for staff roster and salary payments.
class StaffRepository {
  StaffRepository._();
  static final StaffRepository instance = StaffRepository._();

  final _db = DatabaseHelper.instance;

  // ── Staff CRUD ─────────────────────────────────────────────────────────────

  Future<List<Staff>> getAll({int? businessId, bool activeOnly = true}) async {
    final db = await _db.database;
    final conditions = <String>[];
    final args = <dynamic>[];
    if (activeOnly) conditions.add('is_active = 1');
    if (businessId != null) {
      conditions.add('(business_id = ? OR business_id IS NULL)');
      args.add(businessId);
    }
    final where =
        conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final rows = await db.rawQuery(
      'SELECT * FROM staff $where ORDER BY name COLLATE NOCASE',
      args,
    );
    return rows.map(Staff.fromMap).toList();
  }

  Future<Staff?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('staff', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Staff.fromMap(rows.first);
  }

  Future<int> insert(Staff staff) async {
    final db = await _db.database;
    return db.insert('staff', staff.toMap());
  }

  Future<void> update(Staff staff) async {
    final db = await _db.database;
    final map = staff.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    await db.update('staff', map, where: 'id = ?', whereArgs: [staff.id]);
  }

  Future<void> deactivate(int id) async {
    final db = await _db.database;
    await db.update(
      'staff',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Salary Payments ────────────────────────────────────────────────────────

  Future<List<SalaryPayment>> getPaymentsForStaff(int staffId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT * FROM salary_payments WHERE staff_id = ? '
      'ORDER BY pay_period_year DESC, pay_period_month DESC',
      [staffId],
    );
    return rows.map(SalaryPayment.fromMap).toList();
  }

  /// Payments for a given month across all staff (for payroll run view).
  Future<List<SalaryPayment>> getPaymentsForPeriod(
    int month,
    int year,
  ) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT * FROM salary_payments '
      'WHERE pay_period_month = ? AND pay_period_year = ?',
      [month, year],
    );
    return rows.map(SalaryPayment.fromMap).toList();
  }

  Future<int> insertPayment(SalaryPayment payment) async {
    final db = await _db.database;
    return db.insert('salary_payments', payment.toMap());
  }

  Future<void> updatePayment(SalaryPayment payment) async {
    final db = await _db.database;
    await db.update(
      'salary_payments',
      payment.toMap(),
      where: 'id = ?',
      whereArgs: [payment.id],
    );
  }

  Future<void> deletePayment(int id) async {
    final db = await _db.database;
    await db.delete('salary_payments', where: 'id = ?', whereArgs: [id]);
  }
}
