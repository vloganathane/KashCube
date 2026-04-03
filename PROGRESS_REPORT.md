# Kash Cube - Progress Report
**Date:** 3 April 2026
**Current Phase:** M6 Security and Release Readiness Gate 🔄 · M1 ✅ · M2 ✅ · M3 ✅ · M4 ✅ · M5 ✅ · LAN Sync ✅ · KashCube Web W1 ✅ · Sprint 3 IAP ✅ · Code Review P0–P4 ✅ · Conflict-Free Invoice Numbering ✅

---

## Executive Summary (3 April 2026)

**M6 Slice 34 delivered**: Key rotation check infrastructure for connect-anywhere mode. `SyncKeyRotationPolicy` (sealed status types + `DefaultSyncKeyRotationPolicy` with configurable time/version thresholds) + `SyncKeyRotationChecker` that evaluates `trusted_peers` rows. DB schema v85 adds `key_version` and `key_rotated_at` to `trusted_peers`. M6 is now ~40% complete.

**M6 Slice 33 delivered**: App-layer HMAC-SHA256 per-frame integrity for the cloud signaling transport path. `HmacSyncFrameIntegrityChecker` signs every outbound data-plane frame with `_kash_sig` and silently drops inbound frames whose proof is absent or invalid. Local-first/LAN path is unchanged — the default `PassthroughSyncFrameIntegrityChecker` is a no-op. M6 is now ~20% complete.

**M5 is now complete**: the cloud signaling beta readiness gate validates all preconditions (cloud mode selected, adapter injected, TURN config consistent) before any cloud connect attempt, falling back to local signaling with structured log on failure. M5 closes with fail-closed local-first behavior fully preserved.

## Transparent Slice Reporting Contract

Starting now, every slice completion update will include this exact status block:

1. Slice ID and objective completed
2. Files changed and commit hash
3. Validation status
  - focused tests pass/fail
  - `flutter analyze` delta (new issues vs baseline)
4. Milestone progress delta
  - M1 percentage change
  - M2 percentage change
  - M3 percentage change
  - M4 percentage change
5. Estimated completion
  - remaining slices for current phase
  - estimated completion window for current phase
6. Risk flags
  - blockers
  - assumptions
  - rollback impact

Current transparent baseline:

1. M1: 100% complete
2. M2: 100% complete
3. M3: 100% complete
4. M4: 100% complete
5. M5: 100% complete
6. M6: ~40% complete (Slices 33–34 done)

Current estimated completion (if no blockers):

1. M1 closure: complete
2. M2 closure: complete
3. M3 closure: complete
4. M4 closure: complete
5. M5 closure: complete
6. M6 closure: ~2-3 slices remaining (threat model review, release hardening gate)

### Latest Work — M6 Security and Release Readiness Gate (Slice 34: Key Rotation Check)

**Commit:** `5870489` — M6 Slice 34: Key rotation check for connect-anywhere mode

Added key rotation infrastructure to complete the M6 ADR exit criterion "Verify key handling and rotation behavior":

1. `SyncKeyRotationStatus` sealed class hierarchy — `SyncKeyRotationOk`, `SyncKeyRotationRecommended(reason)`, `SyncKeyRotationRequired(reason)` — pure types with no platform dependencies
2. `SyncKeyRotationPolicy` abstract + `DefaultSyncKeyRotationPolicy` — evaluates any combination of:
   - Version floor: `keyVersion < minAcceptableVersion` → Required
   - Soft age threshold: key age > `recommendRotationAfterDays` (default 30) → Recommended
   - Hard age threshold: key age > `maxKeyAgeDays` (default 90) → Required
3. `SyncKeyRotationChecker` — maps `trusted_peers` DB rows to rotation results; uses `key_rotated_at` falling back to `paired_at` for unrotated keys; injectable `clock` for deterministic testing; `evaluateAll()` for batch audit
4. DB schema v85 (dbVersion 84 → 85): `ALTER TABLE trusted_peers ADD COLUMN key_version INTEGER NOT NULL DEFAULT 1` + `key_rotated_at TEXT` — safe defaults; all existing paired peers default to version 1 with age computed from `paired_at`

Files changed:
- `lib/data/services/sync/security/sync_key_rotation_policy.dart` (new, 130 lines)
- `lib/data/services/sync/security/sync_key_rotation_checker.dart` (new, 97 lines)
- `lib/core/constants/app_constants.dart` (dbVersion 84 → 85)
- `lib/data/services/database_helper.dart` (v85 migration block added)
- `lib/data/services/database_helper_tables.dart` (fresh-install DDL updated)
- `test/data/services/sync/sync_key_rotation_policy_test.dart` (new, ~130 lines)
- `test/data/services/sync/sync_key_rotation_checker_test.dart` (new, ~230 lines)

Validation:
1. Focused tests: 29 tests passed (0 failures)
2. New-file analyze: no issues (2 pre-existing warnings in database_helper.dart unchanged)

Milestone delta (this slice):
1–5. M1–M5: 100% → 100%
6. M6: ~20% → ~40%

Estimated completion (updated):
1. M6 in progress — next slices: threat model review, release hardening gate

---

### Latest Work — M6 Security and Release Readiness Gate (Slice 33: App-layer Frame Integrity)

**Commit:** `8c6d3a9` — M6 Slice 33: App-layer HMAC-SHA256 frame integrity for cloud sync

Added `SyncFrameIntegrityChecker` contract with two implementations:
1. `PassthroughSyncFrameIntegrityChecker` — no-op default; preserves full local-first behavior with zero overhead; correct trust boundary for LAN sessions where the existing session token is the authentication layer
2. `HmacSyncFrameIntegrityChecker({required List<int> secretBytes})` — per-frame HMAC-SHA256 integrity proof added as `_kash_sig` (hex-encoded); lexicographic key canonicalization + `jsonEncode` matches the `P2pAuthService` signing convention already in the codebase; constant-time comparison guards against timing attacks

Wired into `CloudSignalingTransportChannel`:
- Outbound: `mapOutbound → sign → sendFrame` — data-plane frames leave with `_kash_sig` added
- Inbound: `mapInbound → verify → emit` — frames without a valid proof are silently dropped before reaching the coordinator

Frame type scoping:
- Data-plane types signed/verified: `PULL`, `ROWS`, `WRITE`, `WRITE_OK`, `PUSH`, `SYNC_PLAN`
- Control-plane types pass through unsigned: `AUTH`, `SIGNAL_OFFER`, `SIGNAL_ANSWER`, `PING`, `PONG`

Files changed:
- `lib/data/services/sync/transport/sync_frame_integrity_checker.dart` (new, 131 lines)
- `lib/data/services/sync/transport/cloud_signaling_transport_channel.dart` (modified — integrity seam wired)
- `test/data/services/sync/sync_frame_integrity_checker_test.dart` (new, ~230 lines)
- `test/data/services/sync/cloud_signaling_transport_channel_test.dart` (modified — 5 integration tests added)

Validation:
1. Focused tests: 31 tests passed (0 failures)
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 100% -> 100%
4. M4: 100% -> 100%
5. M5: 100% -> 100%
6. M6: 0% -> ~20%

Estimated completion (updated):
1. M6 in progress — next slices: key rotation check, threat model review, release hardening gate

---

### Latest Work — M5 Progression (Slice 32: Cloud Signaling Beta Readiness Gate) — M5 CLOSE

**Commit:** `1b2129c` — Add cloud signaling beta readiness gate and wire into provider connect path

