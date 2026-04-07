# dart_libp2p Integration Guide (Phase 1.5)

**Date**: 7 April 2026  
**Package**: `dart_libp2p: ^1.0.3`  
**Status**: Implementation guide for replacing UnimplementedError placeholders

---

## Overview

This document provides the integration blueprint for connecting KashCube's libp2p service layer to the actual `dart_libp2p` package API. It's based on pub.dev documentation analysis and needs verification against v1.0.3 actual API.

## ⚠️ Version Warning

**Critical**: Documentation fetched shows examples for dart_libp2p **0.5.2**, but KashCube uses **1.0.3**. API may have changed. **Always verify with actual package imports before implementing.**

---

## Quick Start Example (from dart_libp2p docs)

```dart
import 'package:dart_libp2p/dart_libp2p.dart';
import 'package:dart_libp2p/config/config.dart' as p2p_config;
import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519;  
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/p2p/security/noise/noise_protocol.dart';
import 'package:dart_libp2p/p2p/transport/udx_transport.dart';
import 'package:dart_libp2p/p2p/transport/connection_manager.dart' as p2p_conn_manager;
import 'package:dart_udx/dart_udx.dart';

Future<Host> createHost({String? listen}) async {
  final keyPair = await crypto_ed25519.generateEd25519KeyPair();
  final udx = UDX();
  final connMgr = p2p_conn_manager.ConnectionManager();

  final options = <p2p_config.Option>[
    p2p_config.Libp2p.identity(keyPair),
    p2p_config.Libp2p.connManager(connMgr),
    p2p_config.Libp2p.transport(UDXTransport(connManager: connMgr, udxInstance: udx)),
    p2p_config.Libp2p.security(await NoiseSecurity.create(keyPair)),
    if (listen != null) p2p_config.Libp2p.listenAddrs([MultiAddr(listen)]),
  ];

  final host = await p2p_config.Libp2p.new_(options);
  await host.start();
  return host;
}
```

---

## File 1: `lib/data/services/libp2p/libp2p_node.dart`

### Current State
- 360 lines of placeholder code
- Key methods throw `UnimplementedError`
- Uses `dynamic` for Host and Stream types

### Implementation Tasks

#### 1. Add dart_libp2p Imports

```dart
import 'package:dart_libp2p/dart_libp2p.dart' as dart_libp2p;
import 'package:dart_libp2p/config/config.dart' as p2p_config;
import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519;
import 'package:dart_libp2p/core/multiaddr.dart' as p2p_multiaddr;
import 'package:dart_libp2p/p2p/security/noise/noise_protocol.dart';
import 'package:dart_libp2p/p2p/transport/tcp_transport.dart';
import 'package:dart_libp2p/p2p/transport/connection_manager.dart' as p2p_conn_manager;
import 'package:dart_libp2p/core/peer/addr_info.dart' as p2p_addr_info;
```

**TODO**: Verify these imports work with v1.0.3. Package structure may have changed.

#### 2. Update Type Definitions

```dart
// Replace: libp2p.Host? _host;
dart_libp2p.Host? _host;

// Replace: final Map<String, List<dynamic>> _activeStreams = {};
final Map<String, List<dart_libp2p.Stream>> _activeStreams = {};

// Replace: typedef StreamHandler = Future<void> Function(dynamic stream);
typedef StreamHandler = Future<void> Function(dart_libp2p.Stream stream);
```

**TODO**: Confirm `dart_libp2p.Stream` type exists. May be `core/network/stream`.

#### 3. Implement `_createHost` Method

**Location**: Line 94 (currently throws `UnimplementedError`)

