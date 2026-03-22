# Privacy Architecture
# Kash Cube - Privacy-First Design

**Version:** 1.0  
**Date:** February 24, 2026  
**Status:** Design Phase

**Philosophy:** "Your data lives on YOUR phone. Forever."

---

## 1. Privacy Principles

### 1.1 Core Commitments

1. **Local-Only Storage**
   - All data stored in local SQLite database
   - No cloud sync by default
   - No external API calls

2. **No Data Collection**
   - Zero telemetry
   - No analytics tracking
   - No crash reporting to external services
   - No user profiling

3. **No Account Required**
   - No signup/login
   - No email/phone collection
   - No user identification

4. **Transparent Permissions**
   - Only REQUEST one permission: READ_SMS
   - Clear explanation why we need it
   - App works without it (manual entry fallback)

5. **User Control**
   - User owns their data
   - Export anytime
   - Delete anytime
   - No vendor lock-in

---

## 2. Data Storage

### 2.1 Local SQLite Database

**Location:** 
```
/data/data/com.kashcube.app/databases/kash_cube.db
```

**Security:**
- Android app sandbox (OS-level isolation)
- Not accessible to other apps
- Backed up only if user explicitly exports

**Encryption:**
- Phase 1 (MVP): No encryption (rely on Android sandbox)
- Phase 2: Optional SQLCipher (password-protected encryption)

**Justification:**
- SMS data already on device
- Android sandbox is sufficient for MVP
- Adding encryption increases complexity
- Future: Let users opt-in to encryption

### 2.2 Data Flow

```
SMS Inbox (Android)
    │ (READ_SMS permission)
    ▼
SMS Parser (In-App)
    │ (No network call)
    ▼
Transaction Object (Memory)
    │
    ▼
SQLite Database (Device Storage)
    │
    ▼
UI Display (Local)
```

**No Cloud Path:**
```
❌ SQLite → Network → Cloud Server
❌ Analytics → Firebase
❌ Crash Logs → Sentry
```

---

## 3. Permissions

### 3.1 READ_SMS (Optional)

**Why We Need It:**
- Auto-capture transaction from bank/UPI SMS
- Core feature: saves time vs manual entry

**How We Use It:**
- Read incoming SMS in real-time
- Parse only financial SMS (bank sender IDs)
- Extract: amount, merchant, date
- Discard non-financial SMS

**What We DON'T Do:**
- ❌ Read personal messages
- ❌ Send SMS data to server
- ❌ Store full SMS body (except financial ones)
- ❌ Share SMS with third parties

**User Control:**
- Permission requested on first launch
- Educational screen explaining purpose
- "Deny" option available
- App works without it (manual entry mode)
- Can revoke in Android settings anytime

### 3.2 No Other Permissions

**We Never Request:**
- INTERNET (no network access needed)
- CAMERA (no receipt scanning in MVP)
- LOCATION (no geo-tagging)
- CONTACTS (no contact book access)
- STORAGE (Android 10+ uses scoped storage)
- PHONE_STATE (no need)
- ACCOUNTS (no account access)

**Manifest:**
```xml
<manifest>
  <uses-permission android:name="android.permission.READ_SMS" />
  
  <!-- Explicitly declare we DON'T need internet -->
  <uses-permission 
    android:name="android.permission.INTERNET" 
    tools:node="remove" />
</manifest>
```

---

## 4. SMS Handling

### 4.1 Real-Time Parsing

**Process:**
1. User grants READ_SMS permission
2. App registers BroadcastReceiver for `SMS_RECEIVED`
3. New SMS arrives → Receiver triggered
4. Check sender ID:
   - Known bank/UPI sender? → Parse
   - Unknown sender? → Ignore (discard)
5. Extract transaction data → Save to local DB
6. Original SMS untouched (stays in SMS inbox)

**Code Example:**
```dart
class SmsReceiver extends BroadcastReceiver {
  @override
  void onReceive(BuildContext context, Intent intent) {
    final messages = Telephony.instance.getIncomingSms(intent);
    
    for (var sms in messages) {
      // Check if financial SMS
      if (isKnownFinancialSender(sms.address)) {
        // Parse locally
        final transaction = SmsParser.parse(sms.body, sms.address);
        
        if (transaction != null) {
          // Save to local DB (no network)
          await db.insertTransaction(transaction);
          
          // Notify UI
          notifyNewTransaction(transaction);
        }
      }
      // Ignore non-financial SMS (privacy)
    }
  }
}
```

### 4.2 What We Store

**Stored:**
- Parsed transaction amount
- Merchant/party name
- Transaction type (income/expense)
- Date & time
- Payment method
- Reference ID (UPI ref, etc.)
- Sender ID (e.g., "PHONEPE")
- SMS body (optional, for user reference)

**NOT Stored:**
- SMS from non-financial senders
- Personal messages
- SMS metadata (phone numbers of personal contacts)

