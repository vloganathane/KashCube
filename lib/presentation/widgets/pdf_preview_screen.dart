import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../data/services/pdf_download_request.dart';
import '../../data/services/web/pdf_download_stub.dart'
    if (dart.library.html) '../../data/services/web/pdf_download_web.dart';

class PdfPreviewScreen extends StatelessWidget {
  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.fileName,
    required this.previewBuilder,
    this.downloadCopiesBuilder,
    this.shareSubject,
    this.shareBody,
  });

  final String title;
  final String fileName;
  final LayoutCallback previewBuilder;
  final Future<List<PdfDownloadRequest>> Function()? downloadCopiesBuilder;
  final String? shareSubject;
  final String? shareBody;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      PdfPreviewAction(
        icon: const Icon(Icons.download_outlined),
        onPressed: (context, build, pageFormat) async {
          if (downloadCopiesBuilder != null) {
            final files = await downloadCopiesBuilder!();
            await downloadPdfFiles(files);
          } else {
            final bytes = await build(pageFormat);
            await downloadPdfBytes(bytes, fileName);
          }
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: previewBuilder,
        pdfFileName: fileName,
        shareActionExtraSubject: shareSubject,
        shareActionExtraBody: shareBody,
        allowPrinting: !kIsWeb,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        useActions: true,
        actions: actions,
      ),
    );
  }
}
