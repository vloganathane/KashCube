/// App-wide constants for Kash Cube.
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'Kash Cube';
  static const String appVersion = '1.0.0';
  static const String currencySymbol = '₹';
  static const String locale = 'en_IN';

  // Database
  static const String dbName = 'kash_cube.db';
  static const int dbVersion = 45;

  // Categories (MVP - 10 pre-defined)
  static const List<String> defaultCategories = [
    'Food & Dining',
    'Transportation',
    'Shopping',
    'Bills & Utilities',
    'Healthcare',
    'Entertainment',
    'Groceries',
    'Education',
    'Business Expense',
    'Other',
  ];

  // Income Categories
  static const List<String> incomeCategories = [
    'Salary',
    'Business Income',
    'Freelance',
    'Investment',
    'Refund',
    'Other Income',
  ];

  // Payment Methods
  static const List<String> paymentMethods = [
    'UPI',
    'Cash',
    'Credit Card',
    'Debit Card',
    'Net Banking',
    'Wallet',
  ];

  // UPI Apps
  static const List<String> upiApps = [
    'PhonePe',
    'Google Pay',
    'Paytm',
    'BHIM',
    'Other',
  ];

  // Transaction Modes
  static const List<String> transactionModes = [
    'personal',
    'business',
    'investment',
  ];

  // SMS Confidence Thresholds
  static const double highConfidence = 0.8;
  static const double mediumConfidence = 0.5;

  // UI
  static const int maxRecentTransactions = 10;
  static const int searchDebounceMs = 300;
  static const double minTouchTarget = 48.0;
}
