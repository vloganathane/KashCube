# Web Companion Reliability Plan

## Context

Kash Cube Web Companion currently depends on local LAN reachability between:

- Phone app HTTP/WebSocket server (`0.0.0.0:50505`)
- Laptop browser (`http://<phone-ip>:50505`)

In user networks with AP/client isolation, unstable multicast, or transient packet loss, this path is fragile and appears as "random failure" to users.

## Observed Failure Pattern

From runtime diagnostics and logs:

1. Server starts correctly on phone (`/health` returns healthy).
2. mDNS discovery can resolve peers (phone and Mac discover each other).
3. P2P discovery occasionally evicts peers immediately on a single failed `/hello` probe.
4. Browser connection path has no inbound `/ws` handshake in some failure windows.

This means reliability is impacted by both network conditions and aggressive stale-peer eviction.

## LocalSend-Inspired Practices

LocalSend improves resilience using layered discovery and operational fallbacks:

1. Multicast discovery first.
2. HTTP/TCP scan fallback when multicast discovery is empty.
3. Manual IP-based targeting and favorites.
4. Troubleshooting guidance for firewall and AP isolation.

For Kash Cube, we keep privacy-first local-only constraints and adopt the same philosophy incrementally.

## Implemented In This Change

### 1) Multi-strike stale-peer eviction

File: `lib/data/services/p2p/p2p_discovery_service.dart`

Changes:

- Added probe failure threshold (`_kProbeFailureThreshold = 3`).
- Track per-peer consecutive probe failures (`_probeFailureCounts`).
- Do **not** evict on first timeout/error.
- Evict only after 3 consecutive probe failures.
- Reset failure count on successful probe or explicit peer loss.
- Added probe failure counter logs for diagnostics.

Why:

A single transient timeout should not remove an otherwise healthy peer. This directly addresses false stale evictions seen in logs (`reason=probe failed`).

### 2) Smart discovery legacy fallback scan

Files:

- `lib/data/services/p2p/p2p_discovery_service.dart`
- `lib/data/services/p2p/p2p_server.dart`
- `lib/data/services/p2p/p2p_coordinator.dart`

Changes:

- Added a lightweight unauthenticated endpoint: `GET /discover`.
- Endpoint returns minimal device metadata for discovery fallback:
   - `app`
   - `identity_id`
   - `display_name`
   - `port`
- Discovery now schedules a fallback scan after multicast startup.
- If no peers are found via mDNS after delay, perform a bounded `/24` HTTP probe on default P2P port.
- Successful fallback probes are added to in-memory peer list and surfaced in diagnostics logs.

Why:

Some LANs suppress multicast or make mDNS unreliable. A lightweight HTTP fallback gives LocalSend-style resilience while staying local-only and privacy-first.

## Next Implementation Steps

### Phase A (short-term, low risk)

1. Add Smart Discovery fallback for empty discovery windows:
   - Trigger optional HTTP subnet scan when mDNS finds no peers after delay.
2. Add Manual peer connect by IP:port in P2P UI.
3. Add "save peer" favorites for direct retries.

### Phase B (web companion reliability)

1. Add browser-side preflight statuses:
   - `server reachable` -> `ws reachable` -> `auth challenge` -> `approved`.
2. Add one-click retry with preserved endpoint.
3. Add explicit AP isolation/firewall guidance in UI.

### Phase C (product fallback)

1. Add guided hotspot mode.
2. Add offline export/import fallback for non-reachable LANs.

## Non-goals

- No cloud relay/server dependency.
- No financial data leaves device.
- Preserve local-first architecture.
