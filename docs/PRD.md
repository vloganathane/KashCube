# Product Requirements Document (PRD)
# Kash Cube - Privacy-First Financial Tracker for India

**Version:** 1.0  
**Date:** February 24, 2026  
**Status:** Planning Phase  
**Author:** Loganathan EV

---

## 1. Executive Summary

### 1.1 Product Vision
Kash Cube is a privacy-first financial tracking application specifically designed for the Indian market, focusing on small business owners and individuals who use UPI for daily transactions. The app automatically captures financial transactions from SMS, manages customer credits (udhar), tracks loans, and provides complete financial visibility—all while keeping data 100% local on the device.

### 1.2 Problem Statement
**Who:** Small business owners, freelancers, and privacy-conscious individuals in India  
**Problem:** Struggle to track mixed personal and business finances across multiple UPI apps, manually maintain credit records (khata), and fear sharing bank credentials with apps  
**Current Solutions:** Either too complex (accounting software), too simple (expense trackers), or privacy-invasive (bank linking required)

### 1.3 Solution
A mobile app that:
- Auto-captures transactions from UPI, bank, and credit card SMS (local parsing)
- Intelligently categorizes income and expenses
- Tracks credits given to customers and loans taken
- Auto-links repayments to outstanding credits
- Separates personal and business finances
- Provides daily business dashboard
- **Never uploads data to cloud** (privacy-first)

### 1.4 Success Metrics
- 90%+ transaction auto-capture rate
- <10 seconds to confirm a transaction
- Daily active usage (5+ opens per day)
- Zero manual entry for UPI transactions
- User willing to pay for the app

---

## 2. Target Market

### 2.1 Primary Target Users
1. **Small Business Owners** (60% of target)
   - Kirana stores with UPI QR codes
   - Street food vendors
   - Beauty salons, barber shops
   - Tailors, cobblers, local services
   - Small online sellers
   
2. **Freelancers & Gig Workers** (25% of target)
   - Designers, developers, consultants
   - Delivery partners, cab drivers
   - Home tutors, coaches
   - Content creators

3. **Privacy-Conscious Individuals** (15% of target)
   - Don't trust bank-linking apps
   - Want complete financial visibility
   - Tech-savvy users who value data ownership

### 2.2 Market Size (India)
- UPI users: 500M+ (growing)
- Small businesses: 63M
- Freelancers: 15M+
- Target addressable market: 25M users (5% penetration)

### 2.3 Geographic Focus
- **Phase 1:** Metro cities (Bangalore, Mumbai, Delhi, Hyderabad)
- **Phase 2:** Tier 2 cities
- **Phase 3:** Tier 3 towns and rural

---

## 3. Product Goals & Objectives

### 3.1 Primary Goals
1. **Eliminate manual expense tracking** through SMS auto-capture
2. **Digitize the traditional khata** (credit ledger book)
3. **Provide complete financial visibility** across all payment methods
4. **Maintain 100% privacy** with local-only data storage

### 3.2 Key Objectives (6 months)
- Launch Android MVP with core features
- Achieve 10,000 active users
- 70% Day-7 retention rate
- 4.5+ app store rating
- 10% conversion to Pro plan

### 3.3 Non-Goals (Initial Phase)
- ❌ Investment portfolio tracking
- ❌ Full accounting software features
- ❌ Tax filing automation
- ❌ Bill payment integration
- ❌ Social features or comparison with others

---

## 4. User Personas

### Persona 1: Rajesh - Kirana Store Owner
**Age:** 35  
**Location:** Bangalore  
**Tech Savvy:** Medium  
**Income:** ₹50,000/month  

**Pain Points:**
- Maintains physical khata, easy to lose
- Forgets who owes money
- Can't separate shop income from personal expenses
- Awkward to ask customers for payment

**Goals:**
- Track all business income and expenses
- Know exactly who owes how much
- Send professional payment reminders
- Understand daily profit

**Usage Pattern:**
- 30-50 transactions per day
- Gives credit to 10-15 regular customers
- Uses PhonePe and GPay
- Checks app 5-10 times daily

### Persona 2: Priya - Freelance Designer
**Age:** 28  
**Location:** Mumbai  
**Tech Savvy:** High  
**Income:** ₹80,000/month  

