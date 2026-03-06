# Foundation: Personal + Business Mode

## Goal

Make KashCube work seamlessly for:
- **Personal-only users** — no business, just udhar/khata tracking, loans, reminders
- **Business users** — invoices, GST, item catalog on top of the personal base
- **Both** — the common case (small business owner who also lends to friends)

The personal layer is **always on**. Business mode is an **additive unlock**, not a replacement.

---

## Phase F1 — Data Layer: Schema + Models

### DB v44 — Three `business_id` migrations

| Table | Change | Semantics |
|-------|--------|-----------|
| `credits` | `ADD COLUMN business_id INTEGER` | `NULL` = personal credit; `N` = belongs to Business N |
| `loans` | `ADD COLUMN business_id INTEGER` | `NULL` = personal loan; `N` = belongs to Business N |
| `party_reminders` | `ADD COLUMN business_id INTEGER` | `NULL` = personal reminder; `N` = sent in context of Business N |

Existing rows default to `NULL` (personal) — safe, backward-compatible, no data loss.

### New: `Credit` model class

`lib/data/models/credit.dart` — mirrors the `credits` table exactly:

```
id, customerName, customerId, phoneNumber,
totalAmount, paidAmount, pendingAmount,
direction (CreditDirection: given | received),
creditDate, dueDate, clearedDate,
isCleared, isOverdue, interestRate, interestType,
notes, tags, businessId,   ← NEW
createdAt, updatedAt, deletedAt
```

### Updated: `Loan` model

Add `final int? businessId` to `Loan`:
- constructor, `toMap()`, `fromMap()`, `copyWith()`

---

## Phase F2 — Repository Layer: Context-Aware Queries

### `LoanRepository` additions

```dart
/// Personal loans only (business_id IS NULL)
Future<List<Loan>> getPersonal();

/// Loans for a specific business
Future<List<Loan>> getForBusiness(int businessId);

/// Active personal loans by direction
Future<List<Loan>> getActivePersonalByDirection(LoanDirection direction);
```

### New: `CreditRepository` (interface + impl)

`lib/domain/repositories/credit_repository.dart`
`lib/data/repositories/credit_repository_impl.dart`

```dart
abstract class CreditRepository {
  Future<List<Credit>> getAll();
  Future<List<Credit>> getActive();                       // not cleared, not deleted
  Future<List<Credit>> getPersonal();                     // business_id IS NULL
  Future<List<Credit>> getForBusiness(int businessId);
  Future<List<Credit>> getByPartyName(String name);
  Future<List<Credit>> getActiveByDirection(CreditDirection direction);
  Future<List<Credit>> getOverdue();
  Future<double> getTotalPendingGiven();                  // money owed TO you
  Future<double> getTotalPendingReceived();               // money you owe
  Future<int> insert(Credit credit);
  Future<void> update(Credit credit);
  Future<void> delete(int id);
  Future<void> recordPayment(int creditId, double amount);
}
```

### New: `creditProvider` Riverpod providers

`lib/presentation/providers/credit_provider.dart`

```dart
final creditRepositoryProvider  → Provider<CreditRepository>
final creditsProvider           → StateNotifierProvider<CreditsNotifier, AsyncValue<List<Credit>>>
final personalCreditsProvider   → FutureProvider<List<Credit>>   (given + active + personal)
```

---

## Phase F3 — UI: Personal-First Surfaces

### 3a. Home `_AlertsSection` — show credits without business mode

**Current:** `final hasOverdue = businessMode && overdueCount > 0; // personal = nothing`

**Fix:** Also show a "Credits Outstanding" chip when `totalPendingGiven > 0`, regardless of business mode.

### 3b. Party detail Documents tab — Credit & Loan card

When `invoices.isEmpty` (personal or no-invoice party):
- Show a **Credit Balance card** (mirrors `_OutstandingBalanceCard` but sourced from credits/loans)
- Shows: Total Lent, Total Repaid, Pending from this party
- Reminder nudge fires on `netCredit > 0` as well as unpaid invoices

### 3c. Reminder sheet — credit-mode message

`_buildDefaultMessage()` chooses template by context:
- Has unpaid invoices → invoice breakdown (existing)
- Has credits outstanding → credit template: *"Hi Ravi, friendly reminder — ₹5,000 lent on 15 Jan 2026 is pending. Please settle when convenient."*
- Both → combined breakdown

---

## Phase F4 — Action Center Screen

Built on top of F1-F3. Requires clean `business_id` separation to be useful.

**To Collect (↑):** Overdue invoices (business) + outstanding credits given (personal + business)
**To Pay (↓):** Overdue bills + outstanding credits received + loan EMIs due

Separate session. Not started until G1-G4 are verified.

---

## Gap Analysis (Post F1-F3 Review — 6 Mar 2026)

After F1-F3, the data layer is ~85% solid. Remaining gaps are **all UI/navigation** — the data exists but is unreachable by the user.

### G1 — Credits/Udhar has no entry point *(Blocking)*

The entire credits data layer is built but:
- No "Add Udhar" in the FAB
- No Credits list screen
- A personal user saying "I lent Raju ₹500" cannot record it

**Fix:** `CreditsScreen` + `AddCreditScreen` in `lib/presentation/screens/ledger/credits_screen.dart`

### G2 — Home alert navigation is broken *(Blocking)*

`totalCreditsPendingGivenProvider` fires the home alert tile, but tapping it navigates to `LedgerScreen` (loans table). Dead end.

**Fix:** New `CreditsScreen`, update home alert nav target.

### G3 — Loans vs Credits UX confusion *(Confusing)*

Two parallel "lend/borrow" systems with no clear distinction:
- `loans` table → Ledger/Loans screen, FAB "Loan / Lend" → formal EMI-bearing agreements
- `credits` table → nowhere → informal udhar/khata

**Fix:** Explicit label distinction:
- **Loans** = formal (EMI, interest, schedule) — Ledger/Loans screen unchanged
- **Udhar** = informal daily IOU — new Credits screen, own FAB entry

### G4 — Business tab wasted for personal-only users *(Poor UX)*

Bottom nav "Business" slot → `BusinessHubScreen` full of invoicing features. Personal-only users hit a wall.

**Fix:** `BusinessHubScreen` detects `businessMode = false` → renders a **Personal Finance hub**: credits/udhar, loans, bills, budget, reports.

---

## Current Status

| Phase | Status |
|-------|--------|
| F1 — DB v44 + Credit model + Loan.businessId | ✅ Complete |
| F2 — CreditRepository + LoanRepository additions | ✅ Complete |
| F3 — Home alerts + Party credit card + Reminder message | ✅ Complete |
| G1 — AddCreditScreen + CreditsScreen | ✅ Complete |
| G2 — Home alert nav to CreditsScreen | ✅ Complete |
| G3 — Loans vs Udhar UX distinction | ✅ Complete |
| G4 — Business tab → Personal Finance hub | ✅ Complete |
| F4 — Action Center screen | ⬜ Ready to start |