Completed M5 with a structured readiness gate before any cloud connect attempt:
1. Added `CloudSignalingReadinessResult` sealed type (`CloudSignalingReady` / `CloudSignalingNotReady`)
2. Added `CloudSignalingNotReadyReason` enum (cloudModeNotSelected / noAdapterInjected / turnRequiredButNoHints)
3. Added `CloudSignalingReadinessGate` that accumulates all failure reasons in a single check call
4. Added `cloudAdapterInjected` bool to `WebSyncNotifier` constructor (defaults `false`)
5. Replaced inline cloud connect block with gate-guarded flow: not-ready → log + fall back to local; ready → attempt cloud connect with existing fallback on exception
6. Added focused tests for:
  - all three ready/not-ready conditions individually
  - multi-reason accumulation
  - TURN disabled with empty hints is not a failure
  - sealed type exhaustion / distinguishability
  - provider gate default (`cloudAdapterInjected: false`)
  - provider accepts `cloudAdapterInjected: true`

Validation:
1. Focused tests: `cloud_signaling_readiness_gate_test.dart` + `web_sync_provider_test.dart` — 23 tests passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 100% -> 100%
4. M4: 100% -> 100%
5. M5: 60% -> 100% ✔ CLOSED

Estimated completion (updated):
1. M5 closure: complete
2. M6 closure: next phase (security and release readiness gate)

---

### Latest Work — M5 Progression (Slice 31: Staged TURN Config Source)

**Commit:** `e1a2053` — Add staged TURN config source abstraction and wire into provider

Completed config source abstraction to decouple TURN resolution from the provider:
1. Added `SyncTurnConfig` value type (relayMode + relayServerHints)
2. Added `SyncTurnConfigSource` abstract contract with single `resolve()` method
3. Added `EnvSyncTurnConfigSource` — compile-time env-backed default (behavioral parity with previous inline resolver)
4. Added `StaticSyncTurnConfigSource` — deterministic test double
5. Replaced `_turnRelayMode` flat field in `WebSyncNotifier` with `_turnConfigSource`; `_connectTransport` calls `.resolve()` per connect attempt
6. Replaced `resolveDefaultTurnRelayMode()` static with `defaultTurnConfigSource()` returning `EnvSyncTurnConfigSource`
7. Added focused tests for:
  - `SyncTurnConfig` default values and `toString`
  - `StaticSyncTurnConfigSource` resolve and idempotency
  - `EnvSyncTurnConfigSource` defaults in test env
  - abstract contract polymorphism
  - provider `defaultTurnConfigSource` resolver

Validation:
1. Focused tests: `sync_turn_config_source_test.dart` + `web_sync_provider_test.dart` — 21 tests passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 100% -> 100%
4. M4: 100% -> 100%
5. M5: 48% -> 60%

Estimated completion (updated):
1. M5 closure: 1-2 slices

---

### Latest Work — M5 Progression (Slice 30: Cloud Signaling Frame Mapper)

**Commit:** `8be9194` — Add cloud signaling frame mapper with coordinator parity checks

Completed frame mapper to enforce schema parity at the cloud transport boundary:
1. Added `CloudSignalingFrameMapper` with `mapInbound` (drop unknown types) and `mapOutbound` (fail-fast on unrecognized types)
2. Wired mapper into `CloudSignalingTransportChannel` for both inbound stream filtering and outbound validation
3. Made mapper injectable for testability and subclassing
4. Added parity-table test asserting all `SyncSignalingMessages` types round-trip through both directions
5. Added focused tests for:
  - all control-plane and data-plane eligible types pass inbound
  - missing/empty/non-string type fields return null inbound
  - unrecognized cloud-only types are dropped inbound
  - all routable types pass outbound
  - missing/unrecognized types throw `ArgumentError` outbound
  - transport channel drops unrecognized inbound frames
  - transport channel validates outbound types via mapper
  - custom mapper injection is observable

Validation:
1. Focused tests: `cloud_signaling_frame_mapper_test.dart` + `cloud_signaling_transport_channel_test.dart` — 21 tests passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 100% -> 100%
4. M4: 100% -> 100%
5. M5: 36% -> 48%

Estimated completion (updated):
1. M5 closure: 1-3 slices

---

### Latest Work — M5 Progression (Slice 29: TURN Relay Scaffolding)

**Commit:** `41d020d` — Add TURN relay mode scaffolding seam

Completed TURN fallback scaffolding at signaling seam without enabling network behavior:
1. Added typed TURN relay mode enums (`disabled`, `preferred`, `required`)
2. Added cloud signaling session options contract with relay mode + relay server hints
3. Threaded relay mode from provider env resolver into signaling policy selection
4. Threaded relay options from policy into cloud signaling adapter connect contract
5. Added focused tests for:
  - relay options passthrough in cloud signaling transport
  - relay mode mapping in signaling policy cloud channel creation
  - provider default TURN relay mode resolver

Validation:
1. Focused tests: `cloud_signaling_transport_channel_test.dart` + `sync_transport_policy_test.dart` + `web_sync_provider_test.dart` passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 100% -> 100%
4. M4: 100% -> 100%
5. M5: 24% -> 36%

Estimated completion (updated):
1. M5 closure: 2-4 slices

---

### Latest Work — M5 Progression (Slice 28: Cloud Signaling Adapter Seam)

**Commit:** `61d32b7` — Add cloud signaling adapter contract seam

Completed the cloud signaling transport seam behind existing feature gates:
1. Added `CloudSignalingAdapter` contract (connect/send/inbound/close)
2. Added `CloudSignalingTransportChannel` wrapper that bridges adapter frames into `SyncTransportChannel`
3. Kept default adapter fail-closed via `CloudSignalingUnavailableAdapter`
4. Extended transport policy to construct cloud signaling channel with adapter-factory injection seam
5. Added focused tests for:
  - cloud signaling transport inbound bridge and outbound forwarding
  - policy cloud-mode channel creation and fail-closed connect behavior

Validation:
1. Focused tests: `cloud_signaling_transport_channel_test.dart` + `sync_transport_policy_test.dart` + `web_sync_provider_test.dart` passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 100% -> 100%
4. M4: 100% -> 100%
5. M5: 12% -> 24%

Estimated completion (updated):
1. M5 closure: 3-5 slices

---

### Latest Work — M5 Progression (Slice 27: Feature-Gated Cloud Signaling Scaffold)

**Commit:** `ac0a93d` — Add feature-gated cloud signaling scaffolding

Completed first anywhere-mode infrastructure slice without enabling network behavior:
1. Added explicit signaling mode policy (`localLan`, `cloudRelay`)
2. Added cloud signaling placeholder channel that fails closed with `UnsupportedError`
3. Added provider signaling-mode resolver (`KASHCUBE_SYNC_SIGNALING_MODE`) with local default
4. Added cloud-mode connect attempt path with deterministic fallback to local signaling
5. Added focused tests for:
  - signaling mode selection and channel creation policy
  - cloud placeholder fail-closed behavior
  - provider default signaling mode resolver

Validation:
1. Focused tests: `sync_transport_policy_test.dart` + `web_sync_provider_test.dart` passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 100% -> 100%
4. M4: 100% -> 100%
5. M5: 0% -> 12%

Estimated completion (updated):
1. M5 closure: 4-6 slices

---

### Latest Work — M4 Closure (Slice 26: Disconnect Cleanup Integration Coverage)

**Commit:** `182f64a` — Add disconnect cleanup sync integration tests

Completed the final M4 integration coverage slice at provider boundary:
1. Added focused integration-style test proving disconnect clears pending outbound WRITE state before next session
2. Added focused integration-style test proving disconnect clears inbound replay dedupe cache before next session
3. Verified same `sync_id` can be re-sent or re-merged after session teardown because stale reliability state is not leaked across sessions

Validation:
1. Focused tests: `web_sync_provider_test.dart` passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 100% -> 100%
4. M4: 52% -> 100%

Estimated completion (updated):
1. M4 closure: complete

---

### Latest Work — M4 Progression (Slice 25: Inbound Replay Dedupe)

