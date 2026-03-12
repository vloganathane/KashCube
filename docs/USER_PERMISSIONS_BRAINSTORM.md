# User & Permission Management: Multi-User on a Local App
# KashCube Architecture Brainstorm

**Version:** 1.0  
**Date:** 12 March 2026  
**Status:** Brainstorm / RFC — not yet committed to roadmap  
**Author:** Engineering

---

## 1. The Fundamental Distinction

From `PRIVATE_SYNC_BRAINSTORM.md`:

> **Multi-user ≠ Multi-device sync.**  
> Multi-device sync = same person, multiple devices, same data.  
> Multi-user = different people, different roles, **shared device or shared data**.  
> They require completely different architectures. Do not conflate them.

This doc is strictly about **multi-user on a local device**: different people using the same phone or different phones that happen to have a copy of the same data, with different levels of access.

**The privacy rule still holds:** No network calls. No cloud. Users are local constructs stored in SQLite.

---

## 2. Who Are "Users" in a Local App?

In cloud software, a "user" is an identity authenticated against a server. In KashCube, there is no server — but there are still distinct personas who need different access:

| Persona | Device situation | What they need |
|---------|-----------------|----------------|
| **Owner** | Their phone | Full access everywhere; current state |
| **Cashier / Billing Staff** | Owner hands them the phone | Create invoices/sales for one business only; no reports, no loans, no personal data |
| **Manager** | Second phone (manual sync via backup) | Full business access except settings; can see reports and credits |
| **Accountant / Auditor** | Their own device (read-only export import) | View only; cannot add or delete anything |
| **Family member** | Same phone (e.g. spouse managing household) | Access only to personal transactions; blocked from business data |

