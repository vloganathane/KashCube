import 'package:flutter/material.dart';
import 'package:world_countries/world_countries.dart';

import '../../core/constants/app_spacing.dart';

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

/// Default country widget — India.
const WorldCountry kIndiaCountry = WorldCountry.ind();

/// Extracts the dialling-code digits (no '+') from a [WorldCountry].
///
/// Uses the package's official `Idd.phoneCode()` extension which handles:
/// - India `Idd(root: 9, suffixes: [1])` → `"91"`
/// - UAE   `Idd(root: 9, suffixes: [71])` → `"971"`
/// - UK    `Idd(root: 4, suffixes: [4])` → `"44"`
/// - USA   `Idd(root: 1, suffixes: [201…])` → `"1"` (multi-suffix → omitted)
///
/// Falls back to `"91"` (India) when IDD data is absent.
String dialCodeFor(WorldCountry country) {
  final idd = country.idd;
  if (idd == null) return '91';
  return idd.phoneCode(leading: ''); // e.g. "91", "971", "44"
}

/// Finds a [WorldCountry] by its common English name (e.g. 'India').
/// Returns `null` when no match is found.
WorldCountry? countryByName(String? name) {
  if (name == null || name.isEmpty) return null;
  try {
    return WorldCountry.list.firstWhere(
      (c) => c.name.common == name,
    );
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// A tappable read-only field that opens a full-screen country search.
///
/// Displays the selected country as emoji flag + common English name
/// (e.g. 🇮🇳 India). When [selectedCountry] is `null` the field shows
/// India as the visual default but does NOT treat India as "selected" —
/// the caller distinguishes null (unset / India default) from an explicit
/// India selection based on their own state.
///
/// Usage:
/// ```dart
/// CountryPickerField(
///   selectedCountry: _selectedCountry,
///   onChanged: (country) {
///     setState(() {
///       _selectedCountry = country;
///       _dialCode = dialCodeFor(country);
///     });
///   },
/// )
/// ```
class CountryPickerField extends StatelessWidget {
  const CountryPickerField({
    super.key,
    required this.selectedCountry,
    required this.onChanged,
    this.labelText = 'Country',
  });

  final WorldCountry? selectedCountry;
  final void Function(WorldCountry country) onChanged;
  final String labelText;

  @override
  Widget build(BuildContext context) {
    final display = selectedCountry ?? kIndiaCountry;

    return GestureDetector(
      onTap: () => _openSearch(context),
      child: AbsorbPointer(
        child: TextField(
          readOnly: true,
          decoration: InputDecoration(
            labelText: labelText,
            border: const OutlineInputBorder(),
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              child: Text(
                display.emoji,
                style: const TextStyle(fontSize: 20),
                textAlign: TextAlign.center,
              ),
            ),
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          controller:
              TextEditingController(text: display.name.common),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    final selected = await CountryPicker().showInSearch(context);
    if (selected != null && context.mounted) {
      onChanged(selected);
    }
  }
}
