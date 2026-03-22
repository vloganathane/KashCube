# Privacy Policy - Kash Cube

**Version:** 1.1  
**Last Updated:** March 22, 2026  
**Status:** Active

## Our Privacy Commitment

Kash Cube is built with privacy at its core. We believe your financial data is yours and yours alone.

## Data Storage

### Local-Only Storage
- **All data is stored locally** on your device using SQLite
- **No cloud synchronization** by default
- **No remote servers** - your data never leaves your device
- **No user accounts** - no login required

### What We Store
- Transaction amounts
- Categories
- Descriptions and notes
- Transaction dates
- Transaction types (income/expense)

### Where It's Stored
- **Android**: Local device storage in app-private directory
- **iOS**: App sandbox in Application Support directory
- **Accessible only** to Kash Cube app, not to other apps

## Data We DO NOT Collect

We explicitly DO NOT collect, store, or transmit:
- ❌ Personal information (name, email, phone)
- ❌ Location data
- ❌ Device information
- ❌ Crash reports
- ❌ Advertising IDs
- ❌ IP addresses
- ❌ Any financial data to third parties
- ✅ **Anonymous usage analytics** — opt-in only, off by default (see [Analytics](#analytics--tracking) below)

## Permissions

### Required Permissions
- **Storage**: To save database locally on device
  - Android: Local storage for SQLite database
  - iOS: App sandbox storage

### NOT Required
- ❌ Internet/Network access
- ❌ Location access
- ❌ Contacts access
- ❌ Camera access (in current version)
- ❌ Microphone access
- ❌ Phone access

## Data Sharing

**We do not share any data because we don't have access to it.**

Your transaction data:
- Never leaves your device
- Is never uploaded to any server
- Is never shared with anyone
- Is never sold to third parties
- Is never used for advertising

## Data Backup

Since all data is local:
- **Device backups** may include app data (iOS iCloud, Android backup)
- **Manual export** (coming soon) - you control when and where
- **No automatic cloud backup** unless you enable device-level backups

## Data Security

- Data stored in SQLite database with standard security
- Access restricted to Kash Cube app only
- Protected by device-level security (lock screen, encryption)
- No transmission over network = no interception risk

## Children's Privacy

Kash Cube does not collect any data from anyone, including children. The app can be safely used by anyone to track expenses.

## Changes to This Policy

Since we don't collect data:
- This policy is unlikely to change fundamentally
- Any updates will be reflected in the app repository
- Check the "Last Updated" date above

## Open Source

Kash Cube is open source. You can:
- Review the code to verify these claims
- Audit the database implementation
- Confirm no network calls are made
- Build from source yourself

## Your Rights

Since all data is local on your device, you have complete control:
- **Access**: View all your data anytime in the app
- **Delete**: Clear all data by uninstalling the app
- **Export**: (Coming soon) Export to CSV/PDF
- **Modify**: Edit or delete any transaction
- **Port**: Database file can be backed up and restored

## Data Retention

- Data is retained **indefinitely** on your device
- Data is **never automatically deleted**
- You can **manually delete** individual transactions
- **Uninstalling** the app deletes all data

## Analytics & Tracking

Kash Cube includes **opt-in anonymous usage analytics** powered by Firebase Analytics. This feature is **off by default**. You must explicitly enable it in **Settings → Privacy**.

### What we collect (only when opted in)
- Screen navigation events (e.g., "opened Reports screen")
- Feature interaction events (e.g., "exported CSV", "enabled App Lock")
- App session metadata provided automatically by Firebase (OS version, country)

### What we NEVER collect (even when opted in)
- ❌ Transaction amounts, descriptions, or dates
- ❌ Party names, phone numbers, or addresses
- ❌ Account balances or credit amounts
- ❌ Any personally identifiable financial information
- ❌ SMS content
- ❌ Crashlytics or crash data

### Your control
- Default state: **disabled**
- Toggle in **Settings → Privacy → Anonymous Analytics**
- Disabling stops all event collection immediately
- Firebase Analytics data is subject to [Google's Privacy Policy](https://policies.google.com/privacy)

If analytics is disabled, no data is sent to Firebase. Period.

## Contact

For questions about this privacy policy or the app:
- Check the GitHub repository for source code
- Open an issue if you have concerns
- Verify privacy claims by reviewing the code

## Third-Party Services

Kash Cube uses these open-source packages:
- **sqflite**: Local database (no network calls)
- **provider**: State management (local only)
- **fl_chart**: Charts rendering (local only)
- **intl**: Date formatting (local only)
- **path_provider**: File paths (local only)

None of these packages collect or transmit data.

## Compliance

- **GDPR**: Compliant by design (no data collection)
- **CCPA**: Compliant (no data sale, no collection)
- **COPPA**: Compliant (no collection from anyone)

## Verification

You can verify these claims by:
1. Checking network permissions (none required)
2. Reviewing source code (fully open)
3. Using network monitoring tools (no traffic)
4. Inspecting the database file (local only)

## Bottom Line

**Kash Cube is privacy-first by design, not just by policy.**

Your financial data is personal. We built Kash Cube to keep it that way.

---

**Questions?** Review the source code or open an issue on GitHub.

**Trust, but verify.** We encourage you to audit the code yourself.