**Pain Points:**
- Client payments scattered across UPI apps
- Needs separate business expense tracking for taxes
- Current apps require bank linking (privacy concern)
- No good way to track pending invoices

**Goals:**
- Automatic transaction capture
- Clear business vs personal separation
- Tax-ready reports
- Privacy-first solution

**Usage Pattern:**
- 10-20 transactions per day
- 5-8 clients with pending payments
- Uses HDFC credit card + UPI
- Reviews finances weekly

### Persona 3: Amit - Privacy Advocate
**Age:** 32  
**Location:** Delhi  
**Tech Savvy:** Very High  
**Income:** ₹1,20,000/month  

**Pain Points:**
- Doesn't trust apps with bank credentials
- Wants to audit app's data usage
- Existing apps are closed-source black boxes
- No good open-source alternative

**Goals:**
- Complete data ownership
- Verifiable privacy (open source)
- No cloud dependency
- Export anytime

**Usage Pattern:**
- 15-25 transactions per day
- Primarily personal use
- Multiple banks and credit cards
- Tech enthusiast, will contribute code

---

## 5. Core Features (MVP)

### 5.1 Transaction Management

#### 5.1.1 Automatic SMS Capture
- **Description:** Automatically detect and parse financial SMS from UPI apps, banks, and credit cards
- **Priority:** P0 (Critical)
- **User Story:** "As a user, I want my transactions to be automatically captured from SMS so I don't have to manually enter them"

**Acceptance Criteria:**
- ✅ Parse UPI SMS (PhonePe, GPay, Paytm, BHIM)
- ✅ Extract: amount, merchant/person, date, UPI ref
- ✅ Distinguish between money sent and received
- ✅ Show notification with quick confirm/edit/ignore
- ✅ 90%+ accuracy in parsing
- ✅ Handle malformed SMS gracefully

#### 5.1.2 Transaction Types
- Income (Business)
- Income (Personal)
- Expense (Business)
- Expense (Personal)
- Credit Given (Udhar)
- Credit Received (Repayment)
- Loan Taken
- Loan Repayment

#### 5.1.3 Smart Categorization
- **Description:** Automatically suggest category based on merchant name
- **Priority:** P0 (Critical)

**Categories:**

**Business Income:**
- Product Sales
- Service Fees
- Consultation
- Other

**Business Expense:**
- Inventory/Stock
- Rent
- Utilities
- Transportation
- Marketing
- Other

**Personal:**
- Food & Dining
- Groceries
- Transport
- Shopping
- Bills
- Entertainment
- Health
- Education
- Other

#### 5.1.4 Manual Entry
- **Description:** Add transactions manually for cash or missed SMS
- **Priority:** P0 (Critical)
- Quick entry form with smart defaults

### 5.2 Credit Management (Udhar/Khata)

#### 5.2.1 Give Credit
- **Description:** Record when customer takes goods/services on credit
- **Priority:** P0 (Critical)

**Fields:**
- Customer name (autocomplete existing)
- Amount
- Due date (optional)
- Interest rate (optional)
- Notes

#### 5.2.2 Auto-Link Repayments
- **Description:** When money is received from customer with pending credit, suggest linking to credit
- **Priority:** P0 (Critical)

**Flow:**
1. SMS: "Received ₹500 from Ramesh"
2. Check: Does Ramesh have pending credit?
3. Show: "Apply ₹500 to Ramesh's ₹4,000 credit?"
4. User confirms → Pending reduced to ₹3,500

#### 5.2.3 Collections Dashboard
- **Description:** View all pending credits with status
- **Priority:** P0 (Critical)

**Features:**
- Overdue credits (highlighted in red)
- Due soon (yellow)
- Total outstanding amount
- Sort by: amount, date, customer
- Customer detail view with payment history

### 5.3 Loan Management

#### 5.3.1 Record Loan
- **Description:** Track loans taken from friends, family, or lenders
- **Priority:** P1 (Important)

**Fields:**
- Lender name
- Principal amount
- Interest rate
- Repayment schedule (EMI or lumpsum)
- Due date

#### 5.3.2 EMI Tracking
- Auto-mark EMI when payment made
- Track remaining EMIs
- Calculate interest
- Next EMI reminder

### 5.4 Business Dashboard

#### 5.4.1 Daily Summary
- **Priority:** P0 (Critical)

