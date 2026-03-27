# ADR-004: Event-Driven Sync Refresh Through Provider Invalidation

**Status:** Accepted  
**Date:** March 27, 2026

## Context

Sync and browser-companion writes can update SQLite without flowing through widget-local notifiers. The UI still needs to refresh promptly and correctly.

## Decision

Use `SyncEventBus` plus a declarative table-to-provider invalidation map to translate storage changes into provider refreshes.

## Consequences

- sync merges become visible without manual refresh actions
- correctness depends on maintaining table coverage in the invalidation map
- unknown tables can still trigger a safe broad refresh fallback

## Evidence In Current Implementation

- `docs/codebase/architecture/STATE_AND_DATAFLOW_ARCHITECTURE_AS_BUILT.md`
- `docs/codebase/architecture/RUNTIME_CROSS_CUTTING_AS_BUILT.md`
- `docs/codebase/SYNC_AND_IDENTITY_AS_BUILT.md`

## Related Decisions

- ADR-001
- ADR-002