# ADR-005: Defensive Startup And Graceful Degradation

**Status:** Accepted  
**Date:** March 27, 2026

## Context

The app initializes optional services such as analytics, notifications, reminders, and background tasks during startup. Those integrations should not block bookkeeping access.

## Decision

Keep startup defensive: optional subsystem failures must degrade features rather than block `runApp()` or the first frame.

## Consequences

- first-frame reliability remains prioritized over perfect subsystem availability
- startup logic stays centralized and explicit
- lock/setup/session gates run even when optional integrations fail

## Evidence In Current Implementation

- `docs/codebase/architecture/BOOT_AND_STARTUP_AS_BUILT.md`
- `docs/codebase/architecture/RUNTIME_CROSS_CUTTING_AS_BUILT.md`

## Related Decisions

- ADR-002
- ADR-003