**Commit:** `3e40574` — Deduplicate replayed inbound sync rows

Completed provider-boundary replay dedupe for inbound sync frames:
1. Added bounded per-table dedupe cache keyed by row `sync_id`
2. Replayed `PUSH` rows with already-seen `sync_id` are filtered before merge
3. Replayed `ROWS` rows with already-seen `sync_id` are filtered before merge
4. Duplicate-only frames no longer trigger repeat database merge or repeat change notification
5. Added focused provider tests for:
  - deduping replayed `PUSH` rows before merge/notify
  - deduping replayed `ROWS` rows before merge/notify

Validation:
1. Focused tests: `web_sync_provider_test.dart` passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 100% -> 100%
4. M4: 38% -> 52%

Estimated completion (updated):
1. M4 closure: 1-2 slices

---

### Latest Work — M4 Progression (Slice 24: WRITE Ack/Retry Tracking)

**Commit:** `5655ecd` — Add WRITE ack and retry tracking

Completed bounded ack/retry semantics for outbound browser WRITE flow:
1. Outbound WRITE frames are now tracked as pending by `sync_id`
2. Incoming `WRITE_OK` clears the corresponding pending write
3. Stale unacknowledged writes retry after configurable ack timeout
4. Retry attempts are bounded and surfaced in payload metadata (`retry_count`, `is_retry`)
5. Retry exhaustion is surfaced to sync state instead of silently dropping the pending write
6. Added focused provider tests for:
  - clearing pending write on `WRITE_OK`
  - retrying stale pending writes with retry markers
  - stopping retries after max attempts

Validation:
1. Focused tests: `web_sync_provider_test.dart` passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 100% -> 100%
4. M4: 24% -> 38%

Estimated completion (updated):
1. M4 closure: 1-3 slices

---

### Latest Work — M4 Progression (Slice 23: Reconnect/Resume On Heartbeat Timeout)

**Commit:** `4926d86` — Add heartbeat-timeout reconnect orchestration

Completed bounded reconnect/resume orchestration in browser sync provider:
1. `SIGNAL_ERROR` with `HEARTBEAT_TIMEOUT` now schedules automatic reconnect attempts
2. Reconnect uses persisted session authentication path (`SESSION_AUTH`) with bounded retries
3. Retry scheduling uses incremental delay and avoids overlapping reconnect attempts
4. On successful recovery, reconnect state is reset and sync reports reconnected
5. On max retry exhaustion, state transitions to explicit user reconnect message
6. Added focused provider tests for:
  - reconnect scheduling when session is available
  - no reconnect when session context is unavailable
  - retry stop at max attempts

Validation:
1. Focused tests: `web_sync_provider_test.dart` + `webrtc_sync_transport_channel_test.dart` passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 100% -> 100%
4. M4: 12% -> 24%

Estimated completion (updated):
1. M4 closure: 2-4 slices

---

### Latest Work — M4 Progression (Slice 22: Heartbeat Liveness Foundation)

**Commit:** `8c92b59` — Add heartbeat liveness checks to hybrid WebRTC transport

Completed first reliability-hardening slice for transport liveness:
1. Added periodic control-plane heartbeat pings from `WebRtcSyncTransportChannel`
2. Added pong tracking and heartbeat timeout detection
3. On heartbeat timeout, transport emits structured `SIGNAL_ERROR` frame with `HEARTBEAT_TIMEOUT`
4. Added focused transport tests for:
  - periodic heartbeat ping emission
  - timeout signaling when pong is missing
  - timeout re-arm behavior after pong recovery

Validation:
1. Focused tests: `webrtc_sync_transport_channel_test.dart` passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 100% -> 100%
4. M4: 0% -> 12%

Estimated completion (updated):
1. M4 closure: 3-5 slices

---

### Latest Work — M3 Closure (Slice 21: Session-Scoped Data-Plane Routing)

**Commit:** `d4a903a` — Scope WebRTC routing by payload session

Completed final M3 closeout hardening for multi-session correctness:
1. Data-plane routing now resolves target bridge from payload `session_id` when present
2. Eligible payloads are no longer implicitly routed by only the latest active session
3. If a payload targets a non-ready session, transport falls back to WebSocket instead of leaking to another ready session
4. Added focused regression tests for:
  - multi-session routing to matching bridge by payload `session_id`
  - fallback to control plane when payload targets non-ready session

Validation:
1. Focused tests: `webrtc_sync_transport_channel_test.dart` passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 94% -> 100%

Estimated completion (updated):
1. M3 closure: complete

---

### Latest Work — M3 Progression (Slice 20: Data-Plane Failure Fallback Hardening)

**Commit:** `741e81e` — Harden WebRTC payload routing with control-plane fallback on send failure

Completed fail-safe routing for ready-state data-plane sends:
1. Data-plane sends are now awaited in transport dispatch path
2. If bridge/data-channel send throws, payload is immediately rerouted over WebSocket control plane
3. Added focused regression test validating fallback when ready data-plane send fails
4. Existing control-plane/data-plane split behavior remains unchanged

Validation:
1. Focused tests: `webrtc_sync_transport_channel_test.dart` passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 86% -> 94%

Estimated completion (updated):
1. M3 closure: 1 slice

---

### Latest Work — M3 Progression (Slice 19: Hybrid Transport Activation)

**Commit:** `7c43d8d` — Activate hybrid WebRTC transport routing

Completed the first live hybrid transport activation slice:
1. `WebRtcSyncTransportChannel.connect()` now opens a WebSocket-backed control plane instead of throwing
2. Control-plane inbound frames are merged into the WebRTC transport stream so preferred-WebRTC mode is now live
3. Control-plane frames continue to route over WebSocket
4. Data-plane-eligible sync frames route over WebRTC only when the active bridge reports `DATA_CHANNEL_READY`
5. Eligible payloads still fall back to WebSocket until readiness is established
6. Added focused tests for:
  - control-plane stream wiring during connect
  - control-plane routing over WebSocket
  - data-plane routing over WebRTC after readiness

Validation:
1. Focused tests: `webrtc_sync_transport_channel_test.dart` passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 78% -> 86%

Estimated completion (updated):
1. M3 closure: 1 slice

---

### Latest Work — M3 Progression (Slice 18: Ready-Gated Payload Activation)

**Commit:** `fd7d249` — Gate WebRTC payload flow on data channel readiness

Completed explicit data-channel readiness gating for payload flow:
1. Bridge shell now tracks `isDataChannelReady`
2. Outbound WebRTC frames remain buffered until `DATA_CHANNEL_READY` is received
3. Buffered frames flush immediately once runtime reports ready
4. Inbound payload frames are ignored until readiness is established
5. Added focused tests verifying:
  - outbound frames do not send before ready
  - buffered frames flush after ready event
  - inbound payloads are suppressed before ready and delivered after ready

Validation:
1. Focused tests: `webrtc_peer_ops_test.dart` + `webrtc_sync_transport_channel_test.dart` passed
2. Changed-file analyze: no issues

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 70% -> 78%

Estimated completion (updated):
1. M3 closure: 1 slice

---

### Previous Work — M3 Progression (Slice 17: Payload Callback Scaffold)

**Commit:** `e56a0ed` — Add WebRTC payload callback scaffolding

Completed initial payload-path activation scaffold:
1. Added `payloadFrames` stream and `sendDataChannelFrame()` to `WebRtcPeerOps`
2. Bridge shell now:
  - forwards buffered/live outbound frames to attached peer ops
  - forwards inbound payload frames from peer ops into bridge inbound stream
3. Android native channel now supports:
  - `sendDataChannelFrame`
  - `onDataChannelFrame` callback into Dart
