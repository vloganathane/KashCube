# KashCube — Code Review & Brainstorm
**Date:** 15 March 2026  
**DB Version at time of review:** 65  
**Scope:** Full `lib/` tree — architecture, bugs, security, technical debt, roadmap  
**Last updated:** 15 March 2026 — P0 + P1 + P1.5 (SMS UI) + P2 audit fixes applied, see §7

---

## 1. Architecture Assessment

### Strengths
- MVVM + Repository pattern well-executed — clean separation between `data/`, `domain/`, `presentation/`
- Riverpod-only state management; no BLoC/GetX/setState drift for shared state
- SQLite at v65: WAL mode, foreign keys, integrity check on every open, daily DB snapshot, periodic VACUUM — production-grade setup
- Privacy commitment consistent throughout — no HTTP imports, no analytics, no crash reporting SDKs
- 25 domain repository interfaces each matched 1:1 by a `data/` implementation
- Indian locale throughout: `en_IN` currency format, `NumberFormat.currency(locale: 'en_IN', symbol: '₹')` used correctly

### Weaknesses
- **`domain/` layer is hollow** — `usecases/` folder from the original spec never materialized. Business logic leaks into repositories and services instead of living in dedicated use cases
- **`domain/models/`** has only `permission.dart` — all other "domain models" are actually `data/models/`
- **No unit or widget tests** — only the default Flutter scaffold `widget_test.dart` exists. 65 DB migrations and a complex SMS parser have zero test coverage

---

## 2. Bugs

### Critical

| # | Location | Description |
|---|----------|-------------|
| ~~B1~~ ✅ | `lib/presentation/providers/dashboard_provider.dart` | ~~`DashboardNotifier` constructs `TransactionRepositoryImpl()` directly — bypasses `transactionRepositoryProvider`. When the user switches to a linked business context, the home dashboard still shows personal data.~~ **Fixed:** All five providers (`dashboardSummaryProvider`, `todayCashflowProvider`, `accountBalancesProvider`, `allTimeInvestmentProvider`, `totalBalanceProvider`) now use `ref.watch(transactionRepositoryProvider)` and rebuild on context switch. |
| ~~B2~~ ✅ | `lib/presentation/providers/dashboard_provider.dart` | ~~`allTimeInvestmentProvider` casts `_transactionRepo as TransactionRepositoryImpl`.~~ **Fixed:** `getAllTimeInvestments()` and `getAllTimeByPaymentMethod()` added to the abstract `TransactionRepository` interface; `@override` added to the impl; cast removed. |

### Medium

| # | Location | Description |
|---|----------|-------------|
| ~~B3~~ ✅ | `lib/data/services/sms_parser.dart` | ~~Fi Money (`FIMONY`), Slice (`SLICEP`), Jupiter (`JUPBNK`), OneCard, IDFC First Bank absent.~~ **Fixed:** Added 18 new sender IDs: Fi Money (`FIMONY`, `FIMNBY`), Slice (`SLICEP`, `SLICEB`), Jupiter (`JUPBNK`, `JUPITE`), OneCard (`ONECRD`), IDFC First Bank (`IDFCBK`, `IDFCFB`), Yes Bank, RBL Bank, Central Bank, Canara Bank, Union Bank, Bandhan Bank. `_isUpiApp()` updated to include Fi/Slice/Jupiter for generic UPI pattern gating. |
| ~~B4~~ ✅ | `lib/data/services/sms_parser.dart` | ~~`_gpayReceivedAlt` greedy pattern caused false positives.~~ **Fixed:** (1) Regex now uses a bounded named-person group `[A-Za-z][A-Za-z0-9 .&\-]{1,40}?` instead of greedy `.+?$`. (2) Pattern now only fires when `_normalizeSender` resolves to `GPAY` or `GOOGLEPAY` — completely eliminated for non-GPay senders. |
| B5 | `lib/data/repositories/bill_repository_impl.dart` | `bills` table (legacy) and `scheduled_payments` table both exist with separate repos. `BillsAndPaymentsScreen` still queries the legacy table, creating a split view of what the user sees across screens. |
| B6 | `lib/data/services/database_helper.dart` | `recurring_transactions` table coexists with `scheduled_payments` — two sources of truth for the same concept, no tombstoning or migration to unify them. |

