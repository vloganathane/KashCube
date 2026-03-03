// GST tax split calculator — 100% offline, zero network calls.
//
// Rules:
//   • Intra-state (seller state == buyer state) → CGST + SGST (each = gst% / 2)
//   • Inter-state (different states, or either state unknown) → IGST (= full gst%)
//
// Usage:
//   final split = GstCalculator.calculate(
//     sellerState: business.state,
//     buyerState:  party.state,
//     taxableAmount: lineSubtotal,
//     gstPct: item.taxPct,
//   );

/// Result of a GST split calculation.
class GstSplit {
  const GstSplit({
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.total,
    required this.isInterState,
    required this.gstPct,
    required this.taxableAmount,
  });

  /// CGST component (0 for inter-state transactions).
  final double cgst;

  /// SGST component (0 for inter-state transactions).
  final double sgst;

  /// IGST component (0 for intra-state transactions).
  final double igst;

  /// Total GST = cgst + sgst + igst.
  final double total;

  /// True when IGST applies (different states or unknown state).
  final bool isInterState;

  /// The GST rate percentage used (e.g. 18.0 for 18%).
  final double gstPct;

  /// The taxable (pre-tax) amount this split was computed on.
  final double taxableAmount;

  /// Convenience label: e.g. "CGST 9% + SGST 9%" or "IGST 18%"
  String rateLabel({int decimals = 1}) {
    if (isInterState) {
      return 'IGST ${_fmt(gstPct, decimals)}%';
    }
    final half = gstPct / 2;
    return 'CGST ${_fmt(half, decimals)}% + SGST ${_fmt(half, decimals)}%';
  }

  String _fmt(double v, int d) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(d);

  @override
  String toString() =>
      'GstSplit(taxable=$taxableAmount, cgst=$cgst, sgst=$sgst, igst=$igst, '
      'total=$total, interState=$isInterState)';
}

/// Aggregated GST row for the summary table — grouped by HSN/SAC + rate.
class GstSummaryRow {
  const GstSummaryRow({
    required this.hsnOrSac,
    required this.code,
    required this.taxableAmount,
    required this.gstPct,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.total,
    required this.isInterState,
  });

  /// 'HSN' or 'SAC'.
  final String hsnOrSac;

  /// The HSN or SAC code (empty string if not set).
  final String code;

  final double taxableAmount;
  final double gstPct;
  final double cgst;
  final double sgst;
  final double igst;
  final double total;
  final bool isInterState;

  /// Display label for the code column, e.g. "998314 (SAC)" or "8541 (HSN)".
  /// Shows "— (HSN)" / "— (SAC)" when no code is stored so it is visually
  /// distinct from the column header and clearly indicates a missing code.
  String get codeLabel =>
      code.isNotEmpty ? '$code ($hsnOrSac)' : '— ($hsnOrSac)';
}

/// Stateless GST calculation utilities.
class GstCalculator {
  GstCalculator._();

  // ─── GSTN-registered state names (lower-cased for comparison) ──────────────
  // Includes common abbreviations and alternate spellings.
  static const Map<String, String> _stateNormalMap = {
    'andaman & nicobar': 'andaman & nicobar',
    'andaman and nicobar': 'andaman & nicobar',
    'andhra pradesh': 'andhra pradesh',
    'arunachal pradesh': 'arunachal pradesh',
    'assam': 'assam',
    'bihar': 'bihar',
    'chandigarh': 'chandigarh',
    'chhattisgarh': 'chhattisgarh',
    'dadra & nagar haveli': 'dadra & nh',
    'dadra and nagar haveli': 'dadra & nh',
    'dadra & nh': 'dadra & nh',
    'daman & diu': 'daman & diu',
    'daman and diu': 'daman & diu',
    'delhi': 'delhi',
    'goa': 'goa',
    'gujarat': 'gujarat',
    'haryana': 'haryana',
    'himachal pradesh': 'himachal pradesh',
    'jammu & kashmir': 'jammu & kashmir',
    'jammu and kashmir': 'jammu & kashmir',
    'jharkhand': 'jharkhand',
    'karnataka': 'karnataka',
    'kerala': 'kerala',
    'ladakh': 'ladakh',
    'lakshadweep': 'lakshadweep',
    'madhya pradesh': 'madhya pradesh',
    'maharashtra': 'maharashtra',
    'manipur': 'manipur',
    'meghalaya': 'meghalaya',
    'mizoram': 'mizoram',
    'nagaland': 'nagaland',
    'odisha': 'odisha',
    'orissa': 'odisha',
    'puducherry': 'puducherry',
    'puducherey': 'puducherry', // common typo
    'pondicherry': 'puducherry',
    'pondicheery': 'puducherry', // common typo
    'pondicherey': 'puducherry', // common typo
    'punjab': 'punjab',
    'rajasthan': 'rajasthan',
    'sikkim': 'sikkim',
    'tamil nadu': 'tamil nadu',
    'telangana': 'telangana',
    'tripura': 'tripura',
    'uttar pradesh': 'uttar pradesh',
    'up': 'uttar pradesh',
    'uttarakhand': 'uttarakhand',
    'west bengal': 'west bengal',
  };

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Calculate CGST/SGST vs IGST split for a single line item.
  ///
  /// [sellerState] and [buyerState] are state name strings as stored in the
  /// `businesses.state` and `parties.state` columns respectively. Comparison
  /// is case-insensitive and handles common abbreviations.
  ///
  /// [taxableAmount] is the pre-tax line total (after discount).
  /// [gstPct] is the GST rate percentage (e.g. 18.0).
  static GstSplit calculate({
    required String? sellerState,
    required String? buyerState,
    required double taxableAmount,
    required double gstPct,
  }) {
    if (gstPct <= 0 || taxableAmount <= 0) {
      return GstSplit(
        cgst: 0, sgst: 0, igst: 0, total: 0,
        isInterState: false,
        gstPct: gstPct, taxableAmount: taxableAmount,
      );
    }

    final inter = isInterState(sellerState, buyerState);
    final taxAmt = _round2(taxableAmount * gstPct / 100);

    if (inter) {
      return GstSplit(
        cgst: 0, sgst: 0, igst: taxAmt, total: taxAmt,
        isInterState: true,
        gstPct: gstPct, taxableAmount: taxableAmount,
      );
    } else {
      final half = _round2(taxAmt / 2);
      final other = _round2(taxAmt - half); // avoids rounding drift
      return GstSplit(
        cgst: half, sgst: other, igst: 0, total: taxAmt,
        isInterState: false,
        gstPct: gstPct, taxableAmount: taxableAmount,
      );
    }
  }