```dart
Future<dart_libp2p.Host> _createHost({
  Uint8List? identity,
  List<String> listenAddrs = const [],
}) async {
  // Generate or import Ed25519 key pair
  final keyPair = identity != null
      ? await crypto_ed25519.importEd25519PrivateKey(identity)
      : await crypto_ed25519.generateEd25519KeyPair();

  // Create connection manager
  final connMgr = p2p_conn_manager.ConnectionManager();

  // Parse multiaddrs
  final listenMultiaddrs = listenAddrs
      .map((addr) => p2p_multiaddr.MultiAddr(addr))
      .toList();

  // Configure libp2p options
  final options = <p2p_config.Option>[
    p2p_config.Libp2p.identity(keyPair),
    p2p_config.Libp2p.connManager(connMgr),
    p2p_config.Libp2p.transport(TCPTransport(connManager: connMgr)),
    p2p_config.Libp2p.security(await NoiseSecurity.create(keyPair)),
    p2p_config.Libp2p.listenAddrs(listenMultiaddrs),
  ];

  // Create and start host
  final host = await p2p_config.Libp2p.new_(options);
  await host.start();
  
  return host;
}
```

**TODOs**:
- Verify `importEd25519PrivateKey()` signature (may need seed vs full key)
- Check if `TCPTransport` constructor is correct (may need additional params)
- Confirm `Libp2p.new_()` is correct factory method name
- Verify `host.start()` is needed or called automatically

#### 4. Implement `dial` Method

**Location**: Line 150 (currently throws `UnimplementedError`)

```dart
Future<dart_libp2p.Stream> dial({
  required String peerMultiaddr,
  required String protocolId,
}) async {
  if (_host == null) {
    throw StateError('Host not initialized');
  }

  try {
    // Parse multiaddr
    final ma = p2p_multiaddr.MultiAddr(peerMultiaddr);
    
    // Extract peer ID from multiaddr (last component)
    // Format: /ip4/192.168.1.10/tcp/9090/p2p/QmPeerId...
    final peerId = _extractPeerIdFromMultiaddr(ma);
    
    // Create AddrInfo
    final addrInfo = p2p_addr_info.AddrInfo(peerId, [ma]);
    
    // Connect to peer
    await _host!.connect(addrInfo);
    
    // Open stream with protocol ID
    final stream = await _host!.newStream(peerId, [protocolId]);
    
    // Track stream
    _activeStreams.putIfAbsent(peerId.toString(), () => []).add(stream);
    
    debugPrint('[LibP2pNode] Dialed $peerMultiaddr on protocol $protocolId');
    return stream;
  } catch (e, stack) {
    debugPrint('[LibP2pNode] Dial failed: $e');
    debugPrint(stack.toString());
    rethrow;
  }
}

dart_libp2p.PeerId _extractPeerIdFromMultiaddr(p2p_multiaddr.MultiAddr ma) {
  // Extract /p2p/QmXXX component
  final components = ma.toString().split('/');
  for (var i = 0; i < components.length - 1; i++) {
    if (components[i] == 'p2p') {
      return dart_libp2p.PeerId.fromString(components[i + 1]);
    }
  }
  throw FormatException('No peer ID in multiaddr: $ma');
}
```

**TODOs**:
- Verify `Host.connect()` signature (may return connection object)
- Check `Host.newStream()` method (may be `openStream` or use different API)
- Confirm `PeerId.fromString()` constructor name
- Validate multiaddr parsing logic

#### 5. Implement `registerProtocol` Method

**Location**: Line 173 (currently placeholder only)

```dart
void registerProtocol(String protocolId, StreamHandler handler) {
  if (_host == null) {
    throw StateError('Host not initialized');
  }

  _protocolHandlers[protocolId] = handler;
  
  // Register with libp2p host
  _host!.setStreamHandler(protocolId, (dart_libp2p.Stream stream) async {
    try {
      await handler(stream);
    } catch (e, stack) {
      debugPrint('[LibP2pNode] Protocol handler error: $e');
      debugPrint(stack.toString());
      await stream.close();
    }
  });
  
  debugPrint('[LibP2pNode] Registered protocol: $protocolId');
}
```

**TODOs**:
- Verify `Host.setStreamHandler()` method name (may be `setHandler`, `addStreamHandler`, etc.)
- Check handler signature expectations
- Confirm error handling pattern

---

## File 2: `lib/data/services/libp2p/libp2p_protocol.dart`