**Display:**
- Today's income (count + amount)
- Today's expense (count + amount)
- Net profit/loss
- Pending collections (total amount)
- Next loan EMI due

#### 5.4.2 Quick Stats
- This week summary
- This month summary
- Top customers
- Top expense categories

### 5.5 Reports

#### 5.5.1 Daily Report
- Transaction list
- Income vs Expense
- Running balance

#### 5.5.2 Monthly Report
- Category-wise breakdown
- Income vs Expense trend
- Top merchants/customers
- Profit & Loss statement

#### 5.5.3 Yearly Report
- Month-by-month comparison
- Yearly totals
- Growth trends

### 5.6 Search & Filter
- **Priority:** P0 (Critical)

**Search by:**
- Merchant/customer name
- Amount (range)
- Category
- Date range
- Transaction type
- Payment method

### 5.7 Data Management

#### 5.7.1 Backup & Export
- **Priority:** P0 (Critical)

**Options:**
- Export database file
- Export CSV (Excel-compatible)
- Export PDF report
- Import from backup

#### 5.7.2 Recurring Transactions
- **Priority:** P1 (Important)

**Features:**
- Set recurring income (salary)
- Set recurring expenses (rent, subscriptions)
- Auto-add on schedule
- Edit/skip/delete occurrence

### 5.8 Security

#### 5.8.1 App Lock
- **Priority:** P0 (Critical)

**Features:**
- PIN lock (4-6 digits)
- Biometric lock (fingerprint/face)
- Auto-lock after inactivity
- Lock on app switch

---

## 6. Technical Requirements

### 6.1 Platform
- **Primary:** Android (95% of target market)
- **Future:** iOS, Web

### 6.2 Minimum Requirements
- Android 8.0+ (API 26+)
- 100 MB storage
- SMS read permission
- No internet required (offline-first)

### 6.3 Performance
- App launch: <2 seconds
- Transaction list scroll: 60 FPS
- SMS parsing: <500ms
- Search: <100ms for 10,000 transactions
- Database operations: <50ms

### 6.4 Privacy Requirements
- ✅ All data stored locally (SQLite)
- ✅ No network requests by default
- ✅ No analytics or tracking
- ✅ No user accounts required
- ✅ Open source codebase
- ✅ SMS parsing on-device only
- ✅ Optional encrypted backup

---

## 7. User Experience Requirements

### 7.1 Onboarding
**Goal:** Get user tracking in <60 seconds

**Flow:**
1. Welcome screen (5 sec)
2. SMS permission request with clear explanation (10 sec)
3. Choose mode: Personal / Business / Both (5 sec)
4. Scan SMS: Import last 30 days (15 sec)
5. Review sample transactions (20 sec)
6. Done! → Dashboard (5 sec)

### 7.2 Daily Usage Pattern
**Primary Flow (10 seconds):**
1. Make UPI payment
2. SMS arrives → App notification
3. Tap notification → Quick confirm screen
4. Tap "✓ Business Expense - Food" → Done

**Alternate Flow (Cash/Manual):**
1. Tap [+ Add]
2. Amount → Category → Save (15 sec)

### 7.3 Design Principles
1. **Privacy-First UI:** Always show "Local only, no cloud"
2. **Speed:** Every action <2 taps
3. **Smart Defaults:** Pre-fill based on context
4. **Forgiving:** Easy undo/edit
5. **Progressive Disclosure:** Advanced features hidden until needed

### 7.4 Accessibility
- Support system font sizes
- High contrast mode
- Screen reader compatible
- Hindi language support (future)

---

## 8. Monetization Strategy

### 8.1 Free Tier (Forever Free)
- Unlimited transactions
- Unlimited SMS parsing
- Basic categories
- Daily/Monthly reports
- Backup to device
- Single user

### 8.2 Pro Plan (₹199/year or ₹29/month)
- Advanced reports (yearly trends)
- Unlimited customer/vendor tracking
- GST reports
- PDF export with branding
- Recurring transactions
- Budget tracking
- Priority support

### 8.3 Business Pro (₹699/year or ₹99/month)
- Everything in Pro
- Multi-user access (3 users)
- Invoice generation
- Inventory tracking (basic)
- Accountant read-only access
- WhatsApp/SMS reminders

