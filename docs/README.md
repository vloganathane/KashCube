# Kash Cube — Documentation Index

**Last Updated:** March 22, 2026

```
docs/
├── README.md          ← you are here
├── user/              end-user guide
├── product/           PRD, design, UX, monetization
├── technical/         architecture, DB schema, privacy
├── features/          feature specifications
├── sync/              P2P sync, web companion, RBAC plan
├── planning/          roadmap, setup guide
├── legal/             privacy policy, terms
└── archive/           completed / superseded docs
```

---

## `user/`

| Document | Description |
|----------|-------------|
| [HOW_TO_USE.md](./user/HOW_TO_USE.md) | End-user guide — setup, all features, FAQ |

---

## `product/`

| Document | Description |
|----------|-------------|
| [PRD.md](./product/PRD.md) | Product Requirements Document — vision, personas, features |
| [SCREEN_FLOWS.md](./product/SCREEN_FLOWS.md) | Navigation map and user journey flows |
| [UI_UX_GUIDELINES.md](./product/UI_UX_GUIDELINES.md) | Design system, colors, spacing, components |
| [MONETIZATION_STRATEGY.md](./product/MONETIZATION_STRATEGY.md) | Revenue model and pricing |
| [COMPETITIVE_GAP_ANALYSIS.md](./product/COMPETITIVE_GAP_ANALYSIS.md) | Feature comparison vs competitors |

---

## `technical/`

| Document | Description |
|----------|-------------|
| [TECHNICAL_ARCHITECTURE.md](./technical/TECHNICAL_ARCHITECTURE.md) | System design, patterns, tech stack |
| [ARCHITECTURE_DECISIONS.md](./technical/ARCHITECTURE_DECISIONS.md) | ADRs — key architecture decisions (v58+) |
| [DUAL_PRIMARY_IDENTITY_SPEC.md](./technical/DUAL_PRIMARY_IDENTITY_SPEC.md) | Dual-primary sync identity spec (v63+) |
| [FEATURE_EXTENSION_PRINCIPLES.md](./technical/FEATURE_EXTENSION_PRINCIPLES.md) | Rules for extending the app safely |
| [DATABASE_SCHEMA.md](./technical/DATABASE_SCHEMA.md) | Full SQLite schema and data models |
| [PRIVACY_ARCHITECTURE.md](./technical/PRIVACY_ARCHITECTURE.md) | Privacy-first design — data residency, threat model |
| [FOUNDATION_PERSONAL_BUSINESS.md](./technical/FOUNDATION_PERSONAL_BUSINESS.md) | Personal / business mode architecture |
| [STORAGE_AND_DISASTER_MANAGEMENT.md](./technical/STORAGE_AND_DISASTER_MANAGEMENT.md) | Storage growth strategy and disaster recovery |

---

## `features/`

| Document | Status | Description |
|----------|--------|-------------|
| [SMS_PARSING_SPEC.md](./features/SMS_PARSING_SPEC.md) | ✅ Implemented | Sender registry, regex patterns, confidence scoring |
| [UNIFIED_TRACKING_SYSTEM.md](./features/UNIFIED_TRACKING_SYSTEM.md) | ✅ Phase 1–2 done | Transaction tracking model |
| [FISCAL_YEAR_MANAGEMENT.md](./features/FISCAL_YEAR_MANAGEMENT.md) | ✅ Implemented | Indian FY, year-end close, invoice resets |
| [GSTR1_WORKBOOK_SPEC.md](./features/GSTR1_WORKBOOK_SPEC.md) | 🚧 Planned | GSTR-1 workbook and JSON export |
| [GST_COMPLIANCE_PLAN.md](./features/GST_COMPLIANCE_PLAN.md) | 🚧 Planned | Full GST compliance roadmap |
| [HRMS_STAFF_SPEC.md](./features/HRMS_STAFF_SPEC.md) | 🚧 Planned | Staff management and HRMS features |
| [BOOKINGS_SPEC.md](./features/BOOKINGS_SPEC.md) | 🚧 Planned | Bookings / appointments system |
| [INVOICE_REMINDERS_SPEC.md](./features/INVOICE_REMINDERS_SPEC.md) | 🚧 Planned | Automated payment reminder flows |
| [PARTY_DOCUMENT_LEDGER_SPEC.md](./features/PARTY_DOCUMENT_LEDGER_SPEC.md) | 🚧 Planned | Party 360 with full document history |
| [CONTACT_DEEP_LINK_SPEC.md](./features/CONTACT_DEEP_LINK_SPEC.md) | 🚧 Planned | Contact QR codes for user acquisition |
| [UNIFIED_NOTIFICATIONS_SPEC.md](./features/UNIFIED_NOTIFICATIONS_SPEC.md) | 🚧 Planned | Notification system across all triggers |

---

## `sync/`

