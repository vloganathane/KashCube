# KashCube WebRTC Data Plane Architecture (Draft)

Status: Proposed
Date: 2026-04-03
Updated: 2026-04-04
Owner: Sync/Web Companion

Change log:
- 2026-04-04a: Named PeerJS-protocol signaling server as cloud signaling implementation. Added hosted shell as a distinct browser delivery layer. Added Section 3.3 and updated Sections 4.2, 8, 9, 11, 12.
- 2026-04-04b: Added self-hosted STUN/TURN infrastructure (coturn) as Section 3.4. Expanded Section 6 with reliability scorecard and go/no-go pass thresholds. Updated Section 9 Phase 3 with coturn deployment tasks and phased STUN/TURN rollout. Added TURN-specific risks in Section 11. Updated decision summary in Section 12.

## 1. Goal

Adopt WebRTC DataChannel as the primary sync transport (data plane) while keeping signaling and session orchestration in a separate control plane.

This architecture targets two outcomes:

1. Reliable Web Companion connectivity on local networks.
2. Optional connect-anywhere capability through cloud-assisted signaling and relay fallback.

## 2. Scope

In scope:

1. Phone <-> Browser sync transport and session lifecycle.
2. Local-first operation with cloud-assisted fallback mode.
3. Reliability, reconnect, and failover behavior.
4. Security model for encrypted sync payloads.

Out of scope (initially):

1. Full commerce mesh routing across many peers.
2. Multi-hop gossip transport.
3. General media call features (audio/video).

## 3. Architecture Overview

KashCube will split sync into two planes:

1. Control plane
2. Data plane

### 3.1 Control Plane (Signaling + Session)

Responsibilities:

1. Peer identity and session bootstrap.
2. Offer/answer and ICE candidate exchange.
3. Session liveness and reconnect signaling.
4. Presence and pairing metadata.

Implementations:

1. Local control plane: embedded signaling service hosted by app on LAN.
2. Cloud control plane: self-hosted PeerJS-protocol signaling server for Anywhere Mode.

Cloud signaling implementation — PeerJS server:

1. Protocol: JSON-over-WebSocket peer lifecycle messages (offer/answer/ICE/heartbeat).
2. Deployment: self-hosted `peerjs-server` (Node.js). Must be operated by KashCube — never use the public `0.peerjs.com` endpoint (privacy: it observes connection metadata).
3. Dart adapter: `PeerJsSignalingAdapter` implementing the signaling adapter interface (see Section 8).
4. Browser adapter: `peerjs` npm package bundled in the Flutter web build.
5. Peer ID lifecycle: short-lived, device-bound, rotated at session teardown.

### 3.2 Data Plane (WebRTC)

Responsibilities:

1. DataChannel transport for sync messages.
2. Ordered delivery profile for row-sync protocol.
3. Backpressure-aware chunking for larger payloads.
4. Peer-to-peer direct path preference.

Fallback:

1. TURN relay path when direct NAT traversal fails.

### 3.3 Browser Shell Delivery (separate concern)

The browser shell is not part of the control or data plane. It is the mechanism by which the browser loads the Flutter web application before any sync session begins.

1. Local mode: Flutter web build served by phone's embedded `shelf` HTTP server.
2. Anywhere mode: Flutter web build deployed to CDN/static hosting, loaded independently of phone reachability.

Key constraint: shell delivery and sync transport evolve independently. A hosted shell does not fix LAN reachability failures; WebRTC with cloud signaling does. Both are needed for a fully reliable Anywhere Mode experience.

Non-goal: the hosted shell origin must never process or proxy sync payloads. It serves static assets only.

### 3.4 STUN/TURN Infrastructure (NAT traversal)

WebRTC ICE will fail on symmetric NAT, CGNAT (common on Indian mobile operators), and enterprise firewalls that block UDP. STUN/TURN is the fallback path.

Self-hosted implementation:

1. STUN server: part of coturn — provides public IP discovery for ICE candidates. Stateless and low bandwidth.
2. TURN server: coturn relay — proxies encrypted WebRTC UDP/TCP traffic when direct ICE fails. Stateful, bandwidth-bearing.
3. Must be self-operated. No third-party TURN services (they observe relay traffic volume and timing).
4. TURN is untrusted transport infrastructure: only sees DTLS-encrypted datagrams; never plaintext financial data.
5. Deploy separately from the PeerJS signaling server (different process, different host optionally).

