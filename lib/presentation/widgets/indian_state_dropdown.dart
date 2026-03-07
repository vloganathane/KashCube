import 'package:flutter/material.dart';

import '../../core/constants/indian_states.dart';

/// A dropdown field that constrains state selection to the canonical list of
/// Indian states/UTs. Using a fixed list prevents typos that would cause the
/// GST calculator to mis-classify intra-state transactions as inter-state.
///
/// Works with a [TextEditingController]: reads the current text to pre-select
/// and writes the chosen value back on change. Listens to the controller so
/// that programmatic writes (e.g. from pincode auto-fill) also update the UI.
class IndianStateDropdown extends StatefulWidget {
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
  State<IndianStateDropdown> createState() => _IndianStateDropdownState();
}

class _IndianStateDropdownState extends State<IndianStateDropdown> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() => setState(() {});

  @override
  void didUpdateWidget(IndianStateDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Find the canonical entry that matches the stored value (case-insensitive)
    final current = widget.controller.text.trim();
    final String? selected = kIndianStates.cast<String?>().firstWhere(
      (s) => s!.toLowerCase() == current.toLowerCase(),
      orElse: () => null,
    );

    return DropdownButtonFormField<String>(
      key: ValueKey(selected),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
      ),
      hint: const Text('Select state'),
      items: kIndianStates
          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
          .toList(),
      onChanged: (v) {
        if (v != null) widget.controller.text = v;
      },
      validator: widget.validator,
    );
  }
}
