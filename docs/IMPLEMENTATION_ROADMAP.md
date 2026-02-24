# Implementation Roadmap
# Kash Cube Development Plan

**Version:** 1.0  
**Date:** February 24, 2026  
**Duration:** 6 months (26 weeks)

---

## Overview

This roadmap follows a **core-first, iterative approach**:
1. Build minimal core (Weeks 1-6)
2. Self-test for 2 weeks
3. Scale with essential features (Weeks 7-10)
4. Beta test (Weeks 11-14)
5. Launch & grow (Weeks 15-26)

---

## Phase 1: Core MVP (Weeks 1-6)

### Week 1-2: Transaction Foundation

#### Week 1: Project Setup & SMS Reading
**Goal:** Get basic SMS parsing working

**Tasks:**
- [x] Set up Flutter project structure
- [x] Configure SQLite database
- [x] Implement SMS permissions (Android)
- [x] Create SMS listener service
- [x] Parse basic UPI SMS (PhonePe, GPay)
- [ ] Test with real SMS from personal phone

**Deliverables:**
- Flutter app that can read and parse UPI SMS
- Extract: amount, merchant, date, type (sent/received)

**Time Estimate:** 40 hours

#### Week 2: Transaction UI
**Goal:** Display and add transactions

**Tasks:**
- [x] Design transaction data model
- [x] Create transaction list UI
- [x] Build add transaction screen (manual entry)
- [x] Implement transaction detail view
- [x] Add edit/delete functionality
- [x] Basic category dropdown
- [x] Bill/receipt attachment support (photo + PDF, per transaction)

**Deliverables:**
- Transaction list displaying parsed SMS
- Manual entry form for cash transactions
- CRUD operations working

**Time Estimate:** 40 hours

---

### Week 3-4: Intelligence & Credit System

#### Week 3: Smart Categorization & Business Mode
**Goal:** Auto-suggest categories and separate business/personal

**Tasks:**
- [x] Implement merchant-based categorization logic
- [x] Add business/personal toggle to transactions
- [x] Create quick confirmation dialog after SMS detection
- [x] Build daily summary dashboard
- [x] Implement smart suggestions based on history
- [x] Add transaction filters (today, week, month)

**Deliverables:**
- Auto-categorization working (80%+ accuracy)
- Quick confirm flow (<10 seconds)
- Dashboard showing daily income/expense/profit

**Time Estimate:** 40 hours

#### Week 4: Credit Management (Udhar)
**Goal:** Track credits given and received

**Tasks:**
- [x] Design credit record data model (with direction, payments)
- [x] Create "Give/Receive Credit" screen
- [x] Build collections dashboard (pending credits with filters)
- [x] Implement customer profile view
- [x] Build payment history per customer
- [x] Record payment screen with quick amount buttons

**Deliverables:**
- Can record credit given to/received from customers
- Collections dashboard with pending/overdue/cleared filters
- Customer profiles with full credit history
- Payment recording with method tracking
- DB migration v3: credit_payments table + direction column

**Time Estimate:** 40 hours

---

### Week 5-6: Essential Polish

#### Week 5: Reports & Search
**Goal:** Make data actionable

**Tasks:**
- [x] Build monthly report with P&L
- [x] Add category breakdown charts (pie charts with fl_chart)
- [x] Implement search functionality (global search screen)
- [x] Add filters (date, category, mode, type, payment method)
- [x] Add monthly trend bar chart (last 6 months)
- [x] Add loan tracking (basic model, repo, screen, payments)

**Deliverables:**
- Monthly reports showing profit/loss with month selector
- Category breakdown pie charts (income & expense)
- Monthly trend bar chart with income/expense comparison
- Top parties list by transaction volume
- Global search across transactions and credits
- Advanced transaction filters (type, category, payment method)
- Full loan tracking (add, pay, delete, detail, overdue/cleared tabs)
- Loans accessible via Home screen quick action

**Time Estimate:** 40 hours

