# KashCube - Play Store Production Release Checklist
**Date:** 13 April 2026  
**Version:** 1.0.0+1  
**Target:** First production release

---

## ✅ PRIVACY & SECURITY — Critical

### Network Calls Audit
- [ ] **No http/dio packages** — Verified ✓ (no imports found)
- [ ] **No connectivity_plus** — Verified ✓ (not in pubspec.yaml)
- [ ] **Analytics consent enforced**
  - [ ] Check `AnalyticsService` checks consent before every event
  - [ ] Default is opt-out (consent = false)
  - [ ] Settings UI clearly explains what's collected
  - [ ] Firebase Analytics is the ONLY network-enabled package
- [ ] **SMS data stays local**
  - [ ] No SMS content sent to analytics
  - [ ] SMS parser only extracts local transactions
  - [ ] Verify no raw SMS text logged

### Permissions Review
- [ ] **AndroidManifest.xml permissions justified**
  - [ ] INTERNET — LAN sync & opt-in analytics ONLY
  - [ ] ACCESS_NETWORK_STATE — LAN discovery
  - [ ] ACCESS_WIFI_STATE — LAN discovery
  - [ ] POST_NOTIFICATIONS — Local reminders
  - [ ] SMS (runtime) — Auto-capture (optional)
  - [ ] CAMERA (runtime) — QR scan (optional)
  - [ ] CONTACTS (runtime) — Import/save (optional)
- [ ] **Runtime permissions requested contextually**
  - [ ] SMS: Only when user enables auto-detect
  - [ ] Camera: Only when user scans QR
  - [ ] Contacts: Only when user imports/saves
  - [ ] Notifications: When enabling reminders
- [ ] **Biometric permission explanation**
  - [ ] Used for app lock only
  - [ ] Optional feature

### Data Security
- [ ] **All data stored in SQLite locally**
- [ ] **PIN lock uses PBKDF2 (100k iterations)** — Verify in code
- [ ] **Encrypted backup uses AES-256-GCM** — Verify in code
- [ ] **No plaintext passwords in SharedPreferences**
- [ ] **No sensitive data in analytics events**

---

## 📱 APP CONFIGURATION

### Version & Build Info
- [ ] **Version name:** 1.0.0
- [ ] **Version code:** 1
- [ ] **Package ID:** com.kashcube.app
- [ ] **minSdk:** Check Flutter default (min API 21/Android 5.0)
- [ ] **targetSdk:** Latest stable (API 34/Android 14)
- [ ] **compileSdk:** Latest (API 35)

### App Signing
- [ ] **Release keystore exists** — Check `key.properties`
- [ ] **Signing config points to correct keystore**
- [ ] **Key alias & passwords configured**
- [ ] **Keystore backed up securely**

### App Metadata
- [ ] **App name:** "Kash Cube" (matches in AndroidManifest)
- [ ] **App icon:** High-res launcher icon (adaptive)
- [ ] **Splash screen:** Clean branding
- [ ] **Feature graphic** for Play Store (1024x500)
- [ ] **Screenshots** (phone + tablet, 2-8 images)

---

## 🔧 CRITICAL FUNCTIONALITY

### Database
- [ ] **Schema version correct** — Check current version
- [ ] **All migrations tested** (v1 → v2, v2 → v3, etc.)
- [ ] **Integrity check on startup** — Verify in logs
- [ ] **Daily snapshot working** — Verify in logs
- [ ] **Vacuum scheduled** — Check DatabaseHelper

### SMS Auto-Capture
- [ ] **Sender registry up-to-date** (HDFC, ICICI, SBI, PhonePe, GPay, Paytm, etc.)
- [ ] **Regex patterns tested** with real SMS samples
- [ ] **Deduplication working** (SHA-256 hash)
- [ ] **Confidence scoring accurate** (HIGH/MEDIUM/LOW)
- [ ] **Auto-categorization working**

### Backup & Restore
- [ ] **Encrypted backup (.kashcube) works**
  - [ ] Test export on one device
  - [ ] Test import on another device
  - [ ] Verify AES-256-GCM encryption
- [ ] **Backup includes all tables**
- [ ] **Media files backed up** (if applicable)

