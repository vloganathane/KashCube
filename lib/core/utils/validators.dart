/// Form validation utilities.
class Validators {
  Validators._();

  /// Validates that the amount is a positive number.
  static String? validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Amount is required';
    }
    final amount = double.tryParse(value.replaceAll(',', ''));
    if (amount == null) {
      return 'Enter a valid amount';
    }
    if (amount <= 0) {
      return 'Amount must be greater than zero';
    }
    if (amount > 99999999) {
      return 'Amount is too large';
    }
    return null;
  }

  /// Validates that a required text field is not empty.
  static String? validateRequired(
    String? value, {
    String fieldName = 'This field',
  }) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Validates party/customer name.
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name is required';
    }
    if (value.trim().length < 2) {
      return 'Name must be at least 2 characters';
    }
    if (value.trim().length > 100) {
      return 'Name is too long';
    }
    return null;
  }

  /// Validates phone number (Indian format).
  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Phone is optional
    }
    final cleaned = value.replaceAll(RegExp(r'[\s\-\+]'), '');
    if (!RegExp(r'^(\+91|91)?[6-9]\d{9}$').hasMatch(cleaned)) {
      return 'Enter a valid Indian phone number';
    }
    return null;
  }

  /// Validates notes field (optional, max length).
  static String? validateNotes(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Notes are optional
    }
    if (value.length > 500) {
      return 'Notes must be under 500 characters';
    }
    return null;
  }
}
