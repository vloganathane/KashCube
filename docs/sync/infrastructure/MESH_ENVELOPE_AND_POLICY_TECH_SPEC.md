# KashCube Mesh Envelope and Policy Technical Spec

Date: 6 April 2026  
Status: Draft technical specification

## Purpose

Define the envelope format and processing rules for KashCube mesh sync over a libp2p transport adapter.

This specification covers:

- Envelope schema
- ACK and retry flow
- Dedupe and replay protection
- Policy evaluation model
- Apply pipeline and error handling

## Design constraints

- Privacy-first and local-first behavior.
- No central sync server required.
- Deterministic convergence for financial data.
- Role- and scope-aware authorization.

## Transport assumptions (libp2p adapter)

The libp2p layer provides:

- Peer identity and secure sessions
- Point-to-point and relay-capable paths
- Message transport for envelope bytes

The libp2p layer does not define KashCube table semantics.

## Envelope schema (v1)

```json
{
  "ver": 1,
  "env_id": "uuid-v7",
  "origin_peer": "peer-id",
  "origin_device": "device-id",
  "business_scope": "business-id-or-global",
  "table": "transactions",
  "op": "upsert",
  "record_id": "sync-id",
  "record_version": 42,
  "vector": {
    "device-a": 42,
    "device-b": 17
  },
  "sent_at_ms": 1770000000000,
  "ttl": 6,
  "mode": "replica-readable",
  "cipher_suite": "xchacha20poly1305",
  "key_scope": "business:abc",
  "payload_ciphertext": "base64",
  "payload_nonce": "base64",
  "payload_aad": "base64",
  "sig_alg": "ed25519",
  "sig": "base64"
}
```

Optional extensibility fields (recommended for future compatibility):

- payload_digest_multihash: self-describing payload digest
- attachment_refs: list of content-addressed artifact references
- attachment_codec: codec hint for attachment decoding

Note:
- These fields can adopt Multiformats without requiring full IPFS network coupling.
- If IPFS is used for large immutable attachments, store only encrypted payload references for private scopes.

Required fields:

- ver, env_id, origin_peer, table, op, record_id, sent_at_ms, ttl, mode, payload_ciphertext, sig

Mode enum:

- relay-only
- replica-encrypted
- replica-readable

Operation enum:

- upsert
- delete
- tombstone

## ACK schema (v1)

```json
{
  "ver": 1,
  "ack_id": "uuid-v7",
  "env_id": "uuid-v7",
  "from_peer": "peer-id",
  "to_peer": "peer-id",
  "status": "applied",
  "reason": "",
  "sent_at_ms": 1770000005000,
  "sig": "base64"
}
```

Status enum:

- received
- relayed
- applied
- rejected
- expired

## Processing pipeline

On envelope receipt, run in order:

1. Basic validation
- Schema version supported
- Required fields present
- ttl > 0

2. Signature verification
- Verify origin signature before any apply path

3. Replay and dedupe gate
- Reject if env_id already seen in active dedupe window
- Reject if nonce replay is detected for origin/key scope

4. Policy evaluation
- Determine whether local peer is relay-only, replica-encrypted, or replica-readable for this scope/table

5. Decrypt decision
- relay-only: never decrypt
- replica-encrypted: optional decrypt false (store/forward only)
- replica-readable: decrypt and continue

6. Apply decision
- Apply only if policy allows and envelope passes conflict gate

7. Relay decision
- Decrement ttl
- Forward only once per env_id to eligible peers

8. Emit ACK
- received/relayed/applied/rejected/expired as appropriate

## Conflict strategy interface

Conflict strategy is table-class specific and remains KashCube-owned.

Interface sketch:

```text
resolve(table, local_record, incoming_record, vector, record_version) -> resolution
```

Resolution outputs:

- apply incoming
- keep local
- merge fields
- mark conflict for manual review (rare fallback)

## Dedupe and replay protection

### Dedupe cache

- Key: env_id
- TTL: configurable (default 24h)
- Storage: persistent bounded LRU + memory index

### Nonce replay window

- Track recent nonces per origin_peer and key_scope
- Reject duplicates and stale window overflow