### 8.4 One-Time Pro Unlock (₹1,499)
- Lifetime Pro features
- Support indie development
- Pay once, own forever

### 8.5 Revenue Projections (Conservative)
**End of Year 1:**
- Free users: 50,000
- Pro conversion: 5% = 2,500 users
- Business Pro: 2% = 1,000 users
- Revenue: ₹2,500 × ₹199 + ₹1,000 × ₹699 = ₹11.97 lakhs/year

---

## 9. Success Criteria

### 9.1 Product-Market Fit Indicators
- ✅ 70%+ Day-7 retention
- ✅ NPS score >50
- ✅ 90%+ SMS parsing accuracy
- ✅ Users track 20+ transactions/week
- ✅ 4.5+ star rating on Play Store
- ✅ Organic word-of-mouth growth

### 9.2 Business Success
- 10,000 users in 6 months
- 5% Pro conversion rate
- ₹10 lakhs ARR by end of Year 1
- Featured on Play Store
- Positive press coverage

### 9.3 User Success
- User saves 30+ minutes per week
- Never misses a credit repayment
- Knows exact business profit daily
- Feels confident about data privacy
- Recommends to 3+ friends

---

## 10. Risks & Mitigations

### 10.1 Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| SMS parsing accuracy <90% | High | Medium | Extensive testing with real SMS; user feedback loop |
| Battery drain from SMS listening | High | Low | Optimize listeners; background restrictions |
| Database performance with 10k+ transactions | Medium | Low | Pagination; indexing; performance testing |
| Duplicate transaction detection fails | Medium | Medium | Hash-based deduplication; user confirmation |

### 10.2 Business Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Low adoption (privacy concerns) | High | Medium | Transparent privacy policy; open source; education |
| Competitors add SMS parsing | Medium | High | Focus on UX and privacy; build loyal user base |
| Google/UPI apps block SMS reading | High | Low | Lobby for user rights; provide manual fallback |
| Monetization fails | High | Low | Freemium model; optional features; community support |

### 10.3 Privacy Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Data breach (device stolen) | High | Low | App lock; optional encryption; remote wipe |
| SMS data misuse perception | Medium | Medium | Clear privacy policy; open source; audits |
| Government regulations change | Low | Low | Monitor policy; adapt; legal compliance |

---

## 11. Timeline & Milestones

### Phase 1: MVP (Weeks 1-6)
**Goal:** Core transaction tracking with credit management

**Milestones:**
- Week 2: SMS parsing working
- Week 4: Credit management complete
- Week 6: MVP ready for personal use

### Phase 2: Beta (Weeks 7-10)
**Goal:** Scale features and polish

**Milestones:**
- Week 8: Budget tracking added
- Week 10: Beta ready for 50 users

### Phase 3: Launch (Weeks 11-14)
**Goal:** Public release

**Milestones:**
- Week 12: Play Store submission
- Week 14: Public launch

### Phase 4: Growth (Weeks 15-26)
**Goal:** Feature completion and user growth

**Milestones:**
- Week 18: 1,000 users
- Week 22: Pro plan launch
- Week 26: 10,000 users

---

## 12. Open Questions

### 12.1 Product Questions
- [ ] Should we support multiple currencies from day 1?
- [ ] What's the ideal credit repayment flow?
- [ ] How to handle partial credit repayments?
- [ ] Should we allow custom categories?

### 12.2 Technical Questions
- [ ] Which state management: Provider vs Riverpod vs Bloc?
- [ ] Database encryption by default or optional?
- [ ] How to handle SMS from unknown banks?
- [ ] Background SMS processing or foreground only?

### 12.3 Business Questions
- [ ] Free tier limitations (if any)?
- [ ] Pricing for Business Pro tier?
- [ ] Partnerships with accounting software?
- [ ] Open core vs fully open source?

---

## 13. Appendix

### 13.1 Glossary
- **Udhar:** Hindi word for credit given to customers
- **Khata:** Traditional ledger book for credit records
- **UPI:** Unified Payments Interface (India's payment system)
- **Kirana:** Small neighborhood grocery store
- **EMI:** Equated Monthly Installment

### 13.2 References
- UPI Transaction Statistics: NPCI Reports 2025
- Small Business Census India 2024
- Mobile App Usage Patterns: Google India Reports

### 13.3 Version History
- v1.0 (Feb 24, 2026): Initial PRD