**Retention:**
- Keep forever (until user deletes)
- User can delete individual transactions
- User can clear all data

---

## 5. Security

### 5.1 PIN Lock (MVP)

**Purpose:**
- Prevent unauthorized access if device shared/stolen
- Add layer beyond device lock

**Implementation:**
- 4-digit PIN
- Set up on first launch (mandatory)
- Required every time app opened
- Auto-lock after 5 minutes inactive

**Storage:**
- PIN stored as SHA-256 hash in local DB
- Never store plain-text PIN

**Code:**
```dart
// Hash PIN before storing
String hashPin(String pin) {
  final bytes = utf8.encode(pin);
  return sha256.convert(bytes).toString();
}

// Verify PIN
bool verifyPin(String entered, String storedHash) {
  return hashPin(entered) == storedHash;
}
```

### 5.2 Biometric Lock (MVP - Optional)

**Supported:**
- Fingerprint (Android 6+)
- Face unlock (Android 10+)

**Fallback:**
- If biometric fails/unavailable, fallback to PIN
- User can disable biometric in settings

**Implementation:**
```dart
final auth = LocalAuthentication();

// Check if biometric available
final canAuth = await auth.canCheckBiometrics;

if (canAuth) {
  final authenticated = await auth.authenticate(
    localizedReason: 'Unlock Kash Cube',
    options: const AuthenticationOptions(
      biometricOnly: true,
      stickyAuth: true,
    ),
  );
  
  if (authenticated) {
    // Unlock app
  } else {
    // Show PIN screen
  }
}
```

### 5.3 Database Encryption (Phase 2)

**Library:** SQLCipher for Flutter
**Encryption:** AES-256

**User Flow:**
1. User enables "Encrypt Database" in settings
2. User sets encryption password (6+ characters)
3. App encrypts existing database
4. Future reads/writes use encrypted DB
5. Password stored securely (Android Keystore)

**Trade-offs:**
- **Pro:** Military-grade encryption
- **Con:** Slightly slower performance (~10%)
- **Con:** If password forgotten, data lost forever

**MVP Decision:** Not included (rely on Android sandbox + PIN)

---

## 6. Backup & Export

### 6.1 Local Backup (MVP)

**Process:**
1. User taps "Backup Database" in settings
2. App exports `.db` file to Downloads folder
3. User can:
   - Share via file manager (WhatsApp, Drive, etc.)
   - Copy to computer via USB
   - Store on external SD card

**Privacy:**
- User controls where backup goes
- No auto-upload to cloud
- No backup to Google Drive by default

**File Format:**
```
kash_cube_backup_2026-02-24_15-30.db
```

### 6.2 CSV Export (MVP)

**Process:**
1. User taps "Export to CSV" in settings
2. Generates CSV file with all transactions
3. Columns:
   - Date, Amount, Category, Party, Type, Notes

**Privacy:**
- Human-readable format
- Can open in Excel/Sheets
- User can redact sensitive data before sharing

**File Format:**
```
transactions_2026-02-24.csv
```

### 6.3 Cloud Sync (Future - Phase 3)

**If Added Later:**
- Fully optional (opt-in)
- Encrypted before upload (zero-knowledge)
- User provides own storage (Google Drive, Dropbox)
- We never see unencrypted data
- User can disable anytime

**Architecture:**
```
Local DB → Encrypt (User Key) → Cloud (Encrypted Blob)
Cloud → Download → Decrypt (User Key) → Local DB
```

---

## 7. Multi-User Access

### 7.1 Local Profile System (Phase 2)

**Requirement:** 
- User wants spouse/partner to view transactions
- But maintain separate PINs

**Solution: Local Profiles**
```
Profile 1 (Owner):
  - PIN: 1234
  - Permissions: Full (add/edit/delete)
  
Profile 2 (Viewer):
  - PIN: 5678
  - Permissions: Read-only
```

**Implementation:**
- New table: `profiles`
- Each profile has own PIN
- Permissions: full, read-only, limited
- Data shared in same local DB
- No cloud sync required

### 7.2 Privacy Considerations

**Challenges:**
1. Multiple PINs on same device
2. One person can see other's PIN entry
3. No way to hide specific transactions

**Solutions:**
1. Trust model: This is for trusted family/partners
2. Future: Private categories (hidden from certain profiles)
3. Future: Transaction-level permissions

**Transparency:**
- Document in help: "Profiles share same database"
- Not recommended for untrusted users
- Consider separate devices if true isolation needed

---

## 8. Network & Telemetry

### 8.1 Zero Network Calls