---

## 3. Security Checklist

| Item | Status | Notes |
|------|--------|-------|
| SQL injection: parameterized queries | ⚠️ Unverified | Run: `grep -rn "rawQuery\|rawInsert\|rawUpdate" lib/data/repositories/` and confirm no string interpolation in SQL args |
| PIN storage | ✅ Fixed | Was bare SHA-256 (no salt). Upgraded to **PBKDF2-HMAC-SHA256** (100k iterations, 16-byte random salt, `v2:` prefix). Legacy hashes accepted and silently re-hashed on next successful unlock. Constant-time comparison added. |
| Encrypted backup IV | ✅ Confirmed safe | IV generated via `Random.secure()` per export — no reuse. Salt also random per export. PBKDF2-HMAC-SHA256 key derivation. |
| LAN sync private key storage | ✅ Confirmed safe | Ed25519 seed stored in `FlutterSecureStorage` under `primary_signing_key` and `identity_private_key` — not SharedPreferences. |
| Network calls | ℹ️ Accepted exception | `iap_service.dart` calls Google Play Billing — unavoidable for subscription verification. No other network calls exist. |
| GSP connector | ⚠️ Unverified | `domain/repositories/gsp_connector.dart` defines optional HTTP POST for GST e-invoice IRN. Confirm UI gate (explicit user action) exists before invoking it. |

---

## 4. Technical Debt

| Debt | Priority | Notes |
|------|----------|-------|
| Hollow `domain/` layer — no use cases | Medium | Extract: `ProcessSmsUseCase`, `CreateTransactionUseCase`, `GenerateGstr1UseCase`, `RecordCreditPaymentUseCase` |
| Deprecate `bills` table (DB v66) | Medium | Migrate all screens to `scheduled_payments`; drop `bill_repository_impl.dart`; remove table in migration |
| Deprecate `recurring_transactions` table (DB v66) | Medium | Migrate remaining data to `scheduled_payments`; drop repo and table |
| Split `DatabaseHelper._onCreate` | Low | Extract per-domain schema builders: `_createTransactionTables()`, `_createGstTables()`, `_createSyncTables()`, etc. At v65 the method must be enormous |
| `_LockGate` routing god widget | Low | Extract into a `GoRouter` redirect guard — currently handles PIN, biometric, identity check, user selection, web session in one widget |
| `SmsParser` as static class | Low | Refactor to injectable singleton (non-static) so it can be properly unit-tested with mocked dependencies |

---

## 5. Layer-by-Layer Summary

### `core/`
- `AppConstants.dbVersion = 65` — heavy migration history
- `CurrencyFormatter` uses `en_IN` locale — correct Indian comma grouping (₹1,23,456)
- `AppSpacing` tokens used consistently — no hardcoded sizes detected
- `KashCubeColors` extension implements both `copyWith` and `lerp` correctly
- `SubscriptionTier` enum with gate-checking extensions is clean

### `data/models/` (42 files)
- `Transaction` — 9 types (`income, expense, lent, borrowed, invested, receivedBack, paidBack, redeemed, transfer`) with V6 migration fallbacks
- `Invoice` — supports `tax_invoice / bill_of_supply / credit_note / debit_note` + IRN + EWB fields
- `MyIdentity` — Ed25519 public key model for LAN sync identity
- `HomeWidgetConfig` — configurable home tile order/visibility
- Models are data-layer-only; domain has only `permission.dart`

### `data/repositories/` (25 files)
- All use `DatabaseHelper.instance.withDatabase(...)` — resilient to WorkManager isolate collisions
- All async, all parameterized queries (to be confirmed by audit)

