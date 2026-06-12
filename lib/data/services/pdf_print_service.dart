import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Local PDF print/share helper for generated documents.
///
/// Routes PDF bytes to the platform print dialog or native share sheet using
/// the `printing` package. No network calls are involved.
class PdfPrintService {
  PdfPrintService._();

  static final instance = PdfPrintService._();

  Future<PdfPrintOutcome> printPdfBytes(
    Uint8List bytes, {
    String? jobName,
  }) async {
    final info = await Printing.info();
    if (!info.canPrint) {
      return PdfPrintOutcome.unavailable;
    }

    final printed = await Printing.layoutPdf(
      name: jobName ?? 'Document',
      onLayout: (_) async => bytes,
    );

    return printed ? PdfPrintOutcome.printed : PdfPrintOutcome.canceled;
  }

  Future<bool> sharePdfBytes(
    Uint8List bytes, {
    String filename = 'document.pdf',
    String? subject,
    String? body,
  }) {
    return Printing.sharePdf(
      bytes: bytes,
      filename: filename,
      subject: subject,
      body: body,
    );
  }
}

enum PdfPrintOutcome { printed, canceled, unavailable }
