# Fiscal Year Management

## Overview

KashCube targets Indian businesses. India's standard fiscal year (FY) runs **1 April → 31 March**. This document covers how the app should handle FY boundaries, invoice number resets, year-end closing, carry-forwards, and multi-year reporting.

> **Urgent:** The FY flips on 1 April 2026 — 29 days away. Phase 1 items must land before that date.

---

## Indian Context

| Aspect | Default | Notes |
|---|---|---|
| Fiscal year | 1 Apr → 31 Mar | India standard; GST and ITR both align to this |
| Invoice numbering | Resets each FY | GST mandate recommends FY-prefixed numbering |
| Calendar year | 1 Jan → 31 Dec | Some private limited companies, MNCs |
| Custom year | User-defined | Some businesses follow Diwali–Diwali or other cycles |

The default must be April–March, but the start month and day must be configurable in Settings.

---

## Five Distinct Concerns at Year-End

Most apps treat FY as just a date filter. KashCube must handle five separate concerns:

### 1. Invoice / Quote Number Reset

The most visible change. `INV-2025-001` becomes `INV-2026-001` (or `INV-25-26-001`).

**Supported formats:**

| Format | Example | Typical use |
|---|---|---|
| Simple | `INV-0042` | Very small businesses |
| Calendar year | `INV-2025-0042` | Calendar-year companies |
| FY prefix (most common India) | `INV-25-26-0042` | GST-registered businesses |
| FY compact | `INV-2526-0042` | Compact variant |
| Custom prefix | `HI-0042` | Branded businesses |

Rules:
- Format set once at initial setup; preview shown before confirming
- Changing mid-year warns: "Existing invoices will not be renumbered"
- On FY start date, sequence resets to 1 automatically (if `auto_reset_invoice_no = true`)
- User is warned 7 days before rollover: "Invoice numbers reset to INV-26-27-001 on 1 April"

### 2. FY-Scoped Reports

All P&L, income, expense, and tax summaries should treat FY as a first-class reporting period.

- Default report period = current FY (not rolling 30/90 days)
- Quick switches: **This FY** / **Last FY** / **Custom range**
- Financial year label displayed clearly: "FY 2025–26"
- Year-end summary report: income, expenses, gross profit, GST collected, GST paid, net liability

### 3. Opening Balances and Carry-Forward

At year-end, outstanding items must carry into the new FY rather than disappear.

Items that carry forward:
- Unpaid invoices (still owed — same invoice number, same party)
- Outstanding credits / udhar (khata balances)
- Unsettled loans

Items that do not automatically carry forward:
- Bad debts (user decides to write off or carry)
- Draft invoices / quotes (user reviews and decides)

This requires an explicit **Year-End Closing** action with user confirmation — not silent automation. Some businesses write off bad debts at year-end; the app must allow that choice.

### 4. GST / Tax Summary

The year-end summary should surface:

| Line | Description |
|---|---|
| Total taxable income | Sum of all invoice totals (excl. GST) |
| Output GST collected | GST charged on invoices |
| Input GST paid | GST paid on expenses/purchases |
| Net GST liability | Output − Input |

This feeds directly into GSTR-9 (annual GST return) and ITR filing. No computation is done by KashCube — the summary is presented as a reference table for the user or their CA.

### 5. Data Separation Between Years

Day-to-day screens (transactions, invoices, credits) default to current FY data. Prior-year data is accessible but not mixed in.

Options (in order of complexity):
- **Filter model** — everything in one DB, all screens default to current FY filter *(recommended for v1)*
- **Archive model** — FY close triggers archiving of that FY's rows to `archive_FY{YYYY}.db`. This is the preferred long-term approach — see [STORAGE_AND_DISASTER_MANAGEMENT.md §1.4](STORAGE_AND_DISASTER_MANAGEMENT.md#14-tiered-data-access--hot--warm--cold) for the tiering model. FY close is the semantic gateway to cold storage — not a background age-based job.
- **Multi-book model** — each FY is a separate logical book with a switcher UI *(future)*