4. Platform mode now has loopback-safe payload callback delivery for staged data-channel flow
5. Added focused tests for:
  - method-channel payload invocation
  - callback-driven payload receipt
  - bridge forwarding of outbound and inbound payload frames

Validation:
1. Focused tests: `webrtc_peer_ops_test.dart` + `webrtc_sync_transport_channel_test.dart` passed
2. Changed-file analyze: no issues
3. Android compile: `./gradlew :app:compileDebugKotlin` passed

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 64% -> 70%

Estimated completion (updated):
1. M3 closure: 1-2 slices

---

### Previous Work — M3 Progression (Slice 16: Native Runtime Callback Path)

**Commit:** `b4bb5ce` — Add native callback path for WebRTC runtime events

Completed native-to-Dart runtime callback delivery for platform peer-ops mode:
1. Added shared method-call handler setup in `MethodChannelWebRtcPeerOps`
2. Added per-session runtime-event controller registry for callback dispatch
3. Added native callback method contract: `onRuntimeEvent`
4. Android `MainActivity` now invokes runtime callbacks back into Dart after:
  - `createPeerSession`
  - `ensureDataChannel`
  - `closePeerSession`
5. Switched platform-mode event tests to validate callback-driven runtime event delivery instead of synthetic local emission

Validation:
1. Focused tests: `webrtc_peer_ops_test.dart` + `webrtc_sync_transport_channel_test.dart` passed
2. Changed-file analyze: no issues
3. Android compile: `./gradlew :app:compileDebugKotlin` passed

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 100% -> 100%
3. M3: 60% -> 64%

Estimated completion (updated):
1. M3 closure: 2-3 slices

---

### Previous Work — M2 Closure (Slice 15: Runtime Frames Integrated In Provider)

**Commit:** `7388284` — Handle WebRTC runtime frames in web sync provider

Completed runtime frame integration at browser provider boundary:
1. Added `WEBRTC_RUNTIME` handling in `WebSyncNotifier` message switch
2. Implemented runtime event mapping in provider:
  - `PEER_SESSION_CREATED` -> staged session progress
  - `DATA_CHANNEL_READY` -> data channel readiness progress
  - `PEER_SESSION_CLOSED` -> teardown progress
3. Preserved fallback-safe behavior while making runtime transitions visible to UI state/progress

Validation:
1. Focused tests: `webrtc_peer_ops_test.dart` + `webrtc_sync_transport_channel_test.dart` passed
2. Changed-file analyze: no issues
3. Android compile: `./gradlew :app:compileDebugKotlin` passed

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 94% -> 100%
3. M3: 57% -> 60%

Estimated completion (updated):
1. M2 closure: complete
2. M3 closure: 2-4 slices

---

### Previous Work — M2 Progression (Slice 14: Runtime Event Propagation)

**Commit:** `9bb1621` — Add WebRTC peer runtime event propagation scaffolding

Completed runtime event propagation and readiness signaling scaffolding:
1. Added peer runtime event model (`PEER_SESSION_CREATED`, `DATA_CHANNEL_READY`, `PEER_SESSION_CLOSED`)
2. Added `runtimeEvents` stream contract to `WebRtcPeerOps`
3. Implemented lifecycle event emission in:
  - `FlutterWebRtcPeerOpsShell`
  - `MethodChannelWebRtcPeerOps`
4. Added `WEBRTC_RUNTIME` control frame type for bridge/transport signaling
5. Bridge shell now subscribes to peer runtime events and forwards control frames via inbound stream
6. Bridge registration order adjusted to attach inbound listeners before peer attach/runtime sync

Validation:
1. Focused tests: `webrtc_peer_ops_test.dart` + `webrtc_sync_transport_channel_test.dart` passed
2. Changed-file analyze: no issues
3. Android compile: `./gradlew :app:compileDebugKotlin` passed

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 88% -> 94%
3. M3: 53% -> 57%

Estimated completion (updated):
1. M2 closure: 0-1 slices
2. M3 closure: 3-5 slices

---

### Previous Work — M2 Progression (Slice 13: Explicit Peer Session Lifecycle)

**Commit:** `3b43bdf` — Add explicit WebRTC peer session lifecycle contract

Completed deterministic peer session lifecycle wiring across Dart bridge and Android channel handler:
1. Added explicit peer ops lifecycle methods: `createPeerSession` and `closePeerSession`
2. Bridge shell now creates native peer session on attach and closes it during bridge teardown
3. Android channel now enforces explicit create-before-use flow
4. Added deterministic native error codes:
  - `SESSION_ALREADY_EXISTS`
  - `SESSION_NOT_FOUND`
  - existing payload codes preserved (`MISSING_SESSION_ID`, `MISSING_SDP`, `MISSING_CANDIDATE`)
5. Updated focused tests to validate lifecycle call ordering and close hook behavior

Validation:
1. Focused tests: `webrtc_peer_ops_test.dart` + `webrtc_sync_transport_channel_test.dart` passed
2. Changed-file analyze: no issues in modified Dart files
3. Android compile: `./gradlew :app:compileDebugKotlin` passed

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 82% -> 88%
3. M3: 50% -> 53%

Estimated completion (updated):
1. M2 closure: 1 slice
2. M3 closure: 3-5 slices

---

### Previous Work — M2 Progression (Slice 12: Android Peer-Ops Channel Wiring)

**Commit:** `a1a48c4` — Wire Android WebRTC peer-ops method channel

Completed native channel contract wiring for WebRTC peer ops on Android:
1. Added `kashcube/webrtc_peer_ops` method channel handler in `MainActivity`
2. Implemented session-scoped in-memory peer state for offer/answer/ICE/datachannel markers
3. Added method handlers for `setLocalOfferSdp`, `setRemoteAnswerSdp`, `addRemoteIceCandidate`, `ensureDataChannel`
4. Added validation errors for missing `session_id` / malformed payloads
5. Added structured debug logs for negotiation state transitions per session

Validation:
1. Focused tests: `webrtc_peer_ops_test.dart` + `webrtc_sync_transport_channel_test.dart` passed
2. `flutter analyze`: 35 baseline issues, 0 new hard errors
3. Android compile: `./gradlew :app:compileDebugKotlin` passed

Milestone delta (this slice):
1. M1: 100% -> 100%
2. M2: 78% -> 82%
3. M3: 48% -> 50%

Estimated completion (updated):
1. M2 closure: 1-2 slices
2. M3 closure: 3-5 slices

---

### Previous Work — M1 Closure (Slice 10: Signaling Contract Validation)

**Commit:** `7aa0b5c` — Add M1 signaling contract guard tests for coordinator

Completed M1 closure guard coverage in coordinator tests:
1. Missing `session_id` returns `SIGNAL_ERROR` with `MISSING_SESSION_ID`
2. `SIGNAL_ANSWER` before offer returns `SIGNAL_ERROR` with `ANSWER_BEFORE_OFFER`
3. Duplicate offer in same session returns `SIGNAL_ERROR` with `DUPLICATE_OFFER`
4. ICE before answer returns `SIGNAL_ACK` with `ice_queued_waiting_for_answer`

Added targeted test hooks to drive deterministic signaling frame tests:
1. `handleWebSignalFrameForTest(...)`
2. `clearWebSignalStateForTest()`

**Validation:**
- Focused tests: `test/data/services/p2p/p2p_coordinator_test.dart` ✅
- `flutter analyze`: 35 baseline issues, 0 new hard errors ✅

**Milestone delta (this slice):**
1. M1: 90% -> 100%
2. M2: 75% -> 75%
3. M3: 47% -> 47%

**Estimated completion (updated):**
1. M2 closure: 2-3 slices
2. M3 closure: 4-6 slices

---

### Previous Work — WebRTC Signaling (Slice 6: Queued ICE Replay)

**Commit:** `c9facd3` — Add queued ICE replay progression for signaling state