#### Week 6: Data & Security
**Goal:** Backup and security essentials

**Tasks:**
- [x] Implement database backup/restore
- [x] Add CSV export functionality
- [x] Build PIN lock screen
- [x] Add biometric authentication
- [x] Implement recurring transactions
- [x] Fix critical bugs from testing

**Deliverables:**
- Database backup/restore via BackupService (copy/share .db files)
- CSV export with share sheet integration
- PIN lock screen (4-digit, setup/confirm/unlock/remove flows)
- Biometric authentication (fingerprint/face) via local_auth
- App lock gate on launch with auto biometric attempt
- Recurring transactions (model, repo, provider, screen, auto-generation)
- Settings screen fully wired: PIN toggle, biometric toggle, backup, restore, export
- Recurring quick action on Home screen
- MVP ready for daily use

**Time Estimate:** 40 hours

---

## ✅ End of Phase 1 Checkpoint

### Self-Test Period (2 weeks)
**Goal:** Use Kash Cube exclusively for personal finances

**Activities:**
- Use app for all financial tracking
- Note every friction point
- Test with different SMS patterns
- Measure: Do I open it 5+ times per day?
- Validate: Can I close my manual tracking sheet?

**Success Criteria:**
- ✅ 90%+ transactions auto-captured
- ✅ <10 sec to confirm transaction
- ✅ Daily dashboard gives instant insight
- ✅ Zero major bugs
- ✅ I genuinely depend on it

**Decision Point:**
- **If success criteria met:** Proceed to Phase 2
- **If not:** Iterate on core untilmet

---

## Phase 2: Scale Features (Weeks 7-10)

### Week 7: Money Management
**Goal:** Add budget tracking and savings goals

**Tasks:**
- [ ] Implement category-wise budgets
- [ ] Add budget vs actual tracking
- [ ] Build budget alerts (80%, 100%,exceeded)
- [ ] Create savings goals feature
- [ ] Add spending insights
- [ ] Build weekly summary email/notification

**Deliverables:**
- Can set monthly budgets per category
- Alerts when approaching limit
- Visual progress on savings goals

**Time Estimate:** 40 hours

---

### Week 8: Complete Financial View
**Goal:** Parse all financial SMS, not just UPI

**Tasks:**
- [ ] Add credit card SMS parsing (HDFC, ICICI, SBI, Axis)
- [ ] Add debit card SMS parsing
- [ ] Add bank account SMS parsing (NEFT, RTGS, balance updates)
- [ ] Implement account management (track multiple accounts)
- [ ] Add duplicate transaction detection
- [ ] Build account balance tracking

**Deliverables:**
- Parses SMS from major banks and cards
- Tracks balances across accounts
- Eliminates duplicate entries

**Time Estimate:** 45 hours

---

### Week 9: Smart Features
**Goal:** Handle edge cases and advanced scenarios

**Tasks:**
- [ ] Add refund tracking and linking
- [ ] Implement failed transaction tracking
- [ ] Add cashback detection and tracking
- [ ] Build merchant intelligence (spending patterns)
- [ ] Add ATM withdrawal tracking
- [ ] Implement wallet balance tracking (Paytm, Amazon Pay)
- [ ] Receipt scanning via on-device ML Kit OCR (Indian receipt layouts)

**Deliverables:**
- Refunds link back to original transactions
- Cashback tracked separately
- Complete picture of all money movement
- Auto-extract amount + store from photographed receipts (cash transactions)

**Time Estimate:** 40 hours

---

### Week 10: UX Polish
**Goal:** Make experience delightful

**Tasks:**
- [ ] Build home screen widget (Android)
- [ ] Add quick actions (long-press app icon)
- [ ] Implement voice input for manual entry
- [ ] Add calculator in amount fields
- [ ] Build net worth dashboard
- [ ] Add spending pattern insights
- [ ] Performance optimization (handle 10k+ transactions)