Security requirements for TURN:

1. Short-lived TURN credentials: generate per-session HMAC credentials (standard `coturn` HMAC mechanism); never use static username/password.
2. REST API for credential vending: phone app requests a TURN credential from a small API endpoint (requires phone's auth session) before initiating Anywhere Mode ICE.
3. Rate limiting: restrict relay allocations per authenticated user per time window.
4. Bandwidth quotas: set `max-bps` in coturn config and monitor relay egress.
5. TLS TURN endpoints only: `turns:` (TURN-over-TLS) and `turn:` with DTLS for browser compatibility.

Phased rollout:

1. Phase A (STUN only, staging): enable STUN discovery, measure direct ICE success rate before investing in TURN.
2. Phase B (TURN enabled, internal beta): enable relay fallback for internal beta devices; measure relay usage ratio.
3. Phase C (production, Anywhere Mode GA): TURN serving production traffic with alerting, quota enforcement, and uptime SLO.

Key decision: TURN relay should carry < 20% of sessions in steady state. If relay ratio is high, the root cause is network topology, not ICE policy — diagnose before accepting high TURN egress cost.

## 4. Transport Policy

Connection policy is deterministic and mode-aware.

### 4.1 Local-First Mode (default)

1. Discover local peer using existing LAN discovery path.
2. Negotiate WebRTC via local signaling endpoint.
3. Prefer direct candidate pair.
4. If direct fails on LAN, retry with bounded attempts and clear diagnostics.

### 4.2 Anywhere Mode (opt-in)

1. Load browser shell from CDN/static host (no phone reachability required for asset delivery).
2. Browser and phone both connect to self-hosted PeerJS signaling server to exchange peer IDs.
3. QR payload changes from `http://phone-ip:port?token=X` to `peerID=X&sigServer=https://your-peerjs-host`.
4. Negotiate WebRTC DataChannel via PeerJS signaling.
5. Attempt direct ICE candidate pair first.
6. Fallback to TURN relay when NAT traversal fails.
7. Surface connection state in UI: Direct, Relay, or Offline.

## 5. Security Model

Transport encryption from DTLS is not sufficient alone for financial data. Payload security is application-owned.

Requirements:

1. End-to-end payload encryption at application layer.
2. Device-bound key material with explicit pairing trust.
3. Short-lived session tokens for signaling.
4. Replay prevention with nonce/sequence strategy.
5. Integrity verification on every sync frame.

Trust boundary:

1. Signaling and relay are untrusted transport infrastructure.
2. They must never require plaintext financial payload access.

## 6. Reliability Requirements

The protocol must explicitly handle unstable networks.

1. Heartbeat and stale-session detection.
2. Reconnect loop with exponential backoff and jitter.
3. Idempotent message processing (ack, retry, dedupe).
4. Session resume after short network interruptions.
5. Explicit error taxonomy for user-facing diagnostics.

Minimum target SLOs (MVP):

1. Successful session establishment >= 95% on supported test matrix.
2. Reconnect-to-ready <= 10s for transient drops.
3. Direct path usage preferred whenever possible.

### Reliability Scorecard (go/no-go before Anywhere Mode GA)

This scorecard must pass before Anywhere Mode is enabled for production users.

| Metric | Pass Threshold | Measurement Method |
|--------|---------------|--------------------|
| Session establish success rate | >= 95% | Automated test matrix (see below) |
| Reconnect-to-ready | <= 10s after simulated drop | Integration test: kill/restore network |
| Direct ICE path usage | >= 80% of sessions | TURN server allocation counter |
| TURN relay ratio | <= 20% of sessions | coturn stats endpoint |
| 5+ min background stability | Pass on all test devices | Manual QA (from hardening plan) |
| Time-to-first-sync after QR scan | <= 5s (Local), <= 8s (Anywhere) | Instrumented session timing |
| Signaling server uptime (30-day) | >= 99.5% | Uptime monitor alert |
| TURN server credential auth failure rate | < 0.5% | coturn auth error log |

Test matrix (minimum):

| Scenario | Expected result |
|----------|----------------|
| Same Wi-Fi LAN (Local mode) | Direct ICE, no TURN |
| Phone hotspot → laptop (Pixel 7) | Direct ICE, no TURN |
| Phone hotspot → laptop (Xiaomi 13) | TURN relay fallback |
| Home broadband NAT → browser | Direct ICE preferred |
| CGNAT (mobile data) → home Wi-Fi browser | TURN relay |
| Enterprise firewall (UDP blocked) | TURN-over-TLS (TCP) |
| App backgrounded 5 min | Session alive, no reconnect required |
| Network drop and restore < 10s | Auto-reconnect, no re-auth |

What the scorecard will not prevent:

1. Aggressive OEM battery kills on Xiaomi/Redmi (document as known limitation).
2. Enterprise environments that block both UDP and TCP TURN (document as unsupported).
3. Infra outages causing signaling or TURN unavailability (mitigate with uptime SLO and alerting).

## 7. Same App as Server and Client

The app can act as both roles depending on context.

1. As local signaling host in LAN mode.
2. As WebRTC peer endpoint in all modes.
3. As cloud-signaled peer in anywhere mode.

Important caveat:

1. Embedded local signaling alone cannot provide global connectivity behind NAT.
2. Connect-anywhere requires internet-reachable signaling and TURN infrastructure.

## 8. Protocol Layers

Layering keeps migration controlled.

Layer 0 — Browser shell delivery (orthogonal to sync):
- Local mode: phone `shelf` server → `GET /`
- Anywhere mode: CDN/static host → `GET /`
- This layer is completely independent of layers 1–4 below.

Layer 1 — Sync domain protocol: tables, deltas, merge semantics.

Layer 2 — Secure frame protocol: encrypt/sign/nonce/ack. Application-layer E2E; DTLS alone is not sufficient for financial data.

Layer 3 — Transport adapter: `WebRtcDataChannelAdapter` (primary), WS/HTTP adapter (fallback during migration).

Layer 4 — Signaling adapter: `LocalSignalingAdapter` (LAN, embedded in app) or `PeerJsSignalingAdapter` (cloud, self-hosted PeerJS server).

This layering allows reuse of existing merge/sync logic while swapping transport and signaling independently.

## 9. Implementation Plan

### Phase 1: Foundations (Phone <-> Browser)

1. Define signaling message schema.
2. Implement transport abstraction with DataChannel adapter.
3. Establish local signaling path and DataChannel handshake.
4. Add connection state model and debug instrumentation.

### Phase 2: Reliability Hardening

1. Add heartbeat, reconnect, and resume state machine.
2. Add ack/retry/dedupe semantics for sync frames.
3. Add backpressure/chunking and large-payload handling.
4. Add automated integration tests for network fault cases.

### Phase 3: Anywhere Mode

#### 3A — Signaling + shell (STUN only)

1. Implement `PeerJsSignalingAdapter` in Dart (PeerJS JSON-over-WS protocol, ~300 lines).
2. Bundle `peerjs` npm package in Flutter web build; wire to DataChannel session.
3. Deploy self-hosted `peerjs-server` (Node.js) to managed hosting (e.g. Fly.io or Railway).
4. Deploy Flutter web build to CDN/static host for hosted shell delivery.
5. Deploy coturn in **STUN-only mode** (no relay); measure direct ICE success rate.
6. Update QR payload schema: add `peerID`, `sigServer`, and `stunUrl` fields; keep backward compat with local QR.
7. Add Anywhere Mode toggle, consent flow, and trust UX.
8. Measure direct ICE success rate in staging (Phase A of STUN/TURN rollout).

#### 3B — TURN relay (internal beta)

1. Enable TURN relay in coturn (same host or separate).
2. Implement short-lived TURN credential REST endpoint (HMAC, per-session).
3. Phone requests TURN credentials from credential endpoint before initiating Anywhere Mode ICE.
4. Configure coturn: `max-bps`, rate limits, `turns:` TLS endpoint, auth-secret for HMAC.
5. Run internal beta with TURN fallback enabled; monitor relay ratio (target < 20% of sessions).
6. Define and enable coturn metrics: allocation count, auth failures, relay bytes, active allocations.

#### 3C — Production readiness

1. Run reliability scorecard (Section 6) — all pass thresholds must be met.
2. Publish operational playbook: PeerJS server deployment, coturn config, uptime SLOs, key rotation, peer ID lifecycle, TURN credential rotation, abuse response.
3. Enable Anywhere Mode for production opt-in users with explicit metadata disclosure in privacy policy.

Constraints across all 3A–3C:
- PeerJS server must be self-operated. Prohibit `0.peerjs.com` or any third-party signaling endpoint.
- TURN server must be self-operated. No third-party TURN services.
- Hosted shell origin must serve static assets only; no sync payload proxying permitted.
- All TURN credentials must be short-lived HMAC; no static credentials in app or config.

### Phase 4: Commerce Extensions

1. Evaluate star/mesh patterns for commerce-specific features.
2. Keep web companion path optimized for 1:1 reliability.

## 10. Acceptance Criteria

Ready for production candidate when:

1. Local-first mode is stable and regression-safe.
2. Anywhere mode is explicit opt-in and encrypted end-to-end.
3. Relay path never receives plaintext financial payloads.
4. Existing sync conflict semantics remain correct under new transport.
5. Observability exists for connect, reconnect, relay usage, and failure classes.

## 11. Risks and Mitigations

1. NAT and firewall variability
Mitigation: direct-first ICE plus TURN relay fallback; `turns:` TLS endpoint for environments that block UDP; explicit candidate diagnostics in UI.

2. Increased complexity vs current LAN HTTP/WS path
Mitigation: strict layering (Section 8) with swappable transport and signaling adapters; phased rollout (Phases 3A → 3B → 3C).

3. UX confusion between local and cloud modes
Mitigation: explicit mode label in UI ("Local" / "Anywhere"); connection path (Direct / Relay / Offline) shown in diagnostics.

4. Operational burden for self-hosted PeerJS signaling + coturn TURN
Mitigation: start with Phase 3A (STUN only); validate before enabling relay; define uptime SLO and alerting before Anywhere Mode GA.

5. Public PeerJS endpoint usage (privacy risk)
Mitigation: hard-code prohibition of `0.peerjs.com` in `PeerJsSignalingAdapter`; only accept `sigServer` URLs matching an allowlist of self-operated domains.

6. Hosted shell origin as supply-chain risk
Mitigation: shell host serves compiled, versioned, integrity-checked static assets only; no server-side execution or data access.

7. PeerJS signaling server sees connection metadata (peer IDs, IP pairs, timing)
Mitigation: peer IDs are ephemeral; no financial data in signaling messages; document metadata disclosure in privacy policy for Anywhere Mode.

8. TURN relay bandwidth cost and abuse
Mitigation: short-lived HMAC credentials (no static credentials); per-user rate limits and `max-bps` quota in coturn; monitor relay bytes and alert on anomalies.

9. TURN server as new attack surface (amplification, credential stuffing)
Mitigation: HMAC credential vending tied to authenticated app session; no open TURN allocation (unauthenticated requests rejected); rate limit credential endpoint; coturn behind TLS only.

10. Reliability ceiling — not solving all failure modes
Mitigation: document known unsupported scenarios (aggressive OEM battery kill, full UDP+TCP enterprise firewall); use reliability scorecard (Section 6) as production gate; set user expectations via in-app connection state.

## 12. Decision Summary

Decision:

1. Move to WebRTC DataChannel as the primary sync transport (data plane).
2. Cloud signaling backend: self-hosted PeerJS-protocol server (`peerjs-server` / Node.js). No third-party signaling permitted.
3. Browser shell delivery: phone-served (Local Mode) or CDN/static host (Anywhere Mode). Shell delivery is a separate concern from sync transport.
4. Preserve local-first as the default user experience. Anywhere Mode is explicit opt-in with consent and metadata disclosure.
5. NAT traversal: self-hosted `coturn` for both STUN and TURN relay. No third-party TURN services. TURN credentials are short-lived HMAC; no static credentials. TURN is untrusted transport only — never sees plaintext financial data.
6. Anywhere Mode rollout is gated on the reliability scorecard (Section 6) passing all thresholds.

Related documents:
- [WEB_COMPANION_HARDENING_PLAN.md](WEB_COMPANION_HARDENING_PLAN.md) — local Web Companion reliability phases (all 4 phases complete) and the architectural alternative discussion that led to this update.
- [ADR-007](../decisions/adr/ADR-007-webrtc-data-plane-with-local-and-cloud-signaling.md) — ratified decision record for WebRTC data plane.

This document supersedes the assumption that WebRTC is not used for future transport direction, while current production code may still run on existing LAN HTTP/WS until phased migration is implemented.