Completed two-phase ICE handling:
1. **ICE queueing phase** — If candidates arrive before answer, queue in-memory per session (up to 10 min TTL, 64-session capacity)
2. **ICE replay phase** — On answer arrival, iterate queued candidates and replay each with replayed flag to browser

State progression guardrails:
- Reject duplicate offers (DUPLICATE_OFFER status)
- Reject answer-before-offer (ANSWER_BEFORE_OFFER status)
- Reject ICE-before-negotiation (ICE_BEFORE_NEGOTIATION status)

Browser send-helpers (3 typed methods):
- `sendSignalOffer()` — stage offer SDP
- `sendSignalAnswer()` — stage answer SDP
- `sendSignalIceCandidate()` — stage candidate JSON

Established session lifecycle: authenticated session ID tracked through browser session → server → coordinator, cleaned up on disconnect to prevent staleness.

**Analyzer:** ✅ 34 baseline warnings, 0 new hard errors

---
---
### M2 — Local Peer Connection Adapter (Slices 7–8)

**Commits:** `eb3f6e3` · `31c9320`
## Prior Work Summary (15 March — Conflict-Free Invoice Numbering + Code Audit)
**LocalPeerConnectionAdapter** (new file):
- Per-session adapter: processes browser offer SDP and generates corresponding answer SDP
- `processOfferAndGenerateAnswer(String offerSdp)` — caches offer, generates synthetic answer
- `_generateSyntheticAnswer(String offerSdp)` — creates structurally valid answer SDP mirroring offer
- Enables deterministic negotiation without requiring real flutter_webrtc peer engine (yet)

**Coordinator integration:**
- `_webRtcAdapters` map: tracks adapter per browser session ID
- SIGNAL_OFFER handler: creates adapter, processes offer, returns ACK + staged status
- SIGNAL_ANSWER handler: retrieves cached answer from adapter, includes SDP in response
- Lifecycle: adapters cleaned up on session close and state pruning
A full code review audit was performed (P0–P4 all resolved) plus several LAN sync UX improvements and a major new feature — conflict-free multi-device invoice numbering:
**Result:** Full offer/answer/ICE exchange completes deterministically over local signaling. Browser receives complete handshake payload in single response.

**Analyzer:** ✅ 35 baseline issues, 0 new hard errors
1. **P0 — Security hardening** — PIN upgraded to PBKDF2-HMAC-SHA256 (100k iterations, 16-byte random salt) — **done** (`8737651`)
---
2. **P1 — SMS parser improvements** — sender registry expanded to 56 IDs; GPay regex bounded; dedup hash includes UPI ref no — **done**
3. **P1.5 — SMS inbox scan UI** — Scan Inbox tile, pending-SMS banner, `SmsBatchReviewSheet` — **done**
4. **P2 — Audit gaps** — permission guard, recurring catchup, action center routing, batch error surfacing — **done**
5. **P3 — DB v66 + query audit + unit tests + SMS permission screen** — bills/recurring consolidated into `scheduled_payments`; 40 unit tests passing; `/sms-permission` onboarding screen — **done** (`79efea5`)
6. **P4 — Architecture cleanup** — domain use cases extracted, `SmsParser` injectable, quotes search, home widget updates — **done** (`556bc43`)
7. **DatabaseHelper refactor** — `_onCreate` split into 11 domain schema builders — **done** (`da1d834`)
8. **Name sync** — `MyPersonalCard` ↔ `MyIdentity` kept in sync (Option A) — **done** (`1a5ed28`)
9. **Link Device QR fix** — role picker shown on FAB so joiners can scan QR — **done** (`d348214`)
10. **Devices & Sync merged screen** — `LinkedDevicesScreen` + `LinkedSessionsScreen` unified into `DevicesSyncScreen` — **done** (`00c1114`)
11. **Conflict-free invoice numbering (DB v67)** — atomic cursor table; real-time `reserve_number` protocol over Wi-Fi LAN; `pendingNumber` status for offline devices — **done** (`889356c`)

**Database:** v67
**Flutter Analyze:** ✅ **0 errors, 0 warnings**
**App Status:** All P0–P4 audit findings resolved. Codebase clean and commit-ready.

---

## What Shipped Since Last Report (15 March 2026 — P3–P4 + LAN improvements + Conflict-Free Numbers)

### P3 — DB v66 Migration + Query Audit + Unit Tests + SMS Permission Screen ✅ (commit `79efea5`)

#### DB v66 — Bills/Recurring Consolidation
- Active `recurring_transactions` rows migrated into `scheduled_payments` (`auto_create=1`, `bill_context='personal'`)
- Active `bills` rows migrated into `scheduled_payments` with `next_date` derived from `due_day`; legacy rows soft-deleted
- `recurring_transactions` rows deactivated post-migration to prevent double-generation
- Legacy tables retained (soft-deprecated) to avoid breaking existing UI until W2 cleanup

#### Parameterized Query Audit ✅
- All `rawQuery`/`rawInsert`/`rawUpdate` calls verified — zero string interpolation in SQL args

#### Unit Tests (40/40 passing) ✅
- `test/core/utils/currency_formatter_test.dart` — 20 cases covering Indian grouping (`₹1,50,000`), zero, negative, shorthand (`₹1.5L`)
- `test/data/services/sms_parser_test.dart` — all 16 sender banks/wallets tested including dedup hash stability across duplicate and near-duplicate SMS
- `test/data/services/gst_calculator_test.dart` — 10 GST rate combinations (5%, 12%, 18%, 28%); CGST/SGST split; inter-state IGST; reverse charge

#### SMS Permission Onboarding Screen ✅
- `lib/presentation/screens/settings/sms_permission_screen.dart` *(new)* — `/sms-permission` named route; rationale illustration + bullet list; "Grant Access" (calls `requestPermission()`) / "Skip for now" buttons
- `settings_screen.dart` — Scan Inbox tile now routes to `SmsPermissionScreen` when permission not yet granted, bypassing the old SnackBar dead-end

---

### P4 — Architecture Cleanup ✅ (commit `556bc43`)

#### Domain Use Cases Extracted
- `lib/domain/usecases/create_transaction_use_case.dart` *(new)* — validation + SMS dedup + repository write in one callable; used by `AddEditTransactionScreen`
- `lib/domain/usecases/process_sms_use_case.dart` *(new)* — parse → dedup check → enqueue pending confirmation; replaces inline logic in `SmsService`
- `lib/domain/usecases/record_credit_payment_use_case.dart` *(new)* — ledger debit + balance recalc + receipt generation in one atomic call
- `lib/domain/usecases/generate_gstr1_use_case.dart` *(new)* — orchestrates workbook assembly from invoice + party + HSN repos

#### SmsParser Made Injectable
- `lib/data/services/sms_parser_service.dart` *(new)* — thin `SmsParserService` wrapper with `SmsParser` field; enables constructor injection in tests
- `sms_service.dart` — now accepts `SmsParserService` param; `processSmsInbox()` delegates to `ProcessSmsUseCase`

#### Quotes Search in SearchScreen
- `search_screen.dart` — `_QuoteTile` widget added; quotes included in unified search results alongside invoices, DCs, parties, transactions

#### Home Screen Widget Config
- `home_widget_config.dart` — `pendingSmsCount` field + refresh logic on `SmsBatchReviewSheet` dismiss

---

### DatabaseHelper Refactor ✅ (commit `da1d834`)
- `_onCreate` split into 11 focused domain schema builders:
  `_createCoreTables`, `_createTransactionTables`, `_createCreditTables`, `_createSalesTables`, `_createInventoryTables`, `_createStaffPayrollTables`, `_createSyncTables`, `_createAuthTables`, `_createSchedulingTables`, `_createSettingsTables`, `_createSchemaVersionTable`
