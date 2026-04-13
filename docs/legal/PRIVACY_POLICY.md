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

### Core App Storage
- **Local SQLite files** on your device

### Declared on Android Build
- Internet + network state (LAN web companion/P2P sync and optional analytics transport)
- Wi-Fi/multicast access (LAN discovery and local connectivity)
- Notifications + boot receiver + vibration (local reminders)
- Camera (QR scan and camera capture flows)
- Contacts read/write (optional import/save contact flows)
- Biometric/fingerprint (optional app lock)
- Billing/install-referrer permissions (Play Billing and install attribution)
- Additional platform/SDK-injected permissions used by enabled dependencies

### Runtime Prompts (shown only when feature is used)
- Notifications (when enabling reminders)
- SMS (when enabling SMS auto-detect)
- Camera (when using QR/camera flows)
- Contacts (when importing/saving contacts)
- Biometric (when enabling biometric app lock)

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
- Any updates will be posted on GitHub Pages
- Check the "Last Updated" date above

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

For support or privacy-related questions:
- Contact us through the Play Store listing
- Email support channel as listed on app store page

## Third-Party Services

Kash Cube uses these open-source packages:
- **sqflite**: Local database (no network calls)
- **flutter_riverpod**: State management (local only)
- **fl_chart**: Charts rendering (local only)
- **intl**: Date formatting (local only)
- **path_provider**: File paths (local only)
- **firebase_analytics**: Optional analytics (opt-in only, off by default)

Core packages do not collect or transmit data. Firebase Analytics only operates when explicitly enabled by user.

## Compliance

- **GDPR**: Compliant by design (no data collection except opt-in analytics)
- **CCPA**: Compliant (no data sale, minimal collection)
- **COPPA**: Compliant (no collection from children)
- **DPDP Act 2023**: Compliant

## Data Security

- SQLite database with standard security
- Access restricted to Kash Cube app only
- Protected by device-level security (lock screen, encryption)
- PIN protected with PBKDF2-HMAC-SHA256 (100,000 iterations)
- No financial data transmission = no network interception risk

## Bottom Line

**Kash Cube is privacy-first by design, not just by policy.**

Your financial data is personal. We built Kash Cube to keep it that way.

---

**Questions?** Contact us through the Play Store listing or visit our GitHub Pages site.
