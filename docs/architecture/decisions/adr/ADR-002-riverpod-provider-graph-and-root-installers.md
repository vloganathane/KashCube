# ADR-002: Riverpod Provider Graph And Root Installers

**Status:** Accepted  
**Date:** March 27, 2026

## Context

The application needs shared state across many business modules, along with long-lived runtime installers for sync refresh, notification scheduling, and in-app purchase listeners.

## Decision

Use Riverpod as the shared state and dependency graph, with root-level installer providers activated from the app root.

## Consequences

- cross-feature state can be composed without widget-tree coupling
- long-lived runtime behaviors are installed once at the root
- providers become the main refresh surface after sync or settings mutations
- architecture stays testable through provider and repository boundaries

## Evidence In Current Implementation

- `docs/codebase/architecture/STATE_AND_DATAFLOW_ARCHITECTURE_AS_BUILT.md`
- `docs/codebase/architecture/BOOT_AND_STARTUP_AS_BUILT.md`
- `docs/codebase/STATE_AND_NAVIGATION_AS_BUILT.md`

## Related Decisions

- ADR-004
- ADR-005