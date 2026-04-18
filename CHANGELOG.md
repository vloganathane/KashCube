# Changelog

All notable changes to Kash Cube will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-04-18

### Fixed
- **CRITICAL: Database Migration Fix (Build 5)**: Fixed app hanging on loading screen for existing users upgrading from older database versions (v90 → v92). Migration scripts now use `conflictAlgorithm: ConflictAlgorithm.replace` on all 89 schema_version inserts, allowing partial migrations to be retried safely. Resolves `UNIQUE constraint failed: schema_version.version` errors that left users stuck unable to use the app without uninstalling (losing all data).
- **CRITICAL: App Loading Issue (Build 4)**: Fixed infinite loading screen after Play Store updates. Resolved database initialization race condition where multiple providers competed for database access on startup. Implemented initialization mutex in `DatabaseHelper` to ensure single database open operation with all callers waiting for same Future.
- **Biometric Authentication Crash**: Fixed `PlatformException(no_fragment_activity)` crash when enabling biometric unlock in Settings. Changed `MainActivity` to extend `FlutterFragmentActivity` as required by the `local_auth` plugin.
- **PIN Lock UX**: Resolved issue where PIN lock screen triggered during normal app usage (transaction saves, keyboard input, dialogs). Implemented intelligent lifecycle state tracking to distinguish real backgrounding from transient UI events.
- **Payment Method Selection**: Payment method dropdown now remains interactive when an account is selected, showing filtered valid methods for that account type instead of being disabled.

### Changed
- **Asset Optimization**: Reduced APK size by ~45MB by archiving unused web_ui assets (Web Companion feature disabled for initial Play Store release). Assets moved to `assets_archive/` for future re-enablement.
- **Payment Method UX**: Smart auto-selection now only changes payment method if current selection is invalid for newly selected account type, preserving user choice when possible.

### Added
- Error handling for biometric authentication failures with user-friendly messages
- Documentation for re-enabling Web Companion feature (`docs/WEB_COMPANION_REENABLE.md`)
- Archive inventory and restoration guide (`assets_archive/README.md`)

## [1.0.0] - 2026-04-03

### Added
- Initial Play Store release candidate
- Privacy-first financial tracking
- Automatic SMS transaction capture for Indian banks and UPI apps
- Credit/Udhar (khata) management
- Local SQLite database with 100% offline operation
- PIN lock with biometric authentication
- Transaction categorization and budgeting
- Chart visualizations
- Indian locale support (₹ currency, date formats)
- Dark mode support

### Security
- All data stored locally, zero network calls
- No analytics or telemetry for financial data
- Optional anonymous usage analytics (Firebase Analytics) with user consent
- Biometric authentication support