### Analytics (Opt-in)
- [ ] **Firebase config valid** (google-services.json)
- [ ] **Consent check before every event**
- [ ] **No financial data in events**
  - [ ] No amounts
  - [ ] No party names
  - [ ] No transaction details
- [ ] **Only feature usage tracked** (screen names, button taps)

---

## 🎨 UI/UX POLISH

### Empty States
- [ ] All list screens show helpful empty states
- [ ] Instructions guide user to first action
- [ ] Icons/illustrations are relevant

### Loading States
- [ ] Skeleton screens / shimmer on data load
- [ ] Progress indicators on async operations
- [ ] No blank screens during fetch

### Error Handling
- [ ] User-friendly error messages (not technical jargon)
- [ ] Retry buttons where applicable
- [ ] Network errors explained (for LAN sync features)

### Accessibility
- [ ] Touch targets ≥ 48dp
- [ ] Text contrast meets WCAG guidelines
- [ ] Semantic labels for screen readers
- [ ] Dark mode fully functional

---

## 📋 PLAY STORE REQUIREMENTS

### Privacy Policy
- [x] **Privacy policy accessible in app** — Settings → About → Privacy Policy ✓
- [x] **Privacy policy hosted online** (Play Store requires URL)
  - [x] Uploaded to GitHub Pages: https://vloganathane.github.io/kashcube-privacy/privacy.html
  - [ ] Add URL to Play Store listing (Play Console → Store settings → Privacy Policy)
- [x] **Terms of Use accessible** — Settings → About → Terms of Use ✓
  - [x] Hosted: https://vloganathane.github.io/kashcube-privacy/terms.html

### Data Safety Form (Play Console)
- [ ] **No data collected** (except opt-in analytics)
- [ ] **Analytics marked as optional**
- [ ] **No data shared with third parties**
- [ ] **No sensitive data (financial/location/health) collected**
- [ ] **Device ID collection explained** (for LAN sync pairing)

### Content Rating
- [ ] **IARC questionnaire completed**
- [ ] **Age rating appropriate** (likely Everyone/3+)

### App Category
- [ ] **Category:** Finance or Business & Productivity
- [ ] **Tags:** Expense tracker, Invoice, GST, Accounting

---

## 🧪 TESTING CHECKLIST

### Functional Testing
- [ ] **Fresh install** (uninstall → reinstall)
- [ ] **App startup** (cold start < 3 seconds)
- [ ] **Navigation** (all screens reachable)
- [ ] **Forms** (all inputs validate correctly)
- [ ] **Database CRUD** (Create, Read, Update, Delete)
- [ ] **SMS parsing** (test with 10+ real messages)
- [ ] **PDF generation** (invoice, quote, challan)
- [ ] **Backup/restore flow** end-to-end
- [ ] **Analytics opt-in/opt-out** toggle works

### Edge Cases
- [ ] **No SMS permission** — app handles gracefully
- [ ] **No camera permission** — QR flow disabled correctly
- [ ] **No contacts permission** — import disabled correctly
- [ ] **Airplane mode** — LAN features disable cleanly
- [ ] **Low storage** — backup fails gracefully
- [ ] **Large database** (1000+ transactions) — performance OK