**Key insight:** In a single-device shop scenario (cashier uses owner's phone), the primary need is **temporary access switching** — the owner hands the phone and the cashier gets a restricted view without knowing the owner's PIN.

---

## 3. Current State

```
app_lock_enabled   → key in settings table
pin_hash           → SHA-256(4-digit PIN) in settings table  
biometric_enabled  → key in settings table

At startup: if app_lock_enabled → show PinLockScreen → full access once unlocked
```

There is exactly **one user**. There are **no app_users, profiles, or permission tables**. All auth state is flat key-value in the `settings` table.

**Business isolation already exists:** `transactions`, `credits`, `invoices` all carry `business_id`. The `activeBusinessProvider` gates which business is shown. This is the foundation permission enforcement will build on.

---

## 4. Option A — Profile-Based (Separate Data Partitions)

**Concept:** Each user has their own isolated profile. Every table gets a `profile_id` column. Switching users switches the entire data view.

```
Profile 1: Owner         ─── full access ─── all data
Profile 2: Cashier Ravi  ─── restricted ──── business_id=2 data only
Profile 3: Wife          ─── restricted ──── personal transactions only
```

**Privacy score:** ⭐⭐⭐⭐⭐ (complete isolation)  
**Complexity:** ⭐⭐⭐⭐⭐ (every query gains profile_id; backup/restore doubles in complexity; shared data — e.g. party names — becomes unclear which profile they belong to)  
**Verdict:** ❌ Reject. Over-engineered for our use case. Breaks the existing schema badly. Shared entities (categories, parties, businesses) don't map cleanly to per-profile isolation.

---

## 5. Option B — Role-Based Access Control (RBAC) on Shared Data ⭐ Recommended

**Concept:** One database. Multiple named "app users" each with a PIN and a role. Permissions determine what modules they can see and what actions they can take. Enforcement is at the Riverpod provider and UI layer (not SQLite row-level security).

### 5.1 The User Model

```
Owner (you)
├── Full access
├── Authenticated by device PIN + biometric (existing flow, unchanged)
└── Manages all other app users

App User (e.g. "Cashier – Ravi")
├── named profile stored in app_users table
├── has a separate 4-digit PIN
├── has a role → permission set
└── optionally linked to a Staff party in parties table
```

### 5.2 Role Presets

| Role | Transactions | Invoices | Credits | Reports | Settings | Staff | Inventory |
|------|-------------|----------|---------|---------|----------|-------|-----------|
| **Owner** | Full | Full | Full | Full | Full | Full | Full |
| **Manager** | Full | Full | Full | View | View-only | View | Full |
| **Cashier** | Create only | Create only | ✗ | ✗ | ✗ | ✗ | View |
| **Auditor** | View | View | View | View | ✗ | ✗ | View |
| **Custom** | Configurable per module | | | | | | |

**Business scoping:** Every role except Owner can be further restricted to one or more specific businesses. A cashier for Business A cannot see Business B's invoices.

### 5.3 DB Schema (v58 or later)

```sql
CREATE TABLE app_users (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  display_name    TEXT    NOT NULL,
  pin_hash        TEXT,                  -- SHA-256(PIN); NULL = no PIN (owner-manages)
  role            TEXT    NOT NULL DEFAULT 'custom',
                                         -- 'manager' | 'cashier' | 'auditor' | 'custom'
  linked_party_id INTEGER,               -- FK parties(id) for staff members
  is_active       INTEGER NOT NULL DEFAULT 1,
  created_at      TEXT    DEFAULT (datetime('now')),
  last_login_at   TEXT,
  FOREIGN KEY (linked_party_id) REFERENCES parties(id) ON DELETE SET NULL
);

CREATE TABLE user_permissions (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL,
  business_id INTEGER,                   -- NULL = applies to all businesses
  module      TEXT    NOT NULL,
                                         -- 'transactions' | 'invoices' | 'purchase_bills'
                                         -- 'credits' | 'reports' | 'settings'
                                         -- 'inventory' | 'staff' | 'accounts' | 'budgets'
  can_view    INTEGER NOT NULL DEFAULT 1,
  can_create  INTEGER NOT NULL DEFAULT 0,
  can_edit    INTEGER NOT NULL DEFAULT 0,
  can_delete  INTEGER NOT NULL DEFAULT 0,
  UNIQUE (user_id, business_id, module),
  FOREIGN KEY (user_id)     REFERENCES app_users(id)   ON DELETE CASCADE,
  FOREIGN KEY (business_id) REFERENCES businesses(id)  ON DELETE CASCADE
);
```

**Owner is NOT stored in `app_users`.** The owner is identified by the existing `settings` PIN/biometric flow. This avoids any breaking migration of current auth.

---

## 6. Option C — Kiosk / Mode Switching (No DB Changes)

**Concept:** No persistent user records. Instead, the owner pre-configures a "Cashier Mode" (a set of restrictions). Entering Cashier Mode requires a separate PIN. Exiting requires the owner's PIN.

```
Owner Mode (full)  ←──────────────────────  needs owner PIN
                                              ↕
Cashier Mode (restricted)  ←── separate PIN ──
```

**Privacy score:** ⭐⭐⭐⭐⭐  
**Complexity:** ⭐ (very low — just conditional rendering)  
**Limitation:** One cashier mode, not named individuals. No audit trail (who did what). No per-business scoping beyond the active business.  
**Verdict:** ✅ Good MVP step. Can ship as "Cashier Mode" in v1, evolve to full RBAC in v2.

The two are not mutually exclusive — Kiosk Mode is Phase U1, full RBAC is Phase U2.

---

## 7. Option D — Linked Staff Access ⭐ Natural Extension of HRMS

**Concept:** A staff member (already in `parties` as `PartyType.staff`) can be "granted app access." This creates an `app_user` record linked to their party. Their default permissions match their role (e.g. Cashier, Manager).

```
Staff Party (Ravi, Cashier, ₹18,000/month)
      └── "Grant App Access" → app_user created
                └── role: cashier
                └── PIN set by owner
                └── business_id: this business only
```

This is the cleanest UX story: "Add staff → optionally give them app access → they see only what they need."

Revoking access: toggle `is_active = 0` on the `app_user` record. Staff party record untouched.

---

## 8. Session Management

### 8.1 App Startup Flow

```
App opens
    │
    ├── [Single user = owner, lock enabled]
    │       → PinLockScreen (existing) → main app [unchanged]
    │
    ├── [Multi-user exists]
    │       → UserSelectionScreen
    │             Owner tile  → existing PIN/biometric flow
    │             Staff tile  → StaffPinScreen → limited app
    │
    └── [No lock, no other users]
            → main app directly [unchanged]
```

### 8.2 Active Session in Riverpod

```dart
// In memory only — never written to DB
final activeAppUserProvider = StateProvider<AppUser?>((ref) => null);
// null = owner mode (full access)

// Permission check helper
final permissionProvider = Provider.family<Permission, ({String module, int? businessId})>(
  (ref, arg) {
    final user = ref.watch(activeAppUserProvider);
    if (user == null) return Permission.full;  // owner
    return ref.read(userPermissionRepositoryProvider)
              .getPermission(userId: user.id, module: arg.module, businessId: arg.businessId);
  },
);
```

### 8.3 Session Timeout

Configurable idle timeout per app_user (or global setting):

| Timeout | Use case |
|---------|---------|
| 1 min | Cashier in a busy shop — phone sits idle between customers |
| 5 min | Manager checking reports |
| 15 min | Personal use |
| Never | Owner's personal device they always keep locked |

On timeout → return to UserSelectionScreen (or PinLockScreen if single user).

---

## 9. Permission Enforcement Architecture

Enforcement happens at **three layers** (defence in depth). Never trust just one layer.

### Layer 1 — UI (Navigation)

Bottom nav items and FABs are hidden/shown based on permissions:

```dart
// In home_screen.dart / bottom_nav
if (ref.watch(permissionProvider(('reports', activeBusinessId))).canView)
  BottomNavItem(icon: Icons.bar_chart, label: 'Reports'),
```

### Layer 2 — Provider (Data Access)

Providers return empty/filtered data for unauthorized modules:

```dart
final transactionsProvider = FutureProvider<List<Transaction>>((ref) {
  final perm = ref.watch(permissionProvider(('transactions', activeBusinessId)));
  if (!perm.canView) return [];
  return ref.read(transactionRepositoryProvider).getAll(...);
});
```

### Layer 3 — Action Guards (Mutation)

Before any write operation, check permission:

```dart
Future<void> saveTransaction(Transaction tx) async {
  final perm = ref.read(permissionProvider(('transactions', tx.businessId)));
  if (!perm.canCreate) throw PermissionDeniedException('transactions', 'create');
  await _repo.save(tx);
}
```

**Note:** We do NOT enforce at the SQLite layer. Row-level security in SQLite is complex and fragile; Dart-layer enforcement is sufficient given the app runs in one process.

---

## 10. Audit Trail (Optional but Valuable)

Once multi-user exists, "who did what" becomes important. Add `created_by_user_id` and `updated_by_user_id` to key tables:

```sql
-- Non-breaking additions (nullable, defaults fine for existing rows)
ALTER TABLE transactions  ADD COLUMN created_by_user_id INTEGER;
ALTER TABLE invoices       ADD COLUMN created_by_user_id INTEGER;
ALTER TABLE credit_payments ADD COLUMN created_by_user_id INTEGER;
```

`NULL` = owner (backward compatible). Display name resolved at query time via JOIN to `app_users`.

Use case: Owner sees "Invoice #INV-042 created by Ravi (Cashier)" in the transaction detail or audit log screen.

---

## 11. UX Screens Required

### Phase U1 — Kiosk / Cashier Mode (minimal, no DB)

| Screen | Description |
|--------|-------------|
| `CashierModeSetupScreen` | Owner enables cashier mode, sets cashier PIN, selects which business |
| `CashierModeBanner` (widget) | Persistent banner at top: "Cashier Mode — Tap to exit (requires owner PIN)" |
| `ExitCashierModeSheet` | PIN entry to return to owner mode |

Settings path: Settings → Security → Cashier Mode

### Phase U2 — Full RBAC

| Screen | Description |
|--------|-------------|
| `UserSelectionScreen` | Launch screen when multiple users exist; shows initials avatar per user |
| `StaffPinScreen` | Simple 4-digit PIN for non-owner users |
| `ManageUsersScreen` | List of app users; Settings → Team |
| `AddEditUserSheet` | Name, role, PIN, business assignment. Reuses `PartyFormSheet` if linked to staff |
| `UserPermissionsScreen` | Fine-grained CRUD toggles per module per business |
| `SessionTimeoutScreen` | "You've been logged out" with user selector |

---

## 12. Integration with HRMS

The cleanest integration point is `StaffDetailScreen`:

```
[Staff Profile Tab]
────────────────────────────────
Ravi Kumar
Cashier  •  ₹18,000/month
────────────────────────────────
📱 App Access         [Grant Access]   ← if no app_user linked
              or      [Active ●]        ← if active app_user exists  
                      Role: Cashier
                      Last login: Today 9:41 AM
                      [Manage Permissions] [Revoke Access]
```

**Key rule:** Deleting a staff party does NOT delete the app_user (they may have created records). Instead, `is_active = 0` and `linked_party_id` is set to NULL (via ON DELETE SET NULL FK).

---

## 13. What NOT to Build

| Idea | Why not |
|------|---------|
| SQLite row-level security | Cannot be reliably enforced in SQLite; Dart-layer is sufficient |
| Separate SQLite DB per user | Makes backup/restore, shared data, and reporting impossible |
| Cloud-based user directory | Violates privacy promise unconditionally |
| Biometric per user | Android biometric is device-wide; only the device holder can use it |
| "Shared access" over internet | That is the sync problem, entirely different architecture |
| Fine-grained per-record permissions | Over-engineering; role-based is sufficient |
| Password recovery via email/SMS | No network. PIN recovery = owner resets it. |

---

## 14. Security Considerations

| Risk | Mitigation |
|------|-----------|
| Cashier sees owner PIN by shoulder-surfing | Owner and cashier use **different** PIN entry flows; owner can use biometric |
| Staff reuses PIN across their accounts | Local PINs are 4-digit; not used for anything outside the app |
| Owner loses phone, staff has PIN | PIN only unlocks the app, not the device; Android device lock is the outer security layer |
| Brute-force staff PIN | Lock user after 5 failed attempts; owner must unlock |
| Staff exports data before access revoked | Revoke access immediately; `share_plus` export can be restricted to owner-only in permissions |
| Session hijacking | No network sessions; active user is in-memory only; app restart resets to owner |

PIN storage: already using **SHA-256** via `crypto` package. For new user PINs, consider upgrading to **scrypt or PBKDF2** (still local, no network, just slower hashing). SHA-256 is fine for a 4-digit PIN with brute-force protection.

---

## 15. Key Open Questions

| # | Question | Recommendation |
|---|----------|----------------|
| Q1 | Should owner be stored in `app_users` or remain in `settings`? | **Keep in settings** — no breaking migration, backward compatible. Owner detected by `user = null` in activeAppUserProvider. |
| Q2 | Can a business have multiple owners? | No. Owner is the device holder. Other power users get `manager` role. |
| Q3 | What happens to records created under a deleted user? | Keep records; `created_by_user_id` becomes dangling FK → show "Former User" in UI. Use `ON DELETE SET NULL`. |
| Q4 | Should permissions be checked for personal (non-business) transactions? | Yes, but `business_id = NULL` in `user_permissions` means "personal data". Cashier should never see personal data. |
| Q5 | How does the backup/export respect permissions? | Only the owner can do full export. Staff can export only their own views (if `can_view` is true for that module). |
| Q6 | Should categories and accounts be permission-gated? | No — they are read-only reference data. Only settings management (CRUD on categories) should be gated. |
| Q7 | Can a Manager add other users? | No. Only the owner manages users. This avoids privilege escalation. |
| Q8 | What if the owner forgets their PIN? | Existing flow: Settings → Security → Remove PIN (requires current PIN or biometric). No change. |

---

## 16. Prioritized Implementation Plan

### Phase U0: Foundation (prerequisite, ~0.5 sprint)
- [ ] Create `app_users` table (DB v58)
- [ ] Create `user_permissions` table
- [ ] `AppUser` model + `AppUserRepository` (interface + impl)
- [ ] `activeAppUserProvider` StateProvider in Riverpod
- [ ] `permissionProvider` family provider
- [ ] Role preset seed data (manager, cashier, auditor permission sets)

### Phase U1: Cashier / Kiosk Mode (~1 sprint)
- [ ] `CashierModeSetupScreen` in Settings → Security
- [ ] Stores cashier config in `settings` table (pin + business_id) — no `app_users` yet
- [ ] `CashierModeBanner` widget (top bar badge, exit button)
- [ ] Bottom nav hides Reports, Credits, Settings in cashier mode
- [ ] FAB only shows "New Invoice" / "New Bill"
- [ ] Exit cashier mode requires owner PIN

**This phase can ship without Phase U0 (no schema changes needed for a single cashier mode).**

### Phase U2: Named Users + RBAC (~2 sprints)
- [ ] Schema + repositories from Phase U0
- [ ] `UserSelectionScreen` (launch screen when >1 user exists)
- [ ] `ManageUsersScreen` + `AddEditUserSheet` (Settings → Team)
- [ ] `StaffDetailScreen` "App Access" section (HRMS integration)
- [ ] Session timeout (idle timer in `AppWrapper`)
- [ ] Brute-force protection (lockout after 5 wrong PINs)

### Phase U3: Audit Trail (~1 sprint)
- [ ] `created_by_user_id` + `updated_by_user_id` on transactions, invoices, credit_payments
- [ ] "Created by" line in transaction detail + invoice detail
- [ ] Audit log screen (Settings → Activity Log) — filter by user, date range

---

## 17. Summary Recommendation

```
Today:     Nothing — existing single-owner model is correct for most users

Sprint 1:  Cashier Mode (Phase U1) — zero DB changes, maximum practical value
           "Hand phone to cashier; they can only create bills"

Sprint 2:  Named Users + RBAC (Phase U2) — after HRMS is stable
           "Ravi is in your staff list. Tap 'Grant App Access'. Done."

Sprint 3:  Audit Trail (Phase U3) — after multi-user is in production and proven
           "Who added this ₹50,000 credit? Ravi Kumar, yesterday at 3:42 PM."

Never:     Cloud user directory, per-row permissions, biometric per user
```

**The user story becomes a competitive differentiator:**  
"Add your cashier as staff, give them a PIN, they open the app and see their billing screen — nothing else. Your data stays yours."

---

*Last updated: 12 March 2026*  
*Next review: After HRMS Phase S2 (payslip) is shipped*
