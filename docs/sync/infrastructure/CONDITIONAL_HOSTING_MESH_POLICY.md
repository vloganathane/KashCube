# Conditional Hosting for KashCube Mesh Sync

Date: 6 April 2026  
Status: Draft architecture note

## Summary

This document captures the adaptation of the ZeroNet-style idea "each visitor is also a host" for KashCube.

For KashCube, the correct model is:

Each trusted peer is a conditional host, not a universal host.

That means a linked device may relay and replicate only the scoped data it is authorized to hold. This keeps the system private, offline-first, and resilient without exposing all financial data to every participant.

## Why this adaptation

The original concept improves availability and resilience, but KashCube has stricter requirements:

- Financial and business records are sensitive.
- Devices can have different roles and permissions.
- Sync must remain deterministic and auditable.
- The app is privacy-first with local-first storage and no cloud dependency.

A universal-host model would over-share data and increase breach impact if one device is compromised.

## Design principle

Use controlled replication:

- Authorization first: a device can only decrypt datasets allowed by role and business scope.
- Relay separately from read: a node may forward encrypted payloads even when it cannot decrypt them.
- Least privilege by default: replicate only what is required for user workflows.
- Deterministic convergence: preserve current table-level sync semantics and conflict strategy.

## Replication modes

Each sync payload should be tagged with one mode:

1. Relay-only
- Node can store short-lived ciphertext and forward it.
- Node cannot decrypt payload content.
- Used to enable multi-hop delivery while minimizing exposure.

2. Replica-encrypted
- Node can persist ciphertext for delayed forwarding and retry.
- Node still cannot decrypt.
- Used for store-and-forward reliability when destination is offline.

3. Replica-readable
- Node is authorized to decrypt and use the data locally.
- Used for the owner device and explicitly linked trusted devices.

## Policy matrix (initial recommendation)

| Data class | Example tables | Default mode | Notes |
|---|---|---|---|
| Device identity and sync internals | my_identity, trusted_peers, sync_outbox, sync_watermarks | Local-only | Never replicated outside origin device |
| User/session control | app_users, user_permissions, device_session | Replica-readable (restricted) | Admin/owner scope only |
| Core personal finance | transactions, credits, loans, payments | Replica-readable (trusted linked devices only) | Enforce role and business/user scope |
| Business billing and inventory | invoices, invoice_items, item_catalog, stock tables | Replica-readable (business-scoped devices) | Business-level access policy required |
| Attachments/media metadata | bill attachments, image paths, media refs | Replica-encrypted by default | Upgrade to readable only when needed |
| Broadcast operational events | sync announcements, heartbeat, route metadata | Relay-only | No financial payloads in broadcast metadata |

## Security requirements

1. End-to-end payload encryption
- Transport encryption is not enough.
- Relay nodes should not gain read access by default.

2. Signed envelopes
- Every sync event envelope must be signed by origin device identity.
- Receiver verifies signature before apply.

3. Replay and dedupe protection
- Envelope ID, nonce/window checks, and seen-ID cache required.

4. Key rotation and revocation
- On device unlink or compromise suspicion:
  - revoke device authorization,
  - rotate dataset/group keys,
  - block future decrypt for revoked node.

5. Scoped key distribution
- Separate key material by business/user scope where possible.
- Avoid one global key for all financial datasets.

## Mesh behavior requirements (multi-hop)

- Envelope header includes origin, destination scope, TTL, timestamp, message ID.
- Intermediate relay decrements TTL and forwards once (dedupe by message ID).
- Optional store-and-forward queue with bounded retention.
- ACK and retry for reliable delivery in lossy environments.

## Operational safeguards

- Retention limits for relay queues.
- Backpressure and rate limits to prevent battery drain.
- Routing and sync metrics (delivery latency, retry count, convergence lag).
- Audit log for replication decisions and policy denials.

## What to borrow vs what to avoid

Borrow:

- The resilience mindset: peers can help host and relay.
- TTL-based forwarding and dedupe patterns.
- Store-and-forward for intermittent connectivity.

Avoid:

- Universal replication to all peers.
- Protocol choices that prioritize public content distribution over financial data governance.
- Any approach that weakens role-based data boundaries.

## Direct options comparison

Here is the direct comparison for KashCube.

