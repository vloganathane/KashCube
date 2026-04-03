# ADR-007: WebRTC Data Plane With Local And Cloud Signaling

**Status:** Accepted  
**Date:** April 3, 2026

## Context

Web Companion and sync reliability requirements now include two execution contexts:

1. local network sessions (phone <-> browser on LAN)
2. optional connect-anywhere sessions for users who opt in

The current implementation path is primarily LAN HTTP/WebSocket transport. It works for local scenarios but does not provide a single transport model that can reliably span both local and internet-assisted connectivity.

## Decision

Adopt WebRTC DataChannel as the primary sync transport data plane.

Separate control plane from data plane:

1. control plane handles signaling, session bootstrap, and liveness
2. data plane carries sync payloads over WebRTC

Support two signaling backends behind one protocol:

1. local signaling backend (embedded in app runtime)
2. cloud signaling backend (for opt-in anywhere mode)

Connection policy is direct-first with relay fallback:

1. attempt direct peer connection first
2. fallback to TURN relay only when direct path fails

## Consequences

- one transport architecture can serve both local-first and connect-anywhere modes
- reliability improves through ICE negotiation and relay fallback under difficult NAT/firewall conditions
- signaling infrastructure is introduced for anywhere mode and must be operated with clear SLOs
- protocol complexity increases and requires explicit state-machine handling for reconnect/resume
- existing sync merge/domain logic remains reusable through a transport adapter boundary

## Security And Trust Constraints

- transport-level DTLS is necessary but not sufficient for financial data
- payload encryption and integrity remain application-layer responsibilities
- signaling and relay infrastructure are treated as untrusted transport components
- local-first behavior remains the default product posture; anywhere mode is explicit opt-in

## Migration Checklist

| Milestone | Owner | Target Date | Status | Exit Criteria |
| --- | --- | --- | --- | --- |
| M1: Signaling protocol freeze (v1) | Sync Lead | 2026-04-10 | Done | Offer/answer/ICE schema finalized in docs with coordinator guard contract tests |
| M2: Transport adapter integration | App Lead | 2026-04-17 | Done | WebRTC DataChannel adapter wired behind sync transport interface |
| M3: Local mode end-to-end path | Web Companion Lead | 2026-04-24 | Done | Phone and browser complete authenticated sync over local signaling |
| M4: Reliability hardening | QA Lead | 2026-05-01 | Done | Heartbeat, reconnect, ack/retry, dedupe pass integration test suite |
| M5: Anywhere mode infrastructure beta | Infra Lead | 2026-05-08 | In Progress | Cloud signaling plus TURN fallback available in staging |
| M6: Security and release readiness gate | Security Lead | 2026-05-15 | Not Started | App-layer payload encryption, key rotation checks, and threat review approved |

Notes:

1. Local mode remains default throughout migration.
2. Anywhere mode stays feature-flagged until M6 sign-off.

## Detailed Implementation Plan (Execution Slices)

The migration is being delivered in guarded slices so existing LAN WebSocket behavior remains stable while WebRTC components are introduced behind explicit policy boundaries.

### Guiding Constraints

1. Do not regress current WebSocket-based sync reliability.
2. Keep WebRTC components injectable and feature-gated until end-to-end validation is complete.
3. Preserve local-first behavior as default.
4. Maintain deterministic signaling state transitions (offer, answer, ICE, replay).

### Phase A: Signaling Control Plane Completion (M1)

1. Finalize signaling schema with ACK and ERROR frame contract.
2. Enforce session-scoped validation guards:
	- duplicate offer rejection
	- answer-before-offer rejection
	- ICE-before-negotiation rejection
3. Maintain queue/replay behavior for ICE received before answer.
4. Add lifecycle cleanup hooks for session close and stale-state pruning.

Status: Done

### Phase B: Transport Boundary and Runtime Staging (M2)

1. Keep `SyncTransportChannel` abstraction stable.
2. Introduce WebRTC-specific staging components:
	- negotiation mailbox
	- runtime snapshot model
	- bridge contract for DataChannel traffic
3. Add negotiation-aware bridge shell with artifact buffering and deduplicated ICE handling.
4. Add peer-ops abstraction with factory injection so implementation can switch between noop and plugin-backed runtimes.

Status: Done

### Phase C: Local End-to-End Data Plane Bring-Up (M3)

1. Implement plugin-backed peer ops (`flutter_webrtc`) behind existing factory hook.
2. Wire peer ops into bridge shell lifecycle without changing default fallback policy.
3. Enable controlled WebRTC connect path in policy while preserving WebSocket fallback.
4. Route sync payload frames through DataChannel stream once channel is established.

Status: Done

### Phase D: Reliability Hardening (M4)

1. Add heartbeat and liveness checks on WebRTC transport.
2. Implement reconnect and resume behavior for transient failures.
3. Add ack/retry semantics and dedupe verification at transport boundary.
4. Expand integration tests for ordering, replay, reconnect, and session cleanup.

Status: Done

### Phase E: Anywhere Mode Infrastructure (M5)

1. Introduce cloud signaling backend compatible with existing frame schema.
2. Add TURN relay fallback path for difficult NAT/firewall environments.
3. Keep mode opt-in and feature-flagged during beta validation.

Status: In Progress (feature-gated scaffold and adapter seam complete)

### Phase F: Security and Release Readiness (M6)

1. Validate app-layer payload encryption and integrity checks over all transport paths.
2. Verify key handling and rotation behavior for connect-anywhere mode.
3. Complete threat review and release gate sign-off criteria.

Status: Not Started

### Current Progress Snapshot

1. M1: 100% complete.
2. M2: 100% complete.
3. M3: 100% complete.
4. M4: 100% complete.
5. M5: approximately 24% complete.
6. M6: pending.

### Immediate Next Slices

1. Add TURN relay fallback scaffolding for staging.
2. Add cloud signaling frame mapper for coordinator parity checks.
3. Preserve local-first mode as default while M5 remains gated.

## Evidence And Supporting Specs

- `docs/sync/infrastructure/WEBRTC_DATA_PLANE_ARCHITECTURE.md`
- `docs/sync/infrastructure/WEB_COMPANION_SPEC.md`
- `docs/codebase/SYNC_AND_IDENTITY_AS_BUILT.md`

## Related Decisions

- ADR-001
- ADR-004
- ADR-006