**No HTTP Requests:**
- No API calls to our servers (we don't have servers)
- No analytics pings
- No update checks
- No feature flag syncs

**Manifest:**
```xml
<!-- Explicitly remove INTERNET permission -->
<uses-permission 
  android:name="android.permission.INTERNET" 
  tools:node="remove" />
```

**Why:**
- Privacy guarantee: No data leaks possible
- Works offline (airplane mode)
- Faster (no network latency)
- Lower battery usage

### 8.2 No Analytics

**What We DON'T Track:**
- Screen views
- Button clicks
- Feature usage
- User demographics
- Device info
- App crashes

**Why:**
- Privacy commitment
- No need (we're not VC-funded growth startup)
- No third-party SDKs
- Smaller app size

**Alternative:**
- Beta testers give manual feedback (surveys)
- App store reviews
- GitHub issues

---

## 9. Third-Party Dependencies

### 9.1 Package Audit

**All Dependencies (MVP):**

| Package | Purpose | Privacy Risk |
|---------|---------|--------------|
| riverpod | State management | ❌ None (local) |
| sqflite | Database | ❌ None (local) |
| telephony | SMS reading | ❌ None (local) |
| fl_chart | Charts | ❌ None (local) |
| local_auth | Biometric | ❌ None (local) |
| intl | Date formatting | ❌ None (local) |
| path | File paths | ❌ None (local) |

**What We DON'T Use:**
- ❌ firebase_core (analytics, crashlytics)
- ❌ sentry_flutter (crash reporting)
- ❌ google_sign_in (no accounts)
- ❌ cloud_firestore (no cloud)
- ❌ http / dio (no network)

**Philosophy:**
- Audit every dependency
- Prefer local-only packages
- Reject any that phone home
- Minimize dependency count

### 9.2 Supply Chain Security

**Verification:**
- Use only pub.dev verified packages
- Check package source code (GitHub)
- Avoid packages with minified/obfuscated code
- Monitor security advisories

---

## 10. Privacy Policy (User-Facing)

### 10.1 Simple Language

**Privacy Policy (Draft):**

---

**Kash Cube Privacy Policy**

Last updated: February 24, 2026

**Short version:**
- Your data never leaves your phone
- We don't collect anything
- No accounts, no tracking, no cloud

**Long version:**

**Data Collection**  
We don't collect any data. Period.

**SMS Permission**  
We ask for SMS permission to read bank/UPI transaction messages. These messages are parsed on your phone and stored in a local database. We never send SMS data to any server.

**Data Storage**  
All your transactions are stored in a local database on your device. No cloud sync. No external servers.

**Third Parties**  
We don't share any data with third parties because we don't have any data. We don't use analytics, advertising, or crash reporting services.

**Your Rights**  
- You can export your data anytime (Settings → Backup)
- You can delete all data anytime (Settings → Clear Data)
- You can revoke SMS permission in Android settings

**Changes to Policy**  
If we add cloud sync in future (optional feature), we'll update this policy and notify you in the app.

**Contact**  
Questions? Email us at privacy@kashcube.app

---

**End of Privacy Policy**

### 10.2 Accessibility

**Where to Find:**
- In-app: Settings → About → Privacy Policy
- Google Play listing: Link to web version
- GitHub: PRIVACY.md

**Formats:**
- Simple markdown (easy to read)
- No legalese
- Bullet points
- Clear language

---

## 11. Compliance

### 11.1 Indian Regulations

**Personal Data Protection Bill (Draft):**
- We don't collect personal data → Not applicable
- SMS permission disclosed clearly → Compliant
- User can revoke permission → Compliant

### 11.2 Google Play Requirements

**Data Safety Form:**
```
Does your app collect or share user data?
→ No

Does your app access SMS?
→ Yes, for financial transaction parsing (explained in listing)

Is data encrypted in transit?
→ N/A (no network transmission)

Can users request data deletion?
→ Yes (Settings → Clear Data)

```

### 11.3 GDPR (If Expanding to EU)

**Compliance:**
- ✅ Data minimization (only transaction data)
- ✅ User consent (SMS permission)
- ✅ Right to access (export feature)
- ✅ Right to deletion (clear data)
- ✅ No profiling
- ✅ No cross-border transfer (data stays on device)

---

## 12. Transparency

### 12.1 Open Source (Future)

**Consideration:**
Should we open-source Kash Cube?

**Pros:**
- Ultimate transparency (users can verify privacy claims)
- Community contributions (more SMS patterns)
- Trust building

**Cons:**
- Competitors can clone
- Monetization harder (freemium model still works)

**Decision:** 
- Phase 1 (MVP): Closed source
- Phase 2 (After launch): Consider open-sourcing core (not branding)

### 12.2 Privacy Audit

**Self-Audit Checklist:**
- [ ] No network calls in production build
- [ ] No third-party SDKs with telemetry
- [ ] SMS permission clearly explained
- [ ] Privacy policy reviewed by legal (if formal launch)
- [ ] Data safety form accurate in Play Store
- [ ] Users can export/delete data

**External Audit (Future):**
- Hire security researcher to audit app
- Publish findings
- Fix any issues
- Market as "audited for privacy"

---

## 13. Competitive Advantage

### 13.1 Privacy as Feature

**Market Positioning:**
> "Kash Cube: The Only Expense Tracker That Respects Your Privacy"

**Differentiators:**
- No account required (competitors force signup)
- No cloud by default (competitors auto-sync)
- No analytics (competitors track everything)
- No ads (free tier with dignity)

**Target Users:**
1. Privacy advocates
2. People in regions with poor internet
3. Those burned by data breaches
4. Small businesses avoiding cloud costs

### 13.2 Marketing Privacy

**Key Messages:**
- "Your data lives on YOUR phone"
- "No login needed"
- "Works offline"
- "No tracking, no analytics, no BS"

**Proof:**
- Open-source code (future)
- Privacy audit (future)
- No INTERNET permission (verifiable)
- Simple privacy policy

---

## 14. Future Privacy Features

### 14.1 Phase 2

**Advanced Security:**
- Database encryption (SQLCipher)
- Encrypted backups (password-protected ZIP)
- Hidden categories (private transactions)
- Incognito mode (don't save certain transactions)

**Multi-User Privacy:**
- Profile-specific PIN timeouts
- Private transactions (not visible to all profiles)
- Audit log (who viewed what)

### 14.2 Phase 3

**Optional Cloud Sync (Privacy-Preserving):**
- Zero-knowledge encryption
- Client-side encryption before upload
- We never see unencrypted data
- Open-source sync protocol

**Advanced Features:**
- Self-hosted sync server option
- End-to-end encrypted family sharing
- Encrypted cloud backups

---

## 15. Privacy-First Development Principles

### 15.1 Design Guidelines

**Every Feature Ask:**
1. "Do we NEED to collect this data?"
2. "Can we do this locally instead of cloud?"
3. "What's the minimum data required?"
4. "Can user opt-out?"
5. "Can user delete this data?"

**Default Answer:** If in doubt, don't collect.

### 15.2 Code Review Checklist

**Before Merging:**
- [ ] No new network calls
- [ ] No new permissions
- [ ] No logging sensitive data
- [ ] No third-party SDKs added
- [ ] User can disable new feature
- [ ] Privacy policy updated (if needed)

---

## 16. Risk Mitigation

### 16.1 Potential Risks

**Risk 1: Android Backup**
- **Issue:** Android auto-backs up app data to Google Drive
- **Impact:** User's transaction data uploaded without consent
- **Mitigation:** Disable auto-backup in manifest

```xml
<application
  android:allowBackup="false"
  android:fullBackupContent="false">
  ...
</application>
```

**Risk 2: Screenshot/Screen Recording**
- **Issue:** Another app can capture screenshots
- **Impact:** Sensitive transaction data leaked
- **Mitigation:** 
  - Warn users in settings
  - Optional: `FLAG_SECURE` (prevents screenshots)

**Risk 3: Device Theft**
- **Issue:** Stolen device with unlocked app
- **Impact:** Thief sees all transactions
- **Mitigation:** 
  - PIN lock (mandatory)
  - Auto-lock after 5 min
  - Recommend device encryption

**Risk 4: Rooted Device**
- **Issue:** Root apps can access any file
- **Impact:** Bypass app security, read database
- **Mitigation:**
  - Detect root (warn user)
  - Recommend database encryption
  - Cannot prevent (OS level issue)

### 16.2 Incident Response

**If Privacy Breach Occurs:**
1. Immediate rollback of affected feature
2. Public disclosure (blog post + in-app notification)
3. Offer remediation (free premium, support)
4. Third-party security audit
5. Publish findings and fixes

**Philosophy:** Be transparent, act fast, take responsibility.

---

## 17. Privacy Guarantees

### 17.1 Written Commitments

**We Promise:**
1. ✅ No data leaves your device without your explicit action (export/share)
2. ✅ No analytics or tracking ever
3. ✅ No selling data (we don't have it to sell)
4. ✅ No ads based on your spending habits
5. ✅ No account required, no email collected
6. ✅ You can delete all data anytime
7. ✅ Open to external privacy audits

**We Will NEVER:**
1. ❌ Add analytics without opt-in
2. ❌ Sell user data
3. ❌ Share data with third parties
4. ❌ Require cloud sync
5. ❌ Track you across apps
6. ❌ Build user profiles

### 17.2 Accountability

**If We Break These Promises:**
- We will publicly apologize
- Offer full refunds (if premium user)
- Rollback changes
- Open-source the app (accountability)

**Contact:** privacy@kashcube.app

---

**Privacy is not a feature. It's the foundation.**

---

**Next Steps:** Review [Implementation Roadmap](./IMPLEMENTATION_ROADMAP.md) to begin development