  /// Aggregate per-item splits into HSN/SAC + rate rows for the GST summary
  /// table required on a compliant Tax Invoice.
  ///
  /// Lines with zero GST are excluded.
  ///
  /// [items] — pass [GstSplitInput] list; use [InvoiceItemsSplit.toSplitInputs]
  /// on concrete model lists.
  static List<GstSummaryRow> summarise({
    required String? sellerState,
    required String? buyerState,
    required List<GstSplitInput> items,
  }) {
    // Group by (hsnOrSac, code, gstPct)
    final Map<String, _RowAccum> map = {};

    for (final item in items) {
      if (item.gstPct <= 0) continue;
      final taxable =
          _round2(item.qty * item.unitPrice * (1 - item.discountPct / 100));
      final split = calculate(
        sellerState: sellerState,
        buyerState: buyerState,
        taxableAmount: taxable,
        gstPct: item.gstPct,
      );
      final key = '${item.hsnOrSac}|${item.code}|${item.gstPct}';
      final acc = map.putIfAbsent(
        key,
        () => _RowAccum(
          hsnOrSac: item.hsnOrSac,
          code: item.code,
          gstPct: item.gstPct,
          isInterState: split.isInterState,
        ),
      );
      acc.taxableAmount += taxable;
      acc.cgst += split.cgst;
      acc.sgst += split.sgst;
      acc.igst += split.igst;
      acc.total += split.total;
    }

    return map.values
        .map((a) => GstSummaryRow(
              hsnOrSac: a.hsnOrSac,
              code: a.code,
              taxableAmount: _round2(a.taxableAmount),
              gstPct: a.gstPct,
              cgst: _round2(a.cgst),
              sgst: _round2(a.sgst),
              igst: _round2(a.igst),
              total: _round2(a.total),
              isInterState: a.isInterState,
            ))
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));
  }

  /// Whether the transaction is inter-state based on state name strings.
  static bool isInterState(String? sellerState, String? buyerState) {
    if (sellerState == null || sellerState.isEmpty) return true;
    if (buyerState == null || buyerState.isEmpty) return true;
    final s = _normalise(sellerState);
    final b = _normalise(buyerState);
    return s != b;
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  static String _normalise(String state) =>
      _stateNormalMap[state.trim().toLowerCase()] ??
      state.trim().toLowerCase();

  static double _round2(double v) => (v * 100).roundToDouble() / 100;
}

// ─── Internal ──────────────────────────────────────────────────────────────

/// Minimal input DTO for GstCalculator.summarise().
class GstSplitInput {
  const GstSplitInput({
    required this.qty,
    required this.unitPrice,
    required this.discountPct,
    required this.gstPct,
    required this.code,
    required this.hsnOrSac,
  });

  final double qty;
  final double unitPrice;
  final double discountPct;
  final double gstPct;
  final String code;
  final String hsnOrSac;
}

/// Accumulator used while building summary rows.
class _RowAccum {
  _RowAccum({
    required this.hsnOrSac,
    required this.code,
    required this.gstPct,
    required this.isInterState,
  });

  final String hsnOrSac;
  final String code;
  final double gstPct;
  final bool isInterState;

  double taxableAmount = 0;
  double cgst = 0;
  double sgst = 0;
  double igst = 0;
  double total = 0;
}

/// Extension to convert InvoiceItem / QuoteItem list → GstSplitInput list.
extension InvoiceItemsSplit on List<dynamic> {
  List<GstSplitInput> toSplitInputs() => map((item) {
        return GstSplitInput(
          qty: (item.qty as num).toDouble(),
          unitPrice: (item.unitPrice as num).toDouble(),
          discountPct: (item.discountPct as num).toDouble(),
          gstPct: (item.taxPct as num).toDouble(),
          code: (item.hsnCode as String?) ?? '',
          hsnOrSac: (item.hsnOrSac as String?) ?? 'HSN',
        );
      }).toList();
}
