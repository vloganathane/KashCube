import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../models/transaction.dart';

/// Exports transactions to Tally XML format for import into Tally ERP / Tally Prime.
///
/// Format: TALLYMESSAGE envelope with individual VOUCHER entries.
/// Compatible with Tally ERP 9 and Tally Prime import via Gateway of Tally →
/// Import Data → Vouchers.
///
/// All processing is 100% local — no network calls.
class TallyXmlService {
  TallyXmlService._();
  static final TallyXmlService instance = TallyXmlService._();

  static const _exportDir = 'exports';
  static final _tallyDateFormat = DateFormat('yyyyMMdd');

  /// Generates a Tally XML file from [transactions] and returns the file path.
  ///
  /// [companyName] should match the company name in Tally (case-sensitive).
  Future<String> export(
    List<Transaction> transactions, {
    required String companyName,
    String? fileName,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(join(appDir.path, _exportDir));
      if (!await dir.exists()) await dir.create(recursive: true);

      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final name = fileName ?? 'kash_cube_tally_$timestamp.xml';
      final filePath = join(dir.path, name);

      final xml = _buildXml(transactions, companyName: companyName);
      await File(filePath).writeAsString(xml, encoding: const SystemEncoding());

      debugPrint('[Tally] Exported ${transactions.length} vouchers → $filePath');
      return filePath;
    } catch (e) {
      debugPrint('[Tally] Export failed: $e');
      rethrow;
    }
  }

  String _buildXml(
    List<Transaction> transactions, {
    required String companyName,
  }) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<ENVELOPE>');
    _writeHeader(buf);
    buf.writeln('  <BODY>');
    buf.writeln('    <IMPORTDATA>');
    buf.writeln('      <REQUESTDESC>');
    buf.writeln('        <REPORTNAME>Vouchers</REPORTNAME>');
    buf.writeln('        <STATICVARIABLES>');
    buf.writeln(
        '          <SVCURRENTCOMPANY>${_esc(companyName)}</SVCURRENTCOMPANY>');
    buf.writeln('        </STATICVARIABLES>');
    buf.writeln('      </REQUESTDESC>');
    buf.writeln('      <REQUESTDATA>');
    buf.writeln(
        '        <TALLYMESSAGE xmlns:UDF="TallyUDF">');

    for (final txn in transactions) {
      _writeVoucher(buf, txn);
    }

