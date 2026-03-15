# LAN Sync Improvements — 15 March 2026
## TXT-Record Discovery (bonsoir) + Persistent Sessions + Ping/Pong Keepalive

**Inspired by:** [wifi-mirror](https://github.com/navneetprajapati26/wifi-mirror) — architecture review of Network Discovery Service and Signaling Service.

---

## Background & Motivation

Two issues were identified during the codebase review against wifi-mirror's approach:

### Issue 1 — mDNS blind discovery (nsd, no TXT records)

KashCube uses `nsd: ^4.1.0` for mDNS. When a secondary device scans the LAN it receives only `(ip, port, serviceName)`. The `serviceName` is the static string `"KashCube"`, not the actual device name. This means:

- The secondary device sees "Found KashCube" but has no idea which device it's pairing with.
- In a shop with two tablets both running as primaries at different counters, there is no disambiguation before the pairing QR is scanned.

**Fix:** Migrate to `bonsoir: ^6.0.0`. Bonsoir supports **TXT records** (`attributes`) embedded in the mDNS service advertisement. We embed `device_id`, `display_name`, and `role` so the secondary can show the primary's name ("Navneet's Tab") in the DevicesSyncScreen before the user taps Connect.

### Issue 2 — Single-message-per-connection server / idle timeout drops

The current `SyncServer._handleConnection` reads **one** message, handles it, and closes the socket. This creates two problems:

**2a. Multi-operation sessions are silently broken.** `SyncNowNotifier.syncNow()` calls `_transport.pullDeltas()` and then `_transport.pushDeltas()` on the **same** open socket. The server closes after the first (delta_request), so the second (delta_upload) was sent to a dead socket and never processed. Same issue with `pair()` → first pull on same connection.

**2b. Idle socket drops at the OS TCP layer.** For the POS counter scenario (secondary keeps one connection open to reserve invoice numbers), Android kernel drops idle TCP connections after 2–4 minutes. Without application-level keepalive, `reserveNumber()` calls fail silently with `SocketException`.

**Fix:** Convert `_handleConnection` to a **persistent message loop** (one connection handles N operations). Add a server-side ping/pong keepalive: the server sends `{"type":"ping"}` after 30 seconds of idle, the client auto-replies `{"type":"pong"}`, and the connection stays alive.

---

## Architecture After Changes

```
PRIMARY DEVICE
  SyncServer._handleConnection(socket)
    loop:
      msg = _readMessage(socket)   ← 60s timeout per read
      resetPingTimer()             ← cancels+restarts 30s idle timer
      switch msg.type:
        'pong'        → (no-op; timer already reset)
        'pair_request'→ _handlePairRequest        → sends pair_response
        'delta_request'→ _handleDeltaRequest      → sends delta_response
        'delta_upload' → _handleDeltaUpload        → sends upload_ack
        'payroll_...'  → _handlePayrollNotif       → sends response
        'reserve_number'→ _handleReserveNumber    → sends number_reserved
    pingTimer fires at 30s → server sends {'type':'ping'}
    loop continues; client replies with 'pong' on next message

SECONDARY DEVICE
  SyncClient._readResponse()          ← NEW helper
    wraps _readMessage
    if response is {'type':'ping'}:
      send {'type':'pong'}
      continue waiting
    else: return the real response
  
  All response-reads in:
    sendPairRequest / pullDeltas / pushDeltas /
    fetchPayrollNotifications / reserveNumber
  …now use _readResponse() instead of _readMessage()

LAN DISCOVERY
  LanDiscoveryService (bonsoir rewrite)
    Primary broadcasts BonsoirService with attributes:
      device_id:    "ulid-xxx"
      display_name: "Navneet's Galaxy Tab"
      role:         "primary"
    Secondary receives DiscoveredPrimary(ip, port, displayName, deviceId)
    sync_provider callers pass rich model instead of raw (ip, port, name)
```

---

## Session Flow (After Fix)

```
SECONDARY                              PRIMARY
  │                                       │
  │── TCP connect ───────────────────────►│ _handleConnection → loop
  │── pair_request ──────────────────────►│ _handlePairRequest
  │◄── pair_response ─────────────────────│
  │── delta_request ─────────────────────►│ _handleDeltaRequest
  │◄── delta_response ────────────────────│
  │── delta_upload ──────────────────────►│ _handleDeltaUpload
  │◄── upload_ack ────────────────────────│
  │                                       │  [idle 30s]
  │◄── ping ──────────────────────────────│ pingTimer fires
  │── pong ─────────────────────────────►│ resetPingTimer
  │── reserve_number ────────────────────►│ _handleReserveNumber
  │◄── number_reserved ───────────────────│
  │── [TCP close] ───────────────────────►│ _readMessage → null → loop exits
```

---

## New Files

| File | Purpose |
|------|---------|
| `lib/data/models/discovered_primary.dart` | Rich discovery result from bonsoir (ip, port, displayName, deviceId) |

---

## Changed Files

| File | Change |
|------|--------|
| `pubspec.yaml` | `nsd: ^4.1.0` → `bonsoir: ^6.0.0` |
| `lib/data/services/lan_discovery_service.dart` | Full rewrite: BonsoirBroadcast + TXT records; onFound callback now delivers `DiscoveredPrimary` |
| `lib/presentation/providers/sync_provider.dart` | `LinkHostNotifier.start()` passes identity metadata to `startServer()`; three `onFound` callbacks updated to `DiscoveredPrimary`; `LinkJoinNotifier` stores `_foundPrimary` with device label |
| `lib/data/services/sync_server.dart` | `_handleConnection` is now a persistent message loop; ping/pong keepalive; server `_readMessage` timeout bumped to 60s |
| `lib/data/services/sync_client.dart` | New `_readResponse()` that auto-replies to server pings; all response-reads updated |

---

## What Does NOT Change

- 4-byte length-prefixed framing — unchanged
- Token-per-message auth — unchanged  
- All message type payloads — unchanged (except `ping`/`pong` added)
- WebServerService (WS path) — unchanged; ping/pong is TCP-server only
- Android manifest permissions — already correct (`CHANGE_WIFI_MULTICAST_STATE` was in place)

---

## Testing Notes

- Manual test: pair secondary → verify DevicesSyncScreen shows primary's display name before tapping Connect
- Manual test: trigger Sync Now → verify both pullDeltas AND pushDeltas succeed (new multi-message fix)
- Manual test: leave connection idle 35s → verify ping/pong keeps it alive, `reserveNumber()` still works
- No unit tests required: integration behavior verified via logs + manual flow