### `data/services/` (56 files)
- `database_helper.dart` — WAL mode, FK enforcement, integrity check, daily snapshot, periodic VACUUM
- `sms_parser.dart` — 38 sender IDs, 15+ regex patterns, SHA-256 dedup hash, confidence scoring
- `backup_service.dart` + `encrypted_backup_service.dart` — AES-256-GCM, no cloud
- `sync_server.dart` + `sync_client.dart` + `ws_sync_transport.dart` — LAN WebSocket sync
- `web_server_service.dart` — local HTTP server for browser companion
- `fiscal_year_service.dart` — April–March FY management with archive triggers
- `gstr1_service.dart` + `gstr3b_service.dart` + `gst_calculator.dart` — full GST compliance
- `iap_service.dart` — Google Play Billing, kept alive via `keepAlive` provider
- `identity_service.dart` — Ed25519 keypair for device identity

### `presentation/providers/` (44 files)
- Pure Riverpod 2.x; `StateNotifierProvider` for CRUD lists, `FutureProvider` for read-only, `StateProvider` for simple sync state
- `transactionRepositoryProvider` and `creditRepositoryProvider` rebuild on `activeContextProvider` change — correct
- `dashboardProvider` does NOT rebuild on context change — **BUG B1**

### `presentation/screens/` (21 folders, ~80 files)
- All 5 tabs present: Home, Transactions, Business, Contacts, Settings
- GST screens: GSTR-1, GSTR-3B offset, purchase bills
- Settings: 23 sub-screens (PIN, biometric, backup, LAN sync, FY close wizard, KashCube Web, storage health, etc.)

### `presentation/widgets/` (20 files)
- `SpeedDialFab` — contextual per-tab FAB
- `SmsConfirmationSheet` — pending SMS review queue
- `UpgradePromptSheet` — subscription gate UI
- `ReadOnlyModeBanner` — shown during active LAN sync transport

---

## 6. Feature Brainstorm (Privacy-Compliant, Local-Only)

| Feature | Value | Effort | Notes |
|---------|-------|--------|-------|
| **Cashflow forecast** | High | Medium | Use `scheduled_payments` upcoming items to project balance 30/60/90 days forward — pure local math, no ML needed |
| **Smart category suggestion** | High | Medium | Learn from prior categorisations of the same `party_name` — local map, updated on every save |
| **Pincode-based locality autocomplete** | Medium | Low | `assets/data/` pincode asset already exists; surface in `PartyFormSheet` address fields |
| **WhatsApp reminder deep link** | High | Low | `PartyReminder` model exists; add one-tap "Send via WhatsApp" using `wa.me/+91{phone}?text=...` — no API key, deep link only |
| **PDF batch export by FY** | Medium | Medium | Bundle all invoices for a FY into a single PDF — useful for CA handoff |
| **Android home screen widget** | Medium | High | Expose today's balance via WorkManager + Android `AppWidgetProvider` — no data leaves device |
| **Party merge** | Medium | Medium | When two party records share phone/similar name, offer merge — reassigns all linked transactions/credits/invoices |
| **Tally XML nightly auto-export** | Low | Low | WorkManager task to auto-generate and save to `Downloads/` folder — user already has Tally export screen |
| **Action Center priority ranking** | Medium | Low | Define explicit priority: overdue credit > low stock > upcoming EMI > backup nudge |
| **Search coverage audit** | Medium | Low | Ensure `SearchScreen` indexes invoices, quotes, bookings (likely only transactions + parties today) |

---

## 7. Recommended Next Actions (Ordered by Priority)

