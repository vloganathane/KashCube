# KashCube WebRTC Data Plane Architecture (Draft)

Status: Proposed
Date: 2026-04-03
Owner: Sync/Web Companion

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
2. Cloud control plane: managed signaling endpoint for internet scenarios.

### 3.2 Data Plane (WebRTC)

Responsibilities:

1. DataChannel transport for sync messages.
2. Ordered delivery profile for row-sync protocol.
3. Backpressure-aware chunking for larger payloads.
4. Peer-to-peer direct path preference.

Fallback:

1. TURN relay path when direct NAT traversal fails.

## 4. Transport Policy

Connection policy is deterministic and mode-aware.

### 4.1 Local-First Mode (default)

1. Discover local peer using existing LAN discovery path.
2. Negotiate WebRTC via local signaling endpoint.
3. Prefer direct candidate pair.
4. If direct fails on LAN, retry with bounded attempts and clear diagnostics.

### 4.2 Anywhere Mode (opt-in)

1. Use cloud signaling for rendezvous.
2. Attempt direct WebRTC first.
3. Fallback to TURN relay when direct fails.
4. Surface connection state in UI: Direct or Relay.

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

1. Sync domain protocol (tables, deltas, merge semantics).
2. Secure frame protocol (encrypt/sign/nonce/ack).
3. Transport adapter (WebRTC DataChannel, existing WS/HTTP fallback if needed).
4. Signaling adapter (local or cloud backend).

This allows reuse of existing merge/sync logic while swapping transport.

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

1. Introduce cloud signaling backend.
2. Integrate TURN fallback.
3. Add mode toggles, consent, and trust UX.
4. Publish operational playbook for signaling/TURN services.

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
Mitigation: direct-first plus TURN fallback and candidate diagnostics.

2. Increased complexity vs current LAN HTTP/WS path
Mitigation: strict layering with transport adapters and phased rollout.

3. UX confusion between local and cloud modes
Mitigation: explicit mode labels and connection state visibility.

4. Operational burden for cloud signaling/TURN
Mitigation: start with limited regions and clear SLO/alerting definitions.

## 12. Decision Summary

Decision:

1. Move to WebRTC-based data plane for sync transport.
2. Keep signaling as separable control plane with local and cloud backends.
3. Preserve local-first default and add connect-anywhere as opt-in mode.

This document supersedes the assumption that WebRTC is not used for future transport direction, while current production code may still run on existing LAN HTTP/WS until phased migration is implemented.
