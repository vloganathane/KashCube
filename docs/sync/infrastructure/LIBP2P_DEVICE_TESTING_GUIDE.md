# libp2p Device Testing Guide

**Date**: 8 April 2026  
**Purpose**: Verify libp2p integration works on real Android devices

---

## Prerequisites

✅ **Available Devices**:
- Physical device: `2003bcd1` (connected via adb)
- Android emulator: `emulator-5554` (running)

✅ **Implementation Status**:
- All libp2p services implemented
- Feature flag added: `SettingsKeys.enableLibp2pSync`
- Smoke tests created (4/5 passing)

---

## Test Setup

### Step 1: Enable libp2p Feature Flag

The app defaults to WebRTC sync. To test libp2p:

1. **Launch app** on device: `flutter run -d <device-id>`
2. **Navigate to Settings** (hamburger menu → Settings)
3. **Scroll to Data section**
4. **Toggle "Experimental: libp2p Sync"** ✅
5. **Restart app** (feature flag loads on startup)

**Expected UI**:
```
┌─────────────────────────────────────────┐
│ ⚗️ Experimental: libp2p Sync           │
│ Current: libp2p (TCP + mDNS)           │
│ Restart required after changing        │
│                                    [ON] │ ← Toggle this
└─────────────────────────────────────────┘
```

---

## Test Scenarios

### 🧪 Test 1: Host Initialization (Single Device)

**Purpose**: Verify libp2p node starts successfully

**Steps**:
1. Enable libp2p sync (Settings → toggle ON)
2. Restart app
3. Check logs for successful initialization

**Expected Logs** (via `flutter run`):
```
[LibP2pNode] Initialized with peer ID: 12D3KooW...
[LibP2pNode] Started listening on: /ip4/192.168.x.x/tcp/xxxxx, ...
[Libp2pSync] Initialized successfully
```

**Success Criteria**:
- ✅ App starts without crashes
- ✅ Peer ID generated (shows in logs)
- ✅ Listening addresses populated (not empty)
- ✅ No "Bad state" or "Unimplemented" errors

---

### 🧪 Test 2: mDNS Peer Discovery (Two Devices, Same Network)

**Purpose**: Verify mDNS discovers peers on local network

**Requirements**:
- 2 devices on **same WiFi network**
- Both devices have libp2p enabled

**Steps**:

**Device A** (Physical device `2003bcd1`):
1. Enable libp2p sync
2. Restart app
3. Navigate to Sync screen (or trigger peer discovery)
4. Note peer ID in logs: `12D3KooW...`

**Device B** (Emulator `emulator-5554`):
1. Enable libp2p sync
2. Restart app
3. Navigate to Sync screen
4. Wait 10-15 seconds for mDNS discovery

**Expected Logs on Device B**:
```
[LibP2pDiscovery] Starting discovery...
[LibP2pDiscovery] Discovered peer: 12D3KooW... (KashCube Device)
[Libp2pSync] Discovered peer: KashCube Device
```

**Success Criteria**:
- ✅ Device B discovers Device A within 15 seconds
- ✅ Peer shows in discovered peers list
- ✅ Multiaddrs logged correctly

**Troubleshooting**:
- If no discovery: Check both devices on same WiFi (not cellular)
- Emulator may need network bridge config (use 2 physical devices if possible)
- Check firewall settings (mDNS uses UDP port 5353)

---

### 🧪 Test 3: Peer Connection (Two Devices)

**Purpose**: Verify two devices can establish libp2p connection

**Requirements**:
- Test 2 completed (peers discovered)

**Steps**:
1. Device A: Wait for discovery
2. Device B: Tap discovered peer to initiate sync
3. Observe connection establishment

**Expected Logs**:
```
Device B:
[Libp2pSync] Connecting to peer: 12D3KooW...
[LibP2pNode] Dialing peer at: /ip4/.../tcp/.../p2p/12D3KooW...
[Libp2pSync] Connected to 12D3KooW...

Device A:
[LibP2pNode] Incoming stream from peer: 12D3KooW...
[LibP2pProtocol] Handling stream for peer: 12D3KooW...
```

**Success Criteria**:
- ✅ Connection state changes to "Connected"
- ✅ No "No element" or "Bad state: No active stream" errors
- ✅ Protocol handler invoked

---

