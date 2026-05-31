# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project

Kash Cube is a **privacy-first** Flutter financial tracker for the Indian market: auto-captures UPI/bank transactions from SMS, manages customer credits (udhar/khata), supports GST invoicing, and offers LAN-only multi-device sync. All data lives in local SQLite on-device.

Primary target is Android (SMS reading uses `telephony`); the codebase also runs on web (sqflite_ffi_web), Windows, and macOS for the companion experiences.

## Critical Privacy Rule — Non-Negotiable

**No network calls.** Do not introduce `http`, `dio`, `connectivity_plus`, cloud SDKs, crash reporting, or any package that phones home. The two explicit exceptions, already wired up:

1. `firebase_core` + `firebase_analytics` — opt-in only, gated through `AnalyticsService` which checks `SettingsKeys.analyticsConsent` before every call. **No financial data** (amounts, party names, balances) may ever appear in event payloads.
2. P2P/LAN-only sync via `dart_libp2p`, `bonsoir` (mDNS), `shelf` (web companion). These never reach KashCube servers.

When in doubt, assume "no network" and ask.

## Architecture

MVVM + Repository, four-layer:

```
lib/
├── core/          # theme, constants, utils, extensions
├── data/          # models, repository impls, services (DB, SMS parser, PDF, sync, GST, IAP, …)
├── domain/        # abstract repository interfaces and use cases
└── presentation/  # screens, widgets, Riverpod providers, app_shell.dart
```

**State management is Riverpod only** (`flutter_riverpod ^2.6`). Never use Provider, BLoC, GetX, or `ChangeNotifier` for shared state. `setState` is reserved for local widget state (animations, form fields).

**Repository pattern is strict:** abstract interface lives in `domain/repositories/`, implementation in `data/repositories/`. Providers depend on the interface, not the impl. There are 25 repositories and 56 SQLite tables; see `docs/codebase/DATABASE_AS_BUILT.md` for the full schema and `docs/codebase/ARCHITECTURE_AS_BUILT.md` for runtime flow.

**Database**: SQLite via `sqflite`. Always use parameterized queries. Schema changes require migrations and an update to `DATABASE_SCHEMA.md`. The auto-generated inventory at `docs/codebase/DATABASE_INVENTORY_AUTO.md` is regenerated via `make db-inventory`.

**Startup** (`lib/main.dart`): paints the loading shell first, then runs heavy async init (DB open, integrity check, Firebase init guarded by `kIsWeb || Android`, notification scheduling) after `runApp()`. Don't move blocking I/O before `runApp`.

## Theme and Locale — Always Use Tokens

```dart
final colors = Theme.of(context).extension<KashCubeColors>()!;
// Semantic colors: colors.income, colors.expense, colors.credit, colors.overdue
// Spacing: AppSpacing.xs/sm/md/base/lg/xl/xxl/xxxl
```

Never hardcode colors, font sizes, or spacing. All currency formatting uses the **Indian numbering system** (`₹1,23,456` not `₹123,456`) via `intl` with locale `en_IN`. Dates use `"24 Feb 2026"` / `"Today"`. Terminology: "Credit" not "Loan" (for udhar), "Party" not "Vendor".

## Common Commands

```bash
# Dev
flutter pub get
flutter run                         # connected device / emulator
flutter analyze                     # lint via package:flutter_lints
dart format .                       # format (CONTRIBUTING.md uses `flutter format .`, same thing)

# Tests
flutter test                                              # full suite
flutter test test/data/repositories/transaction_repository_test.dart   # single file
flutter test --name "formats in Indian numbering system"               # by test name

# Android release builds (see Makefile)
make apk            # arm64-only release APK (fastest)
make apk-universal  # split-per-ABI APKs
make apk-install    # build arm64 + adb install
make apk-aab        # Play Store App Bundle

# Tooling
make db-inventory       # regenerate docs/codebase/DATABASE_INVENTORY_AUTO.md
make db-inventory-check # asserts table count is 56
```

Test layout mirrors `lib/` (e.g. `test/data/repositories/` for `lib/data/repositories/`).

## Conventions

- Imports within the project are **relative** (`import '../models/transaction.dart'`), not `package:kash_cube/...`.
- Prefer `const` constructors; trailing commas for widget arguments.
- File names are `snake_case.dart`. One major widget per file.
- After an `await`, check `mounted` before using `BuildContext`.
- Use `debugPrint` or `AppLogger` (`talker`-backed) — never raw `print`.
- Generated files (`*.g.dart`, `*.freezed.dart`) and `build/` are excluded from analysis (see `analysis_options.yaml`).

## SMS Pipeline

`lib/data/services/` contains the SMS parser covering 46 senders / 20+ regex patterns (HDFC, ICICI, SBI, Axis, Kotak, PhonePe, GPay, Paytm, BHIM, …). Output is scored HIGH (≥0.8) / MEDIUM (0.5–0.79) / LOW (<0.5) and deduped by hash of `(amount + date + merchant + type)`. Auto-categorizer maps merchant keywords to 9 expense + 5 income categories. See `docs/codebase/SMS_PIPELINE_AS_BUILT.md` and `docs/SMS_PARSING_SPEC.md`.

## Where Else to Look

- `.github/copilot-instructions.md` — fuller rule set (privacy, theming, spacing, semantic colors). Treat as authoritative for style.
- `docs/codebase/` — **as-built** documentation generated from current source; the most accurate reference for architecture, DB, state graph, sync, PDF pipeline, GST pipeline, invoice numbering. Read these before reasoning about cross-cutting changes.
- `docs/` — product/PRD/roadmap/legal (intent, not necessarily current).
- `CONTRIBUTING.md` — PR checklist and contribution flow.
