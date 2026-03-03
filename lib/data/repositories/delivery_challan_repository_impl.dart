import '../../data/models/delivery_challan.dart';
import '../../data/models/invoice.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/delivery_challan_repository.dart';

class DeliveryChallanRepositoryImpl implements DeliveryChallanRepository {
  final _db = DatabaseHelper.instance;

  @override
  Future<List<DeliveryChallan>> getAll() async {
    final db = await _db.database;
    final rows = await db.query(
      'delivery_challans',
      orderBy: 'created_at DESC',
    );
    final result = <DeliveryChallan>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final items = await _itemsFor(db, id);
      result.add(DeliveryChallan.fromMap(row, items: items));
    }
    return result;
  }

  @override
  Future<DeliveryChallan?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'delivery_challans',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final items = await _itemsFor(db, id);
    return DeliveryChallan.fromMap(rows.first, items: items);
  }

  Future<List<ChallanItem>> _itemsFor(dynamic db, int challanId) async {
    final rows = await db.query(
      'delivery_challan_items',
      where: 'challan_id = ?',
      whereArgs: [challanId],
    );
    return rows.map<ChallanItem>(ChallanItem.fromMap).toList();
  }

  @override
  Future<int> insert(DeliveryChallan challan, List<ChallanItem> items) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final id = await txn.insert('delivery_challans', challan.toMap());
      for (final item in items) {
        await txn.insert(
          'delivery_challan_items',
          item.copyWith(challanId: id).toMap(),
        );
      }
      return id;
    });
  }

  @override
  Future<void> update(DeliveryChallan challan, List<ChallanItem> items) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'delivery_challans',
        challan.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: [challan.id],
      );
      await txn.delete(
        'delivery_challan_items',
        where: 'challan_id = ?',
        whereArgs: [challan.id],
      );
      for (final item in items) {
        await txn.insert(
          'delivery_challan_items',
          item.copyWith(challanId: challan.id!).toMap(),
        );
      }
    });
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('delivery_challans', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> markDispatched(int id, {DateTime? dispatchDate}) async {
    final db = await _db.database;
    final now = DateTime.now();
    await db.update(
      'delivery_challans',
      {
        'status': ChallanStatus.dispatched.dbValue,
        'dispatch_date': (dispatchDate ?? now).toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ? AND status = ?',
      whereArgs: [id, ChallanStatus.draft.dbValue],
    );
  }

  @override
  Future<void> markReturned(int id) async {
    final db = await _db.database;
    await db.update(
      'delivery_challans',
      {
        'status': ChallanStatus.returned.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND status = ?',
      whereArgs: [id, ChallanStatus.dispatched.dbValue],
    );
  }

  @override
  Future<Invoice> convertToInvoice(int challanId, String invoiceNo) async {
    final db = await _db.database;
    final challan = await getById(challanId);
    if (challan == null) throw Exception('Challan $challanId not found');
    if (challan.isConverted) {
      throw Exception('Challan ${challan.challanNo} is already converted');
    }

    final now = DateTime.now();
    final subtotal =
        challan.items.fold<double>(0, (s, i) => s + i.lineTotal);

    final invoice = Invoice(
      invoiceNo: invoiceNo,
      challanId: challanId,
      customerPartyId: challan.customerPartyId,
      customerName: challan.customerName,
      businessId: challan.businessId,
      status: InvoiceStatus.draft,
      issueDate: now,
      dueDate: now.add(const Duration(days: 30)),
      subtotal: subtotal,
      taxTotal: 0,
      total: subtotal,
      notes: 'Converted from Delivery Challan ${challan.challanNo}',
      vehicleNo: challan.vehicleNo,
      transporterName: challan.transporterName,
      transportMode: challan.transportMode,
      distanceKm: challan.distanceKm,
      customerGstin: challan.customerGstin,
      placeOfSupply: challan.placeOfSupply,
      ewbNo: challan.ewbNo,
      createdAt: now,
      updatedAt: now,
    );

    final invoiceId = await db.transaction((txn) async {
      final id = await txn.insert('invoices', invoice.toMap());
      for (final ci in challan.items) {
        await txn.insert('invoice_items', {
          'invoice_id': id,
          'item_name': ci.itemName,
          'description': ci.description,
          'qty': ci.qty,
          'unit_price': ci.unitPrice,
          'tax_pct': 0.0,
          'discount_pct': 0.0,
          'line_total': ci.lineTotal,
          'hsn_code': ci.hsnCode,
          'unit': ci.unit,
          'hsn_or_sac': ci.hsnOrSac,
        });
      }
      await txn.update(
        'delivery_challans',
        {
          'status': ChallanStatus.converted.dbValue,
          'converted_invoice_id': id,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [challanId],
      );
      return id;
    });

    return invoice.copyWith(id: invoiceId);
  }
}