### 🧪 Test 4: Frame Exchange (SYNC_PLAN)

**Purpose**: Verify protocol frame sending/receiving works

**Steps**:
1. Test 3 completed (connection established)
2. Device B sends SYNC_PLAN frame
3. Device A receives and responds

**Expected Logs**:
```
Device B:
[Libp2pSync] Sending SYNC_PLAN frame
[LibP2pProtocol] Sent frame to peer (type: SYNC_PLAN, size: XXX bytes)

Device A:
[LibP2pProtocol] Received frame from peer (type: SYNC_PLAN)
[Libp2pSync] Processing SYNC_PLAN: tables=[...]
[Libp2pSync] Sending WRITE_OK response
```

**Success Criteria**:
- ✅ SYNC_PLAN sent successfully
- ✅ WRITE_OK received
- ✅ No frame serialization errors

---

### 🧪 Test 5: Data Sync (End-to-End)

**Purpose**: Verify actual transaction data syncs between devices

**Setup**:
1. Device A: Create 5 test transactions (manual entry)
2. Device B: No transactions initially

**Steps**:
1. Device B: Initiate sync with Device A
2. Wait for sync to complete
3. Verify transactions appear on Device B

**Expected Logs**:
```
Device B:
[Libp2pSync] Starting sync with peer...
[Libp2pSync] Received ROWS frame: table=transactions, count=5
[Libp2pSync] Upserted 5 rows to transactions
[Libp2pSync] Sync completed: 5 rows synced
```

**Success Criteria**:
- ✅ All 5 transactions appear on Device B
- ✅ Data integrity preserved (amounts, dates, merchants match)
- ✅ No duplicate rows
- ✅ Sync completion event triggered

---

## Known Issues & Limitations

### ⚠️ Listening Addresses Empty (Test Environment Only)
- **Issue**: `host.addrs` returns `[]` in Flutter test VM
- **Impact**: Integration tests skip connection/frame tests
- **Expected on Device**: Should populate with real network interfaces
- **Verification**: Check logs for actual IP addresses (not empty)

### ⚠️ mDNS Discovery Timing
- **Expected**: 5-15 seconds for initial discovery
- **Reason**: mDNS uses periodic queries (5-second intervals)
- **Workaround**: Wait patiently, don't trigger rapid re-scans

### ⚠️ Emulator Network Limitations
- **Issue**: Android emulator may not support mDNS properly
- **Workaround**: Use 2 physical devices for reliable mDNS testing
- **Alternative**: Use explicit peer addresses (skip mDNS, dial directly)

---

## Debugging Commands

### View Real-Time Logs (Filtered)
```bash
# Device A
flutter run -d 2003bcd1 | grep -E '\[Libp2p|\[LibP2p'

# Device B  
flutter run -d emulator-5554 | grep -E '\[Libp2p|\[LibP2p'
```

### Check Connected Devices
```bash
adb devices
```

### Check Network Connectivity (Device)
```bash
# On device shell
adb shell ip addr show wlan0  # WiFi interface
adb shell netstat -an | grep 4001  # Check if libp2p port listening
```

### Dump Full Logs
```bash
flutter run -d <device-id> --verbose > device_logs.txt 2>&1
```

---

## Success Metrics

**Phase 1.5 Complete** when:
- ✅ Test 1 passes (host initialization)
- ✅ Test 2 passes (mDNS discovery) OR Test 3 passes with manual addressing
- ✅ Test 3 passes (peer connection)
- ✅ Test 4 passes (frame exchange)
- ✅ Test 5 passes (data sync)

**Ready for Phase 1.6** (Comparative Testing) when:
- All 5 tests pass consistently
- No crashes or memory leaks during 5-minute sync session
- Performance comparable to WebRTC baseline

---

## Next Steps After Device Testing

1. **If Tests Pass**: Proceed to Phase 1.6 comparative testing
2. **If Tests Fail**: Document errors, check against known issues, iterate
3. **If Discovery Fails**: Consider adding manual peer addressing UI (fallback)
4. **If Performance Issues**: Profile with Flutter DevTools

---

## Emergency Rollback

If critical issues found:
1. Settings → Toggle libp2p sync **OFF**
2. Restart app (reverts to WebRTC)
3. Report issue with logs

Feature flag allows safe A/B testing without code changes.
