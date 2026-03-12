import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/models/device_session_token.dart';
import '../../data/models/linked_device.dart';
import '../../data/repositories/linked_device_repository_impl.dart';
import '../../data/services/database_helper.dart';
import '../../data/services/identity_service.dart';
import '../../data/services/lan_discovery_service.dart';
import '../../data/services/sync_client.dart';
import '../../data/services/sync_server.dart';
import '../../data/services/token_service.dart';
import '../../domain/repositories/linked_device_repository.dart';
import 'settings_provider.dart';

// ---------------------------------------------------------------------------
// Infrastructure providers
// ---------------------------------------------------------------------------

final linkedDeviceRepositoryProvider = Provider<LinkedDeviceRepository>(
  (_) => LinkedDeviceRepositoryImpl(),
);

/// Initialises [IdentityService] on first access (async).
final identityServiceProvider = FutureProvider<IdentityService>((ref) async {
  final settings = ref.read(settingsRepositoryProvider);
  await IdentityService.instance.ensureInitialized(settings);
  return IdentityService.instance;
});

final tokenServiceProvider = Provider<TokenService>((ref) {
  return TokenService(IdentityService.instance);
});

final syncServerProvider = Provider<SyncServer>((ref) {
  return SyncServer(
    identity:        IdentityService.instance,
    tokenService:    ref.read(tokenServiceProvider),
    linkedDeviceRepo: ref.read(linkedDeviceRepositoryProvider),
    dbHelper:        DatabaseHelper.instance,
  );
});

final syncClientProvider = Provider<SyncClient>((ref) {
  return SyncClient(
    identity: IdentityService.instance,
    dbHelper: DatabaseHelper.instance,
  );
});

// ---------------------------------------------------------------------------
// Is this a secondary device?
// ---------------------------------------------------------------------------

/// `true` when the local `device_session` table has at least one row.
/// Primary devices never have a device_session row.
final isSecondaryDeviceProvider = FutureProvider<bool>((ref) async {
  return DatabaseHelper.instance.withDatabase((db) async {
    final rows = await db.query('device_session', limit: 1);
    return rows.isNotEmpty;
  });
});

// ---------------------------------------------------------------------------
// Linked devices list (primary only)
// ---------------------------------------------------------------------------

class LinkedDevicesNotifier
    extends StateNotifier<AsyncValue<List<LinkedDevice>>> {
  LinkedDevicesNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  final LinkedDeviceRepository _repo;

  Future<void> _load() async {
    try {
      final devices = await _repo.getActive();
      if (mounted) state = AsyncValue.data(devices);
    } catch (e, s) {
      if (mounted) state = AsyncValue.error(e, s);
    }
  }

  Future<void> refresh() => _load();

  Future<void> revoke(String deviceId) async {
    await _repo.revoke(deviceId);
    await _load();
  }
}

final linkedDevicesProvider =
    StateNotifierProvider<LinkedDevicesNotifier, AsyncValue<List<LinkedDevice>>>(
  (ref) => LinkedDevicesNotifier(ref.read(linkedDeviceRepositoryProvider)),
);

// ---------------------------------------------------------------------------
// Sync status
// ---------------------------------------------------------------------------

enum SyncStatus { idle, scanning, connecting, syncing, done, error }

class SyncStatusNotifier extends StateNotifier<SyncStatus> {
  SyncStatusNotifier() : super(SyncStatus.idle);

  void scanning()   => state = SyncStatus.scanning;
  void connecting() => state = SyncStatus.connecting;
  void syncing()    => state = SyncStatus.syncing;
  void done()       => state = SyncStatus.done;
  void error()      => state = SyncStatus.error;
  void reset()      => state = SyncStatus.idle;
}

final syncStatusProvider =
    StateNotifierProvider<SyncStatusNotifier, SyncStatus>(
  (_) => SyncStatusNotifier(),
);

// ---------------------------------------------------------------------------
// Active sync session (secondary side)
// ---------------------------------------------------------------------------

/// Stores the [DeviceSession] after a successful pairing.
/// Null when this device is a primary or hasn't paired yet.
final deviceSessionProvider = StateProvider<DeviceSession?>((ref) => null);