| Document | Status | Description |
|----------|--------|-------------|
| [P2P_SYNC_SPEC.md](./sync/P2P_SYNC_SPEC.md) | ✅ Approved | P2P LAN sync architecture (v2, Mar 2026) |
| [WEB_COMPANION_SPEC.md](./sync/WEB_COMPANION_SPEC.md) | ✅ Approved | Flutter web companion — LAN-serve spec (Mar 2026) |
| [GENERIC_SYNC_ENGINE_MVP_IMPLEMENTATION_CHECKLIST.md](./sync/GENERIC_SYNC_ENGINE_MVP_IMPLEMENTATION_CHECKLIST.md) | 🚧 In progress | Checklist for generic web-companion sync engine |
| [IMPLEMENTATION_PLAN_SYNC_RBAC.md](./sync/IMPLEMENTATION_PLAN_SYNC_RBAC.md) | 🔵 Active | Sprint plan: sync → RBAC → linked devices → dual-primary |

---

## `planning/`

| Document | Description |
|----------|-------------|
| [IMPLEMENTATION_ROADMAP.md](./planning/IMPLEMENTATION_ROADMAP.md) | Phased build plan and milestone tracker |
| [SETUP_GUIDE.md](./planning/SETUP_GUIDE.md) | Developer setup and build instructions |

---

## `legal/`

| Document | Description |
|----------|-------------|
| [PRIVACY_POLICY.md](./legal/PRIVACY_POLICY.md) | User-facing privacy policy |
| [TERMS_OF_USE_V2_2.md](./legal/TERMS_OF_USE_V2_2.md) | Terms of use (v2.2, effective Mar 16 2026) |

---

## `archive/`

Old, superseded, or completed documents:

| Document | Reason archived |
|----------|----------------|
| [FLUTTER_WEB_COMPANION_SPEC.md](./archive/FLUTTER_WEB_COMPANION_SPEC.md) | Superseded by WEB_COMPANION_SPEC.md (Cloudflare approach abandoned) |
| [IMPLEMENTATION_PLAN_SUBSCRIPTION.md](./archive/IMPLEMENTATION_PLAN_SUBSCRIPTION.md) | Status: COMPLETE |
| [INVOICE_NUMBERING_2026_03_15.md](./archive/INVOICE_NUMBERING_2026_03_15.md) | Status: Implemented |
| [CODE_REVIEW_2026_03_15.md](./archive/CODE_REVIEW_2026_03_15.md) | Point-in-time code review snapshot (Mar 15) |
| [LAN_SYNC_IMPROVEMENTS_2026_03_15.md](./archive/LAN_SYNC_IMPROVEMENTS_2026_03_15.md) | Superseded by P2P_SYNC_SPEC.md |
| [SYNC_GAP_AUDIT_2026_03_20.md](./archive/SYNC_GAP_AUDIT_2026_03_20.md) | Point-in-time audit snapshot (Mar 20) |
| [IMPLEMENTATION_PLAN_MAR_APR_2026.md](./archive/IMPLEMENTATION_PLAN_MAR_APR_2026.md) | Superseded by IMPLEMENTATION_ROADMAP.md |
| [MVP_SCOPE.md](./archive/MVP_SCOPE.md) | Superseded by PRD.md |
| [LINKED_DEVICES_BRAINSTORM.md](./archive/LINKED_DEVICES_BRAINSTORM.md) | Superseded by ARCHITECTURE_DECISIONS.md |
| [PRIVATE_SYNC_BRAINSTORM.md](./archive/PRIVATE_SYNC_BRAINSTORM.md) | Superseded by P2P_SYNC_SPEC.md |
| [USER_PERMISSIONS_BRAINSTORM.md](./archive/USER_PERMISSIONS_BRAINSTORM.md) | Superseded by ARCHITECTURE_DECISIONS.md |
| [PARTY_MANAGEMENT_REVIEW.md](./archive/PARTY_MANAGEMENT_REVIEW.md) | Historical review, superseded by PARTY_DOCUMENT_LEDGER_SPEC.md |
| Privacy Architecture | ✅ Complete | Feb 24, 2026 |
| Privacy Policy | ✅ Complete | Feb 24, 2026 |
| Setup Guide | ✅ Complete | Feb 24, 2026 |
| UI/UX Guidelines | ✅ Complete | Feb 24, 2026 |
| Screen Flows | ✅ Complete | Feb 24, 2026 |
| User Personas | ✅ In PRD Section 4 | Feb 24, 2026 |
| Market Analysis | ✅ In PRD Section 2 | Feb 24, 2026 |
| Security Spec | ✅ In Privacy Architecture | Feb 24, 2026 |
| Test Plan | 📝 Planned (Week 4-5) | - |
| Development Guidelines | ✅ See CONTRIBUTING.md | Feb 24, 2026 |

## 🤝 Contributing to Documentation

When updating documentation:
1. Update version number
2. Add "Last Updated" date
3. Update this README if adding new documents
4. Cross-reference related documents

## 📞 Contact

Documentation maintained by: Loganathan EV  
Project: Kash Cube - Privacy-First Expense Tracker for India