### Current State
- 390 lines of frame parsing/serialization logic
- Stream I/O uses placeholders (`dynamic stream`)
- Frame format: 4-byte big-endian length + JSON payload

### Implementation Tasks

#### 1. Add Stream Type

```dart
import 'package:dart_libp2p/dart_libp2p.dart' as dart_libp2p;
import 'dart:typed_data';

typedef LibP2pStream = dart_libp2p.Stream;
```

#### 2. Fix Stream I/O in `_readFrame` Method

**Location**: Line 254 (currently throws `UnimplementedError`)

```dart
Future<Map<String, dynamic>?> _readFrame(LibP2pStream stream) async {
  try {
    // Read 4-byte length prefix (big-endian u32)
    final lengthBytes = await _readExactly(stream, 4);
    if (lengthBytes == null) {
      return null; // EOF
    }
    
    final length = ByteData.sublistView(lengthBytes).getUint32(0, Endian.big);
    
    // Validate frame size
    if (length > maxFrameSize) {
      throw FormatException(
        'Frame too large: $length bytes (max: $maxFrameSize)',
      );
    }
    if (length == 0) {
      throw FormatException('Frame length cannot be zero');
    }
    
    // Read JSON payload
    final payloadBytes = await _readExactly(stream, length);
    if (payloadBytes == null) {
      throw FormatException('Unexpected EOF while reading frame payload');
    }
    
    // Parse JSON
    final json = utf8.decode(payloadBytes);
    return jsonDecode(json) as Map<String, dynamic>;
  } catch (e) {
    debugPrint('[LibP2pProtocol] Frame read error: $e');
    rethrow;
  }
}

/// Read exactly [count] bytes from stream, or return null on EOF.
Future<Uint8List?> _readExactly(LibP2pStream stream, int count) async {
  final buffer = <int>[];
  
  // TODO: Verify dart_libp2p Stream API for reading bytes
  // This is placeholder logic - actual API may differ
  
  // Option A: If Stream has read() method
  while (buffer.length < count) {
    final chunk = await stream.read();  // TODO: Check actual signature
    if (chunk == null || chunk.isEmpty) {
      if (buffer.isEmpty) return null; // EOF
      throw FormatException('Unexpected EOF');
    }
    buffer.addAll(chunk);
  }
  
  return Uint8List.fromList(buffer.sublist(0, count));
}
```

**TODOs**:
- **CRITICAL**: Verify dart_libp2p Stream read API. May use:
  - `stream.read()` returning `Uint8List?`
  - `stream.listen()` with event-based reads
  - `StreamChannel` pattern
- Check for existing buffering/framing utilities in dart_libp2p
- Validate EOF handling

#### 3. Fix `_sendFrame` Method

**Location**: Line 288 (currently throws `UnimplementedError`)

```dart
Future<void> _sendFrame(
  LibP2pStream stream,
  Map<String, dynamic> frame,
) async {
  try {
    // Serialize JSON
    final json = jsonEncode(frame);
    final payloadBytes = utf8.encode(json);
    
    // Validate size
    if (payloadBytes.length > maxFrameSize) {
      throw FormatException(
        'Frame too large: ${payloadBytes.length} bytes (max: $maxFrameSize)',
      );
    }
    
    // Create length prefix (4-byte big-endian u32)
    final lengthBytes = Uint8List(4);
    ByteData.sublistView(lengthBytes).setUint32(0, payloadBytes.length, Endian.big);
    
    // Send length + payload
    // TODO: Verify dart_libp2p Stream write API
    await stream.write(lengthBytes);
    await stream.write(Uint8List.fromList(payloadBytes));
    
    debugPrint('[LibP2pProtocol] Sent frame: ${frame['type']} (${payloadBytes.length} bytes)');
  } catch (e) {
    debugPrint('[LibP2pProtocol] Frame send error: $e');
    rethrow;
  }
}
```

**TODOs**:
- Verify `stream.write()` method signature
- Check if write needs flush/await
- Confirm error handling pattern

#### 4. Fix `_getPeerId` Helper