---

## Settings Schema

New keys in the `settings` table:

```
fiscal_year_start_month     INTEGER   DEFAULT 4        (April)
fiscal_year_start_day       INTEGER   DEFAULT 1
invoice_no_format           TEXT      DEFAULT 'INV-{YY}-{YY+1}-{SEQ}'
quote_no_format             TEXT      DEFAULT 'QT-{YY}-{YY+1}-{SEQ}'
auto_reset_invoice_no       INTEGER   DEFAULT 1        (boolean)
last_fy_close_date          TEXT      DEFAULT NULL     (ISO8601, null = never closed)
current_fy_start            TEXT                       (ISO8601 date)
```

Format tokens:
| Token | Expands to |
|---|---|
| `{YYYY}` | Full year of FY start (2025) |
| `{YY}` | Short year of FY start (25) |
| `{YY+1}` | Short year of FY end (26) |
| `{SEQ}` | Zero-padded sequence number |
| `{PREFIX}` | User-defined custom prefix |

---

## `FiscalYearService`

New service at `lib/data/services/fiscal_year_service.dart`:

```dart
class FiscalYearService {
  /// Returns the FY date range that contains [date].
  DateRange getFiscalYearFor(DateTime date);

  /// Returns the currently active FY date range.
  DateRange get currentFiscalYear;

  /// Returns a display label, e.g. "FY 2025–26" or "CY 2025".
  String getFYLabel(DateRange range);

  /// Returns true if today is within [daysBeforeEnd] of the FY end date.
  bool isApproachingYearEnd({int daysBeforeEnd = 30});

  /// Returns true if today is the first day of a new FY
  /// and the invoice sequence has not yet been reset.
  bool isResetDue();

  /// Generates the next invoice number respecting FY format and sequence.
  Future<String> nextInvoiceNo();

  /// Generates the next quote number respecting FY format and sequence.
  Future<String> nextQuoteNo();
}
```

---

## Year-End Closing Wizard

A user-initiated flow, not silent automation. Accessible from Settings → Financial Year → Close FY.

```
Step 1 — Summary
──────────────────────────────────────────
FY 2024–25 Summary

Total income      ₹12,45,000
Total expenses     ₹4,32,000
Gross profit       ₹8,13,000

GST collected        ₹1,56,000   (output)
GST paid               ₹48,000   (input)
Net GST liability    ₹1,08,000

Unpaid invoices    3 invoices  ₹78,500
Outstanding credits  12 parties  ₹23,400
──────────────────────────────────────────
[Next →]

Step 2 — Carry-forward decisions
──────────────────────────────────────────
[✓] Carry forward 3 unpaid invoices
[✓] Carry forward 12 outstanding credits
[ ] Write off 2 bad debts  ₹5,200   [Review]
──────────────────────────────────────────
[← Back]  [Close FY 2024–25]

Step 3 — Confirmation
──────────────────────────────────────────
"FY 2024–25 has been closed.

 3 invoices and 12 credit balances
 carried forward to FY 2025–26.

 Invoice numbers will reset to
 INV-25-26-001 on 1 April 2026."

⚠️  Back up your data
"Your FY 2024–25 data is now complete.
 Save an encrypted backup so it is
 never lost."
[Back Up Now]          [Later]
──────────────────────────────────────────
[Done]
```

---

## Interaction with Backup and Storage

FY management directly affects backup completeness and storage archiving. See [STORAGE_AND_DISASTER_MANAGEMENT.md](STORAGE_AND_DISASTER_MANAGEMENT.md) for full details.

### FY Close = Archiving Gateway
- The year-end closing wizard (Phase 2) is the trigger for moving the closed FY's data to `archive_FY{YYYY}.db`
- This replaces the age-based "2 years → cold tier" rule in the storage doc with a semantically correct FY-boundary trigger
- Users understand "last year's data" better than "data older than 730 days"

