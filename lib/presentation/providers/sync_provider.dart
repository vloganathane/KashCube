import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/models/device_session_token.dart';
import '../../data/models/discovered_primary.dart';
import '../../data/models/linked_device.dart';
import '../../data/models/my_identity.dart';
import '../../data/models/payroll_notification.dart';
import '../../data/repositories/linked_device_repository_impl.dart';
import '../../data/services/database_helper.dart';
import '../../data/services/device_session_service.dart';
import '../../data/services/identity_service.dart';
import '../../data/services/lan_discovery_service.dart';
import '../../data/services/sync_client.dart';
import '../../data/services/sync_transport.dart';
import '../../data/services/ws_sync_transport.dart';
import '../../data/services/sync_server.dart';
import '../../data/services/token_service.dart';
import '../../data/services/web_server_service.dart';
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

/// Platform-aware transport: WS on web, TCP on Android.
final syncTransportProvider = Provider<SyncTransport>((ref) {
  if (kIsWeb) {
    return WsSyncTransport(
      identity: IdentityService.instance,
      dbHelper: DatabaseHelper.instance,
    );
  }
  return ref.read(syncClientProvider);
});

// ---------------------------------------------------------------------------
// Is this a secondary device?
// ---------------------------------------------------------------------------

/// `true` when the local `device_session` table has at least one row.
/// Primary devices never have a device_session row.
/// `true` when the local `linked_business_sessions` table has at least one
/// active (unlinked_at IS NULL) row — meaning this device is paired as secondary.
/// Primary devices never have an active linked_business_sessions row.
final isSecondaryDeviceProvider = FutureProvider<bool>((ref) async {
  return DatabaseHelper.instance.withDatabase((db) async {
    final rows = await db.query(
      'linked_business_sessions',
      where: 'unlinked_at IS NULL',
      limit: 1,
    );
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
    // If revoking a web session, also kill the in-memory token so the browser
    // gets an immediate 401 — same behaviour as WhatsApp's "Log out of Web".
    final current = state.valueOrNull;
    if (current != null) {
      final match = current.where((d) => d.deviceId == deviceId);
      if (match.isNotEmpty && match.first.deviceType == 'web') {
        await WebServerService.instance.killWebSession();
      }
    }
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
  ///
  /// Loads the primary's identity to embed as TXT record attributes so
  /// secondary devices can see the device name before pairing.
  Future<void> start() async {
    try {
      state = const AsyncValue.loading();
      final port = await _server.start();

      // Load identity for TXT record metadata (display_name + device_id).
      final myIdentity = await DatabaseHelper.instance.withDatabase((db) async {
        final rows = await db.query('my_identity', limit: 1);
        if (rows.isEmpty) return null;
        return MyIdentity.fromMap(rows.first);
      });
      final deviceId = IdentityService.instance.isInitialized
          ? await IdentityService.instance.deviceId
          : null;

      await _discovery.startServer(
        port,
        displayName: myIdentity?.displayName,
        deviceId:    deviceId,
      );
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

  DiscoveredPrimary? _foundPrimary;

  /// The display label of the discovered primary, or null while scanning.
  String? get foundPrimaryLabel => _foundPrimary?.label;

  /// Starts mDNS discovery; sets state to loading while scanning.
  Future<void> startScan() async {
    state = const AsyncValue.loading();
    await _discovery.startDiscovery(
      onFound: (primary) {
        _foundPrimary = primary;
        state         = const AsyncValue.data(null); // scanning done, ready to pair
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
    final host = ip   ?? _foundPrimary?.ipAddress;
    final p    = port ?? _foundPrimary?.port;
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

// ---------------------------------------------------------------------------
// Payroll notifications (secondary side — personal context)
// ---------------------------------------------------------------------------

/// Loads all pending [PayrollNotification] rows from the local DB.
///
/// Only relevant on secondary devices — primaries never receive these.
final pendingPayrollNotificationsProvider =
    FutureProvider<List<PayrollNotification>>((ref) async {
  final rows = await DatabaseHelper.instance.withDatabase(
    (db) => db.query(
      'payroll_notifications',
      where:   'status = ?',
      whereArgs: ['pending'],
      orderBy: 'received_at DESC',
    ),
  );
  return rows.map(PayrollNotification.fromMap).toList();
});

/// Manages payroll notification actions: dismiss and add-as-income.
class PayrollNotificationsNotifier
    extends StateNotifier<AsyncValue<List<PayrollNotification>>> {
  PayrollNotificationsNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await DatabaseHelper.instance.withDatabase(
        (db) => db.query(
          'payroll_notifications',
          where:     'status = ?',
          whereArgs: ['pending'],
          orderBy:   'received_at DESC',
        ),
      );
      state = AsyncValue.data(rows.map(PayrollNotification.fromMap).toList());
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  void refresh() => _load();

  /// Marks a notification as dismissed without creating a transaction.
  Future<void> dismiss(String notificationId) async {
    await DatabaseHelper.instance.withDatabase(
      (db) => db.update(
        'payroll_notifications',
        {'status': 'dismissed'},
        where:     'notification_id = ?',
        whereArgs: [notificationId],
      ),
    );
    _load();
  }

  /// Marks a notification as added after the caller creates the income
  /// transaction, linking [transactionId] for traceability.
  Future<void> markAdded(String notificationId, {int? transactionId}) async {
    await DatabaseHelper.instance.withDatabase(
      (db) => db.update(
        'payroll_notifications',
        {
          'status': 'added',
          'created_transaction_id': ?transactionId,
        },
        where:     'notification_id = ?',
        whereArgs: [notificationId],
      ),
    );
    _load();
  }
}

final payrollNotificationsNotifierProvider = StateNotifierProvider<
    PayrollNotificationsNotifier, AsyncValue<List<PayrollNotification>>>(
  (_) => PayrollNotificationsNotifier(),
);

// ---------------------------------------------------------------------------
// Sync Now (secondary) — delta exchange against an existing session
// ---------------------------------------------------------------------------

class SyncNowState {
  const SyncNowState({
    this.status    = SyncStatus.idle,
    this.pulled    = 0,
    this.pushed    = 0,
    this.error,
    this.lastSyncAt,
    this.foundLabel,
  });

  final SyncStatus status;
  final int        pulled;
  final int        pushed;
  final String?    error;
  final DateTime?  lastSyncAt;
  /// Display name of the discovered primary (e.g. "Suresh's Phone").
  /// Populated once mDNS discovery resolves; null while scanning.
  final String?    foundLabel;

  bool get isRunning =>
      status == SyncStatus.scanning ||
      status == SyncStatus.connecting ||
      status == SyncStatus.syncing;
}

class SyncNowNotifier extends StateNotifier<SyncNowState> {
  SyncNowNotifier(this._transport, this._discovery, this._ref)
      : super(const SyncNowState());

  final SyncTransport       _transport;
  final LanDiscoveryService _discovery;
  final Ref                 _ref;

  Future<void> syncNow() async {
    if (state.isRunning) return;

    // 1. Load the verified active session.
    final session = await _ref.read(activeDeviceSessionProvider.future);
    if (session == null) {
      state = const SyncNowState(
        status: SyncStatus.error,
        error:  'No active session — pair with a primary device first.',
      );
      return;
    }

    // 2. Connect to primary — WS on web (direct URL), mDNS+TCP on Android.
    if (kIsWeb) {
      // Read the stored WS URL from settings (written during WebConnectScreen).
      final wsUrl = await DatabaseHelper.instance.withDatabase((db) async {
        final rows = await db.query(
          'settings',
          where:     'key = ?',
          whereArgs: ['web_sync_url'],
          limit:     1,
        );
        return rows.isNotEmpty ? rows.first['value'] as String? : null;
      });

      if (wsUrl == null) {
        state = const SyncNowState(
          status: SyncStatus.error,
          error:  'No web session. Scan the QR code from Settings → KashCube Web on your phone.',
        );
        return;
      }

      state = const SyncNowState(status: SyncStatus.connecting);
      try {
        await _transport.open(Uri.parse(wsUrl));
      } catch (e) {
        state = SyncNowState(
          status: SyncStatus.error,
          error:  'Connection failed. Re-scan the QR from your phone. ($e)',
        );
        return;
      }
    } else {
      state = const SyncNowState(status: SyncStatus.scanning);

      // Discover primary via mDNS.
      String? host;
      int?    port;
      String? label;
      final found = Completer<void>();
      await _discovery.startDiscovery(
        onFound: (primary) {
          host  = primary.ipAddress;
          port  = primary.port;
          label = primary.label;
          if (!found.isCompleted) found.complete();
        },
      );
      try {
        await found.future.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        // primary not found within timeout
      }
      await _discovery.stopDiscovery();

      if (host == null || port == null) {
        state = const SyncNowState(
          status: SyncStatus.error,
          error:  'Primary device not found. Make sure both devices are on the same Wi-Fi.',
        );
        return;
      }

      state = SyncNowState(status: SyncStatus.connecting, foundLabel: label);
      try {
        await _transport.open(
            Uri(scheme: 'kashcube-tcp', host: host!, port: port!));
      } catch (e) {
        state = SyncNowState(status: SyncStatus.error, error: e.toString());
        return;
      }
    }

    state = const SyncNowState(status: SyncStatus.syncing);
    try {
      // 3. Pull deltas from primary.
      final pulled = await _transport.pullDeltas(
        session:    session,
        lastSyncAt: session.lastSyncAt,
      );

      // 4. Push local changes to primary.
      final localRows =
          await _transport.buildLocalDeltas(since: session.lastSyncAt);
      final pushed = localRows.isEmpty
          ? 0
          : await _transport.pushDeltas(session: session, rows: localRows);

      // 5. Stamp watermark.
      final now = DateTime.now();
      await DatabaseHelper.instance.withDatabase(
        (db) => db.update(
          'linked_business_sessions',
          {'last_sync_at': now.toIso8601String()},
          where:     'session_id = ?',
          whereArgs: [session.sessionId],
        ),
      );

      await _transport.close();
      state = SyncNowState(
        status:     SyncStatus.done,
        pulled:     pulled,
        pushed:     pushed,
        lastSyncAt: now,
      );
    } on SyncRevokedException {
      await _transport.close();
      await DeviceSessionService.instance.wipeSession(DatabaseHelper.instance);
      state = const SyncNowState(
        status: SyncStatus.error,
        error:  'Access was revoked by the primary.',
      );
    } catch (e) {
      await _transport.close();
      state = SyncNowState(
        status: SyncStatus.error,
        error:  e.toString(),
      );
    }
  }

  void reset() => state = const SyncNowState();

  // ── Reserve a document number from the primary ───────────────────────────

  /// Connects to the primary just long enough to reserve one document number.
  ///
  /// Returns the reserved number (e.g. `INV-25-26-0042`) or a
  /// `PENDING-<token>` placeholder when offline, so the caller can save with
  /// [InvoiceStatus.pendingNumber] and have the primary assign a real number
  /// on the next successful sync.
  ///
  /// [docType] must be one of: `invoice`, `quote`, `dc`, `credit_note`,
  /// `debit_note`.
  Future<String> reserveDocNumber(String docType) async {
    // If sync is currently running, fall back to PENDING to avoid port conflict.
    if (state.isRunning) return _pendingPlaceholder();

    final session = await _ref.read(activeDeviceSessionProvider.future);
    if (session == null) return _pendingPlaceholder();

    SyncTransport? transport;
    try {
      if (kIsWeb) {
        // Web secondary: connect via the stored WS URL.
        final wsUrl = await DatabaseHelper.instance.withDatabase((db) async {
          final rows = await db.query(
            'settings',
            where:     'key = ?',
            whereArgs: ['web_sync_url'],
            limit:     1,
          );
          return rows.isNotEmpty ? rows.first['value'] as String? : null;
        });
        if (wsUrl == null) return _pendingPlaceholder();
        transport = WsSyncTransport(
          identity: IdentityService.instance,
          dbHelper: DatabaseHelper.instance,
        );
        await transport.open(Uri.parse(wsUrl));
      } else {
        // Android secondary: discover primary via mDNS.
        String? host;
        int?    port;
        final found = Completer<void>();
        await _discovery.startDiscovery(
          onFound: (primary) {
            host = primary.ipAddress;
            port = primary.port;
            if (!found.isCompleted) found.complete();
          },
        );
        try {
          await found.future.timeout(const Duration(seconds: 5));
        } on TimeoutException {
          // primary not reachable — fall back to PENDING
        }
        await _discovery.stopDiscovery();

        if (host == null || port == null) return _pendingPlaceholder();

        // Use a fresh SyncClient so syncNow() is unaffected.
        transport = SyncClient(
          identity: IdentityService.instance,
          dbHelper: DatabaseHelper.instance,
        );
        await transport.open(Uri(scheme: 'kashcube-tcp', host: host!, port: port!));
      }

      final numbers = await transport.reserveNumber(
        session:  session,
        docType:  docType,
      );
      return numbers.isNotEmpty ? numbers.first : _pendingPlaceholder();
    } catch (_) {
      return _pendingPlaceholder();
    } finally {
      await transport?.close();
    }
  }

  static String _pendingPlaceholder() {
    final token = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    return 'PENDING-$token';
  }
}

final syncNowProvider =
    StateNotifierProvider.autoDispose<SyncNowNotifier, SyncNowState>(
  (ref) {
    final notifier = SyncNowNotifier(
      ref.read(syncTransportProvider),
      LanDiscoveryService.instance,
      ref,
    );
    if (!kIsWeb) ref.onDispose(LanDiscoveryService.instance.stopDiscovery);
    return notifier;
  },
);

// ---------------------------------------------------------------------------
// Web live-sync listener (web only)
// ---------------------------------------------------------------------------

/// Keeps a persistent WebSocket connection open on the browser companion so
/// `data_changed` events pushed by the phone trigger an automatic sync.
///
/// Activated by `ref.watch(webLiveSyncProvider)` in [AppShell].
/// No-op on Android.
class WebLiveSyncState {
  const WebLiveSyncState({this.isConnected = false});
  final bool isConnected;
}

class WebLiveSyncNotifier extends StateNotifier<WebLiveSyncState> {
  WebLiveSyncNotifier(this._ref) : super(const WebLiveSyncState()) {
    if (kIsWeb) _connect();
  }

  final Ref _ref;
  bool _disposed = false;

  Future<void> _connect() async {
    while (!_disposed) {
      final wsUrl = await DatabaseHelper.instance.withDatabase((db) async {
        final rows = await db.query(
          'settings',
          where:     'key = ?',
          whereArgs: ['web_sync_url'],
          limit:     1,
        );
        return rows.isNotEmpty ? rows.first['value'] as String? : null;
      });

      if (wsUrl == null || _disposed) break;

      try {
        final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
        await channel.ready;
        if (!_disposed) state = const WebLiveSyncState(isConnected: true);

        await for (final raw in channel.stream) {
          if (_disposed) break;
          try {
            final msg = jsonDecode(raw as String) as Map<String, dynamic>;
            if (msg['event'] == 'data_changed') {
              // Trigger a background sync without blocking the listener.
              _ref.read(syncNowProvider.notifier).syncNow();
            }
          } catch (_) {}
        }
      } catch (_) {}

      if (!_disposed) {
        state = const WebLiveSyncState(isConnected: false);
        // Back-off before reconnect.
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final webLiveSyncProvider =
    StateNotifierProvider<WebLiveSyncNotifier, WebLiveSyncState>(
  (ref) {
    ref.keepAlive();
    return WebLiveSyncNotifier(ref);
  },
);
