# KashCube Mesh Sync Strategy and Decision

Date: 6 April 2026  
Status: Proposed decision baseline

## Executive decision

KashCube should adopt a libp2p-based transport direction for long-term multi-hop mesh sync, while preserving the existing KashCube sync engine as the source of truth.

Decision statement:

- Use libp2p for networking primitives: identity, secure channels, discovery, and relay.
- Keep KashCube sync semantics in-app: table rules, conflict handling, and authorization policy.
- Apply conditional hosting: trusted peer is a conditional host, not a universal host.
- Keep the system local-first and privacy-first, with no central server dependency.

## Why this is the right direction

1. Avoids reinventing hard networking/security layers.
2. Preserves KashCube's domain-specific finance data guarantees.
3. Enables gradual rollout from direct sync to relay-assisted multi-hop.
4. Aligns with privacy constraints and offline operation goals.

## Scope and non-goals

In scope:

- Device-to-device sync over local/peer network paths.
- Multi-hop relay where intermediate peers can forward encrypted envelopes.
- Table-level authorization and scoped replication.

Out of scope (for initial phases):

- Universal replication of all data to all peers.
- Public content hosting semantics.
- Cloud-coordinated routing or managed backend dependencies.

## Comparison snapshot

| Option | Fit | Long-term maintainability | Security baseline | Effort | Verdict |
|---|---|---|---|---|---|
| BitChat-inspired custom protocol | Medium-High | Low-Medium | Medium | High | Good only if we intentionally own full protocol lifecycle |
| libp2p transport + KashCube sync semantics | High | High | High | Medium-High | Recommended |
| ZeroNet foundation | Low | Low | Low-Medium | Very High | Not recommended |

## Architecture principle

Use a layered model:

1. Sync domain layer (KashCube-owned)
- Table registry and scope policy
- Conflict strategy by table class
- Idempotent event apply rules

2. Mesh envelope layer (KashCube-owned)
- Signed sync envelopes
- ACK/retry metadata
- Dedupe identifiers and TTL

3. Transport/session layer (libp2p)
- Peer identity, secure channels
- Discovery, relay, and peer connectivity

## Security posture

Baseline requirements:

- End-to-end payload encryption for data confidentiality.
- Per-envelope signature verification before apply.
- Replay protection and dedupe cache.
- Key rotation and peer revocation flow.
- Authorization checks before decrypt and before apply.

## Replication policy stance

- Local-only tables remain local-only.
- Sensitive financial tables are readable only on explicitly authorized peers.
- Intermediate relay peers default to forwarding encrypted payloads without decryption.

## Rollout plan

### Phase 0: Foundation hardening

- Close known direct-sync gaps in existing engine.
- Normalize event identity and dedupe behavior.
- Add sync policy tags to envelopes.

Exit criteria:

- Deterministic convergence across direct paired peers.
- No duplicate apply under retry conditions.

### Phase 1: Direct libp2p peer sync (no multi-hop)

- Introduce libp2p transport adapter.
- Keep one-hop behavior only.
- Maintain current table policies and conflict rules.

Exit criteria:

- Feature parity with current direct sync.
- Stable handshake/session behavior on mobile targets.

### Phase 2: Relay-only multi-hop

- Enable A -> B -> C forwarding.
- Enforce TTL + dedupe.
- Relay peers cannot decrypt by default.

Exit criteria:

- Successful delivery through one intermediary hop.
- Measured bounded duplicate ratio and retry stability.

### Phase 3: Store-and-forward reliability

- Bounded encrypted relay queue.
- ACK/retry tuning for intermittent connectivity.
- Delivery metrics and backpressure.

Exit criteria:

- Eventual delivery under temporary disconnects.
- Battery/network budgets within target.

### Phase 4: Revocation and scoped key hardening

- Business/user scoped key strategy.
- Device unlink revocation workflow.
- Rotation propagation and audit trails.

Exit criteria:

- Revoked peers lose future decrypt ability.
- Rotation completes without divergence.

## Governance and risk controls

Key risks:

1. Mobile background limitations impacting relay reliability.
2. Over-broad replication causing privacy leakage.
3. Merge regressions in finance-critical tables.

Mitigations:

- Keep relay queue bounded and policy-driven.
- Enforce least-privilege data scope at envelope and table level.
- Add table-class regression suites for conflict/retry/replay scenarios.

## Success metrics

- Convergence lag: median and p95 by table class.
- Delivery success under lossy conditions.
- Duplicate suppression rate.
- Unauthorized decrypt/apply attempts blocked.
- Battery and transfer overhead per sync event.

## Implementation recommendation

Proceed with libp2p transport in a phased adapter model, preserving existing sync semantics and conditional hosting policy. Start with direct parity, then add controlled relay and store-and-forward.

## Related documents

- MESH_ENVELOPE_AND_POLICY_TECH_SPEC.md
- MESH_COMMERCE_NETWORK_ARCHITECTURE.md
