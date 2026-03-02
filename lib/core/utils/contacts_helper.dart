import 'package:flutter/material.dart';

import '../../domain/repositories/settings_repository.dart';

const _kContactsPickerExplained = 'contacts_picker_explained';

/// Shows a one-time privacy-rationale dialog before opening the OS contact
/// picker. Returns `true` if the user confirmed (or the dialog was already
/// accepted previously). After the first confirmation the dialog is never
/// shown again.
///
/// No READ_CONTACTS permission is required — [FlutterContacts.openExternalPick]
/// uses the system picker intent (ACTION_PICK) which grants a one-time URI
/// to only the selected contact.
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
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.contacts_outlined, size: 40),
      title: const Text('Import from Contacts'),
      content: const Text(
        'Kash Cube will open your contacts app.\n\n'
        'Only the contact you select will be imported — '
        'your full contact list stays private on your device.',
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
