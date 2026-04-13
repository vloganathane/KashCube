# Data Safety Form Guide — Kash Cube

**Critical:** This form determines what appears on your Play Store listing under "Data safety"  
**Location:** Play Console → Policy → App content → Data safety

---

## 📋 Question-by-Question Guide

### Section 1: Overview

**Question:** Does your app collect or share any of the required user data types?

**Answer:** ✅ **Yes**

**Reason:** Optional Firebase Analytics collects app interaction data

---

### Section 2: Data Collection

**Question:** What data does your app collect or share?

Go through each category:

#### ✅ App Activity (COLLECTED)

Select: **App interactions**

- **Is this data collected?** Yes
- **Is this data shared?** No
- **Is collection optional?** Yes (user must enable analytics)
- **Purpose:** Analytics
- **Ephemeral?** No

#### ✅ Diagnostics (COLLECTED)

Select: **Other app performance data**

- **Is this data collected?** Yes (Firebase automatically collects OS version, country via IP)
- **Is this data shared?** No
- **Is collection optional?** Yes (user must enable analytics)
- **Purpose:** Analytics
- **Ephemeral?** No

#### ❌ Location (NOT COLLECTED)

- Select: **No, this data type is not collected**

#### ❌ Personal Info (NOT COLLECTED)

**Critical:** Select **NO** for all subcategories:
- Name? NO
- Email address? NO
- User IDs? NO (party names are stored locally, not collected by us)
- Address? NO
- Phone number? NO
- Race and ethnicity? NO
- Political or religious beliefs? NO
- Sexual orientation? NO
- Other info? NO

**Why NO?**
- Party names/contacts are stored *locally only*
- Never transmitted to your servers
- "Collected" means sent to YOU, not just stored on device

#### ❌ Financial Info (NOT COLLECTED)

**Critical:** Select **NO** for all subcategories:
- User payment info? NO
- Purchase history? NO
- Credit score? NO
- Other financial info? NO

**Why NO?**
- Transaction amounts stored *locally only*
- Credit/udhar data never leaves device
- SMS content parsed locally, not transmitted
- "Collected" means sent to backend — we have no backend for financial data

#### ❌ Messages (NOT COLLECTED)

- Emails? NO
- SMS or MMS? NO
- Other in-app messages? NO

**Why NO?**
- SMS is read locally with permission
- Content is parsed on-device
- Raw SMS text never sent to your servers
- This is NOT collection, it's local processing

#### ❌ Photos and Videos (NOT COLLECTED)

- Photos? NO
- Videos? NO

#### ❌ Audio Files (NOT COLLECTED)

- Voice or sound recordings? NO
- Music files? NO
- Other audio files? NO

#### ❌ Files and Docs (NOT COLLECTED)

- Files and docs? NO

#### ❌ Calendar (NOT COLLECTED)

- Calendar events? NO

#### ❌ Contacts (NOT COLLECTED)

- Contacts? NO

**Why NO?**
- Contacts imported are stored *locally* in SQLite
- Never transmitted to your servers
- Optional feature, user-initiated
- Not "collection" by your app

#### ❌ App Info and Performance (Mostly NO)

