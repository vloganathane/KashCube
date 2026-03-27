# ADR-006: No KashCube Backend And A Local Trust Model

**Status:** Accepted  
**Date:** March 27, 2026

## Context

The codebase already contains browser companion, peer sync, local identity, and trust/session infrastructure. Those features are designed around device-mediated trust rather than a KashCube-hosted server.

## Decision

Do not introduce a KashCube-operated backend as a prerequisite for core data ownership, identity, or daily workflows. Trust remains local, explicit, and session-based.

## Consequences

- browser and peer surfaces must be attached to the device runtime rather than promoted to cloud authorities
- privacy guarantees remain aligned with the product promise
- more complexity stays in local sync, pairing, and session management

## Evidence In Current Implementation

- `docs/codebase/SYNC_AND_IDENTITY_AS_BUILT.md`
- `docs/architecture/privacy/PRIVACY_ARCHITECTURE.md`
- `docs/architecture/technical/SYSTEM_CONTEXT.md`

## Related Decisions

- ADR-001
- ADR-004