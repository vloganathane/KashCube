import 'dart:io';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/services/app_logger.dart';

import '../models/booking.dart';
import '../models/booking_item.dart';
import '../models/business.dart';
import '../models/party.dart';
import 'document_template_service.dart';
import 'pdf_document_data.dart';
import 'pdf_layout_engine.dart';

/// Thin adapter that serialises [Booking] domain objects into [PdfDocumentData]
/// and delegates all rendering to [PdfLayoutEngine].
///
/// Produces a "Booking Confirmation" PDF — one line item per service,
/// advance and balance shown in totals, T&C in footer.
/// 100% local — no network calls.
class BookingConfirmationPdfService {
  BookingConfirmationPdfService._();
  static final instance = BookingConfirmationPdfService._();

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<File> generateBookingPdf(
    Booking booking, {
    Business? business,
    Party? customerParty,
    String? termsAndConditions,
    List<BookingItem>? items,
    bool showFreeWatermark = false,
  }) async {
    final logo = business != null ? await _loadLogo(business) : null;
    final data = _bookingToData(
      booking,
      business: business,
      customerParty: customerParty,
      logo: logo,
      termsAndConditions: termsAndConditions,
      items: items,
      showFreeWatermark: showFreeWatermark,
    );
    final ref = (booking.bookingRef ?? 'BK-${booking.id}')
        .replaceAll('/', '-')
        .replaceAll(' ', '_');
    final template = await DocumentTemplateService.instance.getActiveTemplate();
    return PdfLayoutEngine.instance.generate(
      data,
      template,
      'Booking_$ref.pdf',
    );
  }

  // ── Serialiser ─────────────────────────────────────────────────────────────

  PdfDocumentData _bookingToData(
    Booking booking, {
    Business? business,
    Party? customerParty,
    pw.MemoryImage? logo,
    String? termsAndConditions,
    List<BookingItem>? items,
    bool showFreeWatermark = false,
  }) {
    final fmt = DateFormat('d MMM yyyy');
    final timeFmt = DateFormat('h:mm a');

    // Build notes: date-range / duration / time info
    final notesParts = <String>[];
    if (booking.endDatetime != null) {
      final nights = booking.endDatetime!
          .difference(booking.startDatetime)
          .inDays;
      notesParts.add(
        'Period: ${fmt.format(booking.startDatetime)} – ${fmt.format(booking.endDatetime!)}',
      );
      if (nights > 0) {
        notesParts.add('Duration: $nights night${nights == 1 ? '' : 's'}');
      }
    } else {
      notesParts.add(
        'Date: ${fmt.format(booking.startDatetime)} at ${timeFmt.format(booking.startDatetime)}',
      );
      if (booking.durationMinutes != null && booking.durationMinutes! > 0) {
        final mins = booking.durationMinutes!;
        final durationStr = mins < 60
            ? '$mins min'
            : mins % 60 == 0
            ? '${mins ~/ 60} hr'
            : '${mins ~/ 60} hr ${mins % 60} min';
        notesParts.add('Duration: $durationStr');
      }
    }
    if (booking.notes != null && booking.notes!.isNotEmpty) {
      notesParts.add(booking.notes!);
    }

    // Line items — multi-service if items provided, else single fallback
    final List<PdfLineItem> lineItems;
    if (items != null && items.isNotEmpty) {
      lineItems = items
          .map(
            (bi) => PdfLineItem(
              name: bi.itemName,
              description: bi.description,
              hsnCode: bi.sacCode,
              qty: bi.qty,
              unit: bi.unit,
              unitPrice: bi.unitPrice,
              taxPct: bi.taxPct,
              discountPct: bi.discountPct,
              lineTotal: bi.lineTotal,
            ),
          )
          .toList();
    } else {
      lineItems = [
        PdfLineItem(
          name: booking.serviceName,
          description: notesParts.isNotEmpty ? notesParts.first : null,
          qty: 1,
          unitPrice: booking.totalAmount,
          lineTotal: booking.totalAmount,
        ),
      ];
    }

    return PdfDocumentData(
      type: PdfDocumentType.booking,
      docNumber: booking.bookingRef ?? 'BK-${booking.id}',
      typeLabel: 'BOOKING CONFIRMATION',
      statusLabel: booking.status.label.toUpperCase(),
      statusColor: _statusColor(booking.status),
      issueDate: booking.startDatetime,
      seller: _sellerInfo(business, logo),
      buyer: PdfPartyInfo(
        name: booking.customerName,
        address: customerParty?.formattedAddress,
        phone: customerParty?.phoneNumber,
        email: customerParty?.email,
        state: customerParty?.state,
      ),
      notes: notesParts.length > 1 ? notesParts.sublist(1).join('\n') : null,
      lineItems: lineItems,
      totals: PdfTotals(
        subtotal: booking.totalAmount,
        grandTotal: booking.totalAmount,
        paidAmount: booking.paidAmount,
      ),
      termsAndConditions: termsAndConditions,
      footerNote: 'Thank you for your booking! We look forward to serving you.',
      showFreeWatermark: showFreeWatermark,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  PdfPartyInfo _sellerInfo(Business? business, pw.MemoryImage? logo) {
    if (business == null) return const PdfPartyInfo(name: 'Your Business');
    final addressParts = [
      business.address,
      business.city,
      business.state,
    ].where((e) => e != null && e.isNotEmpty).cast<String>().toList();
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

  PdfColor _statusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return PdfColors.orange700;
      case BookingStatus.confirmed:
        return PdfColors.green700;
      case BookingStatus.completed:
        return PdfColors.grey600;
      case BookingStatus.cancelled:
        return PdfColors.grey600;
      case BookingStatus.noShow:
        return PdfColors.red700;
    }
  }

  Future<pw.MemoryImage?> _loadLogo(Business business) async {
    if (business.logoPath == null || business.logoPath!.isEmpty) return null;
    try {
      final file = File(business.logoPath!);
      if (await file.exists()) {
        return pw.MemoryImage(await file.readAsBytes());
      }
    } catch (e) {
      AppLogger.instance.debug(
        'Failed to load business logo in booking confirmation PDF',
        category: 'booking_confirmation_pdf',
        error: e,
      );
    }
    return null;
  }
}