**Location**: Line 312 (currently placeholder)

```dart
String _getPeerId(LibP2pStream stream) {
  // TODO: Verify how to get remote peer ID from stream
  // May be:
  // - stream.remotePeerId
  // - stream.conn.remotePeer
  // - stream.connection.remotePeerId
  
  try {
    return stream.conn.remotePeer.toString();  // Placeholder
  } catch (e) {
    debugPrint('[LibP2pProtocol] Failed to get peer ID: $e');
    return 'unknown';
  }
}
```

**TODO**: Find correct API for getting remote peer ID from stream.

---

## File 3: `lib/data/services/libp2p/libp2p_discovery.dart`

### Current State
- 265 lines of mDNS discovery logic
- All methods throw `UnimplementedError`
- Service type: `_kash-sync._tcp`

### Implementation Tasks

#### 1. Add mDNS Package Import

**Option A**: Use dart_libp2p's built-in mDNS

```dart
import 'package:dart_libp2p/p2p/discovery/mdns/mdns.dart' as libp2p_mdns;
```

**Option B**: Use standalone mdns_dart package (recommended by dart_libp2p docs)

```dart
// Add to pubspec.yaml:
// dependencies:
//   mdns_dart: ^0.2.0

import 'package:mdns_dart/mdns_dart.dart';
```

**Recommendation**: Try Option A first. If not available, use Option B (mdns_dart is referenced in dart_libp2p docs).

#### 2. Implement `start` Method (Option B: mdns_dart)

**Location**: Line 68 (currently throws `UnimplementedError`)

```dart
Future<void> start({
  required int port,
  required String multiaddr,
  required String peerName,
  Map<String, String>? metadata,
}) async {
  if (_isStarted) {
    debugPrint('[LibP2pDiscovery] Already started');
    return;
  }

  try {
    debugPrint('[LibP2pDiscovery] Starting mDNS discovery on port $port');
    
    // Create mDNS client
    _client = await MDNS.create();
    
    // Start broadcasting local service
    await _startBroadcast(
      port: port,
      multiaddr: multiaddr,
      peerName: peerName,
      metadata: metadata,
    );
    
    // Start discovering peers
    await _startListening();
    
    _isStarted = true;
    debugPrint('[LibP2pDiscovery] Started successfully');
  } catch (e, stack) {
    debugPrint('[LibP2pDiscovery] Start failed: $e');
    debugPrint(stack.toString());
    await stop();
    rethrow;
  }
}
```

#### 3. Implement `_startBroadcast` Method

**Location**: Line 125 (currently placeholder)

```dart
Future<void> _startBroadcast({
  required int port,
  required String multiaddr,
  required String peerName,
  Map<String, String>? metadata,
}) async {
  try {
    // Create TXT records with multiaddr
    final txtRecords = <String, String>{
      'multiaddr': multiaddr,
      'name': peerName,
      'protocol': kashSyncProtocolId,
      ...?metadata,
    };
    
    // Register service
    _localService = await (_client as MDNS).advertiseService(
      type: kashSyncServiceType,  // '_kash-sync._tcp'
      name: peerName,
      port: port,
      txtRecords: txtRecords,
    );
    
    _isBroadcasting = true;
    debugPrint('[LibP2pDiscovery] Broadcasting as "$peerName" on port $port');
  } catch (e) {
    debugPrint('[LibP2pDiscovery] Broadcast failed: $e');
    rethrow;
  }
}
```

**TODOs**:
- Verify `MDNS.advertiseService()` signature
- Check TXT record format requirements
- Confirm service type format (`_kash-sync._tcp` vs `_kash-sync._tcp.local.`)

#### 4. Implement `_startListening` Method

**Location**: Line 152 (currently placeholder)

