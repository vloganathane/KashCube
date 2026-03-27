# Competitive Gap Analysis — Wave: Small Business Software

**Reference app:** Wave: Small Business Software by Wave HQ  
**Play Store:** https://play.google.com/store/apps/details?id=com.waveapps.sales  
**Rating:** 4.6 ★ · 23.5K reviews · 500K+ downloads  
**Reviewed on:** 26 March 2026  
**Note:** Wave is US/Canada focused. Cloud sync, online card payments, and bank API connections are intentionally excluded from this analysis as they conflict with KashCube's privacy-first, offline-first architecture.

---

## Missing Entirely from KashCube

| Feature | Wave behaviour | Priority |
|---|---|---|
| **Invoice viewed / opened tracking** | Seller gets a push notification the moment the customer opens the PDF/invoice link | 🔴 High |
| **Automated payment reminders** | Configurable schedule (e.g. 3 days before due, on due date, 7 days overdue) fires automatically without any user action | 🔴 High |
| **Receipt OCR scanning** | Camera → OCR extracts vendor name, date, amount; auto-creates expense entry | 🔴 High |
| **Customer-level bulk payment** | Select multiple outstanding invoices for a party and record a single lump-sum payment split across them | 🔴 High |
| **Customer account statement** | Running balance statement per party showing all invoices, payments, and outstanding balance — shareable as PDF | 🟠 Medium |
| **Multi-user team access** | Owner adds staff/accountant users with role-scoped permissions via invite | 🟠 Medium |
| **Estimate → Invoice in one tap** | Convert a sent estimate to a live invoice without re-entering any data | 🟠 Medium |
| **Invoice/estimate brand colors** | Accent color picker applied to invoice header/footer matching business brand | 🟡 Low |

---

## Partially Done in KashCube

| Feature | Wave behaviour | KashCube current state | Gap |
|---|---|---|---|
| **Invoice branding** | Logo + brand colors on all documents | Logo on PDF via `business.logoPath` ✅ | Brand accent color not customizable |
| **Payment reminders** | Fully automated scheduling | Manual WhatsApp/SMS reminder buttons on invoice detail screen ✅ | No auto-scheduler; user must tap each time |
| **Estimate → Invoice conversion** | One-tap, preserves all line items and client | `InvoiceRepository.convertToInvoice(quoteId)` interface exists | Need to verify UI exposes this clearly |
| **DC → Invoice conversion** | Not a Wave feature but KashCube has it | `DeliveryChallanRepository.convertToInvoice(challanId)` ✅ | KashCube is ahead here |
| **Invoice templates** | Single default branded template | 9 presets (classic, modern, plain, receipt + 5 industry) ✅ | Behind on color customization, ahead on variety |
| **Multi-user RBAC** | Full invite + role management UI | `app_users` + permissions tables in DB ✅ | No role management screen or per-user access control UI |
| **UPI / payment method on invoice** | Online card + bank payments (US/Canada) | UPI QR code rendered on PDF ✅ | No shareable payment link; QR only in static PDF |

---

## Intentionally Different (Not Gaps for Indian Market)

| Aspect | Wave | KashCube rationale |
|---|---|---|
| **Cloud sync / desktop web** | Full cloud, data on Wave servers | Privacy-first; LAN P2P sync is the offline equivalent |
| **Bank auto-import** | Connects to US/CA bank APIs | Not available for Indian banks; SMS parsing covers the same need |
| **Online card payment gateway** | Visa/MC/Amex processing built-in | Not viable for India; UPI QR covers digital payment needs |
| **GST / Indian tax compliance** | None | KashCube far ahead: GSTR-1/3B, e-invoicing, HSN/SAC, reverse charge |
| **Inventory / lot tracking** | None | KashCube's unique SME differentiator |
| **Purchase bill / accounts payable** | Limited expense tracking only | KashCube covers full AP with GST ITC |

---

## Top 3 Priorities to Close the Gap

### 1. Invoice Viewed Tracking 🔴
Wave users consistently cite "know when your invoice was read" as a key trust feature. It removes the awkward "did you receive my invoice?" follow-up call. For KashCube, since there's no cloud, this can be approximated via:

**Implementation sketch:**
- Append a unique token to the shareable invoice URL / WhatsApp message
- When PDF is opened via share_plus deep link, record `viewed_at` in `invoices` table
- Home screen / invoice list shows "Viewed" chip with timestamp
- Local notification fires on first open

### 2. Automated Payment Reminders 🔴
Manual WhatsApp reminders exist but require daily user intervention. Wave's automated scheduling converts a passive user into a consistent cash-flow manager without effort.

**Implementation sketch:**
- `reminder_schedules` table: `invoice_id`, `trigger_type` (before_due/on_due/after_due), `days_offset`, `channel` (WhatsApp/SMS), `sent_at`
- WorkManager job runs daily, queries overdue + upcoming invoices, fires reminders via `url_launcher` (WhatsApp) or `telephony` (SMS)
- Per-invoice reminder toggle in invoice detail screen
- Global default schedule in Settings

### 3. Receipt OCR Scanning 🔴
The single biggest friction in expense tracking is manual data entry from paper receipts. Wave's OCR automates this entirely.

**Implementation sketch:**
- Use `google_mlkit_text_recognition` (on-device, no network) for OCR
- Camera sheet: capture → extract text → regex parse amount/vendor/date
- Pre-fill Add Transaction form with extracted fields (user confirms)
- Attach photo to transaction (`receipt_image_path` column)
- Fully offline — MLKit runs on-device

---

## Key Insights from Wave User Reviews

- **Multi-invoice payment** is the #1 user complaint ("have to record payment per invoice even for same customer") — KashCube should solve this before Wave does
- **Stability** ("Wave deletes in-progress work if app is backgrounded") is a major pain point — KashCube's autosave/draft approach is a competitive advantage
- Users praise the **estimate → invoice conversion speed** — KashCube should make this flow more prominent in the UI
- Wave's move to a paywall (H&R Block acquisition) is driving users to look for alternatives — **now is the right time** to position KashCube as the privacy-first, no-cloud alternative for Indian SMEs
