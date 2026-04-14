# KashCube — Play Store Submission: Next Steps

**Status:** Privacy policy deployed ✅  
**Date:** 13 April 2026  
**Version:** 1.0.0+1

---

## 🎯 Immediate Actions (Priority Order)

### 1. Add Privacy Policy URL to Play Console ⚡ **DO NOW**

1. Go to [Google Play Console](https://play.google.com/console)
2. Select **Kash Cube** app
3. Navigate to: **Policy → App content** (left sidebar)
4. Find **Privacy Policy** section
5. Paste URL: `https://vloganathane.github.io/kashcube-privacy/privacy.html`
6. Click **Save**

**Time:** 2 minutes  
**Critical:** Required before release

---

### 2. Complete Data Safety Form ⚡ **HIGH PRIORITY**

Location: **Play Console → Policy → App content → Data safety**

#### What to Declare:

**Does your app collect or share any of the required user data types?**
- Select: **Yes** (because of opt-in analytics)

**Data Collection (when analytics enabled):**

| Data Type | Collected? | Purpose | Optional/Required | Ephemeral? |
|-----------|------------|---------|-------------------|------------|
| App interactions | ✅ Yes | Analytics | Optional (user choice) | No |
| Diagnostics (OS version, country) | ✅ Yes | Analytics | Optional (user choice) | No |

**Data NOT Collected (mark as NO):**
- ❌ Financial info (transactions, balances, amounts)
- ❌ Personal info (name, email, phone)
- ❌ Location
- ❌ Contacts (stored locally, not collected by us)
- ❌ Photos/videos
- ❌ SMS/MMS content
- ❌ Device/other IDs (for analytics purposes)

**Important clarifications:**
- **Analytics is ON by default** — users can disable it in Settings
- **Financial data stays local** — never transmitted
- **SMS content is NOT collected** — only parsed locally
- **Contacts stored locally** — not sent to servers

**Data Sharing:**
- Select: **No data shared with third parties**
- Firebase Analytics processes data but doesn't constitute "sharing" per Google's definition

**Security Practices:**
- ✅ Data is encrypted in transit (HTTPS for analytics)
- ✅ Users can request data deletion (disable analytics)
- ✅ AES-256 encryption for backups
- ✅ PIN lock with PBKDF2-HMAC-SHA256

**Time:** 15-20 minutes  
**Critical:** Required before release

---

### 3. Build Release APK/App Bundle 🔨

```bash
cd /Users/loganathanev/Documents/vloganathane/daily-apps/2026/02/24/KashCube

# Clean previous builds
flutter clean

# Get dependencies
flutter pub get

# Run analyzer (fix if needed)
flutter analyze --no-pub

# Build App Bundle (recommended for Play Store)
flutter build appbundle --release

# Build APK (for testing)
flutter build apk --release
```

**Output locations:**
- App Bundle: `build/app/outputs/bundle/release/app-release.aab`
- APK: `build/app/outputs/flutter-apk/app-release.apk`

**Verify:**
1. Install APK on physical device: `adb install build/app/outputs/flutter-apk/app-release.apk`
2. Test core flows:
   - Fresh install → onboarding
   - Add transaction
   - SMS auto-capture (with permission)
   - Analytics opt-in toggle
   - Backup/restore
3. Check app size: should be < 50MB

**Time:** 30 minutes (build + testing)

---

### 4. Prepare Store Listing Assets 🎨

#### Required Assets:

**App Icon (512x512 px)**
- High-res version of your launcher icon
- PNG format, 32-bit with alpha
- Must match in-app icon

**Feature Graphic (1024x500 px)**
- Banner for Play Store listing header
- Showcase: "Privacy-First Financial Tracker 🔒"
- Highlight: "100% Local · No Cloud"

**Screenshots (REQUIRED 2-8 images):**

Phone screenshots (minimum 2):
1. **Home Dashboard** — Transaction feed with Indian ₹ formatting
2. **Reports Screen** — Pie chart or bar graph
3. **Add Transaction** — Form with categories
4. **SMS Auto-Capture** — Detected transaction list
5. **Settings → Privacy** — Analytics opt-in toggle
6. **Invoice Preview** — GST invoice example

Optional tablet screenshots (7-10" layout)

**Tips:**
- Remove any test/dummy data
- Use realistic amounts (₹1,234, ₹25,000)
- Show dark mode + light mode
- Add captions/annotations if helpful

**Time:** 2-3 hours (design + capture)

---

### 5. Write Store Description 📝

**Short description (80 chars max):**
```
Complete finance manager for India. 100% local. Income, credits, invoices, GST.
```

**Alternatives:**
- All-in-one finance app for India. 100% local. Income, expenses, credits, GST.
- Privacy-first money manager for India. Local-only. Income, credits, UPI, GST.

**Full description (4000 chars max):**

```
🔒 Kash Cube — Complete Privacy-First Finance Manager for India

Your money, your data, your device. Period.

100% LOCAL · ZERO CLOUD · NO TRACKING
All your financial data stays on your phone. No servers, no cloud sync, no data mining.

✨ KEY FEATURES

💰 Complete Financial Tracking
• Track income, expenses, investments, and transfers
• Manage credits/udhar (lent & borrowed money)
• Multiple accounts: Bank, UPI, Wallet, Cash
• Budgets with real-time tracking
• Loan management (personal & business)

📊 Auto-Capture Transactions
Automatically detect UPI, bank SMS, PhonePe, GPay, Paytm payments. One tap to add.

💼 GST Invoices & Business Tools
• Generate professional GST-compliant invoices
• Party/customer management
• Item catalog with HSN/SAC codes
• Quotes and booking PDFs
• Team management (assign roles & permissions)

📈 Smart Reports & Analytics
Visual breakdowns by category, party, account, and date. Track income vs expenses, savings rate, daily spend, and more.

🇮🇳 Built for India
• ₹ Indian numbering (₹1,00,000 not $100,000)
• GST compliance tools
• UPI/NEFT/RTGS/IMPS support
• Hindi/English UI
• Financial year tracking (Apr-Mar)

🔐 Security First
• PIN lock with biometric unlock
• AES-256 encrypted backups
• PBKDF2 password hashing (100k iterations)
• Optional app lock timeout
• No data leaves your device

🌙 Modern Design
• Material Design 3
• Dark mode
• Smooth animations
• Indian color palette (green for income, red for expense)

🎯 100% Privacy Guarantee
• No cloud sync (unless you enable optional LAN sync between YOUR devices)
• No email/phone required
• No login, no user account
• Optional analytics (enabled by default, you can disable it)
• No ads, ever

📱 WHO IS THIS FOR?

• Small business owners managing income, expenses & invoices
• Freelancers tracking payments and client credits
• Anyone managing personal finances (salary, expenses, investments)
• Shopkeepers tracking daily sales and customer udhar/khata
• Users tired of apps that upload everything to the cloud

🚫 NO NETWORK CALLS
We don't just promise privacy — we enforce it. Check our permissions yourself.

📦 BACKUP & RESTORE
Encrypted .kashcube backup file. Restore on new device. AES-256 protected.

🆓 FREE, NO ADS
No premium tiers. No subscription. No data sale. All features included.

📞 SUPPORT
Questions? Contact us through the Play Store or visit our privacy policy.

Privacy Policy: https://vloganathane.github.io/kashcube-privacy/privacy.html
```

**Time:** 30 minutes

---

### 6. Complete Content Rating (IARC) ✅

Location: **Play Console → Policy → App content → Content rating**

Follow questionnaire:
- **Violence:** None
- **Sexual content:** None
- **Language:** None
- **Controlled substances:** None
- **Gambling:** None
- **User interaction:** No (single-player finance app)
- **Data sharing:** Declare analytics opt-in
- **Location sharing:** None

**Expected rating:** Everyone / 3+ / PEGI 3

**Time:** 10 minutes

---

### 7. Internal Testing Track 🧪

**Purpose:** Test release build before production

1. **Upload to Internal Testing:**
   - Play Console → Release → Testing → Internal testing
   - Click **Create new release**
   - Upload `app-release.aab`
   - Add release notes (same as draft in checklist)
   - Click **Save** → **Review release** → **Start rollout**

2. **Add test users:**
   - Add 2-5 email addresses (testers)
   - They get Play Store link to install

3. **Test for 24-48 hours:**
   - Fresh install
   - Core flows
   - Check crash reports in Play Console
   - Collect feedback

4. **Fix critical bugs** (if any)

5. **Promote to Production** (after testing passes)

**Time:** 20 minutes setup, 2 days testing

---

## 📊 Progress Tracker

| Step | Status | Time Estimate | Blocking? |
|------|--------|---------------|-----------|
| 1. Privacy Policy URL in Play Console | ⚠️ TODO | 2 min | ✅ Yes |
| 2. Data Safety Form | ⚠️ TODO | 20 min | ✅ Yes |
| 3. Build release APK/AAB | ⚠️ TODO | 30 min | ✅ Yes |
| 4. Store listing assets | ⚠️ TODO | 2-3 hrs | ✅ Yes |
| 5. Store description | ⚠️ TODO | 30 min | ✅ Yes |
| 6. Content rating (IARC) | ⚠️ TODO | 10 min | ✅ Yes |
| 7. Internal testing | ⚠️ TODO | 2 days | 🔶 Recommended |

**Total estimated time:** ~4-5 hours active work + 2 days testing

---

## 🚨 Critical Reminders

1. **Test release build on physical device** before uploading
2. **Backup your keystore** (`key.properties` + keystore file) — you can NEVER re-sign without it
3. **Enable experimental features** only for internal testing builds
4. **Verify analytics consent** works (on by default, user can disable)
5. **Test SMS parsing** with 10+ real messages
6. **Check database migration** (fresh install + restore from backup)

---

## 📞 Need Help?

- **Play Store docs:** https://support.google.com/googleplay/android-developer
- **Data Safety help:** https://support.google.com/googleplay/android-developer/answer/10787469
- **Review guidelines:** https://support.google.com/googleplay/android-developer/answer/9898485

---

**Next update:** After internal testing completes