### Year-End Forced Backup
- **7 days before FY end:** If the last `.kashcube` encrypted backup is more than 14 days old, show a notification: "Your financial year ends in 7 days and your last backup was {N} days ago — back up now"
- **After FY close (Step 3 of wizard):** Prompt "Back Up Now" inline — the FY is complete and the backup will contain the full year of data
- This is the most important backup moment of the year — the closed FY's data will not change again

### Backup File Completeness
- A `.kashcube` backup includes `kash_cube.db` (active FY) **and** all `archive_FY{YYYY}.db` files
- Restoring from backup restores the complete financial history, not just the current year
- See [STORAGE_AND_DISASTER_MANAGEMENT.md §2.4](STORAGE_AND_DISASTER_MANAGEMENT.md#24-layer-3--encrypted-export--import-kashcube-format) for the multi-DB payload format and restore flow

### Storage Dashboard
- The Settings storage dashboard shows per-FY breakdown (active + closed + archived)
- Users can delete an archived FY from Settings (irreversible, requires confirmation showing record count)

---


The app must not break if year-end closing is skipped:

- Invoice numbering continues without reset (warns once per launch until actioned)
- Reports still work via manual date range pickers
- Year-end closing remains available retroactively (closing FY 2024–25 on 15 May 2026 still works)
- No data loss in any scenario
- A dismissible banner appears on home screen from March 25 onwards

---

## Notification Schedule

| Date | Message |
|---|---|
| 25 March | "Your financial year ends in 7 days. Review and close FY 2024–25." |
| 25 March (if backup stale) | "Your financial year ends in 7 days and your last backup was {N} days ago — back up now." |
| 31 March | "Today is the last day of FY 2024–25. Close the year before midnight." |
| 1 April (if not closed) | "FY 2025–26 has started. Complete year-end closing for FY 2024–25." |
| Weekly reminder | "FY 2024–25 is still open — close it to reset invoice numbering." |

Notifications stop once closing is completed.

---

## Multi-Year Reporting (Future)

Once year-end closing exists, comparative views become possible:

- FY 2025–26 vs FY 2024–25 — income, expenses, top customers
- Year-over-year growth percentages
- Multi-year party ledger (total paid by a customer across 3 years)
- Trend charts spanning multiple FYs

---

## Implementation Roadmap

### Phase 1 — Before 1 April 2026 (Urgent)

| Task | Effort |
|---|---|
| FY settings in `settings` table (new columns) | 2 hrs |
| `FiscalYearService` — date range + label logic | 1 day |
| FY-aware invoice / quote number format + auto-reset on April 1 | 1 day |
| "This FY / Last FY" quick filter in Reports screen | 1 day |
| Year-end warning notification (March 25) | Half day |

### Phase 2 — Before End of April

| Task | Effort |
|---|---|
| Year-end closing wizard (summary + carry-forward UI) | 3 days |
| Opening balance carry-forward to new FY | 2 days |
| GST summary table in year-end report | 1 day |
| FY archival to `archive_FY{YYYY}.db` on close (coordinate with storage doc) | 2 days |
| Trigger encrypted backup export prompt in Step 3 of closing wizard | Half day |

### Phase 3 — Post-Launch

| Task | Effort |
|---|---|
| Multi-year comparative reports | 2 days |
| Multi-book model (FY switcher) | 1 week |
| Prior-FY archiving to cold storage tier | 2 days |

---

## Non-Goals

- KashCube does **not** file GST returns or ITR — it surfaces summary data for the user or their CA
- No double-entry accounting — carry-forwards are recorded as simple balance transfers
- No audit trail locking (v1) — records remain editable after FY close

---

## Related Documents

- [STORAGE_AND_DISASTER_MANAGEMENT.md](STORAGE_AND_DISASTER_MANAGEMENT.md) — FY close drives cold-tier archiving; year-end is the key backup trigger; `.kashcube` backup format includes all FY archive DBs
