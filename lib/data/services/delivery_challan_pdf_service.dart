import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/business.dart';
import '../models/delivery_challan.dart';
import '../models/party.dart';
import 'pdf_document_data.dart';
import 'pdf_layout_engine.dart';

/// Thin adapter that serialises [DeliveryChallan] domain objects into
/// [PdfDocumentData] and delegates all rendering to [PdfLayoutEngine].
///
/// Public API is unchanged — callers do not need to be updated.
/// Generates a Delivery Challan PDF as per GST Rule 55.
/// 100% local — no network calls.
class DeliveryChallanPdfService {
  DeliveryChallanPdfService._();
  static final instance = DeliveryChallanPdfService._();

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<File> generateChallanPdf(
    DeliveryChallan challan, {
    Business? business,
    Party? customerParty,
    String? termsAndConditions,
  }) async {
    final logo = business != null ? await _loadLogo(business) : null;
    final data = _challanToData(challan,
        business: business,
        customerParty: customerParty,
        logo: logo,
        termsAndConditions: termsAndConditions);
    return PdfLayoutEngine.instance.generate(
      data,
      DocumentTemplate.active,
      'DC_${challan.challanNo.replaceAll('/', '-')}.pdf',
    );
  }

  // ── Serialiser ─────────────────────────────────────────────────────────────

  PdfDocumentData _challanToData(
    DeliveryChallan challan, {
    Business? business,
    Party? customerParty,
    pw.MemoryImage? logo,
    String? termsAndConditions,
  }) {
    final hasTransport = (challan.vehicleNo != null && challan.vehicleNo!.isNotEmpty) ||
        (challan.transporterName != null && challan.transporterName!.isNotEmpty) ||
        challan.distanceKm != null;

    return PdfDocumentData(
      type: PdfDocumentType.deliveryChallan,
      docNumber: challan.challanNo,
      typeLabel: 'DELIVERY CHALLAN',
      statusLabel: challan.status.label,
      statusColor: _statusColor(challan.status),
      issueDate: challan.challanDate,
      seller: _sellerInfo(business, logo),
      buyer: PdfPartyInfo(
        name: challan.customerName,
        gstin: challan.customerGstin,
        address: customerParty?.formattedAddress,
        phone: customerParty?.phoneNumber,
        email: customerParty?.email,
        state: customerParty?.state,
      ),
      shipTo: _buildShipTo(challan),
      placeOfSupply: challan.placeOfSupply,
      notes: challan.notes,
      lineItems: challan.items
          .map((item) => PdfLineItem(
                name: item.itemName,
                description: item.description,
                hsnCode: item.hsnCode,
                qty: item.qty,
                unit: item.unit,
                unitPrice: item.unitPrice,
                lineTotal: item.lineTotal,
              ))
          .toList(),
      totals: PdfTotals(
        subtotal: challan.subtotal,
        grandTotal: challan.subtotal,
      ),
      transport: hasTransport
          ? PdfTransportInfo(
              transporterName: challan.transporterName,
              vehicleNo: challan.vehicleNo,
              transportMode: challan.transportMode,
              distanceKm: challan.distanceKm,
              dispatchDate: challan.dispatchDate,
            )
          : null,
      purpose: challan.purpose.label,
      ewbNo: challan.ewbNo,
      footerNote: termsAndConditions ?? '',
    );
  }

  // ── Delivery address helper ──────────────────────────────────────────────

  PdfPartyInfo? _buildShipTo(DeliveryChallan challan) {
    final parts = [
      if (challan.deliveryAddress != null && challan.deliveryAddress!.isNotEmpty)
        challan.deliveryAddress!,
      if (challan.deliveryCity != null && challan.deliveryCity!.isNotEmpty)
        challan.deliveryCity!,
      if (challan.deliveryState != null && challan.deliveryState!.isNotEmpty)
        challan.deliveryState!,
      if (challan.deliveryPincode != null && challan.deliveryPincode!.isNotEmpty)
        challan.deliveryPincode!,
    ];
    if (parts.isEmpty) return null;
    return PdfPartyInfo(
      name: challan.customerName,
      address: parts.join(', '),
      state: challan.deliveryState,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  PdfPartyInfo _sellerInfo(Business? business, pw.MemoryImage? logo) {
    if (business == null) return const PdfPartyInfo(name: 'Your Business');
    final addressParts = [business.address, business.city, business.state]
        .where((e) => e != null && e.isNotEmpty)
        .cast<String>()
        .toList();
    return PdfPartyInfo(
      name: business.name,
      gstin: business.gstNo,
      address: addressParts.isEmpty ? null : addressParts.join(', '),
      phone: business.phone,
      email: business.email,
      state: business.state,
      logoImage: logo,
    );
  }

  PdfColor _statusColor(ChallanStatus status) {
    switch (status) {
      case ChallanStatus.dispatched:
        return PdfColors.blue700;
      case ChallanStatus.returned:
        return PdfColors.orange700;
      case ChallanStatus.converted:
        return PdfColors.green700;
      case ChallanStatus.draft:
        return PdfColors.grey600;
    }
  }

  Future<pw.MemoryImage?> _loadLogo(Business business) async {
    if (business.logoPath == null || business.logoPath!.isEmpty) return null;
    try {
      final file = File(business.logoPath!);
      if (await file.exists()) {
        return pw.MemoryImage(await file.readAsBytes());
      }
    } catch (_) {}
    return null;
  }
}