- No schema changes — pure structural refactor; all 40 unit tests pass unchanged

---

### Name Sync Option A ✅ (commit `1a5ed28`)
- `my_personal_card_screen.dart` — on save: writes `SettingsKeys.ownerName` **and** updates `identity.display_name` in DB; invalidates `myIdentityProvider`
- `profile_screen.dart` (My Identity) — on name save: also writes `SettingsKeys.ownerName` so both screens stay in sync
- Single source of truth regardless of which screen the user edits

---

### Link Device QR Bug Fix ✅ (commit `d348214`)
- `linked_devices_screen.dart` FAB previously navigated directly to the QR scanner skipping role selection
- Now presents a role-picker bottom sheet (Owner / Manager / Staff) before showing the QR, so joiners pair with the correct permissions

---

### Devices & Sync Merged Screen ✅ (commit `00c1114`)
- Separate `LinkedDevicesScreen` and `LinkedSessionsScreen` (for KashCube Web sessions) merged into single `DevicesSyncScreen`
- Segmented control at top: "Devices" tab (Android/iOS peers) vs "Web Sessions" tab (browser companions)
- Reduces navigation depth; Settings tile updated to point to new route

---

### Conflict-Free Multi-Device Invoice Numbering ✅ (commit `889356c`)

#### Problem
Multiple devices (primary tablet + secondary phone for field sales) could independently generate duplicate sequential invoice numbers (e.g., both save `INV-25-26-0042`) causing GSTN filing conflicts.

#### Solution Architecture
- **Primary path (Wi-Fi, real-time)**: secondary device sends `reserve_number` over LAN before saving → primary responds with `number_reserved` → number guaranteed unique via `BEGIN EXCLUSIVE` SQLite transaction
- **Deferred path (offline)**: save with placeholder `'PENDING-<uuid>'`, status `pendingNumber` ("Awaiting No."); primary's `assignPendingNumbers()` fills real numbers in `created_at ASC` order after delta-upload
- **FY rollover**: cursor table prefix mismatch auto-resets `last_seq` to 0 for new fiscal year

#### New Files
- `lib/data/services/number_reservation_service.dart` — `NumberReservationService.instance.reserveNext(db, {docType, prefix, count, padWidth})` — atomic cursor upsert; `assignPendingNumbers(db, fyService)` — deferred batch assignment

#### DB v67
- New table `invoice_number_cursors (doc_type TEXT PK, prefix TEXT, last_seq INTEGER, updated_at TEXT)`
- New column `pending_number_since TEXT` on `invoices`, `quotes`, `delivery_challans`

#### Protocol (both TCP + WebSocket servers)
- `reserve_number` → `number_reserved` messages added to `SyncServer` (TCP) and `WebServerService` (WS)
- `SyncClient.reserveNumber({session, docType, count})` for secondary devices connecting over LAN

#### Status Enums
- `InvoiceStatus.pendingNumber`, `QuoteStatus.pendingNumber`, `ChallanStatus.pendingNumber` added (label: "Awaiting No.", dbValue: `'pending_number'`)
- 20 exhaustive switch locations updated across 10 files — zero analyzer errors

---

## What Shipped Since 13 March 2026 (commit `8737651`)

### Full Code Review & Audit ✅ (docs/CODE_REVIEW_2026_03_15.md)
- Full `lib/` tree reviewed across architecture, bugs, security, technical debt in one session
- 15 gaps identified across P0 (security), P1 (user-visible bugs), P2 (logic & UX gaps)

### P0 — Security ✅
- `pin_hash.dart` — upgraded from bare SHA-256 (no salt) to **PBKDF2-HMAC-SHA256** (100k iterations, 16-byte random salt, `v2:` prefix); constant-time comparison; legacy `v1:` hashes accepted and silently re-hashed on next successful unlock
- `pin_lock_screen.dart` — updated to new `PinHash` API

### P1 — SMS Parser ✅
- Sender registry expanded from 38 to **56 IDs**: added Fi Money (`FIMONY`, `FIMNBY`), Slice (`SLICEP`, `SLICEB`), Jupiter (`JUPBNK`, `JUPITE`), OneCard, IDFC First Bank, Yes Bank, RBL Bank, Central Bank, Canara Bank, Union Bank, Bandhan Bank
- `_gpayReceivedAlt` regex bounded (max 40 chars named-person group) + gated to GPay senders only — eliminates false positives
- `generateDedupeHash()` now includes `upiRefNo ?? referenceId` — two UPI transfers of same amount to same party in the same minute (different ref nos) are no longer collapsed as duplicates

### P1.5 — SMS Inbox Scan UI ✅
- `settings_screen.dart` — Automation section: auto-detect toggle (persisted) + "Scan inbox now" tile with last-scan timestamp subtitle
- `sms_provider.dart` — `pendingSmsConfirmationsProvider`, `smsScanningProvider`, `smsLastScanProvider`, `scanSmsInbox()` use-case (reads up to 300 SMS, dedups via `existsByDedupeHash`, enqueues fresh)
- `app_shell.dart` — `ref.listen` on toggle starts/stops real-time listener; Home nav tab badge shows pending count (capped at "9+")
- `home_screen.dart` — `_PendingSmsBannerSliver` shown when pending count > 0 with "Review" CTA
- `sms_batch_review_sheet.dart` *(new)* — `DraggableScrollableSheet`; per-item Save / Skip / Edit; bulk Save All / Skip All

### P2 — Audit Gap Fixes ✅
- **H1** `app_shell.dart` — toggle-ON now awaits `hasPermission` before calling `startListening()`; `_smsListenerStarted` flag NOT set if permission is missing
- **H2** `scheduled_payment_provider.dart` — `processScheduledAutoCreations()` now has inner `while` loop per item, catching up all missed recurring periods in one cold start (was single-pass — missed 2nd+ periods)
- **M1** `sms_parser.dart` — `generateDedupeHash` includes `refKey = upiRefNo ?? referenceId ?? ''`
- **M2** `sms_batch_review_sheet.dart` — `_saveAll()` tracks `errorCount`; shows SnackBar `"N items could not be saved."` if any fail
- **M3** `sms_batch_review_sheet.dart` — per-row `edit_outlined` icon button opens `AddEditTransactionScreen` pre-filled (type + amount + party); removes item from pending on return
- **M4** `action_center_screen.dart` — `ActionItemType.bill` now routes to `BillsAndPaymentsScreen` in all three switch locations (was `LoansScreen` in two; one `_ActionButton.dest()` was already correct)
- **L1** `settings_screen.dart` — `_scanInbox()` calls `smsService.requestPermission()` when permission is missing instead of showing SnackBar and exiting immediately

---

## What Shipped Since 10 March 2026

### Sprint 3 — Real IAP Wiring ✅ ALL COMPLETE (commit `d21081a`)
- `in_app_purchase: ^3.2.0` added to pubspec
- `lib/data/services/iap_service.dart` — `IapService.instance` singleton; loads Play Store products, handles purchase flow, verifies receipt locally, updates `subscriptionTierProvider`
- `upgrade_screen.dart` — converted to `ConsumerStatefulWidget`; purchase buttons call `IapService.buySubscription()`; loading spinner per product; "Restore" in AppBar; dev simulation buttons retained for debug builds
- Product IDs: `com.kashcube.starter.monthly`, `com.kashcube.starter.annual`, `com.kashcube.business.monthly`, `com.kashcube.business.annual`

