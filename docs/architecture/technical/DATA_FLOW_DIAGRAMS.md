# Data Flow Diagrams
# KashCube

**Version:** 1.0  
**Date:** March 27, 2026  
**Status:** Current / Implementation-backed

---

## 1. Overview

This document captures the major runtime data flows that matter architecturally.

The diagrams focus on where authoritative state lives, how state becomes visible in UI, and how device-local integrations are mediated.

---

## 2. Core Application Data Flow

```mermaid
flowchart LR
  User[User Action] --> UI[Screens / Widgets]
  UI --> P[Riverpod Providers]
  P --> R[Repositories]
  R --> DB[(SQLite)]
  R --> S[Local Services]
  S --> DB
  DB --> R
  R --> P
  P --> UI
```

### Notes

- SQLite remains the authoritative state store.
- Providers expose view state and async data to presentation.
- Services participate when a workflow crosses system boundaries such as SMS, documents, sync, or notifications.

---

## 3. Startup And Runtime Installation Flow

```mermaid
sequenceDiagram
  participant Main as main()
  participant Root as KashCubeApp
  participant Gate as _LockGate
  participant Shell as AppShell
  participant Providers as Installer Providers

  Main->>Main: initialize DB factory and optional subsystems
  Main->>Root: runApp(ProviderScope)
  Root->>Providers: watch sync installer
  Root->>Providers: watch notification scheduler on mobile
  Root->>Providers: watch IAP listener on mobile
  Root->>Gate: enter lock and setup gates
  Gate->>Shell: release to shell when gates pass
```

---

## 4. SMS Capture And Confirmation Flow

```mermaid
flowchart TD
  Sms[Incoming Financial SMS] --> Guard{Permission granted and auto-detect enabled?}
  Guard -- No --> Ignore[Ignore]
  Guard -- Yes --> Parse[Parse SMS locally]
  Parse --> Dedupe{Already seen?}
  Dedupe -- Yes --> Drop[Drop duplicate]
  Dedupe -- No --> Pending[Update pending SMS provider]
  Pending --> Sheet[Open confirmation sheet]
  Sheet --> Confirm[Persist transaction]
  Sheet --> Edit[Open prefilled add/edit flow]
  Confirm --> DB[(SQLite)]
  Edit --> DB
```

### Notes

- Financial SMS parsing is local-only.
- The user remains in control through confirm or edit flows.
- The runtime shell owns the user-facing confirmation surface.

---

## 5. Sync Refresh Flow

```mermaid
flowchart LR
  Merge[Sync merge writes] --> DB[(SQLite)]
  DB --> Bus[SyncEventBus emits changed table]
  Bus --> Installer[syncAutoRefreshInstallerProvider]
  Installer --> Map[Table to provider invalidation map]
  Map --> Providers[Invalidate affected providers]
  Providers --> UI[Refresh visible screens]
```

### Notes

- Sync writes are not assumed to pass through screen-level state notifiers.
- The invalidation map is the refresh bridge from storage mutation to visible UI.

---

## 6. Notification Scheduling Flow

```mermaid
sequenceDiagram
  participant DB as SQLite
  participant Up as upcomingItemsProvider
  participant Scheduler as notificationSchedulerProvider
  participant NS as NotificationService

  DB-->>Up: upcoming items snapshot
  Up-->>Scheduler: AsyncValue<List<UpcomingItem>>
  Scheduler->>NS: scheduleUpcomingNotifications(items)
```

---

## 7. Browser Companion Flow

```mermaid
flowchart TD
  Phone[Phone App Runtime] --> Session[Web Session Service]
  Session --> Token[Issue short-lived session/token]
  Token --> Browser[Browser Companion]
  Browser --> Session
  Session --> Sync[Local sync/read-write handlers]
  Sync --> DB[(SQLite)]
```

### Notes

- The browser companion is device-mediated, not backend-mediated.
- Session issuance originates from the local app runtime.

---

## 8. Backup And Export Flow

```mermaid
flowchart LR
  User[User action or reminder] --> Backup[Backup / export service]
  Backup --> DB[(SQLite)]
  Backup --> Files[Exported file or backup bundle]
  Files --> Share[Share or local storage destination]
```

---

## 9. Architectural Invariants

1. Business data must remain recoverable from local storage.
2. UI freshness after sync depends on provider invalidation, not widget-local state.
3. External inputs such as SMS and browser sessions enter through controlled service boundaries.
4. Cross-cutting runtime actions are installed once at the root, not ad hoc per screen.

---

## 10. Traceability

Seeded from:

- `docs/codebase/architecture/BOOT_AND_STARTUP_AS_BUILT.md`
- `docs/codebase/architecture/STATE_AND_DATAFLOW_ARCHITECTURE_AS_BUILT.md`
- `docs/codebase/architecture/RUNTIME_CROSS_CUTTING_AS_BUILT.md`
- `docs/codebase/SMS_PIPELINE_AS_BUILT.md`
- `docs/codebase/SYNC_AND_IDENTITY_AS_BUILT.md`