// ---------------------------------------------------------------------------
// Gstr3bService — Phase G5
// ---------------------------------------------------------------------------
// Computes the GSTR-3B Consolidated Offset Summary from:
//   • Outward supply (invoices for the period)
//   • Inward supply / RCM (purchase_bills with reverse_charge=1)
//   • ITC eligible/blocked (purchase_bills for the period)
//
// 100% on-device — no network calls.
// ---------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/repositories/business_repository.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../../domain/repositories/purchase_bill_repository.dart';
import '../../presentation/providers/business_provider.dart';
import '../../presentation/providers/invoice_provider.dart';
import '../../presentation/providers/purchase_bill_provider.dart';
import '../models/invoice.dart';
import '../models/purchase_bill.dart';
import 'gst_calculator.dart';

// ── Data models ──────────────────────────────────────────────────────────────

class Gstr3bTaxAmounts {
  const Gstr3bTaxAmounts({
    this.taxableValue = 0,
    this.igst = 0,
    this.cgst = 0,
    this.sgst = 0,
    this.cess = 0,
  });

  final double taxableValue;
  final double igst;
  final double cgst;
  final double sgst;
  final double cess;

  double get totalTax => igst + cgst + sgst + cess;

  Gstr3bTaxAmounts operator +(Gstr3bTaxAmounts other) => Gstr3bTaxAmounts(
    taxableValue: taxableValue + other.taxableValue,
    igst: igst + other.igst,
    cgst: cgst + other.cgst,
    sgst: sgst + other.sgst,
    cess: cess + other.cess,
  );

  Gstr3bTaxAmounts withDecimals() => Gstr3bTaxAmounts(
    taxableValue: _r2(taxableValue),
    igst: _r2(igst),
    cgst: _r2(cgst),
    sgst: _r2(sgst),
    cess: _r2(cess),
  );

  static double _r2(double v) => (v * 100).roundToDouble() / 100;

  static const zero = Gstr3bTaxAmounts();
}

/// Offset computation result — how liability is discharged by ITC vs cash.
class Gstr3bOffset {
  const Gstr3bOffset({
    required this.igstLiability,
    required this.cgstLiability,
    required this.sgstLiability,
    required this.igstItc,
    required this.cgstItc,
    required this.sgstItc,
  });

  final double igstLiability;
  final double cgstLiability;
  final double sgstLiability;
  final double igstItc;
  final double cgstItc;
  final double sgstItc;

  /// IGST offset computation (IGST credit → IGST first, then CGST, then SGST).
  /// Returns: (igstByCredit, cgstByCredit, sgstByCredit, igstByCash, cgstByCash, sgstByCash)
  OffsetResult compute() {
    double igstRemaining = igstItc;
    double cgstRemaining = cgstItc;
    double sgstRemaining = sgstItc;

    // -- Offset IGST liability --
    final igstByIgst = igstRemaining.clamp(0.0, igstLiability);
    igstRemaining -= igstByIgst;
    final igstByCash = igstLiability - igstByIgst;

    // -- Offset CGST liability --
    final cgstByCgst = cgstRemaining.clamp(0.0, cgstLiability);
    cgstRemaining -= cgstByCgst;
    double cgstLiabilityLeft = cgstLiability - cgstByCgst;
    // Use remaining IGST credit for CGST
    final cgstByIgst = igstRemaining.clamp(0.0, cgstLiabilityLeft);
    igstRemaining -= cgstByIgst;
    cgstLiabilityLeft -= cgstByIgst;
    final cgstByCash = cgstLiabilityLeft;

    // -- Offset SGST liability --
    final sgstBySgst = sgstRemaining.clamp(0.0, sgstLiability);
    sgstRemaining -= sgstBySgst;
    double sgstLiabilityLeft = sgstLiability - sgstBySgst;
    // Use remaining IGST credit for SGST
    final sgstByIgst = igstRemaining.clamp(0.0, sgstLiabilityLeft);
    igstRemaining -= sgstByIgst;
    sgstLiabilityLeft -= sgstByIgst;
    final sgstByCash = sgstLiabilityLeft;

    return OffsetResult(
      igstByCredit: _r2(igstByIgst),
      igstByCash: _r2(igstByCash),
      cgstByCredit: _r2(cgstByCgst + cgstByIgst),
      cgstByCash: _r2(cgstByCash),
      sgstByCredit: _r2(sgstBySgst + sgstByIgst),
      sgstByCash: _r2(sgstByCash),
      igstCreditBalance: _r2(igstRemaining),
      cgstCreditBalance: _r2(cgstRemaining),
      sgstCreditBalance: _r2(sgstRemaining),
    );
  }