### KashCube Web Sprint W1 ✅ ALL COMPLETE (commit `0a16e9c`)
- `docs/KASHCUBE_WEB_SPEC.md` — full architecture spec (WhatsApp Web model)
- `pubspec.yaml` — `shelf`, `shelf_router`, `shelf_web_socket`, `web_socket_channel` added; `assets/web_ui/` registered
- `lib/data/services/web_server_service.dart` — shelf HTTP server on random port; `X-KashCube-Token` auth middleware; WebSocket push for live reload
- `lib/data/services/web_api_routes.dart` — REST handlers: dashboard, transactions CRUD (paginated), parties, categories, credits, invoices, invoice PDF (501 stub)
- `assets/web_ui/index.html` — full SPA: Dashboard, Transactions list+search, Add Transaction form, Credits, Invoices tabs
- `lib/presentation/providers/web_server_provider.dart` — `WebServerNotifier` (start/stop/revokeSession)
- `lib/presentation/screens/settings/kashcube_web_screen.dart` — QR pairing screen; "New QR" / "Stop" buttons; privacy note
- `settings_screen.dart` — "KashCube Web" tile in Sync section

### LAN Sync — Secondary Sync Now ✅ (commit `4950b40`)
- `sync_client.dart` — `buildLocalDeltas({DateTime? since})` — collects local rows for push
- `sync_provider.dart` — `SyncNowState`, `SyncNowNotifier`, `syncNowProvider`; flow: mDNS scan (10s) → TCP connect → `pullDeltas` → `pushDeltas` → stamp `last_sync_at` → handle `SyncRevokedException`
- `linked_devices_screen.dart` — secondary FAB: "Sync Now" with inline spinner; AppBar: QR re-pair icon; `ref.listen` snackbar showing rows pulled/pushed; `_syncLabel()` helper

---

## Previously Shipped (before 10 March)

### Sprint 1 — Monetization Foundation ✅ ALL COMPLETE

#### S1-T1 — `SubscriptionTier` enum + provider
- [x] `lib/core/constants/subscription_tier.dart` — `enum SubscriptionTier { free, starter, business }` with `isStarter`, `isBusiness`, `isFree`, `dbValue`, `displayName` extensions
- [x] `SettingsKeys.subscriptionTier` key added to `settings_provider.dart`
- [x] `SubscriptionTierNotifier` + `subscriptionTierProvider` — single source of truth; persisted to SQLite settings

#### S1-T2 — PDF watermark on all 3 document services
- [x] `PdfDocumentData.showFreeWatermark` field added
- [x] `PdfLayoutEngine._buildFooter()` — renders a tinted green watermark band on Free tier: _"Created with KashCube Free · Remove watermark → Upgrade to Starter at ₹499/year"_
- [x] `InvoicePdfService`, `DeliveryChallanPdfService`, `BookingConfirmationPdfService` — all accept and pass `showFreeWatermark` flag

#### S1-T3 — `UpgradePromptSheet` widget
- [x] `lib/presentation/widgets/upgrade_prompt_sheet.dart` — reusable bottom sheet with `[Share with Watermark]` + `[Upgrade to Starter ₹499/yr →]` buttons; never hard-blocks the flow

#### S1-T4 — Report export gate on Reports screen
- [x] Export FAB added to `reports_screen.dart`
- [x] Free → shows `UpgradePromptSheet`; Starter/Business → format picker (PDF P&L or CSV)

#### S1-T5 — Wire PDF share to upgrade prompt on all 4 detail screens
- [x] `InvoiceDetailScreen`, `QuoteDetailScreen`, `DeliveryChallanDetailScreen`, `BookingDetailScreen` — Free tier shows `UpgradePromptSheet` ("Share with Watermark" / "Upgrade"); Starter+ shares directly without watermark

#### S1-T6 — Upgrade Screen (UI, no real IAP yet)
- [x] `lib/presentation/screens/settings/upgrade_screen.dart` — full tier comparison table, pricing (₹59/mo or ₹499/yr · ₹129/mo or ₹999/yr), annual savings callout (30%/35%), cancellation guarantee copy, ITC deductibility note
- [x] `kDebugMode` dev buttons: "Simulate Starter" / "Simulate Business" / "Reset to Free" for QA
- [x] Wired into settings screen

---

### Sprint 2 — Starter Tier Features ✅ ALL COMPLETE

#### S2-T1 — UPI Payment QR on Invoice
- [x] `Business.upiId String?` field added with `copyWith`, `toMap`, `fromMap`, `props` updates
- [x] DB v50 migration: `ALTER TABLE businesses ADD COLUMN upi_id TEXT`
- [x] `businesses_screen.dart` — UPI ID `TextFormField` with `Icons.qr_code_outlined`, hint `'yourname@upi'`
- [x] `PdfDocumentData.upiQrBytes Uint8List?` field added
- [x] `PdfLayoutEngine` — renders 72×72 QR image + "Scan to pay via UPI" label to left of signatory box when QR bytes present
- [x] `InvoicePdfService` — `showUpiQr: bool = false` param; generates UPI URI (`upi://pay?pa=…&pn=…&am=…&tn=…&cu=INR`) → `QrPainter.toImage(200)` → `Uint8List`; uses non-deprecated `eyeStyle`/`dataModuleStyle` API
- [x] `InvoiceDetailScreen` + `QuoteDetailScreen` — `showUpiQr: tier.isStarter` wired