**Deliverables:**
- Widget shows quick stats
- Voice: "Add 500 rupees food"
- Fast even with large dataset

**Time Estimate:** 40 hours

---

## ✅ End of Phase 2 Checkpoint

### Feature Validation (1 week)
**Goal:** Validate scaled features with 10-20 beta users

**Activities:**
- Recruit friends/family as testers
- Collect usage data (crash-free, feature usage)
- Gather qualitative feedback
- Measure retention (Day 1, 3, 7)

**Success Criteria:**
- ✅ 70%+ Day-7 retention
- ✅ No critical bugs
- ✅ Positive NPS from beta users
- ✅ At least 3 features users "can't live without"

**Decision Point:**
- **If validated:** Prepare for public beta
- **If not:** Iterate based on feedback

---

## Phase 3: Beta Release (Weeks 11-14)

### Week 11: Beta Preparation
**Goal:** Prepare for wider testing

**Tasks:**
- [ ] Create comprehensive onboarding flow
- [ ] Write in-app help documentation
- [ ] Set up crash reporting (local logging only)
- [ ] Build feedback mechanism
- [ ] Create beta test plan
- [ ] Prepare beta distribution (Play Store Beta)

**Deliverables:**
- Smooth onboarding (<60 sec)
- In-app help for all features
- Beta track on Play Store

**Time Estimate:** 35 hours

---

### Week 12: Beta Launch
**Goal:** Get to 50-100 beta testers

**Tasks:**
- [ ] Launch TestFlight/Play Store Beta
- [ ] Write launch post for beta community
- [ ] Create demo video
- [ ] Set up feedback channels (Telegram/Discord)
- [ ] Monitor crashes and bugs
- [ ] Daily bug fixes and improvements

**Deliverables:**
- 50+ beta testers onboarded
- Feedback loop established
- Critical bugs identified and fixed

**Time Estimate:** 40 hours

---

### Week 13-14: Beta Iteration
**Goal:** Polish based on real-world usage

**Tasks:**
- [ ] Analyze user feedback and pain points
- [ ] Fix top 10 reported bugs
- [ ] Optimize most-used flows
- [ ] Improve SMS parsing accuracy
- [ ] Add missing bank/UPI patterns
- [ ] Performance optimization
- [ ] Prepare Play Store listing

**Deliverables:**
- Stable build with <1% crash rate
- 90%+ SMS parsing accuracy
- Play Store listing ready (screenshots, description)

**Time Estimate:** 60 hours

---

## Phase 4: Public Launch (Weeks 15-18)

### Week 15: Launch Preparation
**Goal:** Prepare for public release

**Tasks:**
- [ ] Finalize Play Store listing
- [ ] Create marketing materials
- [ ] Write launch blog post
- [ ] Prepare social media content
- [ ] Set up analytics (privacy-friendly)
- [ ] Create demo videos and screenshots
- [ ] Build landing page

**Deliverables:**
- Play Store submission ready
- Marketing collateral complete
- Landing page live

**Time Estimate:** 40 hours

---

### Week 16: Public Launch 🚀
**Goal:** Launch on Play Store

**Tasks:**
- [ ] Submit to Play Store
- [ ] Launch on Product Hunt
- [ ] Post on Reddit (r/india, r/india investments)
- [ ] Tweet launch announcement
- [ ] Email beta users
- [ ] Monitor reviews and respond
- [ ] Track downloads and retention

**Deliverables:**
- Live on Play Store
- Initial reviews and ratings
- 1,000+ downloads (target)

**Time Estimate:** 30 hours (plus monitoring)

---

### Week 17-18: Post-Launch Support
**Goal:** Stabilize and iterate

**Tasks:**
- [ ] Monitor crash reports daily
- [ ] Fix critical bugs within 24 hours
- [ ] Respond to all Play Store reviews
- [ ] Analyze user behavior
- [ ] Identify drop-off points
- [ ] Optimize onboarding if <50% completion
- [ ] Plan next features based on requests