### Forwarding dedupe

- Maintain forwarded_env_ids to ensure one forward per peer path

## ACK and retry flow

Sender behavior:

1. On send, create retry tracker entry with env_id.
2. Wait for ACK within T1.
3. If no ACK, retry with exponential backoff up to N attempts.
4. Stop retries on applied/rejected/expired.

Recommended defaults:

- T1: 3s
- backoff: x2
- max attempts: 5
- max lifetime per envelope: 2m (interactive) or policy-defined for background sync

## Policy evaluation model

Inputs:

- table
- business_scope
- operation
- local peer role and permissions
- trust level and link status
- envelope mode request

Output:

```json
{
  "allow_receive": true,
  "allow_decrypt": false,
  "allow_apply": false,
  "allow_relay": true,
  "effective_mode": "relay-only",
  "reason": "role_insufficient_for_table"
}
```

### Policy rules (initial)

1. Local-only tables
- allow_receive=false, allow_relay=false for non-origin

2. Sensitive finance tables
- allow_apply only for authorized trusted peers in scope

3. Relay fallback
- if not authorized to read, may still relay if envelope policy permits

4. Revoked peer
- deny receive/decrypt/apply/relay

## Store-and-forward queue

Queue entry:

- env_id
- ciphertext blob
- first_seen_ms
- retry_count
- next_retry_ms
- expiry_ms

Rules:

- Enforce max queue size and max item TTL
- Evict oldest expired first
- Never store plaintext in relay-only mode

## Error handling

Reject codes:

- ERR_SCHEMA_UNSUPPORTED
- ERR_SIGNATURE_INVALID
- ERR_TTL_EXPIRED
- ERR_DUPLICATE_ENV
- ERR_REPLAY_DETECTED
- ERR_POLICY_DENY
- ERR_DECRYPT_FAIL
- ERR_CONFLICT_UNRESOLVED

Every reject should emit rejected ACK with reason code.

## Observability

Metrics:

- envelope_received_total
- envelope_applied_total
- envelope_relayed_total
- envelope_rejected_total_by_reason
- ack_latency_ms
- retry_attempts_total
- dedupe_hits_total

Logs:

- Do not log plaintext payloads.
- Log env_id, table, scope, operation, and result code.

## Minimal pseudocode

```text
onEnvelope(env):
  validate(env)
  verifySignature(env)
  if dedupeSeen(env.env_id): reject(DUP)
  if replayDetected(env): reject(REPLAY)

  policy = evaluatePolicy(env, localPeer)
  if !policy.allow_receive: reject(POLICY)

  if policy.allow_decrypt:
    payload = decrypt(env)
    if policy.allow_apply:
      result = resolveAndApply(payload)
      emitAck(result)
    else:
      emitAck(RECEIVED)
  else:
    storeCiphertextIfNeeded(env)

  if policy.allow_relay and env.ttl > 1:
    env.ttl -= 1
    forward(env)
    emitAck(RELAYED)
```

## Compatibility and versioning

- Envelope schema is versioned by ver.
- New optional fields must be backward-compatible.
- Breaking changes require ver increment and adapter compatibility layer.
- Multiformats-based optional fields should remain additive and backward-compatible.

## Test matrix (minimum)

1. Direct sync
- valid apply
- duplicate suppression
- signature failure reject

2. Multi-hop relay
- A -> B -> C success
- TTL expiry at intermediary
- relay dedupe under repeated receipt

3. Policy enforcement
- unauthorized decrypt denied
- unauthorized apply denied
- revoked peer denied

4. Retry behavior
- delayed ACK then success
- max retries exceeded

5. Conflict cases
- concurrent upserts
- delete vs update

## Next implementation tasks

1. Implement envelope DTO + serializer.
2. Add signature verification and replay guard.
3. Add policy evaluator module.
4. Add ACK tracker and retry scheduler.
5. Integrate with libp2p adapter boundaries.
6. Add test harness for A-B-C topology.

## Related documents

- MESH_SYNC_STRATEGY_DECISION.md
- MESH_COMMERCE_NETWORK_ARCHITECTURE.md
