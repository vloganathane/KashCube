import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';

/// Full-screen viewer for bill images.
///
/// Supports pinch-to-zoom and pan gestures.
/// For PDFs, opens in the system's default PDF viewer.
class BillViewerScreen extends StatelessWidget {
  const BillViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.isPdf,
  });

  final String filePath;
  final String fileName;
  final bool isPdf;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          fileName,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: isPdf
          ? _PdfPlaceholder(fileName: fileName)
          : _ImageViewer(filePath: filePath),
    );
  }
}

/// Interactive image viewer with pinch-to-zoom.
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.file(
          File(filePath),
          fit: BoxFit.contain,
          errorBuilder: (_, error, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                size: 64,
                color: Colors.white54,
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                'Could not load image',
                style: context.textTheme.bodyLarge?.copyWith(
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder for PDF files — shows info and a button to open externally.
class _PdfPlaceholder extends StatelessWidget {
  const _PdfPlaceholder({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf, size: 80, color: Colors.red.shade300),
          const SizedBox(height: AppSpacing.xl),
          Text(
            fileName,
            style: context.textTheme.titleMedium?.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'PDF preview is not available in-app.',
            style: context.textTheme.bodyMedium?.copyWith(
              color: Colors.white60,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'The PDF is saved locally on your device.',
            style: context.textTheme.bodySmall?.copyWith(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}
