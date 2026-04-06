# KashCube Mesh Commerce Network Architecture

Date: 6 April 2026  
Status: Directional architecture baseline

## Purpose

Define KashCube as a full mesh commerce network, not only a device sync system.

This document extends existing mesh-sync strategy by introducing commerce-specific identity, trust tiers, envelope operations, and workflow semantics for nearby/offline business exchange.

## Core direction

KashCube should run two protocol layers over one transport foundation:

1. Sync protocol (existing)
- Goal: keep one user's data consistent across trusted devices.
- Semantics: CRDT/LWW-style record convergence.

2. Commerce protocol (new)
- Goal: exchange business data with external peers (customers, suppliers, nearby merchants).
- Semantics: stateful, signed business interactions (invoice/ack/settlement), not just record merge.

Both protocols share:
- libp2p transport/session substrate
- signed envelope framing
- local-first persistence model

## Non-negotiable constraints

- Privacy-first by default: no financial plaintext in open discovery traffic.
- No central server dependency.
- No change to payment rails: money movement remains UPI/bank rails; mesh carries commerce metadata and evidence.
- Least-privilege data access by table, role, and trust relationship.

## Architectural layers

1. Commerce domain layer (new, KashCube-owned)
- Catalog publication
- Quotes/invoices/credit acknowledgements
- Settlement evidence attachment (for example UPI reference capture)
- Dispute and status transitions

2. Sync domain layer (existing, KashCube-owned)
- Table-level conflict strategies
- Deterministic apply/idempotency
- Business scope policy checks

3. Envelope and policy layer (existing, extended)
- Signature, dedupe, replay guard, TTL relay
- Mode: relay-only, replica-encrypted, replica-readable
- Trust-tier policy evaluation

4. Transport/session layer (planned: libp2p)
- Peer identity and secure channels
- Discovery and relay pathing
- Multi-hop message carriage

## IPFS and Multiformats fit review

### Multiformats: use

Recommendation: adopt Multiformats primitives for envelope and commerce object identifiers.

Why:
- Already aligned with libp2p ecosystem usage.
- Self-describing identifiers improve forward compatibility (hash/codec/base agility).
- Can be used without adopting full IPFS content routing/storage behavior.

Suggested use in KashCube:
- CID-like references for catalog/media artifacts.
- Multihash for payload fingerprints and attachment integrity checks.
- Multibase for textual representation consistency in QR/pairing payloads.

### IPFS: limited/optional use

Recommendation: do not make IPFS the core sync or commerce transport protocol in v1.

Why not as core layer:
- KashCube requires strict relationship-scoped authorization and policy-first apply semantics.
- Commerce workflows require actor-validated state transitions, not only content retrieval by hash.
- Ledger/invoice privacy boundaries are stricter than public content distribution defaults.

Where IPFS can still help (optional modules):
- Large immutable blob distribution (for example catalog media packs) when explicitly opted in.
- Content-addressed backup/export bundles shared between trusted peers.

Guardrails if IPFS is introduced later:
- Never publish sensitive finance plaintext to public DHTs/gateways.
- Encrypt private content before any content-addressed publication.
- Keep ledger/event envelopes on KashCube policy-governed channels.

## Identity model

Promote current device cryptographic identity into a commerce identity system:

- Device identity: Ed25519 keypair used for transport/authentication.
- Business identity: signed profile anchored to owner keys and business scope.
- Relationship identity: pairwise trust records for customer/supplier links.

Suggested minimal business profile payload:

- business_id
- display_name
- optional gstin
- optional UPI handle
- catalog_root_hash (or catalog version hash)
- pubkey
- profile_sig

## Trust tiers and disclosure

Define explicit trust tiers to prevent accidental data leakage.

Tier 0: Self devices
- Full sync and full readable replication as policy permits.

Tier 1: Trusted commerce peers
- Scoped readable access to shared business records (invoice/credit/settlement artifacts).

Tier 2: Discovery peers (nearby/untrusted)
- Minimal signed metadata only.
- No financial amounts, party ledgers, balances, or sensitive identifiers.

Discovery payload should include only:
- peer id / key fingerprint
- business display name (optional user-controlled)
- catalog hash/version marker
- capability bits (supports invoice, supports credit ack)
- nonce + timestamp + signature

## Envelope operation model

Existing sync operations remain:
- upsert
- delete
- tombstone

Commerce operations to add:
- catalog_publish
- quote_issue
- quote_accept
- invoice_issue
- invoice_ack
- credit_entry_propose
- credit_entry_confirm
- payment_ref_attach
- settlement_close
- dispute_open
- dispute_resolve

Key rule:
- Sync ops can be conflict-resolved.
- Commerce ops require explicit state transition validation and signature checks by actor role.

## Commerce state machines (initial)

### Invoice lifecycle

draft -> issued -> acknowledged -> paid_ref_attached -> settled

Valid transition authority:
- issued: seller
- acknowledged: buyer
- paid_ref_attached: payer or payee (policy configurable)
- settled: seller and buyer evidence threshold satisfied

### Credit (udhar) lifecycle

proposed -> confirmed -> partially_settled -> settled -> disputed (optional side path)

Valid transition authority:
- proposed: creditor
- confirmed: debtor or prior bilateral trust policy
- settled: both sides or strong payment evidence

## Security and anti-abuse controls

1. Replay protection
- nonce window + env_id dedupe cache + TTL enforcement.

2. Discovery anti-spam
- Ignore unsigned beacons.
- Rate-limit by source key fingerprint.
- Optional local reputation score for relay priority.

3. Policy-first apply
- Validate policy before decrypt/apply.
- Relay-only mode never stores plaintext.

4. Revocation
- Revoked peers lose decrypt/apply rights for new envelopes.
- Rotation/revocation events are signed and monotonic.

## Storage and data partitioning

Partition local data by purpose:

- Private domain: never exported outside self-device trust.
- Shared sync domain: user-device convergence records.
- Shared commerce domain: bilateral/multilateral records with explicit relationship scope.

Every stored commerce record should carry:
- scope id
- origin signer
- counterpart signer(s) where required
- operation type
- immutable event id
- previous state reference (when stateful)

## UX and consent model requirements

Before enabling mesh commerce, user must explicitly opt in to:
- advertising discoverability
- publishing catalog metadata
- accepting inbound commerce requests
- relaying third-party encrypted traffic

Default posture:
- all disabled
- sync-only mode remains available independently

## Rollout recommendation

Phase A: Identity and discovery hardening
- Signed business profile and signed discovery beacons.
- Privacy-safe discovery payload.

Phase B: Commerce envelopes v1
- Add commerce op enums and validation pipeline.
- Implement invoice and credit state machines.

Phase C: Bilateral trust UX
- Approve/revoke business relationships.
- Table/scope permissions visible and auditable.

Phase D: Relay and store-forward tuning
- Battery-aware relay queue and retry strategy.
- Abuse controls and local reputation heuristics.

Phase E: Dispute and audit evidence
- Signed event timelines for invoice/credit disputes.
- Exportable local audit bundles.

## Success criteria

- Mesh commerce interactions complete offline in nearby mode.
- No sensitive financial plaintext appears in discovery traffic.
- State transitions reject invalid actor/signature combinations.
- Duplicate/replay attempts are blocked with bounded overhead.
- Users can understand and control publication/relay permissions.

## Relationship to existing docs

- Mesh sync strategy remains the transport and rollout baseline.
- Envelope tech spec remains the wire/policy baseline.
- This document defines the additional commerce protocol and governance requirements layered on top.