**Deliverables:**
- Stable release (v1.0.1, v1.0.2)
- <1% crash rate
- 60%+ onboarding completion
- Roadmap for next features

**Time Estimate:** 60 hours

---

## Phase 5: Growth & Monetization (Weeks 19-26)

### Week 19-20: Pro Features
**Goal:** Build monetization features

**Tasks:**
- [ ] Implement in-app purchase (Google Play Billing)
- [ ] Build Pro upgrade flow
- [ ] Add advanced reports (Pro only)
- [ ] Add GST reports (Pro only)
- [ ] Implement PDF export with branding
- [ ] Add budget tracking to Pro tier
- [ ] Test payment flow thoroughly

**Deliverables:**
- Pro plan available for purchase
- Upgrade flow smooth
- Pro features working

**Time Estimate:** 50 hours

---

### Week 21-22: Business Features
**Goal:** Add features for business users

**Tasks:**
- [ ] Build invoice generation
- [ ] Add customer management (advanced)
- [ ] Implement payment reminders (SMS/WhatsApp templates)
- [ ] Add multi-user profiles
- [ ] Build accountant view
- [ ] Add inventory tracking (basic)

**Deliverables:**
- Business Pro plan features ready
- Invoice generation working
- Multi-user access functional

**Time Estimate:** 60 hours

---

### Week 23-24: Growth Features
**Goal:** Improve retention and virality

**Tasks:**
- [ ] Add referral program
- [ ] Build import from other apps
- [ ] Add bank statement CSV import
- [ ] Implement smart notifications
- [ ] Build comparison reports (month-over-month)
- [ ] Add spending predictions

**Deliverables:**
- Referral program live
- CSV import working
- Improved retention features

**Time Estimate:** 50 hours

---

### Week 25-26: Scale & Optimize
**Goal:** Prepare for growth

**Tasks:**
- [ ] Performance optimization for 50k+ transactions
- [ ] Build admin dashboard (internal)
- [ ] Add Hindi language support
- [ ] Implement regional language framework
- [ ] Optimize app size (<20MB)
- [ ] Add advanced analytics
- [ ] Plan iOS version

**Deliverables:**
- App handles scale gracefully
- Hindi support live
- iOS development plan ready

**Time Estimate:** 60 hours

---

## Success Milestones

| Milestone | Target Date | Success Metric |
|-----------|-------------|----------------|
| MVP Complete | Week 6 | Daily use by developer |
| Beta Launch | Week 12 | 50 beta users, 70% retention |
| Public Launch | Week 16 | 1,000 downloads |
| First 10,000 users | Week 22 | 10,000 installs, 60% retention |
| Pro Launch | Week 20 | 100 paying users |
| Profitability | Week 26 | ₹50,000/month revenue |

---

## Resource Allocation

### Development Time (26 weeks)
- **Core Development:** 1,000 hours
- **Testing:** 150 hours
- **Bug Fixes:** 100 hours
- **Marketing/Content:** 50 hours
- **Total:** ~1,300 hours

### Team (Initial)
- **Solo Developer:** Core development
- **Beta Testers:** 50-100 volunteers
- **Advisors:** 2-3 for feedback

### Budget (Bootstrap Friendly)
- **Development:** ₹0 (self-developed)
- **Design Assets:** ₹5,000 (icons, graphics)
- **Play Store Fee:** $25 one-time
- **Domain/Hosting:** ₹2,000/year
- **Total Year 1:** <₹10,000

---

## Risk Mitigation

### Technical Risks
- **Risk:** SMS parsing accuracy <90%
  - **Mitigation:** Extensive testing; user feedback loop; pattern database
- **Risk:** Performance issues with large datasets
  - **Mitigation:** Performance testing from Week 1; pagination; indexing

### Product Risks
- **Risk:** Users don't find it useful
  - **Mitigation:** Self-dogfooding; early beta testing; iterate based on feedback