- Crash logs? NO (you don't use Crashlytics)
- Diagnostics? YES (covered above in Diagnostics section)
- Other app performance data? YES (covered above)

#### ❌ Device or Other IDs (NOT COLLECTED)

- Device or other IDs? NO

**Why NO?**
- Firebase generates instance IDs internally
- You don't use them for tracking/attribution
- Analytics is anonymous

#### ❌ Web Browsing (NOT COLLECTED)

- Web browsing history? NO

---

### Section 3: Data Security

**Question:** Is all of the user data collected by your app encrypted in transit?

**Answer:** ✅ **Yes**

**Reason:** Firebase Analytics uses HTTPS

---

**Question:** Do you provide a way for users to request that their data be deleted?

**Answer:** ✅ **Yes**

**Explanation:**  
"Users can disable analytics in Settings → Privacy → Anonymous Analytics. Once disabled, no further data is collected. Previously collected anonymous analytics data is retained by Firebase per their retention policy (typically 2 months), but users can contact support to request manual deletion."

---

### Section 4: Data Usage and Handling

For each data type you marked as collected:

#### App Interactions

- **Purpose:** Analytics
- **Is this data shared?** No
- **Can users choose whether this data is collected?** Yes
- **Data encrypted in transit?** Yes
- **Can users request deletion?** Yes

#### Diagnostics / Other App Performance Data

- **Purpose:** Analytics
- **Is this data shared?** No
- **Can users choose whether this data is collected?** Yes
- **Data encrypted in transit?** Yes
- **Can users request deletion?** Yes

---

## ✅ Summary of What You're Declaring

**Collected (opt-in only):**
1. App interactions (which screens opened, which features used)
2. App diagnostics (OS version, country from IP — automatically by Firebase)

**NOT Collected:**
- ❌ Transaction amounts
- ❌ Party names
- ❌ Financial data
- ❌ SMS content
- ❌ Contacts
- ❌ Location
- ❌ Personal info (email, phone, name)
- ❌ Device IDs (for tracking)

**Key Points:**
- Analytics is OFF by default
- User must explicitly enable it
- Only feature usage tracked (no financial data)
- Data encrypted in transit (HTTPS)
- Users can disable anytime

---

## 🚨 Common Mistakes to Avoid

### ❌ DON'T mark SMS as "collected"
- You read SMS locally with permission
- You parse it on-device
- You don't send SMS content to servers
- This is LOCAL PROCESSING, not collection

### ❌ DON'T mark contacts as "collected"
- Contacts are imported and stored locally in SQLite
- Never transmitted to your backend
- Google defines "collect" as send to developer/backend

### ❌ DON'T mark financial info as "collected"
- Transaction amounts stay on device
- Credit/udhar data never leaves phone
- Local storage ≠ collection

### ❌ DON'T mark device IDs as "collected"
- Firebase may generate IDs internally
- If not used for ads/tracking, don't declare
- Anonymous analytics doesn't require declaring IDs

### ✅ DO mark app interactions & diagnostics
- Firebase Analytics collects which screens are viewed
- Automatically collects OS version and country
- Be transparent about this

---

## 📊 What Users Will See

On your Play Store listing:

**Data safety:**

> **No data shared with third parties**  
> This app may collect App interactions and Diagnostics, and this data is not shared with third parties  
> *Data collection and usage*  
> App interactions — Optional  
> Diagnostics — Optional  
> *Security practices*  
> Data is encrypted in transit  
> You can request that data be deleted

---

## 🔍 Validation Checklist

Before submitting:

- [ ] Only declared: App interactions + Diagnostics
- [ ] Marked both as "optional" (user must enable)
- [ ] NOT declared: Financial info, SMS, Contacts, Location
- [ ] Security practices mention encryption + deletion
- [ ] Explanation says analytics is off by default

---

## 📞 If Google Asks Questions

**"Why do you request SMS permission?"**
> "SMS permission is used solely for local, on-device parsing of financial transaction notifications (UPI, bank SMS) to help users auto-capture expenses. SMS content is never transmitted to our servers. This is optional — users can decline the permission and manually enter transactions."

**"Why do you request Contacts permission?"**
> "Contacts permission is optional and only used when the user explicitly chooses to import party names or save invoice recipients. All contact data is stored locally in SQLite on the device and is never transmitted to our servers."

**"You declared Financial Info as not collected, but you track transactions?"**
> "Transactions, amounts, and financial data are stored locally on the user's device in SQLite. We never transmit this data to our servers or any third party. 'Collected' per Google's definition means sent to the developer's backend — we have no backend for financial data."

---

**Time to complete:** 15-20 minutes  
**Review before submitting:** 5 minutes  
**Total:** ~25 minutes

---

✅ **Form complete! Next: Submit for review**
