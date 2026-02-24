import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';

/// Result from the bill picker bottom sheet.
class BillPickerResult {
  final String filePath;
  final String fileName;

  const BillPickerResult({
    required this.filePath,
    required this.fileName,
  });
}

/// Shows a bottom sheet with options to attach a bill: Camera, Gallery, or PDF.
///
/// Returns a [BillPickerResult] if the user selected a file, null otherwise.
Future<BillPickerResult?> showBillPicker(BuildContext context) async {
  return showModalBottomSheet<BillPickerResult>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg),
      ),
    ),
    builder: (context) => const _BillPickerSheet(),
  );
}

class _BillPickerSheet extends StatelessWidget {
  const _BillPickerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.base),
              decoration: BoxDecoration(
                color: context.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Attach Bill / Receipt',
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _PickerOption(
              icon: Icons.camera_alt_outlined,
              label: 'Take Photo',
              subtitle: 'Capture bill with camera',
              onTap: () => _pickFromCamera(context),
            ),
            _PickerOption(
              icon: Icons.photo_library_outlined,
              label: 'Choose from Gallery',
              subtitle: 'Pick an existing photo',
              onTap: () => _pickFromGallery(context),
            ),
            _PickerOption(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Pick PDF File',
              subtitle: 'Select a PDF document',
              onTap: () => _pickPdf(context),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromCamera(BuildContext context) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (image != null && context.mounted) {
      Navigator.of(context).pop(
        BillPickerResult(
          filePath: image.path,
          fileName: image.name,
        ),
      );
    }
  }

  Future<void> _pickFromGallery(BuildContext context) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (image != null && context.mounted) {
      Navigator.of(context).pop(
        BillPickerResult(
          filePath: image.path,
          fileName: image.name,
        ),
      );
    }
  }

  Future<void> _pickPdf(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );
    if (result != null &&
        result.files.isNotEmpty &&
        result.files.first.path != null &&
        context.mounted) {
      final file = result.files.first;
      Navigator.of(context).pop(
        BillPickerResult(
          filePath: file.path!,
          fileName: file.name,
        ),
      );
    }
  }
}

class _PickerOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _PickerOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.primaryContainer,
        child: Icon(
          icon,
          color: context.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(label),
      subtitle: Text(
        subtitle,
        style: context.textTheme.bodySmall,
      ),
      onTap: onTap,
    );
  }
}

/// Widget that displays a bill attachment preview (thumbnail or PDF icon).
///
/// Shows a small preview card with the bill image or a PDF icon.
/// Tap to view full-screen, long-press to remove.
class BillPreviewCard extends StatelessWidget {
  const BillPreviewCard({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.isPdf,
    this.fileSize,
    this.onTap,
    this.onRemove,
  });

  final String filePath;
  final String fileName;
  final bool isPdf;
  final int? fileSize;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 120,
          child: Row(
            children: [
              // Thumbnail / Icon
              SizedBox(
                width: 100,
                height: 120,
                child: isPdf
                    ? Container(
                        color: context.colorScheme.errorContainer,
                        child: Center(
                          child: Icon(
                            Icons.picture_as_pdf,
                            size: 40,
                            color: context.colorScheme.error,
                          ),
                        ),
                      )
                    : Image.file(
                        File(filePath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: context.colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined, size: 40),
                          ),
                        ),
                      ),
              ),
              // File info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isPdf
                                ? Icons.picture_as_pdf_outlined
                                : Icons.image_outlined,
                            size: AppSpacing.iconSm,
                            color: context.colorScheme.primary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              isPdf ? 'PDF Bill' : 'Photo Bill',
                              style: context.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (fileSize != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _formatFileSize(fileSize!),
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.outline,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Remove button
              if (onRemove != null)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: IconButton(
                    icon: Icon(
                      Icons.close,
                      color: context.colorScheme.error,
                    ),
                    onPressed: onRemove,
                    tooltip: 'Remove bill',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
