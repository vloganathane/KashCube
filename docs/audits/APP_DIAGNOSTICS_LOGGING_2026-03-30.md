# App Diagnostics Logging - V1

Date: 2026-03-30
Status: Implemented (V1)

## Goal

Provide on-device diagnostics logs that are available in release builds and can be copied/shared by users for troubleshooting without any server dependency.

## What Was Implemented

1. `logger` package integrated for structured log output
2. SQLite table `app_logs` with migration to schema v82
3. `AppLogger` service:
   - Log levels: trace/debug/info/warning/error/fatal
   - DB persistence with retention cap (max 1000 rows)
   - Basic redaction of long numeric sequences
4. Global crash boundaries in startup:
   - `FlutterError.onError`
   - `PlatformDispatcher.instance.onError`
   - `runZonedGuarded`
5. In-app Logs screen:
   - Settings -> Data -> Diagnostics Logs
   - Filter by level
   - Copy logs to clipboard
   - Share logs as a text file
   - Clear logs

## Privacy Boundaries

- Logs are stored only on-device in local SQLite.
- No automatic upload or network transport.
- Basic numeric redaction is enabled in `AppLogger`.
- Operators should avoid logging raw financial payloads, SMS bodies, or full party PII.

## Known Limitations (V1)

1. Existing `debugPrint` calls across the codebase are not fully migrated yet.
2. Redaction currently masks long digit sequences only; semantic PII redaction is partial.
3. Historical errors before logger initialization are not persisted.

## Next Steps (V2)

1. Replace highest-risk silent catches with `AppLogger.instance.error(...)`.
2. Add stronger redaction rules for names, UPI IDs, and phone patterns.
3. Add category-based filtering and compact error bundles in share output.
4. Add tests for retention pruning and redaction behavior.