// ---------------------------------------------------------------------------
// Primary host flow — start mDNS + TCP, show QR
// ---------------------------------------------------------------------------

class LinkHostNotifier extends StateNotifier<AsyncValue<int>> {
  LinkHostNotifier(this._server, this._discovery)
      : super(const AsyncValue.loading());

  final SyncServer          _server;
  final LanDiscoveryService _discovery;

  /// Starts the TCP server and registers the mDNS service.
  /// State becomes [AsyncValue.data(port)] on success.
  Future<void> start() async {
    try {
      state = const AsyncValue.loading();
      final port = await _server.start();
      await _discovery.startServer(port);
      state = AsyncValue.data(port);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  /// Stops everything.
  Future<void> stop() async {
    await _discovery.stopServer();
    await _server.stop();
    state = const AsyncValue.loading();
  }
}

final linkHostProvider =
    StateNotifierProvider.autoDispose<LinkHostNotifier, AsyncValue<int>>(
  (ref) {
    final notifier = LinkHostNotifier(
      ref.read(syncServerProvider),
      LanDiscoveryService.instance,
    );
    ref.onDispose(notifier.stop);
    return notifier;
  },
);

// ---------------------------------------------------------------------------
// Secondary join flow — mDNS scan + pair + initial pull
// ---------------------------------------------------------------------------

class LinkJoinNotifier extends StateNotifier<AsyncValue<DeviceSession?>> {
  LinkJoinNotifier(this._client, this._discovery, this._ref)
      : super(const AsyncValue.data(null));

  final SyncClient          _client;
  final LanDiscoveryService _discovery;
  final Ref                 _ref;

  String? _foundIp;
  int?    _foundPort;

  /// Starts mDNS discovery; sets state to loading while scanning.
  Future<void> startScan() async {
    state = const AsyncValue.loading();
    await _discovery.startDiscovery(
      onFound: (ip, port, _) {
        _foundIp   = ip;
        _foundPort = port;
        state      = const AsyncValue.data(null); // scanning done, ready to pair
        _discovery.stopDiscovery();
      },
    );
    _ref.read(syncStatusProvider.notifier).scanning();
  }

  /// Completes pairing via scanned QR or auto-discovered service.
  /// [ip] and [port] may come from QR code instead of mDNS.
  Future<void> pair({
    String? ip,
    int?    port,
    String  preset  = 'owner_mirror',
  }) async {
    final host = ip   ?? _foundIp;
    final p    = port ?? _foundPort;
    if (host == null || p == null) {
      state = AsyncValue.error('No host found', StackTrace.current);
      return;
    }

    state = const AsyncValue.loading();
    _ref.read(syncStatusProvider.notifier).connecting();

    try {
      await _client.connect(ip: host, port: p);
      _ref.read(syncStatusProvider.notifier).syncing();

      final session = await _client.sendPairRequest(
        preset:     preset,
        deviceOs:   Platform.operatingSystem,
        deviceType: 'phone',
        deviceName: Platform.localHostname,
      );

      // Persist device_session row
      await DatabaseHelper.instance.withDatabase((db) async {
        await db.insert(
          'device_session',
          session.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      // Initial full pull
      await _client.pullDeltas(session: session);

      await _client.disconnect();
      _ref.read(syncStatusProvider.notifier).done();
      _ref.read(deviceSessionProvider.notifier).state = session;
      state = AsyncValue.data(session);
    } catch (e, s) {
      await _client.disconnect();
      _ref.read(syncStatusProvider.notifier).error();
      state = AsyncValue.error(e, s);
    }
  }
}

final linkJoinProvider = StateNotifierProvider.autoDispose<LinkJoinNotifier,
    AsyncValue<DeviceSession?>>(
  (ref) {
    final notifier = LinkJoinNotifier(
      ref.read(syncClientProvider),
      LanDiscoveryService.instance,
      ref,
    );
    ref.onDispose(() => LanDiscoveryService.instance.stopDiscovery());
    return notifier;
  },
);