| Option | What it really means | Fit for KashCube | Strengths | Weaknesses | Build effort | Risk | Verdict |
|---|---|---|---|---|---|---|---|
| BitChat-inspired approach | Reuse BitChat ideas and design a KashCube-specific mesh protocol | Medium-High | Tailored to privacy-first local sync, good BLE-first ideas, simple relay/gossip concepts, full control of data model and UX | Team owns protocol design, reliability, routing, security maintenance, and edge cases | High | High | Good only if a custom protocol is a deliberate long-term investment |
| libp2p | Use an existing modular P2P stack and build KashCube sync on top | High | Mature identity/session model, relay/pubsub/discovery options, strong ecosystem, avoids reinventing transport/security basics | Harder mobile and Flutter integration, more infrastructure complexity than simple nearby sync | Medium-High | Medium | Best strategic choice |
| ZeroNet | Reuse a decentralized website/content distribution stack | Low | Proven content signing/distribution ideas, P2P replication concepts | Wrong abstraction, older stack, website-centric, not mobile-first, poor fit for finance sync semantics and Flutter embedding | Very High | High | Not recommended |

### What each option means in practice

BitChat-inspired:

- Best if the goal is a BLE-first, local-proximity, ad hoc mesh with custom behavior.
- Can borrow Noise sessions, TTL relay, ACK/retry, fragmentation, and dedupe.
- KashCube must still design and maintain sync envelope, merge rules, replay model, and device lifecycle behavior.

libp2p:

- Best if the goal is a durable foundation for real multi-hop sync.
- KashCube keeps table/event sync logic and plugs into a maintained networking/security layer.
- Clean separation: libp2p handles networking; KashCube handles finance-grade data semantics.

ZeroNet:

- Best for decentralized web publishing, not local-first financial device sync.
- Solves signed site content distribution, not trusted structured app-state synchronization.
- Pulls architecture away from KashCube's privacy-first local sync model.

### Decision by criteria

| Criteria | BitChat-inspired | libp2p | ZeroNet |
|---|---|---|---|
| True multi-hop mesh potential | Medium | High | Medium |
| Flutter/mobile suitability | Medium | Medium | Low |
| Privacy-first local architecture fit | High | High | Low-Medium |
| Finance-grade sync suitability | Medium | High | Low |
| Time to first prototype | Medium | Medium | Low-Medium |
| Long-term maintainability | Low-Medium | High | Low |
| Security confidence | Medium | High | Low-Medium |
| Risk of reinventing core networking | High | Low | Medium |

### Recommendation

1. Choose libp2p as transport direction.
2. Borrow BitChat ideas for edge behavior:
  - TTL
  - dedupe
  - ACK/retry
  - fragmentation
  - fingerprint verification
3. Do not use ZeroNet as a foundation.

### Pragmatic architecture for KashCube

1. KashCube sync engine remains source of truth.
2. libp2p provides peer identity, secure channels, relay, and peer discovery.
3. KashCube sends signed/encrypted sync envelopes with:
  - table
  - operation
  - record ID
  - version/vector metadata
  - payload delta
  - message ID
4. Relay and retry semantics can borrow from BitChat's approach.

### Shortest path

- MVP: direct peer sync first, no full mesh routing.
- v2: enable relay A -> B -> C.
- v3: optimize routing and background resilience.

## Decision statement

KashCube should adopt conditional hosting:

- Yes to peer-assisted replication and relay for resilience.
- No to full universal hosting.
- Enforce authorization, encryption scopes, and revocation from day one.

## Proposed phased rollout

Phase 1: Direct trusted peer replication
- Keep current direct sync model.
- Introduce envelope signing and stricter policy tags.

Phase 2: Relay-only multi-hop
- Enable A -> B -> C forwarding with TTL and dedupe.
- Keep relay payload opaque by default.

Phase 3: Store-and-forward reliability
- Add bounded encrypted relay queue with ACK/retry.

Phase 4: Key-scoped replication and revocation hardening
- Business/user scoped keys, rotation flows, and full audit trails.

## Open questions

- Which tables should remain strictly local-only forever beyond current list?
- Should payroll and sensitive HR tables default to relay-only unless explicitly approved?
- What retention window is acceptable for relay ciphertext on intermediary devices?
- What policy UX is needed so non-technical users can understand trust scope?