### Device Testing
- [ ] **Android 5.0 (API 21)** — minSdk device
- [ ] **Android 10 (API 29)** — scoped storage
- [ ] **Android 13 (API 33)** — notification permission
- [ ] **Android 14 (API 34)** — latest targetSdk
- [ ] **Tablet** (10" screen) — layout adapts
- [ ] **Low-end device** (2GB RAM) — no crashes

### Stress Testing
- [ ] **Rapidly switch screens** — no memory leaks
- [ ] **Background → foreground** — state retained
- [ ] **Kill app mid-operation** — data not corrupted
- [ ] **Database with 10k+ rows** — queries fast

---

## 🚫 KNOWN ISSUES TO FIX BEFORE RELEASE

### Experimental Features (Already Hidden ✓)
- [x] **Devices & LAN Sync** — Commented out
- [x] **Experimental: libp2p Sync** — Commented out
- [x] **Open on Laptop** — Commented out

### Critical Bugs
- [ ] Check for any crash logs in Firebase Crashlytics (disabled for privacy, but check dev logs)
- [ ] Fix any `setState` on unmounted widgets
- [ ] Fix any database lock errors

### Warnings to Address
- [ ] Resolve "macOS deployment target 10.11" warning (if relevant for Android)
- [ ] Check for Flutter deprecation warnings
- [ ] Resolve any lint warnings (`flutter analyze`)

---

## 🎯 PRE-SUBMISSION TASKS

### Code Quality
- [ ] **Run `flutter analyze`** — 0 errors, 0 warnings
- [ ] **Run tests: `flutter test`** — All tests pass
- [ ] **Remove debug prints** (or use `kDebugMode` guards)
- [ ] **Remove unused imports**
- [ ] **Remove dead code** (commented experimental code is OK)

### Build Artifacts
- [ ] **Build APK:** `flutter build apk --release`
- [ ] **Build App Bundle:** `flutter build appbundle --release`
- [ ] **Test release build** on real device (not debug)
- [ ] **Verify app size** (under 50MB uncompressed)

### Play Console Setup
- [ ] **Create app listing** in Play Console
- [ ] **Add screenshots** (2-8 per device type)
- [ ] **Add feature graphic** (1024x500)
- [ ] **Write app description** (80-4000 chars)
- [ ] **Short description** (80 chars max)
- [ ] **App icon** uploaded (512x512)
- [x] **Privacy policy URL** — https://vloganathane.github.io/kashcube-privacy/privacy.html  
  - [ ] Added to Play Console (Store settings → Privacy Policy)
- [ ] **Complete Data Safety form**
- [ ] **Complete Content Rating** (IARC)

### Internal Testing Track
- [ ] **Upload app bundle** to Internal Testing
- [ ] **Add internal testers** (email list)
- [ ] **Test for 24-48 hours** — collect feedback
- [ ] **Fix any critical issues**

---

## ✅ FINAL GO/NO-GO CHECKLIST

Before promoting to Production:

- [ ] **0 critical bugs** in internal testing
- [ ] **Privacy audit passed** (no leaks, consent works)
- [ ] **Backup/restore tested** on 3+ devices
- [ ] **SMS parsing tested** with 20+ real messages
- [ ] **Performance acceptable** on low-end device
- [ ] **Analytics respects consent**
- [ ] **Privacy policy URL live**
- [ ] **All Play Store metadata complete**
- [ ] **Keystore backed up** (can't re-sign later!)
- [ ] **Version 1.0.0 tagged in Git**

---

## 📣 POST-RELEASE MONITORING

### First 24 Hours
- [ ] Monitor crash rate (target: <0.5%)
- [ ] Monitor ANR rate (Application Not Responding)
- [ ] Check Play Console reviews
- [ ] Verify analytics events (if users opt in)
- [ ] Check database migration success rate

### First Week
- [ ] Gather user feedback
- [ ] Plan v1.0.1 hotfix if needed
- [ ] Monitor backup/restore success rate
- [ ] Check SMS parsing accuracy (via support channel)

---

## 🎉 RELEASE NOTES (Draft)

**Kash Cube v1.0.0 — Privacy-First Financial Tracker**

What's New:
✨ Auto-capture UPI/bank transactions from SMS
📊 Track income, expenses, credits (udhar/khata)
💼 Generate GST-compliant invoices, quotes, challan
📈 Visual reports and expense breakdowns
🔒 100% local — your data never leaves your device
🇮🇳 Built for India — ₹ formatting, GST support
🌙 Dark mode, PIN lock, biometric unlock
📦 Encrypted backup (.kashcube file format)

Privacy Promise:
• All data stored locally in SQLite
• No cloud sync (optional LAN sync between your devices)
• Optional, anonymous analytics (you control it)
• No ads, no tracking, no data sale

Support:
For questions or support, contact us through the Play Store listing.

---

**Notes:**
- This checklist is a living document
- Mark items as complete: `- [x]` when done
- Add new items as discovered
- Keep updated for v1.0.1, v1.1.0, etc.