```dart
Future<void> _startListening() async {
  try {
    // Subscribe to service discovery
    (_client as MDNS).discoverServices(kashSyncServiceType).listen(
      (MDNSService service) {
        _handleDiscoveredService(service);
      },
      onError: (e) {
        debugPrint('[LibP2pDiscovery] Discovery error: $e');
      },
    );
    
    debugPrint('[LibP2pDiscovery] Listening for $kashSyncServiceType services');
  } catch (e) {
    debugPrint('[LibP2pDiscovery] Listen failed: $e');
    rethrow;
  }
}

void _handleDiscoveredService(MDNSService service) {
  try {
    // Extract multiaddr from TXT records
    final multiaddr = service.txtRecords['multiaddr'];
    final peerName = service.txtRecords['name'] ?? service.name;
    
    if (multiaddr == null || multiaddr.isEmpty) {
      debugPrint('[LibP2pDiscovery] Service missing multiaddr: ${service.name}');
      return;
    }
    
    // Extract peer ID from multiaddr
    final peerId = _extractPeerIdFromMultiaddr(multiaddr);
    
    // Emit as SyncPeer
    final peer = SyncPeer(
      id: peerId,
      name: peerName,
      multiaddrs: [multiaddr],
      metadata: service.txtRecords,
    );
    
    _discoveredPeers.add(peer);
    debugPrint('[LibP2pDiscovery] Discovered peer: $peerName ($peerId)');
  } catch (e) {
    debugPrint('[LibP2pDiscovery] Error processing service: $e');
  }
}

String _extractPeerIdFromMultiaddr(String multiaddr) {
  // Extract /p2p/QmXXX from multiaddr string
  final components = multiaddr.split('/');
  for (var i = 0; i < components.length - 1; i++) {
    if (components[i] == 'p2p') {
      return components[i + 1];
    }
  }
  throw FormatException('No peer ID in multiaddr: $multiaddr');
}
```

**TODOs**:
- Verify `MDNS.discoverServices()` returns `Stream<MDNSService>`
- Check `MDNSService` structure (may be different class name)
- Confirm TXT record access pattern

---

## File 4: `lib/data/repositories/libp2p_sync_repository_impl.dart`

### Current State
- 814 lines fully implemented
- Only issue: `_sendFrame` method throws `UnimplementedError`

### Implementation Task

#### Fix `_sendFrame` Method

**Location**: Line 645 (currently throws `UnimplementedError`)

```dart
Future<void> _sendFrame(Map<String, dynamic> frame) async {
  if (_activeStream == null) {
    throw StateError('No active stream for sending frames');
  }
  
  try {
    await _protocol.sendFrame(_activeStream!, frame);
  } catch (e) {
    debugPrint('[Libp2pSync] Send frame error: $e');
    _emitEvent(SyncEvent.error(
      message: 'Failed to send ${frame['type']} frame: $e',
      details: {'frame_type': frame['type']},
    ));
    rethrow;
  }
}
```

**Prerequisites**: Requires `LibP2pProtocol.sendFrame()` public method to be added:

```dart
// Add to LibP2pProtocol class:
Future<void> sendFrame(
  LibP2pStream stream,
  Map<String, dynamic> frame,
) async {
  return _sendFrame(stream, frame);
}
```

**TODO**: Verify stream is stored correctly in `connect()` method.

---

## Testing Strategy

### Unit Tests (Can be updated now)

1. **Mock-based tests** (already passing 22/27):
   - Continue using mocks for Host, Stream, Protocol
   - No changes needed until real integration

2. **Smoke tests** (after integration):
   - Create `test/integration/libp2p_smoke_test.dart`
   - Test: Host creation, stream open, frame send/receive
   - Use two test hosts on localhost

### Integration Tests (Phase 1.6)

1. **Device-to-device test**:
   - Run on 2 Android emulators
   - Enable libp2p feature flag
   - Verify connection + basic sync

2. **Protocol compliance**:
   - Verify /kash-sync/1.0.0 frame format
   - Test all frame types (SYNC_PLAN, ROWS, PUSH, etc.)

---

## Migration Checklist

### Phase 1.5A: Research & Preparation
- [x] Fetch dart_libp2p documentation
- [x] Analyze API for Host creation, streams, mDNS
- [x] Document integration points
- [ ] Verify v1.0.3 API matches docs (try imports, check autocomplete)
- [ ] Check if mdns_dart is needed or use built-in

