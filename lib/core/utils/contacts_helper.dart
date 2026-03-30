import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../data/services/app_logger.dart';

import '../../domain/repositories/settings_repository.dart';

const _kContactsPickerExplained = 'contacts_picker_explained';

/// Shows a one-time privacy-rationale dialog before opening the OS contact
/// picker. Returns `true` if the user confirmed (or the dialog was already
/// accepted previously). After the first confirmation the dialog is never
/// shown again.
///
/// This dialog explains why contact access is needed before requesting the
/// runtime contacts permission.
Future<bool> requestContactsPickerRationale(
  BuildContext context, {
  required SettingsRepository settingsRepository,
}) async {
  // Already accepted — skip the dialog.
  final explained = await settingsRepository.get(_kContactsPickerExplained);
  if (explained == 'true') return true;
  if (!context.mounted) return false;

  final proceed = await showDialog<bool>(
    context: context,
    useRootNavigator: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.contacts_outlined, size: 40),
      title: const Text('Import from Contacts'),
      content: const Text(
        'Kash Cube needs contacts access so you can pick a contact to import '
        'or save a party into your address book.\n\n'
        'Contact data is used only on-device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );

  if (proceed == true) {
    await settingsRepository.set(_kContactsPickerExplained, 'true');
    return true;
  }
  return false;
}

/// Requests Android/iOS contacts runtime permission.
///
/// Returns `true` when permission is already granted or newly granted.
Future<bool> requestContactsRuntimePermission() async {
  try {
    final granted = await FlutterContacts.requestPermission(readonly: false);
    return granted;
  } catch (e, st) {
    AppLogger.instance.warning(
      'Contacts runtime permission request failed',
      category: 'contacts_helper',
      error: e,
      stackTrace: st,
    );
    return false;
  }
}