- **Risk:** Competition copies features
  - **Mitigation:** Focus on privacy and UX; build loyal community; open source advantage

### Business Risks
- **Risk:** Low monetization
  - **Mitigation:** Freemium model; multiple tiers; one-time purchase option
- **Risk:** Play Store rejection
  - **Mitigation:** Follow guidelines strictly; clear SMS permission explanation; privacy policy

---

## Decision Points

### After Phase 1 (Week 6)
**Question:** Is the core MVP useful enough for daily use?
- **Yes:** Proceed to Phase 2
- **No:** Iterate on core features

### After Phase 2 (Week 10)
**Question:** Do beta users find it valuable?
- **Yes:** Proceed to public launch
- **No:** Pivot or improve based on feedback

### After Phase 4 (Week 18)
**Question:** Is there product-market fit?
- **Yes:** Invest in growth and monetization
- **No:** Re-evaluate product direction

---

## Next Steps

### This Week
1. ✅ Complete documentation
2. ✅ Set up development environment
3. ✅ Create Flutter project structure
4. ✅ Week 1 tasks (SMS reading) — complete
5. ✅ Week 2 tasks (Transaction UI) — complete
6. ✅ Week 3 tasks (Smart categorization, filters, confirmation flow) — complete
7. ✅ Week 4 tasks (Credit management / Udhar) — complete
8. ✅ Week 5 tasks (Reports & Search) — complete
9. ✅ Week 6 tasks (Data & Security) — complete
10. Begin self-test period

### This Month (Weeks 1-6)
- ✅ Complete transaction foundation (Week 1-2)
- ✅ Build credit management (Week 3-4)
- ✅ Reports, search, filters, loan tracking (Week 5)
- ✅ Backup, PIN lock, biometric, recurring transactions (Week 6)
- ✅ Phase 1 MVP — Complete
- Begin self-test period

### Overall Progress
| Week | Status | Key Deliverables |
|------|--------|-----------------|
| Week 1 | ✅ Complete (5/6) | SMS parser, DB schema, SMS listener |
| Week 2 | ✅ Complete (7/7) | Transaction CRUD, bill attachments |
| Week 3 | ✅ Complete (6/6) | Auto-categorization, SMS confirmation, filters |
| Week 4 | ✅ Complete (6/6) | Credit give/receive, collections dashboard, customer profiles |
| Week 5 | ✅ Complete (6/6) | Reports with charts, global search, advanced filters, loan tracking |
| Week 6 | ✅ Complete (6/6) | Backup/restore, CSV export, PIN lock, biometric auth, recurring transactions |

**Codebase:** 68 Dart files in `lib/`, 0 lint issues  
**Database:** SQLite v3 (10+ tables including credit_payments, recurring_transactions, settings)  
**Phase 1 MVP:** COMPLETE

### This Quarter (Weeks 1-12)
- Launch MVP
- Scale features
- Beta release

---

## Appendix

### Development Tools
- **IDE:** VS Code with Flutter extensions
- **Version Control:** Git + GitHub
- **Database:** SQLite (sqflite package)
- **State Management:** Riverpod (vs Provider)
- **Testing:** Flutter test framework
- **CI/CD:** GitHub Actions (for automated testing)

### Key Dependencies
```yaml
dependencies:
  flutter:
    sdk: flutter
  sqflite: ^2.3.0
  path_provider: ^2.1.1
  riverpod: ^2.4.0
  telephony: ^0.2.0  # SMS reading
  fl_chart: ^0.66.0  # Charts
  intl: ^0.19.0  # Date formatting
  local_auth: ^2.1.7  # Biometric
  path: ^1.8.3
```

### Performance Targets
- App launch: <2 seconds
- Transaction list (1000 items): 60 FPS scroll
- Search 10k transactions: <100ms
- SMS parsing: <500ms
- Database query: <50ms average

---

**Next Document:** [Technical Architecture](./TECHNICAL_ARCHITECTURE.md)
