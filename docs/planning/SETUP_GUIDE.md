# 🧊 Kash Cube - Quick Start Guide

**Version:** 1.0  
**Date:** February 24, 2026  
**Status:** Active

---

## Prerequisites
- Flutter SDK 3.0+ installed ([Get Flutter](https://flutter.dev/docs/get-started/install))
- Android Studio or Xcode for emulators
- VS Code or Android Studio IDE

## Quick Setup (5 minutes)

### 1. Navigate to Project
```bash
cd /Users/loganathanev/Documents/vloganathane/daily-apps/2026/02/24/KashCube
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Run the App
```bash
# Check available devices
flutter devices

# Run on any device
flutter run

# Or specify device
flutter run -d chrome        # Web (for testing)
flutter run -d <device-id>   # Specific device
```

## First Launch

When you run the app for the first time:

1. You'll see an empty home screen with "No transactions yet"
2. Tap the **+** button to add your first transaction
3. Select **Income** or **Expense**
4. Fill in the details and tap ✓

## Quick Tips

### Adding Transactions
- Tap **+** floating button
- Amount must be positive number
- Category is required
- Date defaults to today

### Viewing Reports
- Tap the **bar chart** icon at bottom
- Switch between Daily/Monthly/Yearly tabs
- Swipe left on transactions to delete

### Understanding the UI
- **Green** = Income
- **Red** = Expense
- **Blue** = Positive Balance
- **Orange** = Negative Balance

## Build for Release

### Android APK
```bash
flutter build apk --release
```
APK location: `build/app/outputs/flutter-apk/app-release.apk`

### iOS
```bash
flutter build ios --release
```

## Development Tips

### Hot Reload
Press `r` in terminal while app is running to hot reload

### Full Restart
Press `R` in terminal for full restart

### Check Logs
```bash
flutter logs
```

### Run Tests
```bash
flutter test
```

## Troubleshooting

**Dependencies not found?**
```bash
flutter clean
flutter pub get
```

**Build errors?**
```bash
flutter doctor -v
```

**Simulator not showing?**
```bash
# iOS
open -a Simulator

# Android
flutter emulators
flutter emulators --launch <emulator-id>
```

## File Structure Reference

```
lib/
├── main.dart                    # App entry point
├── models/
│   ├── transaction.dart         # Transaction data model
│   └── category.dart            # Category definitions
├── database/
│   └── database_helper.dart     # SQLite operations
├── providers/
│   └── transaction_provider.dart # State management
└── screens/
    ├── home_screen.dart         # Navigation
    ├── transactions_screen.dart # Transaction list
    ├── add_transaction_screen.dart # Add form
    └── reports_screen.dart      # Analytics
```

## Database Location

SQLite database is stored at:
- **Android**: `/data/data/com.example.kash_cube/databases/kash_cube.db`
- **iOS**: `Library/Application Support/kash_cube.db`

## Next Steps

1. ✅ Run the app
2. ✅ Add sample transactions
3. ✅ Explore reports
4. 📚 Read [FEATURES.md](FEATURES.md) for complete feature list
5. 🚀 Customize categories in [lib/models/category.dart](lib/models/category.dart)

## Need Help?

- Check [README.md](README.md) for full documentation
- Review [FEATURES.md](FEATURES.md) for architecture details
- Run `flutter doctor` to diagnose issues

## Privacy Note

🔒 All data stays on your device. No internet required. No tracking. Complete privacy.

---

Happy tracking! 🧊
