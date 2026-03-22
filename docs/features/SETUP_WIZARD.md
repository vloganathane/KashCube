# First-Run Setup Wizard

**File:** `lib/presentation/screens/auth/setup_wizard_screen.dart`  
**Status:** Implemented (MVP)

---

## Purpose

Show a guided setup experience **once** — after Terms & Conditions acceptance, before PIN lock and the main shell. Helps first-time users configure the app to their context and seeds initial data (mode, profile, business, fiscal year, opening balances).

---

## Gate Placement

```
App launch
  └─ kIsWeb? → WebConnectScreen
  └─ Terms accepted? (termsAcceptedProvider)
       └─ No  → TermsGateScreen
       └─ Yes
            └─ Wizard done? (setupWizardDoneProvider)
                 └─ No  → SetupWizardScreen  ← HERE
                 └─ Yes
                      └─ PIN locked? → PinLockScreen
                      └─ Staff users? → UserSelectionScreen / AppShell
```

---

## Steps

### Step 1 — Mode Selection
**Page index:** 0

| Selection | Effect |
|-----------|--------|
| Personal  | `businessModeEnabled = false` |
| My Business | `businessModeEnabled = true`; Step 3 (Business) shown |
| Both | `businessModeEnabled = true`; Step 3 (Business) shown |

> Step 3 (Business Setup) is only shown for "My Business" or "Both". Selecting "Personal" skips from Step 2 directly to Step 4.

---

### Step 2 — Your Profile
**Page index:** 1

| Field | Required | Settings key | Notes |
|-------|----------|-------------|-------|
| Name | Optional | `SettingsKeys.ownerName` | Used on invoices, reports |
| Phone | Optional | `SettingsKeys.personalPhone` | Digits only; +91 prefix displayed |
| UPI ID | Optional | Stored on Business record as `upiId` | Shown as "Your UPI" (personal) or "Business UPI" (business/both) |

---

### Step 3 — Business Setup *(business/both only)*
**Page index:** 2

| Field | Required | Storage | Notes |
|-------|----------|---------|-------|
| Business name | Optional | Creates `Business` record | If non-empty, creates + activates the business |
| GSTIN | Optional | `Business.gstNo` | Validated offline via `GstinValidator.isValid()` — "Continue" disabled when format is invalid |
| Address | Optional | `Business.address` | Multi-line |

> If business name is left blank, no Business record is created. The user can create one later in Settings → Businesses.

---

### Step 4 — Financial Setup
**Page index:** 3

| Field | Default | Storage |
|-------|---------|---------|
| Fiscal year start | April (month 4) | `settings('fiscal_year_start_month')` + `settings('fiscal_year_start_day', '1')` |
| Cash in hand | — | Creates `Account(name: 'Cash', type: savings, currentBalance: amount)` if > 0 |
| Bank balance | — | Creates `Account(name: 'Bank Account', type: savings, currentBalance: amount)` if > 0 |

FY options presented: April (Indian default), January, October, July.

---

## Skip Behaviour

- Every step has a **"Skip for now"** button (except the final step, which has **"Finish"**).
- Pressing skip advances to the next step with no data saved for that step.
- Pressing "Finish" on Step 4 saves everything filled so far and calls `SetupWizardNotifier.markDone()`.
- The wizard is marked done regardless of how much the user filled in.
- Pressing "Back" is available on all steps except Step 1.

---

## Data Persistence

All saves happen at **"Finish"** (Step 4 Continue/Finish tap), in this order:

1. `businessModeProvider.notifier.setEnabled(bool)`
2. `settingsRepository.set(ownerName, ...)`
3. `settingsRepository.set(personalPhone, ...)`
4. `businessesProvider.notifier.add(Business, setActive: true)` *(if biz name non-empty)*
5. `settingsRepository.set('fiscal_year_start_month', ...)`
6. `settingsRepository.set('fiscal_year_start_day', '1')`
7. `accountsProvider.notifier.addAccount(Account)` for Cash *(if amount > 0)*
8. `accountsProvider.notifier.addAccount(Account)` for Bank *(if amount > 0)*
9. `setupWizardDoneProvider.notifier.markDone()` — writes `setup_wizard_done = 'true'`
10. `onComplete()` callback → `ref.invalidate(setupWizardDoneProvider)` in `main.dart`

---

## State Flag

| Key | Value | Location |
|-----|-------|----------|
| `setup_wizard_done` | `'true'` | `settings` SQLite table |

Provider: `setupWizardDoneProvider` — `AsyncNotifierProvider<SetupWizardNotifier, bool>` in `settings_provider.dart`.

---

## Security & Privacy

- No network calls; all data stays in local SQLite.
- GSTIN validated entirely offline via `GstinValidator` (no external API).
- Analytics event NOT fired for wizard completion (financial context — consistent with no-financial-data-in-analytics policy).

---

## Future Enhancements (out of scope for MVP)

- Logo upload (image picker) in Step 3
- Multiple account types in Step 4 (credit card, UPI wallet)
- Import from contacts for owner phone
- Re-run wizard from Settings (reset flag + navigate)
