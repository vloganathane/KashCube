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
| M1: Signaling protocol freeze (v1) | Sync Lead | 2026-04-10 | In Progress | Offer/answer/ICE schema finalized and reviewed in docs |
| M2: Transport adapter integration | App Lead | 2026-04-17 | In Progress | WebRTC DataChannel adapter wired behind sync transport interface |
| M3: Local mode end-to-end path | Web Companion Lead | 2026-04-24 | In Progress | Phone and browser complete authenticated sync over local signaling |
| M4: Reliability hardening | QA Lead | 2026-05-01 | Not Started | Heartbeat, reconnect, ack/retry, dedupe pass integration test suite |
| M5: Anywhere mode infrastructure beta | Infra Lead | 2026-05-08 | Not Started | Cloud signaling plus TURN fallback available in staging |
| M6: Security and release readiness gate | Security Lead | 2026-05-15 | Not Started | App-layer payload encryption, key rotation checks, and threat review approved |

Notes:

1. Local mode remains default throughout migration.
2. Anywhere mode stays feature-flagged until M6 sign-off.

## Evidence And Supporting Specs

- `docs/sync/infrastructure/WEBRTC_DATA_PLANE_ARCHITECTURE.md`
- `docs/sync/infrastructure/WEB_COMPANION_SPEC.md`
- `docs/codebase/SYNC_AND_IDENTITY_AS_BUILT.md`

## Related Decisions

- ADR-001
- ADR-004
- ADR-006