  static double _r2(double v) => (v * 100).roundToDouble() / 100;
}

class OffsetResult {
  const OffsetResult({
    required this.igstByCredit,
    required this.igstByCash,
    required this.cgstByCredit,
    required this.cgstByCash,
    required this.sgstByCredit,
    required this.sgstByCash,
    required this.igstCreditBalance,
    required this.cgstCreditBalance,
    required this.sgstCreditBalance,
  });

  final double igstByCredit;
  final double igstByCash;
  final double cgstByCredit;
  final double cgstByCash;
  final double sgstByCredit;
  final double sgstByCash;

  /// Carry-forward credit (not utilised this month).
  final double igstCreditBalance;
  final double cgstCreditBalance;
  final double sgstCreditBalance;

  double get totalCash => igstByCash + cgstByCash + sgstByCash;
  double get totalCredit => igstByCredit + cgstByCredit + sgstByCredit;
}

/// Full GSTR-3B workbook for a period.
class Gstr3bWorkbook {
  const Gstr3bWorkbook({
    required this.businessName,
    required this.businessGstin,
    required this.period,
    required this.from,
    required this.to,
    required this.outwardRegular,
    required this.outwardZeroRated,
    required this.outwardNilExempted,
    required this.rcmLiability,
    required this.itcEligible,
    required this.itcBlocked,
    required this.itcReversed,
    required this.interestLateFee,
  });

  final String businessName;
  final String businessGstin;

  /// Human-readable period label (e.g. "January 2026").
  final String period;
  final DateTime from;
  final DateTime to;

  // ── Table 3.1: Outward supply liability ──────────────────────────────────
  final Gstr3bTaxAmounts outwardRegular;
  final Gstr3bTaxAmounts outwardZeroRated; // manual / not tracked
  final Gstr3bTaxAmounts outwardNilExempted; // manual / not tracked

  // ── Table 3.1(d): RCM (inward supply) ────────────────────────────────────
  final Gstr3bTaxAmounts rcmLiability;

  // ── Table 4: ITC ─────────────────────────────────────────────────────────
  final Gstr3bTaxAmounts itcEligible;
  final Gstr3bTaxAmounts itcBlocked;
  final Gstr3bTaxAmounts itcReversed; // manual entry (rule 42/43)

  // ── Late fees / interest (manual) ────────────────────────────────────────
  final Gstr3bTaxAmounts interestLateFee;

  // ── Derived ──────────────────────────────────────────────────────────────

  Gstr3bTaxAmounts get totalLiability =>
      outwardRegular + outwardZeroRated + outwardNilExempted + rcmLiability;

  Gstr3bTaxAmounts get netItc {
    return Gstr3bTaxAmounts(
      igst: _r2(
        (itcEligible.igst - itcReversed.igst).clamp(0.0, double.infinity),
      ),
      cgst: _r2(
        (itcEligible.cgst - itcReversed.cgst).clamp(0.0, double.infinity),
      ),
      sgst: _r2(
        (itcEligible.sgst - itcReversed.sgst).clamp(0.0, double.infinity),
      ),
    );
  }

  Gstr3bOffset get offsetData => Gstr3bOffset(
    igstLiability: totalLiability.igst,
    cgstLiability: totalLiability.cgst,
    sgstLiability: totalLiability.sgst,
    igstItc: netItc.igst,
    cgstItc: netItc.cgst,
    sgstItc: netItc.sgst,
  );

  static double _r2(double v) => (v * 100).roundToDouble() / 100;
}

// ── Service ───────────────────────────────────────────────────────────────────

class Gstr3bService {
  const Gstr3bService({
    required BusinessRepository businessRepo,
    required InvoiceRepository invoiceRepo,
    required PurchaseBillRepository purchaseBillRepo,
  }) : _business = businessRepo,
       _invoice = invoiceRepo,
       _purchaseBill = purchaseBillRepo;

  final BusinessRepository _business;
  final InvoiceRepository _invoice;
  final PurchaseBillRepository _purchaseBill;

