# Technology Stack
# KashCube

**Version:** 1.0  
**Date:** March 27, 2026  
**Status:** Current / Implementation-backed

---

## 1. Principles For Stack Selection

The current stack reflects these constraints:

1. local-first and privacy-first operation
2. strong mobile fit with a shared codebase
3. reactive UI and feature modularity
4. predictable local persistence and migration support
5. minimal required online dependency

---

## 2. Core Stack

| Layer | Technology | Why it fits KashCube |
|---|---|---|
| UI runtime | Flutter | shared codebase for mobile, desktop, and companion-facing flows |
| Language | Dart | null-safe application code and async-first runtime model |
| State management | Riverpod | explicit dependency graph, testable providers, root installers |
| Local database | SQLite via sqflite | stable relational storage with strong offline characteristics |
| Formatting and locale | intl | Indian date and number formatting support |
| Local auth | local_auth | biometric unlock convenience without remote auth dependency |
| Charts | fl_chart | local analytics and reporting visualizations |
| File access | path_provider | safe access to device file locations |
| Sharing/export | share_plus | local export and sharing flows |
| SMS integration | telephony | Android-side financial SMS capture |

---

## 3. Cross-Cutting Supporting Packages

| Concern | Technology | Architectural role |
|---|---|---|
| In-app purchases | in_app_purchase | store-managed subscription or upgrade flows |
| Notifications | platform notification integration | reminder and upcoming-item scheduling |
| Browser companion | Flutter web and local web/session services | attached local surface, not backend SaaS |
| Sync | custom local services | peer discovery, session trust, query building, merge |

---

## 4. Data And Runtime Model Choices

### 4.1 Why Riverpod

Riverpod matches the app's need for:

- cross-feature shared state without `BuildContext` coupling
- root-installed listeners for sync and notifications
- provider invalidation as a refresh mechanism after sync merges
- testable layering between UI, repositories, and services

### 4.2 Why SQLite

SQLite fits the current architecture because it provides:

- robust local persistence
- relational integrity across business modules
- good performance for offline-heavy usage
- transparent migration control for a fast-moving schema

### 4.3 Why custom sync services instead of hosted sync

The codebase is shaped around local identity, peer trust, and session-mediated browser access. A hosted sync platform would violate the privacy and operational model the rest of the architecture assumes.

---

## 5. Explicit Non-Choices

These are intentionally not part of the stack for core business state:

- KashCube-operated backend servers
- mandatory cloud authentication
- remote primary database
- network-dependent transaction ingestion
- third-party crash or telemetry pipelines that receive financial data

---

## 6. Traceability

Seeded from:

- `pubspec.yaml`
- `docs/codebase/ARCHITECTURE_AS_BUILT.md`
- `docs/codebase/architecture/STATE_AND_DATAFLOW_ARCHITECTURE_AS_BUILT.md`
- `docs/codebase/SYNC_AND_IDENTITY_AS_BUILT.md`
- `docs/architecture/privacy/PRIVACY_ARCHITECTURE.md`