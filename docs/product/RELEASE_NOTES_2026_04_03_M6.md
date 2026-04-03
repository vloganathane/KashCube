# Kash Cube Release Notes

Version: M6 Security and Release Readiness Gate
Date: 3 April 2026
Status: Released to staging

## Highlights

1. Local-first sync remains the default behavior.
2. Anywhere Mode is available as an opt-in beta capability.
3. App-layer integrity checks are enforced for cloud-signaled data-plane sync frames.
4. Key rotation policy and checker are in place for connect-anywhere peers.
5. Unified security threat model and release gate acceptance matrix are now documented.

## Security and Privacy Disclosure

1. Local-first + Beta Anywhere Mode disclaimer:
   - Kash Cube defaults to local-first operation on local networks.
   - Anywhere Mode is optional, explicit opt-in, and currently beta.
2. Anywhere Mode metadata notice:
   - Financial payloads remain end-to-end protected.
   - In Anywhere Mode, limited connection metadata can be visible to cloud relay infrastructure (for example session timing, routing metadata, and peer connectivity events).
   - No financial transaction values, party names, or balances are intentionally sent as analytics payloads.

## Validation Snapshot

1. M6 security acceptance tests: 13 passed, 0 failed.
2. Threat review and release sign-off checklist completed.
3. Existing local-first behavior preserved.

## Known Limitations

1. Rooted or jailbroken devices are out of scope for full compromise protection.
2. Weak backup passphrases remain user-risk; use strong passphrases.
3. macOS key-at-rest hardening is planned for a future revision.

## References

1. docs/architecture/security/THREAT_MODEL.md
2. docs/architecture/decisions/adr/ADR-007-webrtc-data-plane-with-local-and-cloud-signaling.md
3. docs/legal/TERMS_OF_USE_V2_2.md
