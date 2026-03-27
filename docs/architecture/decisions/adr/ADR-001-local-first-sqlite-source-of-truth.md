# ADR-001: Local-First SQLite Source Of Truth

**Status:** Accepted  
**Date:** March 27, 2026

## Context

KashCube manages sensitive financial, credit, invoice, and business records. The implementation stores operational state in SQLite and treats local file storage as the document/export boundary.

## Decision

SQLite on the local device is the authoritative system of record for core business data.

## Consequences

- core bookkeeping workflows remain available offline
- data residency stays inside the user-controlled device boundary
- schema evolution and sync complexity stay in the client runtime
- browser companion and peer-sync flows remain subordinate to local persistence rather than replacing it

## Evidence In Current Implementation

- `docs/codebase/DATABASE_AS_BUILT.md`
- `docs/codebase/ARCHITECTURE_AS_BUILT.md`
- `docs/codebase/architecture/STATE_AND_DATAFLOW_ARCHITECTURE_AS_BUILT.md`

## Related Decisions

- ADR-004
- ADR-006