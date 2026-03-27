# ADR-003: Shell-First Adaptive Navigation With Per-Tab Navigators

**Status:** Accepted  
**Date:** March 27, 2026

## Context

KashCube exposes multiple business modules, global overlays, deep-link entry points, SMS confirmation flows, and role-based tab access. A thin single-stack router would make those interactions fragile.

## Decision

Use an adaptive `AppShell` with five root tabs and per-tab nested navigators, with the shell coordinating access control, overlays, and runtime ingress points.

## Consequences

- each tab preserves its local stack
- shell can centralize global overlays and permission checks
- adaptive navigation can switch between `NavigationRail` and `NavigationBar`
- shell becomes an architectural hotspot that must stay well-specified

## Evidence In Current Implementation

- `docs/codebase/architecture/APP_SHELL_AND_NAVIGATION_AS_BUILT.md`
- `docs/codebase/ARCHITECTURE_AS_BUILT.md`

## Related Decisions

- ADR-002
- ADR-005