### Phase 1.5B: Implementation
- [ ] Update `libp2p_node.dart` (6 methods)
- [ ] Update `libp2p_protocol.dart` (3 methods)
- [ ] Update `libp2p_discovery.dart` (4 methods)
- [ ] Update `libp2p_sync_repository_impl.dart` (1 method)
- [ ] Add missing public methods to LibP2pProtocol

### Phase 1.5C: Testing
- [ ] Fix compilation errors
- [ ] Run unit tests (expect same 22/27 passing)
- [ ] Create smoke test for Host creation
- [ ] Test on Android device with feature flag enabled

### Phase 1.5D: Validation
- [ ] Manual test: 2 devices discover each other
- [ ] Manual test: Send /ping frame
- [ ] Manual test: Sync single table
- [ ] Update implementation plan with results

---

## Known Risks

### API Version Mismatch
- **Risk**: Documentation shows 0.5.2, you have 1.0.3
- **Mitigation**: Verify every import/method before committing code
- **Fallback**: Downgrade to 0.5.2 if API is incompatible

### Stream I/O API Unknown
- **Risk**: Don't know exact read/write API
- **Mitigation**: Check autocomplete in IDE, read package source
- **Fallback**: Use `StreamChannel` or event-based reads if needed

### mDNS Availability
- **Risk**: dart_libp2p may not include mDNS in v1.0.3
- **Mitigation**: Add `mdns_dart: ^0.2.0` dependency
- **Fallback**: Use Bonjour/Avahi native plugins (Android/iOS)

### Android Permissions
- **Risk**: mDNS requires `CHANGE_WIFI_MULTICAST_STATE` permission
- **Mitigation**: Already handled in Phase 0 (see ANDROID_PERMISSION_SURFACE_NOTES.md)
- **Fallback**: None - required for mDNS

---

## Success Criteria

### Minimal (Phase 1.5 complete)
- [ ] All `UnimplementedError` removed
- [ ] Code compiles without errors
- [ ] Unit tests still pass (22/27 minimum)

### Functional (Phase 1.6 ready)
- [ ] Two devices discover each other via mDNS
- [ ] Can open /kash-sync/1.0.0 stream
- [ ] Can send/receive one PING frame
- [ ] Stream closes gracefully

### Complete (Phase 1.6 goals)
- [ ] Full table sync works (transactions)
- [ ] Deduplication verified
- [ ] Comparable performance to WebRTC
- [ ] No memory leaks after 10 disconnect/reconnect cycles

---

## Next Steps

1. **Verify imports** (30 min):
   ```dart
   import 'package:dart_libp2p/dart_libp2p.dart';
   // Check autocomplete for: Host, Stream, PeerId, MultiAddr
   ```

2. **Start with LibP2pNode** (2-3 hours):
   - Smallest surface area
   - Core functionality
   - Easiest to test in isolation

3. **Then LibP2pProtocol** (2-3 hours):
   - Depends on LibP2pNode for stream type
   - Critical for frame handling

4. **Then LibP2pDiscovery** (3-4 hours):
   - May need mdns_dart dependency
   - Can be tested separately

5. **Finally Libp2pSyncRepositoryImpl** (30 min):
   - Just one method to fix
   - Depends on all above

**Total estimate**: 8-11 hours for complete integration.

---

## References

- [dart_libp2p Package](https://pub.dev/packages/dart_libp2p)
- [dart_libp2p Documentation](https://pub.dev/documentation/dart_libp2p/latest/)
- [libp2p Specification](https://github.com/libp2p/specs)
- [mdns_dart Package](https://pub.dev/packages/mdns_dart)
- [KashCube Protocol Spec](./LIBP2P_KASH_SYNC_PROTOCOL.md)

---

**Last Updated**: 7 April 2026  
**Author**: GitHub Copilot (Claude Sonnet 4.5)  
**Status**: Draft - Awaiting v1.0.3 API verification