  /// Computes the GSTR-3B workbook for [businessId] and the date range
  /// [[from], [to]] (both inclusive, date part only).
  ///
  /// [itcReversed] is a manually provided reversal amount (rules 42/43).
  /// [interestLateFee] is manually provided interest/late-fee amounts.
  Future<Gstr3bWorkbook> compute({
    required int businessId,
    required DateTime from,
    required DateTime to,
    Gstr3bTaxAmounts itcReversed = Gstr3bTaxAmounts.zero,
    Gstr3bTaxAmounts interestLateFee = Gstr3bTaxAmounts.zero,
  }) async {
    final business = await _business.getById(businessId);
    if (business == null) throw ArgumentError('Business $businessId not found');

    final sellerState = business.state;

    // ── Fetch invoices for period (exclude drafts + cancelled) ────────────
    final allInvoices = await _invoice.getForPeriod(
      businessId: businessId,
      from: from,
      to: to,
    );
    final invoices = allInvoices
        .where(
          (inv) =>
              inv.status != InvoiceStatus.draft &&
              inv.status != InvoiceStatus.cancelled,
        )
        .toList();

    // ── Fetch purchase bills for period ───────────────────────────────────
    final bills = await _purchaseBill.fetchForPeriod(
      businessId: businessId,
      from: from,
      to: to,
    );

    // ── Compute outward supply from invoices ──────────────────────────────
    double outIgst = 0, outCgst = 0, outSgst = 0, outTaxable = 0;

    for (final inv in invoices) {
      // Skip credit/debit notes (included in regular totals implicitly via
      // negative values, but for now only sum tax invoices + bill of supply)
      if (inv.invoiceType == InvoiceType.creditNote ||
          inv.invoiceType == InvoiceType.debitNote) {
        continue;
      }

      // Sum tax amounts per item using GstCalculator
      for (final item in inv.items) {
        final taxable = _r2(
          item.qty * item.unitPrice * (1 - item.discountPct / 100),
        );
        final split = GstCalculator.calculate(
          sellerState: sellerState,
          buyerState: inv.placeOfSupply,
          taxableAmount: taxable,
          gstPct: item.taxPct,
        );
        outTaxable += taxable;
        outIgst += split.igst;
        outCgst += split.cgst;
        outSgst += split.sgst;
      }
    }

    // ── Compute RCM liability from purchase bills ─────────────────────────
    double rcmIgst = 0, rcmCgst = 0, rcmSgst = 0, rcmTaxable = 0;
    for (final bill in bills.where((b) => b.reverseCharge)) {
      rcmTaxable += bill.subtotal;
      rcmIgst += bill.igstAmount;
      rcmCgst += bill.cgstAmount;
      rcmSgst += bill.sgstAmount;
    }

    // ── Compute ITC from purchase bills ──────────────────────────────────
    double itcEligIgst = 0, itcEligCgst = 0, itcEligSgst = 0;
    double itcBlockedIgst = 0, itcBlockedCgst = 0, itcBlockedSgst = 0;

    for (final bill in bills) {
      if (bill.itcEligibility == ItcEligibility.eligible) {
        itcEligIgst += bill.igstAmount;
        itcEligCgst += bill.cgstAmount;
        itcEligSgst += bill.sgstAmount;
      } else if (bill.itcEligibility == ItcEligibility.blocked) {
        itcBlockedIgst += bill.igstAmount;
        itcBlockedCgst += bill.cgstAmount;
        itcBlockedSgst += bill.sgstAmount;
      }
    }

    final period = DateFormat('MMMM yyyy').format(from);

    return Gstr3bWorkbook(
      businessName: business.name,
      businessGstin: business.gstNo ?? '— Not set —',
      period: period,
      from: from,
      to: to,
      outwardRegular: Gstr3bTaxAmounts(
        taxableValue: _r2(outTaxable),
        igst: _r2(outIgst),
        cgst: _r2(outCgst),
        sgst: _r2(outSgst),
      ),
      outwardZeroRated: Gstr3bTaxAmounts.zero,
      outwardNilExempted: Gstr3bTaxAmounts.zero,
      rcmLiability: Gstr3bTaxAmounts(
        taxableValue: _r2(rcmTaxable),
        igst: _r2(rcmIgst),
        cgst: _r2(rcmCgst),
        sgst: _r2(rcmSgst),
      ),
      itcEligible: Gstr3bTaxAmounts(
        igst: _r2(itcEligIgst),
        cgst: _r2(itcEligCgst),
        sgst: _r2(itcEligSgst),
      ),
      itcBlocked: Gstr3bTaxAmounts(
        igst: _r2(itcBlockedIgst),
        cgst: _r2(itcBlockedCgst),
        sgst: _r2(itcBlockedSgst),
      ),
      itcReversed: itcReversed,
      interestLateFee: interestLateFee,
    );
  }

  static double _r2(double v) => (v * 100).roundToDouble() / 100;
}

// ─── Riverpod Provider ───────────────────────────────────────────────────────

final gstr3bServiceProvider = Provider<Gstr3bService>(
  (ref) => Gstr3bService(
    businessRepo: ref.read(businessRepositoryProvider),
    invoiceRepo: ref.read(invoiceRepositoryProvider),
    purchaseBillRepo: ref.read(purchaseBillRepositoryProvider),
  ),
);

// PDF generation: see gstr3b_pdf_service.dart