#### S2-T2 — 5 Industry Invoice Template Presets
- [x] `pdf_document_data.dart` — 5 new `DocumentTemplate` static consts: `pharmacy` (#006064/banner), `restaurant` (#5D4037/banner), `service` (#1565C0/minimal), `freelancer` (#37474F/minimal/no-logo), `generic` (#1B5E20/minimal)
- [x] `presets` list updated: 9 presets total (classic, modern, plain, receipt + 5 new)
- [x] `database_helper.dart` v50 migration — `_seedDocumentTemplatePresets()` extended with 5 new `INSERT OR IGNORE` rows

#### S2-T3 — Report PDF Export
- [x] `lib/data/services/report_pdf_service.dart` (NEW) — `ReportPdfService.instance.generate(MonthlyPnL, String)` → A4 P&L summary PDF with header, 3-column summary cards, income/expense category tables (sorted by amount, with % share), top 5 parties table, generated-on footer
- [x] `reports_screen.dart` — format picker bottom sheet: "P&L Summary PDF" → `ReportPdfService` → `Share.shareXFiles`; "Transaction CSV" → existing `CsvExporter`

#### S2-T4 — GSTR-1 JSON Export (Business tier)
- [x] `gstr1_service.dart` — `exportJson(Gstr1Workbook)` method added: builds GSTN portal-compatible JSON (b2b, b2cl, b2cs, cdnr, hsn, doc_issue sections); `_round2()` helper; writes to `getTemporaryDirectory()`, returns `XFile(mimeType: 'application/json')`
- [x] `gstr1_screen.dart` — `_exportJson()` method; `onExportJson` callback added to `_WorkbookPreview`; full-width "Export JSON for GST Portal" button (disabled with explanatory label when not Business tier)

#### S2-T5 — EAN Barcode Scanner for Item Catalog (Business tier)
- [x] `qr_scanner_sheet.dart` — `showBarcodeScannerSheet(BuildContext) → Future<String?>` added; scans EAN-13, EAN-8, UPC-A, UPC-E, Code128, Code39, ITF using existing `MobileScanner` + `_ScannerOverlay`
- [x] `item_catalog_screen.dart` — SKU field gets `Icons.barcode_reader` suffix icon on Business tier; taps open scanner, auto-fills SKU controller on successful scan

---

## Database Status

**Current Version:** 67

| Version | Change |
|---------|--------|
| v46–v49 | Subscription tier key, Sprint 1 settings additions |
| v50 | `businesses.upi_id TEXT`; 5 new document template presets |
| v51–v57 | Inventory, staff, RBAC, payroll tables |
| v58 | `sync_id` ULID on all 10 P0 tables; backfill; unique indexes; `linked_devices`, `device_recovery`, `pairing_history`, `plan_features`, `app_users`, auth tables (Phase 0 sync foundation) |
| v59–v60 | RBAC app_users, permissions; LAN discovery + Owner Mirror (L1) |
| v61–v62 | Staff Terminal permission-scoped sync (L2); Phase D1 My Identity |
| v63 | Context layer — `context_id` on 13 tables, `activeContextProvider` |
| v64 | Phase D3 — Linked Sessions, `shareable_plan_features`, `secondary_display_name` |
| v65 | Phase D4 — Payroll Loop; subscription + plan gates |
| v66 | Migrate active `recurring_transactions` + `bills` → `scheduled_payments`; legacy rows deactivated/soft-deleted |
| v67 | `invoice_number_cursors` table (atomic doc-no cursor); `pending_number_since TEXT` on invoices, quotes, delivery_challans |

---

## Code Quality

**Flutter Analyze:** ✅ **No issues found!** (maintained throughout all Sprint 1 + Sprint 2 work)

**Tests:** Unit + widget tests cover core models, repositories, SMS parser, formatters. Widget tests for Unified Tracking System screens (Party360°, CashFlowScreen, ActionCenter multi-select) remain outstanding from previous sprint.

---

## Feature Gate Status (as of 15 March 2026)

| Tier | Feature | Status |
|------|---------|--------|
| FREE | Transactions (SMS + manual) | ✅ |
| FREE | Credits / Udhar | ✅ |
| FREE | Budgets + in-app reports | ✅ |
| FREE | PIN + biometric lock | ✅ |
| FREE | Backup / restore (AES-256) | ✅ |
| FREE | Invoices + Quotes + DCs + Bookings | ✅ |
| FREE | PDF watermark on Free tier | ✅ Sprint 1 |
| STARTER | Watermark-free output + upgrade gate | ✅ Sprint 1 |
| STARTER | Report export (P&L PDF + CSV) | ✅ Sprint 2 |
| STARTER | Invoice templates (9 presets incl. 5 industry) | ✅ Sprint 2 |
| STARTER | UPI payment QR on invoice | ✅ Sprint 2 |
| STARTER | WhatsApp reminder buttons | ✅ |
| BUSINESS | Purchase Bills + ITC | ✅ |
| BUSINESS | E-Way Bill + transporter registry | ✅ |
| BUSINESS | GSTR-3B summary + export | ✅ |
| BUSINESS | GSTR-1 JSON export (portal-ready) | ✅ Sprint 2 |
| BUSINESS | Barcode scanner for items (EAN/UPC/Code128) | ✅ Sprint 2 |
| BUSINESS | Custom invoice templates (unlimited) | ✅ |
| BUSINESS | Inventory management | ✅ |
| BUSINESS | Staff payroll module | ✅ |
| BUSINESS | Tally XML / Excel export | ✅ |
| BUSINESS | LAN sync (Wi-Fi, zero server) | ✅ v58–v66 |
| BUSINESS | KashCube Web (browser companion) | ✅ W1 |
| BUSINESS | Conflict-free multi-device invoice numbers | ✅ v67 |
| ALL | Real IAP (Play Store) | ✅ Sprint 3 |
| ALL | SMS permission onboarding screen | ✅ P3 |
| ALL | Unit tests (40/40) | ✅ P3 |

---

## What's NOT Done (Deferred as of 15 March 2026)

- ❌ **Invoice numbering call sites** — UI save handlers on secondary devices need to call `SyncClient.reserveNumber()` before saving; `_handleDeltaUpload` in both `SyncServer` and `WebServerService` needs to call `NumberReservationService.assignPendingNumbers()` after applying deltas
- ❌ **Legacy table cleanup (bills / recurring_transactions)** — repos, providers, and screens that still read from the legacy tables need updating now that v66 migrated data into `scheduled_payments`
- ❌ **KashCube Web W2** — wire `notifyTransactionChange()` into create/edit flows (live browser push); foreground notification while server active; auto-revoke session on app pause >30 min; invoice PDF generation (current 501 stub)
- ❌ **Periodic background LAN sync** — `WorkManager` periodic task; auto-sync when primary found on same WiFi without user action
- ❌ Widget tests for Unified Tracking System screens (Party360°, CashFlowScreen, ActionCenter)
- ❌ UPI Tip Jar in Settings → About (static QR, zero infra)
- ❌ GSTR-2B reconciliation (match purchase bills vs GSTR-2B JSON import)
- ❌ Beta preparation (onboarding flow, permissions gate, Play Store Internal Test)
- ❌ e-Invoicing / IRN (requires network calls — will **never** be built)

---

## Next Steps — Priority Order

### 1. Invoice Numbering Call Sites (0.5 sprint)
- Wire `SyncClient.reserveNumber()` into the invoice/quote/DC save flow on secondary devices (detect if not primary via `isHosting` provider)
- Call `NumberReservationService.assignPendingNumbers()` in `_handleDeltaUpload` (TCP) and `_wsHandleDeltaUpload` (WS) after applying delta rows

### 2. Legacy Bills/Recurring Table Cleanup (0.5 sprint)
- Update `BillsAndPaymentsScreen` to read from `scheduled_payments` only
- Drop `bill_repository_impl.dart` and `recurring_transaction_repository_impl.dart`
- Remove legacy providers that read from `bills`/`recurring_transactions`
- Validated by: BillsAndPaymentsScreen still shows existing scheduled payments

### 3. KashCube Web W2 (1 sprint)
- Wire `WebServerService.notifyTransactionChange()` into transaction create/edit flows — browser auto-reloads on new transaction
- Add `flutter_local_notifications` persistent notification while server active ("KashCube Web active on 192.168.x.x:8080")
- Auto-revoke session when app goes to background >30 min
- Invoice PDF generation for the W1 501 stub

### 4. Periodic Background LAN Sync (0.5 sprint)
- `WorkManager` periodic task (~15 min interval)
- Check mDNS for primary on same WiFi; if found, run full sync silently
- Update sync badge on Settings tile with "Last synced X min ago"

### 5. UPI Tip Jar (0.25 sprint)
- Settings → About → "Support KashCube" → static UPI QR (₹50/₹100/₹200/custom)
- Zero infrastructure; measures user appreciation

### 6. Beta Preparation
- 3-screen first-launch flow (Welcome → SMS Permission → Profile)
- App version bump to `1.0.0-beta.1+67`
- Push to Play Store Internal Test track
- Recruit 5 real Indian SME users

---

## Current State Assessment

**What's strong:**
- **LAN sync is fully operational** — mDNS discovery, TCP delta exchange, paired device registry, secondary Sync Now flow. Far ahead of the original roadmap.
- **KashCube Web** — WhatsApp Web model, zero internet, QR pairing, full SPA. A genuine differentiator.
- **IAP live** — real Play Store purchase flow wired. Revenue collection is unblocked.
- **DB at v65** — `sync_id` on all tables since v58, all P0 sync tables present. No schema migrations needed before beta.
- **0 analyzer errors** — maintained throughout every sprint.

**Risks / Concerns:**
1. **No real users yet** — all testing is still manual + emulator. Need beta testers to validate IAP, LAN sync, and GST workflows against real Indian SME usage.
2. **KashCube Web W2 pending** — the browser companion is live but changes on the phone don't push to the browser automatically yet. The live-reload WebSocket is wired but `notifyTransactionChange()` isn't called from the transaction write path.
3. **Background sync not automatic** — secondary must tap "Sync Now" manually. A `WorkManager` periodic task would make it feel more like WhatsApp multi-device.

---

**Status:** IAP live, LAN sync end-to-end, KashCube Web W1 complete. Ready for W2 or beta prep.

**HEAD:** `4950b40` — v66 LAN sync secondary Sync Now · `flutter analyze` → 3 pre-existing infos only

