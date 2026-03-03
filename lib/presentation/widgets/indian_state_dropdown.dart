import 'package:flutter/material.dart';

import '../../core/constants/indian_states.dart';

/// A dropdown field that constrains state selection to the canonical list of
/// Indian states/UTs. Using a fixed list prevents typos that would cause the
/// GST calculator to mis-classify intra-state transactions as inter-state.
///
/// Works with a [TextEditingController]: reads the current text to pre-select
/// and writes the chosen value back on change.
class IndianStateDropdown extends StatelessWidget {
  const IndianStateDropdown({
    super.key,
    required this.controller,
    this.label = 'State',
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    // Find the canonical entry that matches the stored value (case-insensitive)
    final current = controller.text.trim();
    final String? selected = kIndianStates.cast<String?>().firstWhere(
      (s) => s!.toLowerCase() == current.toLowerCase(),
      orElse: () => null,
    );

    return DropdownButtonFormField<String>(
      value: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      hint: const Text('Select state'),
      items: kIndianStates
          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
          .toList(),
      onChanged: (v) {
        if (v != null) controller.text = v;
      },
      validator: validator,
    );
  }
}
