# Quality Attributes
# KashCube

**Version:** 1.0  
**Date:** March 27, 2026  
**Status:** Current / Implementation-backed

---

## 1. Overview

This document captures the primary quality attributes the current architecture optimizes for, along with scenario-style descriptions of how the implementation responds.

---

## 2. Privacy And Data Residency

| Scenario element | Description |
|---|---|
| Stimulus | User records financial activity, grants SMS permission, or generates business documents |
| Environment | routine device-local operation |
| Response | data stays on the device in SQLite and local files; no KashCube backend is required |
| Architectural mechanisms | local SQLite, local services, privacy-first constraints, no mandatory network path |

---

## 3. Offline Availability

| Scenario element | Description |
|---|---|
| Stimulus | device has no internet connectivity |
| Environment | normal day-to-day bookkeeping |
| Response | core transaction, credit, invoice, and reporting workflows continue locally |
| Architectural mechanisms | local persistence, local document generation, device-owned session model |

---

## 4. Startup Resilience

| Scenario element | Description |
|---|---|
| Stimulus | optional subsystem such as analytics, notification init, or background registration fails |
| Environment | cold start |
| Response | app continues to first frame and reaches the lock/setup shell |
| Architectural mechanisms | defensive startup ordering, try/catch around optional init, graceful degradation |

---

## 5. UI Freshness After Sync

| Scenario element | Description |
|---|---|
| Stimulus | local sync or browser-driven write updates one or more tables |
| Environment | app remains open |
| Response | affected providers are invalidated and visible screens refresh without manual reload |
| Architectural mechanisms | `SyncEventBus`, declarative table-to-provider invalidation map, root installer provider |

---

## 6. Security And Access Control

| Scenario element | Description |
|---|---|
| Stimulus | app resumes from background or a staff user enters a restricted module |
| Environment | multi-user or locked-device runtime |
| Response | lock policy is re-evaluated, biometrics may be attempted, and tab/module access is permission-checked |
| Architectural mechanisms | `_LockGate`, `local_auth`, app-user providers, module permission checks in shell |

---

## 7. Maintainability

| Scenario element | Description |
|---|---|
| Stimulus | new feature module, new syncable table, or new runtime pipeline is introduced |
| Environment | ongoing product expansion |
| Response | feature can be added within existing layers and documented through as-built plus formal docs |
| Architectural mechanisms | repository separation, provider graph, service boundaries, generated DB inventory, layered docs |

---

## 8. Performance

| Scenario element | Description |
|---|---|
| Stimulus | user navigates across tabs, opens high-volume lists, or app resumes |
| Environment | normal device usage |
| Response | tab roots remain stable, sub-stacks are isolated, and local queries avoid network dependency |
| Architectural mechanisms | nested navigators, indexed shell, local SQLite reads, targeted provider invalidation |

---

## 9. Key Tradeoffs

1. Local-first architecture improves privacy and offline reliability but pushes more sync complexity into the client runtime.
2. Event-driven provider invalidation avoids stale UI after sync but requires disciplined table-to-provider mapping maintenance.
3. Shell-centric orchestration centralizes navigation and overlays, but makes the shell a critical runtime component that must stay well-documented.

---

## 10. Traceability

Seeded from:

- `docs/codebase/architecture/BOOT_AND_STARTUP_AS_BUILT.md`
- `docs/codebase/architecture/APP_SHELL_AND_NAVIGATION_AS_BUILT.md`
- `docs/codebase/architecture/STATE_AND_DATAFLOW_ARCHITECTURE_AS_BUILT.md`
- `docs/codebase/architecture/RUNTIME_CROSS_CUTTING_AS_BUILT.md`
- `docs/architecture/privacy/PRIVACY_ARCHITECTURE.md`