    buf.writeln('        </TALLYMESSAGE>');
    buf.writeln('      </REQUESTDATA>');
    buf.writeln('    </IMPORTDATA>');
    buf.writeln('  </BODY>');
    buf.writeln('</ENVELOPE>');
    return buf.toString();
  }

  void _writeHeader(StringBuffer buf) {
    buf.writeln('  <HEADER>');
    buf.writeln('    <VERSION>1</VERSION>');
    buf.writeln('    <TALLYREQUEST>Import Data</TALLYREQUEST>');
    buf.writeln('    <TYPE>Data</TYPE>');
    buf.writeln('    <ID>Vouchers</ID>');
    buf.writeln('  </HEADER>');
  }

  void _writeVoucher(StringBuffer buf, Transaction txn) {
    final vchType = _voucherType(txn);
    final date = _tallyDateFormat.format(txn.date);
    final party = _esc(txn.partyName ?? 'Cash');
    final narration = _esc(txn.notes ?? txn.category);
    final amount = txn.amount.abs();
    final amountStr = amount.toStringAsFixed(2);

    // In Tally: positive AMOUNT = credit entry, negative = debit entry.
    // For expenses/payments: party ledger is debited (+), cash/bank credited (-).
    // For income/receipts: cash/bank is debited (+), income ledger credited (-).
    final isIncome = txn.type.name == 'income' ||
        txn.type.name == 'received_back' ||
        txn.type.name == 'redeemed';

    final cashLedger = _cashLedger(txn);
    final partyLedger = _categoryToLedger(txn.category, isIncome: isIncome);

    buf.writeln('          <VOUCHER VCHTYPE="$vchType" ACTION="Create">');
    buf.writeln('            <DATE>$date</DATE>');
    buf.writeln('            <NARRATION>$narration</NARRATION>');
    buf.writeln('            <VOUCHERTYPENAME>$vchType</VOUCHERTYPENAME>');
    buf.writeln('            <PARTYLEDGERNAME>$party</PARTYLEDGERNAME>');
    buf.writeln('            <REFERENCE>${txn.upiRefNo ?? txn.id?.toString() ?? ""}</REFERENCE>');
    buf.writeln('            <ALLLEDGERENTRIES.LIST>');
    if (isIncome) {
      // Cash/Bank debited
      buf.writeln('              <LEDGERNAME>$cashLedger</LEDGERNAME>');
      buf.writeln('              <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>');
      buf.writeln('              <AMOUNT>-$amountStr</AMOUNT>');
    } else {
      // Expense/Payment: category ledger debited
      buf.writeln('              <LEDGERNAME>$partyLedger</LEDGERNAME>');
      buf.writeln('              <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>');
      buf.writeln('              <AMOUNT>-$amountStr</AMOUNT>');
    }
    buf.writeln('            </ALLLEDGERENTRIES.LIST>');
    buf.writeln('            <ALLLEDGERENTRIES.LIST>');
    if (isIncome) {
      // Income ledger credited
      buf.writeln('              <LEDGERNAME>$partyLedger</LEDGERNAME>');
      buf.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
      buf.writeln('              <AMOUNT>$amountStr</AMOUNT>');
    } else {
      // Cash/Bank credited
      buf.writeln('              <LEDGERNAME>$cashLedger</LEDGERNAME>');
      buf.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
      buf.writeln('              <AMOUNT>$amountStr</AMOUNT>');
    }
    buf.writeln('            </ALLLEDGERENTRIES.LIST>');
    buf.writeln('          </VOUCHER>');
  }

  String _voucherType(Transaction txn) {
    switch (txn.type.name) {
      case 'income':
      case 'received_back':
      case 'redeemed':
        return 'Receipt';
      case 'expense':
      case 'paid_back':
        return 'Payment';
      case 'lent':
        return 'Payment';
      case 'borrowed':
        return 'Receipt';
      default:
        return 'Journal';
    }
  }

  String _cashLedger(Transaction txn) {
    switch (txn.paymentMethod.name) {
      case 'upi':
        return txn.upiApp != null ? '${txn.upiApp} UPI' : 'UPI';
      case 'credit_card':
        return 'Credit Card';
      case 'debit_card':
        return 'Bank Account';
      case 'bank_transfer':
      case 'net_banking':
        return 'Bank Account';
      case 'wallet':
        return txn.upiApp ?? 'Wallet';
      case 'cash':
      default:
        return 'Cash';
    }
  }

  String _categoryToLedger(String category, {required bool isIncome}) {
    if (isIncome) {
      // Map to standard Tally income groups
      return switch (category.toLowerCase()) {
        'salary' || 'business income' => 'Sales Accounts',
        'freelance' => 'Sales Accounts',
        'investment' || 'redeemed' => 'Capital Account',
        'refund' => 'Sundry Debtors',
        _ => 'Indirect Income',
      };
    }
    // Expense categories → indirect expense ledgers
    return switch (category.toLowerCase()) {
      'food & dining' || 'groceries' => 'Provisions',
      'transportation' => 'Travelling Expenses',
      'bills & utilities' => 'Electricity Charges',
      'healthcare' => 'Medical Expenses',
      'entertainment' => 'Miscellaneous Expenses',
      'business expense' => 'Indirect Expenses',
      'education' => 'Miscellaneous Expenses',
      'shopping' => 'Purchases',
      _ => 'Miscellaneous Expenses',
    };
  }

  /// Escapes special XML characters.
  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