```
P0 — Fix now (data integrity / security)                                  [DONE]
  [x] Fix dashboard_provider.dart — all 5 providers now use transactionRepositoryProvider
  [x] Remove `as TransactionRepositoryImpl` cast — methods added to abstract interface
  [x] pin_hash.dart — upgraded from bare SHA-256 to PBKDF2-HMAC-SHA256 (100k iters, random salt)
  [x] encrypted_backup_service.dart — confirmed: random IV + salt per export ✓
  [x] identity_service.dart — confirmed: private key in FlutterSecureStorage ✓

P1 — Short term (user-visible bugs)                                      [DONE]
  [x] Added 18 new sender IDs: Fi/Slice/Jupiter/OneCard/IDFC First/Yes/RBL/Canara/Union/Bandhan
  [x] Tightened _gpayReceivedAlt: bounded group (max 40 chars) + GPay-sender-only gate

P1.5 — SMS UI (missing feature)                                          [DONE]
  [x] smsAutoDetectEnabledProvider — persisted to settings DB; default true for existing users
  [x] Settings → Automation section — live toggle + "Scan inbox now" button with last-scan subtitle
  [x] scanSmsInbox() — reads up to 300 SMS, dedups against DB via existsByDedupeHash, enqueues fresh
  [x] smsScanningProvider + smsLastScanProvider — scan loading state + SharedPreferences timestamp
  [x] AppShell — ref.listen on toggle starts/stops real-time listener dynamically
  [x] AppShell — Home nav tab badge shows pending count (capped at "9+")
  [x] HomeScreen — _PendingSmsBannerSliver shows banner with "Review" button when count > 0
  [x] SmsBatchReviewSheet — DraggableScrollableSheet; per-item Save/Skip + bulk Save All/Skip All

P2 — Audit gap fixes                                                     [DONE]
  [x] H1: AppShell toggle-ON now awaits hasPermission before startListening(); resets flag on fail
  [x] H2: processScheduledAutoCreations inner while-loop catches up all missed periods per item
  [x] M1: generateDedupeHash includes upiRefNo/referenceId — prevents same-minute duplicate collapse
  [x] M2: Batch Save All reports failed item count via SnackBar instead of silently swallowing
  [x] M3: SmsBatchReviewSheet — per-row "Edit" button opens AddEditTransactionScreen pre-filled
  [x] M4: Action center ActionItemType.bill now navigates to BillsAndPaymentsScreen (was LoansScreen)
  [x] L1: Settings "Scan inbox" requests permission via dialog instead of SnackBar+exit
  Note: L2 (billContext null) — model already defaults to 'personal', no fix needed.

P3 — Medium term (remaining technical debt)                              [NEXT]
  [ ] DB v66 migration: deprecate bills + recurring_transactions tables; unify under scheduled_payments
  [ ] Parameterized query audit: grep rawQuery/rawInsert/rawUpdate across all repositories
  [ ] Write unit tests: SmsParser (all regex patterns), CurrencyFormatter, GstCalculator, dedup hash
  [ ] Add SMS permission onboarding screen (/sms-permission route) with rationale text

P4 — Long term (architecture)
  [ ] Add domain/usecases/ layer — extract business logic from repositories into use cases
  [ ] Refactor _LockGate into GoRouter redirect guard
  [ ] Refactor SmsParser to injectable singleton for testability
  [ ] HomeWidgetId.pendingSms — optional, gated by smsAutoDetectEnabledProvider
  [ ] Search: add SearchFilter.quotes distinct from invoices
```

---

## 8. File Quick-Reference

| Concern | File |
|---------|------|
| Dashboard context bug | [lib/presentation/providers/dashboard_provider.dart](../lib/presentation/providers/dashboard_provider.dart) |
| SMS sender registry | [lib/data/services/sms_parser.dart](../lib/data/services/sms_parser.dart) |
| PIN hashing | [lib/core/utils/pin_hash.dart](../lib/core/utils/pin_hash.dart) |
| Backup encryption | [lib/data/services/encrypted_backup_service.dart](../lib/data/services/encrypted_backup_service.dart) |
| Identity key storage | [lib/data/services/identity_service.dart](../lib/data/services/identity_service.dart) |
| DB schema + migrations | [lib/data/services/database_helper.dart](../lib/data/services/database_helper.dart) |
| Context-aware repo providers | [lib/presentation/providers/transaction_provider.dart](../lib/presentation/providers/transaction_provider.dart) |
| Navigation / routing gate | [lib/main.dart](../lib/main.dart) |
| App shell + tabs | [lib/presentation/app_shell.dart](../lib/presentation/app_shell.dart) |
| Currency formatting | [lib/core/utils/currency_formatter.dart](../lib/core/utils/currency_formatter.dart) |
| Subscription gating | [lib/core/constants/subscription_tier.dart](../lib/core/constants/subscription_tier.dart) |
