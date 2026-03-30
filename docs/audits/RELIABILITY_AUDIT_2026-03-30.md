# Reliability Audit - Silent Failures and Crash Risks

Date: 2026-03-30
Scope: `lib/**/*.dart`

## Objective

Create a reproducible inventory of places where failures can be silently ignored and where runtime crashes are likely, so fixes can be applied in small, safe batches.

## Audit Method

Static scan patterns used:

1. Empty catch blocks: `catch (...) {}`
2. Ignored exception variable: `catch (_) { ... }`
3. Ignored stream error callbacks: `onError: (_) ...`
4. Heuristic non-null assertions (`!`) as crash-risk surface

Generated artifacts:

- `docs/audits/silent_empty_catches_2026-03-30.txt`
- `docs/audits/catch_underscore_2026-03-30.txt`
- `docs/audits/onerror_underscore_2026-03-30.txt`
- `docs/audits/non_null_assertions_heuristic_2026-03-30.txt`

## Headline Metrics

- Empty catch blocks: 13
- `catch (_)`: 61
- `onError: (_)`: 3
- Non-null assertion heuristic matches: 704

Notes:

- `catch (_)`: not always wrong, but high risk when no logging or user feedback exists.
- Non-null assertion count is heuristic and over-inclusive; use as prioritization signal, not absolute defect count.

## Critical Gaps

1. No global crash boundary configured in `main.dart`
   - No matches found for `FlutterError.onError`, `PlatformDispatcher.instance.onError`, or `runZonedGuarded`.
2. Multiple true silent-failure points (`catch (_) {}`) in core/data/presentation paths.
3. Error swallowing in stream listeners can hide connectivity and lifecycle issues.

## Top Hotspots By Ignored Exceptions

From `catch_underscore_2026-03-30.txt`:

1. `lib/presentation/web/web_url_reader_web.dart` (6)
2. `lib/presentation/providers/invoice_provider.dart` (4)
3. `lib/data/services/plan_gate.dart` (3)
4. `lib/data/services/p2p/p2p_discovery_service.dart` (3)
5. `lib/data/services/database_helper.dart` (3)
6. `lib/core/utils/deep_link_vcard.dart` (3)

## Top Hotspots By Non-Null Assertions (Heuristic)

From `non_null_assertions_heuristic_2026-03-30.txt`:

1. `lib/presentation/screens/invoices/quote_builder_screen.dart` (58)
2. `lib/presentation/screens/invoices/invoice_detail_screen.dart` (32)
3. `lib/presentation/screens/invoices/delivery_challan_detail_screen.dart` (30)
4. `lib/presentation/screens/parties/party_360_screen.dart` (27)
5. `lib/presentation/screens/bookings/booking_detail_screen.dart` (24)
6. `lib/presentation/screens/loans/loans_screen.dart` (22)

## Fix Strategy (One-by-One, Low Risk)

### Phase 1 - Stop Silent Failures (highest impact)

Target first:

1. All 13 empty catch blocks (`silent_empty_catches_2026-03-30.txt`)
2. 3 `onError: (_) ...` handlers (`onerror_underscore_2026-03-30.txt`)

Rule for each fix:

1. Preserve behavior where needed.
2. Add `debugPrint` with operation context and exception details.
3. Return explicit fallback or user-visible message (snackbar/banner/result error).
4. Add a focused unit/widget test if the path is user-facing.

### Phase 2 - `catch (_) { ... }` hardening

Process files in descending count (hotspot order above), converting to typed handling.

Preferred pattern:

- `catch (e, st)` and log both error and stack.
- Convert ambiguous bool/null fallback into explicit failure state.

### Phase 3 - Crash-risk review of `!`

Start from top 6 files in non-null assertion list.

For each `!`:

1. Keep if precondition is provably guarded in same path.
2. Replace with safe branch (`if (x == null) return ...`) where user data/lifecycle can violate assumptions.
3. Add assertion comments only when logically guaranteed by invariant.

## Suggested Tracking Format

Use a simple checklist per file:

- [ ] File audited
- [ ] Silent catches removed or justified
- [ ] User-visible error path added where relevant
- [ ] Tests added/updated
- [ ] Re-reviewed after `flutter analyze`

## Recommended Next Execution Batch

Batch A (quick win, minimal behavior change):

1. `lib/presentation/app_shell.dart`
2. `lib/presentation/web/web_url_reader_web.dart`
3. `lib/data/services/web/web_browser_session.dart`
4. `lib/data/services/database_helper.dart` (only empty catches first)

Expected result:

- Eliminate true silent failures in shared lifecycle/linking paths.
- Improve debuggability without changing product flows.

## Implemented Foundation (2026-03-30)

The following reliability foundation was implemented to support release-safe diagnostics:

1. Local diagnostics log storage (`app_logs` table) with retention pruning
2. Startup crash boundaries in `main.dart`:
   - `FlutterError.onError`
   - `PlatformDispatcher.instance.onError`
   - `runZonedGuarded`
3. `AppLogger` service using the `logger` package and DB persistence
4. In-app diagnostics UI (`Diagnostics Logs` in Settings -> Data):
   - View recent logs
   - Filter by level
   - Copy logs
   - Share logs
   - Clear logs

This establishes the baseline needed to fix silent failure points one-by-one and verify outcomes in release builds without relying on remote telemetry.
