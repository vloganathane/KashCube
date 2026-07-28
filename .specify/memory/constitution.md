<!--
Sync Impact Report
Version change: template → 1.0.0
Modified principles:
  - [PRINCIPLE_1_NAME] → I. Privacy-First (NON-NEGOTIABLE)
  - [PRINCIPLE_2_NAME] → II. MVVM + Repository Architecture
  - [PRINCIPLE_3_NAME] → III. Riverpod-Only State Management
  - [PRINCIPLE_4_NAME] → IV. Test-First Discipline
  - [PRINCIPLE_5_NAME] → V. Indian Locale & Semantic Theming — Always
Added sections:
  - Technology Stack (Locked) table
  - Database Discipline
  - SMS Parsing Pipeline
  - Startup Sequence
  - Development Workflow (Code Style, Quality Gates, Documentation Sync)
  - Governance with amendment process and semantic versioning
Removed sections:
  - [SECTION_2_NAME] placeholder
  - [SECTION_3_NAME] placeholder
Templates requiring updates:
  - .specify/templates/plan-template.md → ✅ updated (Constitution Check references Privacy-First, MVVM+Repository, Riverpod-Only, Test-First, Indian Locale)
  - .specify/templates/spec-template.md → ✅ updated (requirements align with principles)
  - .specify/templates/tasks-template.md → ✅ updated (task categories reflect principles)
  - .specify/templates/commands/*.md → ✅ updated (no agent-specific references remain)
Follow-up TODOs: None
-->

# KashCube Constitution
<!-- KashCube: Privacy-first financial tracker for the Indian market -->

## Core Principles

### I. Privacy-First (NON-NEGOTIABLE)
All user data remains 100% local on-device. No network calls are permitted except two explicit, opt-in exceptions:
1. `firebase_core` + `firebase_analytics` — gated by `SettingsKeys.analyticsConsent`; `AnalyticsService` checks consent before every call. **No financial data** (amounts, party names, balances) may ever appear in event payloads.
2. LAN-only P2P sync via `dart_libp2p`, `bonsoir` (mDNS), `shelf` (web companion) — these never reach KashCube servers.

Any proposed dependency or feature that introduces network I/O must be rejected unless it falls under the two exceptions above and passes the privacy review gate.

### II. MVVM + Repository Architecture
Four-layer separation is mandatory:
```
lib/
├── core/              # Theme, constants, utils, extensions
├── data/              # Models, repository implementations, services (DB, SMS parser, backup, sync, GST, IAP)
├── domain/            # Abstract repository interfaces, use cases
└── presentation/      # Screens, widgets, Riverpod providers, app_shell.dart
```
- Repository pattern is strict: abstract interface in `domain/repositories/`, implementation in `data/repositories/`.
- Providers depend on the interface, never the concrete implementation.
- 25 repositories, 56 SQLite tables — schema changes require migrations and `DATABASE_SCHEMA.md` update.

### III. Riverpod-Only State Management
`flutter_riverpod ^2.6` is the sole shared-state mechanism.
- **Allowed**: `StateNotifierProvider`, `NotifierProvider`, `AsyncNotifierProvider`, `FutureProvider`, `StreamProvider`.
- **Forbidden**: `Provider`, `ChangeNotifier`, `Bloc`, `GetX`, `setState` for shared state.
- `setState` is reserved for purely local widget state (animations, form field focus).

### IV. Test-First Discipline
- **Unit tests** for: repositories, SMS parser, formatters, validators, use cases.
- **Widget tests** for: all screens, form validation, empty states.
- Tests live in `test/` mirroring `lib/` structure (e.g., `test/data/repositories/transaction_repository_test.dart`).
- TDD cycle: write failing test → implement → refactor. No feature merge without passing tests.

### V. Indian Locale & Semantic Theming — Always
- **Currency**: Indian numbering system via `intl` locale `en_IN` → `₹1,23,456` (never `₹123,456`).
- **Dates**: `"24 Feb 2026"` / `"Today"` / `"6:30 PM"` (12-hour with AM/PM).
- **Terminology**: "Credit" not "Loan" (udhar/khata), "Party" not "Vendor", "UPI" prominent.
- **Theme tokens only**: `Theme.of(context).extension<KashCubeColors>()!` for `income`, `expense`, `credit`, `overdue`; `AppSpacing.xs/sm/md/base/lg/xl/xxl/xxxl` for spacing. **Zero hardcoded colors, font sizes, or spacing.**

## Additional Constraints

### Technology Stack (Locked)
| Layer | Package | Version Policy |
|-------|---------|----------------|
| State | `flutter_riverpod` | ^2.6.0 |
| Database | `sqflite` | ^2.3.0 |
| SMS (Android) | `telephony` | ^0.2.0 |
| Charts | `fl_chart` | ^0.66.0 |
| Auth | `local_auth` | ^2.1.0 |
| Formatting | `intl` | ^0.19.0 |
| Files | `path_provider` | ^2.1.0 |
| Share/Export | `share_plus` | ^7.2.0 |
| Sync (P2P) | `dart_libp2p`, `bonsoir`, `shelf` | Pinned per `pubspec.yaml` |
| Analytics (opt-in) | `firebase_core`, `firebase_analytics` | Pinned per `pubspec.yaml` |

**Forbidden**: `http`, `dio`, `connectivity_plus`, any cloud SDK, crash reporting, ads, tracking, telemetry packages.

### Database Discipline
- SQLite via `sqflite` (Android/iOS/macOS) / `sqflite_ffi_web` (web).
- **Always parameterized queries** — no string interpolation in SQL.
- Migrations required for every schema change; update `DATABASE_SCHEMA.md` and run `make db-inventory` to regenerate `docs/codebase/DATABASE_INVENTORY_AUTO.md`.

### SMS Parsing Pipeline
- 46 known senders, 20+ regex patterns (HDFC, ICICI, SBI, Axis, Kotak, PhonePe, GPay, Paytm, BHIM, …).
- Confidence scoring: HIGH (≥0.8), MEDIUM (0.5–0.79), LOW (<0.5).
- Deduplication by hash of `(amount + date + merchant + type)`.
- Auto-categorization via merchant keywords → 9 expense + 5 income categories.
- Full spec: `docs/SMS_PARSING_SPEC.md`; as-built: `docs/codebase/SMS_PIPELINE_AS_BUILT.md`.

### Startup Sequence
`lib/main.dart` paints the loading shell **first**, then runs heavy async init (DB open, integrity check, Firebase init guarded by `kIsWeb || Platform.isAndroid`, notification scheduling) **after** `runApp()`. No blocking I/O before `runApp()`.

## Development Workflow

### Code Style
- Relative imports within project (`import '../models/transaction.dart'`).
- `const` constructors preferred; trailing commas in widget argument lists.
- File names: `snake_case.dart`; one major widget per file.
- `debugPrint` or `AppLogger` (`talker`-backed) — never raw `print`.
- After `await`, check `mounted` before using `BuildContext`.

### Quality Gates (CI)
```bash
flutter analyze          # lint via package:flutter_lints
dart format .            # formatting (or `flutter format .`)
flutter test             # full test suite
```
All gates must pass before merge. `make apk` / `make apk-aab` for release artifacts.

### Documentation Sync
As-built docs in `docs/codebase/` are the authoritative reference for architecture, DB schema, state graph, sync, PDF pipeline, GST pipeline, invoice numbering. Update them when behavior changes.

## Governance

- This constitution supersedes all other practices, guides, and informal conventions.
- **Amendment process**: Propose change → update this file → bump version per semantic versioning → update dependent templates (plan, `plan, spec, tasks, commands`) → record in Sync Impact Report (HTML comment at top of this file).
- **Versioning**:
  - MAJOR: Backward-incompatible principle removal or redefinition.
  - MINOR: New principle/section added or materially expanded.
  - PATCH: Clarifications, wording fixes, non-semantic refinements.
- **Compliance review**: Every PR must verify adherence to all principles. Complexity must be justified.
- **Runtime guidance**: `.github/copilot-instructions.md` and `CLAUDE.md` are the living style guides for AI and human contributors; keep them in sync with this constitution.

**Version**: 1.0.0 | **Ratified**: 2026-02-24 | **Last Amended**: 2026-07-08
