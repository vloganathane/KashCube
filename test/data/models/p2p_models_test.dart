import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/models/invoice_event.dart';
import 'package:kash_cube/data/models/peer_device.dart';
import 'package:kash_cube/data/models/sync_watermark.dart';
import 'package:kash_cube/data/models/trusted_peer.dart';

void main() {
  // Reference timestamps for round-trip tests.
  final now   = DateTime.utc(2026, 3, 17, 10, 30);
  final later = DateTime.utc(2026, 3, 17, 12, 0);

  // ── TrustedPeer ───────────────────────────────────────────────────────────

  group('TrustedPeer', () {
    final full = TrustedPeer(
      id:              42,
      peerIdentityId:  'peer-uuid-123',
      peerName:        'Ravi Laptop',
      businessId:      'biz-456',
      sharedSecretEnc: 'ZW5jcnlwdGVk',
      pairedAt:        now,
      lastSeenAt:      later,
      lastSyncedAt:    later,
      isActive:        true,
    );

    test('fromMap(toMap()) round-trip preserves all fields', () {
      final copy = TrustedPeer.fromMap(full.toMap());
      expect(copy.id,             full.id);
      expect(copy.peerIdentityId, full.peerIdentityId);
      expect(copy.peerName,       full.peerName);
      expect(copy.businessId,     full.businessId);
      expect(copy.sharedSecretEnc,full.sharedSecretEnc);
      expect(copy.pairedAt,       full.pairedAt);
      expect(copy.lastSeenAt,     full.lastSeenAt);
      expect(copy.lastSyncedAt,   full.lastSyncedAt);
      expect(copy.isActive,       full.isActive);
    });

    test('toMap excludes id when null', () {
      final noId = TrustedPeer(
        peerIdentityId: 'x', sharedSecretEnc: 'y', pairedAt: now,
      );
      expect(noId.toMap().containsKey('id'), isFalse);
    });

    test('toMap excludes optional nulls', () {
      final minimal = TrustedPeer(
        peerIdentityId: 'x', sharedSecretEnc: 'y', pairedAt: now,
      );
      final map = minimal.toMap();
      expect(map.containsKey('peer_name'),    isFalse);
      expect(map.containsKey('business_id'), isFalse);
      expect(map.containsKey('last_seen_at'), isFalse);
      expect(map.containsKey('last_synced_at'), isFalse);
    });

    test('is_active stored as int (1=true, 0=false)', () {
      expect(full.toMap()['is_active'], 1);
      final inactive = TrustedPeer(
        peerIdentityId: 'x', sharedSecretEnc: 'y',
        pairedAt: now, isActive: false,
      );
      expect(inactive.toMap()['is_active'], 0);
    });

    test('copyWith updates only specified fields', () {
      final updated = full.copyWith(peerName: 'New Name', isActive: false);
      expect(updated.peerName,      'New Name');
      expect(updated.isActive,      isFalse);
      expect(updated.peerIdentityId, full.peerIdentityId); // unchanged
      expect(updated.sharedSecretEnc, full.sharedSecretEnc); // unchanged
    });
  });

  // ── SyncWatermark ─────────────────────────────────────────────────────────

  group('SyncWatermark', () {
    final full = SyncWatermark(
      peerIdentityId: 'peer-uuid-123',
      tableName:      'invoices',
      lastSyncedAt:   now,
      lastSyncCursor: 'cursor-abc',
    );

    test('fromMap(toMap()) round-trip preserves all fields', () {
      final copy = SyncWatermark.fromMap(full.toMap());
      expect(copy.peerIdentityId, full.peerIdentityId);
      expect(copy.tableName,      full.tableName);
      expect(copy.lastSyncedAt,   full.lastSyncedAt);
      expect(copy.lastSyncCursor, full.lastSyncCursor);
    });

    test('toMap excludes lastSyncCursor when null', () {
      final noCursor = SyncWatermark(
        peerIdentityId: 'p', tableName: 't', lastSyncedAt: now,
      );
      expect(noCursor.toMap().containsKey('last_sync_cursor'), isFalse);
    });

    test('copyWith only updates specified fields', () {
      final updated = full.copyWith(lastSyncedAt: later);
      expect(updated.lastSyncedAt,   later);
      expect(updated.peerIdentityId, full.peerIdentityId);
      expect(updated.lastSyncCursor, full.lastSyncCursor);
    });

    test('toString includes identifiable info', () {
      expect(full.toString(), contains('invoices'));
      expect(full.toString(), contains('peer-uuid-123'));
    });
  });

  // ── InvoiceEvent ──────────────────────────────────────────────────────────

  group('InvoiceEvent', () {
    final full = InvoiceEvent(
      id:         7,
      invoiceId:  'inv-sync-uuid',
      eventType:  'status_changed',
      eventData:  '{"from":"draft","to":"sent"}',
      occurredAt: now,
      deviceId:   'dev-abc',
      syncId:     'evt-sync-uuid',
    );

    test('fromMap(toMap()) round-trip preserves all fields', () {
      final copy = InvoiceEvent.fromMap(full.toMap());
      expect(copy.id,         full.id);
      expect(copy.invoiceId,  full.invoiceId);
      expect(copy.eventType,  full.eventType);
      expect(copy.eventData,  full.eventData);
      expect(copy.occurredAt, full.occurredAt);
      expect(copy.deviceId,   full.deviceId);
      expect(copy.syncId,     full.syncId);
    });

    test('toMap excludes id when null', () {
      final noId = InvoiceEvent(
        invoiceId: 'x', eventType: 'e',
        occurredAt: now, deviceId: 'd', syncId: 's',
      );
      expect(noId.toMap().containsKey('id'), isFalse);
    });

    test('toMap excludes eventData when null', () {
      final noData = InvoiceEvent(
        invoiceId: 'x', eventType: 'e',
        occurredAt: now, deviceId: 'd', syncId: 's',
      );
      expect(noData.toMap().containsKey('event_data'), isFalse);
    });
  });

  // ── PeerDevice ────────────────────────────────────────────────────────────

  group('PeerDevice', () {
    final peer = PeerDevice(
      identityId:  'peer-id-1',
      displayName: 'Ravi Phone',
      host:        '192.168.1.100',
      port:        54321,
      businessName:'Ravi Stores',
      isTrusted:   true,
      lastSeenAt:  now,
    );

    test('baseUrl is correct', () {
      expect(peer.baseUrl, 'http://192.168.1.100:54321');
    });

    test('equality based on identityId only', () {
      final same = PeerDevice(
        identityId: 'peer-id-1', displayName: 'different name',
        host: '10.0.0.1', port: 9999,
      );
      expect(peer, same);
      expect(peer.hashCode, same.hashCode);
    });

    test('different identityId == false', () {
      final other = PeerDevice(
        identityId: 'peer-id-2', displayName: 'Ravi Phone',
        host: '192.168.1.100', port: 54321,
      );
      expect(peer, isNot(other));
    });

    test('copyWith updates only specified fields', () {
      final updated = peer.copyWith(isReachable: false, port: 11111);
      expect(updated.isReachable, isFalse);
      expect(updated.port,        11111);
      expect(updated.identityId,  peer.identityId);
      expect(updated.host,        peer.host);
    });
  });
}
