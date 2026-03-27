# Drift Report — ONE_APP_COMPLETE_BUSINESS_AUDIT vs Codebase As-Built

**Date:** 27 March 2026  
**Compared documents:**
- Baseline audit: [ONE_APP_COMPLETE_BUSINESS_AUDIT.md](ONE_APP_COMPLETE_BUSINESS_AUDIT.md)
- As-built sources: [../../codebase/README.md](../../codebase/README.md), [../../codebase/SMS_PIPELINE_AS_BUILT.md](../../codebase/SMS_PIPELINE_AS_BUILT.md), [../../codebase/STATE_AND_NAVIGATION_AS_BUILT.md](../../codebase/STATE_AND_NAVIGATION_AS_BUILT.md), [../../codebase/DATABASE_AS_BUILT.md](../../codebase/DATABASE_AS_BUILT.md), [../../codebase/GST_PIPELINE_AS_BUILT.md](../../codebase/GST_PIPELINE_AS_BUILT.md), [../../codebase/PDF_PIPELINE_AS_BUILT.md](../../codebase/PDF_PIPELINE_AS_BUILT.md)

---

## Executive Summary

The audit is mostly aligned with current as-built documentation, but there are **2 external drift issues** and **1 internal consistency issue** that should be corrected.

- **External drift:** 2
- **Internal consistency issue:** 1
- **High-impact mismatch:** SMS sender coverage count (56 vs 46)

---

## Drift Findings

## 1) SMS sender coverage count mismatch

**Audit says:** `SMS auto-capture (56 Indian sender IDs)` (Section 2, Purchases & Expenses).  
**As-built says:** `46 entries in _senderRegistry`.

**Evidence:**
- [ONE_APP_COMPLETE_BUSINESS_AUDIT.md](ONE_APP_COMPLETE_BUSINESS_AUDIT.md)
- [../../codebase/SMS_PIPELINE_AS_BUILT.md](../../codebase/SMS_PIPELINE_AS_BUILT.md)

**Impact:** Overstates production parser coverage by 10 sender IDs.

**Recommended fix in audit:**
- Replace `56 Indian sender IDs` with `46 sender IDs`.

---

## 2) Inconsistent onboarding status (internal contradiction)

**Audit says (Communication / Reminders):** `Onboarding screen | ❌ folder exists, no files — beta prep backlog`  
**Audit also says (Reference: All Screens Confirmed Implemented):** includes `onboarding` in the “confirmed implemented” list.

**Codebase evidence:** onboarding folder exists and is empty.

**Evidence:**
- [ONE_APP_COMPLETE_BUSINESS_AUDIT.md](ONE_APP_COMPLETE_BUSINESS_AUDIT.md)
- [../../codebase/STATE_AND_NAVIGATION_AS_BUILT.md](../../codebase/STATE_AND_NAVIGATION_AS_BUILT.md)

**Impact:** Readers cannot tell whether onboarding is shipped or backlog.

**Recommended fix in audit:**
- Remove `onboarding` from “All Screens Confirmed Implemented”, **or**
- Rename that section to “Screen Domains Present” and keep onboarding explicitly marked as backlog.

---

## 3) Drift propagated to product docs (same SMS count)

The `56 sender IDs` statement is repeated in other docs, so drift is not isolated to one file.

**Examples found:**
- `docs/product/research/COMPETITIVE_GAP_ANALYSIS_SPENDEE.md`
- `docs/product/strategy/WHY_KASHCUBE_POSITIONING.md`
- `docs/product/research/COMPETITIVE_GAP_ANALYSIS_EXPENSE_MANAGER.md`
- `docs/product/research/COMPETITIVE_GAP_ANALYSIS_MI_NEGOCIO.md`

**Impact:** Marketing/research narrative and implementation docs diverge.

**Recommended fix:**
- Run a docs-wide normalization pass to use one canonical value (`46` unless parser registry is actually expanded).

---

## Confirmed Alignments (spot-check)

These key audit claims align with as-built docs:

- **Database scale and breadth:** 56 tables, including GST, payroll, sync, inventory lots.
  - Evidence: [../../codebase/DATABASE_AS_BUILT.md](../../codebase/DATABASE_AS_BUILT.md)
- **GST capability profile:** GSTR-1 + GSTR-3B + e-Way present; GSTR-2B not implemented.
  - Evidence: [../../codebase/GST_PIPELINE_AS_BUILT.md](../../codebase/GST_PIPELINE_AS_BUILT.md)
- **PDF stack maturity:** templating/layout engine and service coverage is implemented.
  - Evidence: [../../codebase/PDF_PIPELINE_AS_BUILT.md](../../codebase/PDF_PIPELINE_AS_BUILT.md)
- **Navigation/provider footprint:** broad app surface with 69 screen files and 50 provider files.
  - Evidence: [../../codebase/STATE_AND_NAVIGATION_AS_BUILT.md](../../codebase/STATE_AND_NAVIGATION_AS_BUILT.md)

---

## Recommended Next Actions

1. Patch [ONE_APP_COMPLETE_BUSINESS_AUDIT.md](ONE_APP_COMPLETE_BUSINESS_AUDIT.md):
   - `56` → `46` sender IDs
   - resolve onboarding contradiction
2. Patch the four product docs carrying the same stale `56` claim.
3. Add a lightweight governance rule:
   - capability counts in strategy/audit docs must reference a single canonical source under `docs/codebase/`.

---

## Confidence and Scope

This drift report is **document-to-document** validation using the current as-built documentation set (and a quick onboarding folder existence check), not a full deep code audit of all modules.