import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/models/device_session_token.dart';
import '../../data/models/linked_device.dart';
import '../../data/models/my_identity.dart';
import '../../data/repositories/linked_device_repository_impl.dart';
import '../../data/services/database_helper.dart';
import '../../data/services/device_session_service.dart';
import '../../data/services/identity_service.dart';
import '../../data/services/lan_discovery_service.dart';
import '../../data/services/sync_client.dart';
import '../../data/services/sync_server.dart';
import '../../data/services/token_service.dart';
import '../../domain/models/permission.dart';
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
// Active device session (secondary side)
// ---------------------------------------------------------------------------

/// Stores the [DeviceSession] after a successful pairing.
/// Null when this device is a primary or hasn't paired yet.
final deviceSessionProvider = StateProvider<DeviceSession?>((ref) => null);

// ---------------------------------------------------------------------------
// Verified device session — loaded + grace-checked on app start
// ---------------------------------------------------------------------------

/// Loads the local [device_session] row, verifies its Ed25519 signature, and
/// enforces the offline grace period.
///
/// This is the canonical source of truth for whether the current device is a
/// secondary and what permissions it has.  Primary devices get `null`.
final activeDeviceSessionProvider = FutureProvider<DeviceSession?>((ref) async {
  // Ensure identity keypair is available before we try to verify the token.
  await ref.watch(identityServiceProvider.future);

  final session = await DeviceSessionService.instance.loadAndVerify(
    DatabaseHelper.instance,
    IdentityService.instance,
  );
  if (session == null) return null;

  return DeviceSessionService.instance.enforceGrace(
    session,
    DatabaseHelper.instance,
  );
});

/// `true` when the secondary device's offline grace period has been exceeded
/// and all write operations are blocked.
final isReadOnlyProvider = Provider<bool>((ref) {
  final sessionAsync = ref.watch(activeDeviceSessionProvider);
  return sessionAsync.maybeWhen(
    data: (s) => s?.isReadOnlyForced ?? false,
    orElse: () => false,
  );
});

/// Resolves the [Permission] for [module] from the active device session token.
///
/// Returns [Permission.full] when:
/// - There is no active session (primary device).
/// - The session preset is `owner_mirror`.
///
/// Returns the preset-scoped permission otherwise.
final sessionPermissionProvider = Provider.family<Permission, String>(
  (ref, module) {
    final sessionAsync = ref.watch(activeDeviceSessionProvider);
    return sessionAsync.maybeWhen(
      data: (session) {
        if (session == null) return Permission.full;
        if (session.token.preset == 'owner_mirror') return Permission.full;
        try {
          final scope =
              jsonDecode(session.token.permissionScope) as Map<String, dynamic>;
          final m = scope[module] as Map<String, dynamic>?;
          if (m == null) return Permission.none;
          return Permission(
            canView:   m['canView']   as bool? ?? false,
            canCreate: m['canCreate'] as bool? ?? false,
            canEdit:   m['canEdit']   as bool? ?? false,
            canDelete: m['canDelete'] as bool? ?? false,
          );
        } catch (_) {
          return Permission.none;
        }
      },
      orElse: () => Permission.full, // still loading — don't block
    );
  },
);

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

      // Load THIS device's identity to send to the primary (identity-first pairing).
      final myIdentity = await DatabaseHelper.instance.withDatabase((db) async {
        final rows = await db.query('my_identity', limit: 1);
        if (rows.isEmpty) return null;
        return MyIdentity.fromMap(rows.first);
      });

      final session = await _client.sendPairRequest(
        preset:     preset,
        deviceOs:   Platform.operatingSystem,
        deviceType: 'phone',
        deviceName: Platform.localHostname,
        secondaryIdentityId:   myIdentity?.identityId,
        secondaryDisplayName:  myIdentity?.displayName,
      );

      // Persist session row; also update in-memory provider so the UI reacts immediately.
      await DatabaseHelper.instance.withDatabase((db) async {
        await db.insert(
          'linked_business_sessions',
          session.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      // Initial full pull — handle revocation gracefully.
      try {
        await _client.pullDeltas(session: session);
      } on SyncRevokedException {
        // Primary revoked us during the very first pull; wipe the session we
        // just stored and surface the error.
        await DeviceSessionService.instance.wipeSession(DatabaseHelper.instance);
        await _client.disconnect();
        _ref.read(syncStatusProvider.notifier).error();
        state = AsyncValue.error(
          'Device was revoked by the primary.',
          StackTrace.current,
        );
        return;
      }

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

// ---------------------------------------------------------------------------
// All linked business sessions (S7.5 — LinkedSessionsScreen)
// ---------------------------------------------------------------------------

class LinkedSessionsNotifier
    extends StateNotifier<AsyncValue<List<DeviceSession>>> {
  LinkedSessionsNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await DatabaseHelper.instance.withDatabase((db) => db.query(
            'linked_business_sessions',
            where: 'unlinked_at IS NULL',
            orderBy: 'display_order ASC, created_at DESC',
          ));
      state = AsyncValue.data(rows.map(DeviceSession.fromMap).toList());
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  /// Unlinks a session: sets `unlinked_at` timestamp and refreshes.
  Future<void> unlink(String sessionId) async {
    await DatabaseHelper.instance.withDatabase(
      (db) => db.update(
        'linked_business_sessions',
        {'unlinked_at': DateTime.now().toIso8601String()},
        where: 'session_id = ?',
        whereArgs: [sessionId],
      ),
    );
    await _load();
  }

  void refresh() => _load();
}

final linkedSessionsProvider = StateNotifierProvider<LinkedSessionsNotifier,
    AsyncValue<List<DeviceSession>>>(
  (_) => LinkedSessionsNotifier(),
);
