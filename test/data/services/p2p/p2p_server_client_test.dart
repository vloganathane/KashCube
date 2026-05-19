import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:kash_cube/data/services/p2p/p2p_client.dart';
import 'package:kash_cube/data/services/p2p/p2p_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getTemporaryDirectory') {
          return '.dart_tool/test_tmp';
        }
        return '.dart_tool';
      });

  // 32-byte shared secret shared between server and client.
  final sharedSecret = Uint8List.fromList(List.generate(32, (i) => i + 1));
  const peerId = 'test-peer-identity';

  late P2pClient client;
  var clientInitialized = false;
  HttpOverrides? previousHttpOverrides;

  setUpAll(() async {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;

    await P2pServer.instance.start(
      localIdentityId: 'local-test-device',
      localDisplayName: 'KashCube Test Device',
      secretForPeer: (id) async => id == peerId ? sharedSecret : null,
      onPull: (table, afterVersion) async => {
        'table': table,
        'rows': [
          {'sync_id': 'row-1', 'updated_at': '2026-03-17T10:00:00.000Z'},
        ],
      },
      onPush: (table, rows) async {
        // accept silently
      },
      onPairRequest: (id, publicKey, displayName, proof) async => false,
    );

    client = P2pClient(
      baseUrl: 'http://127.0.0.1:${P2pServer.instance.port}',
      identityId: peerId,
      sharedSecret: sharedSecret,
    );
    clientInitialized = true;
  });

  tearDownAll(() async {
    if (clientInitialized) {
      client.dispose();
    }
    await P2pServer.instance.stop();
    HttpOverrides.global = previousHttpOverrides;
  });

  group('P2pServer + P2pClient loopback', () {
    test('hello() returns true for a KashCube server', () async {
      final ok = await client.hello();
      expect(ok, isTrue);
    });

    test('pull() returns rows from onPull callback', () async {
      final result = await client.pull(table: 'invoices', afterVersion: 0);
      expect(result, isNotNull);
      expect(result!['table'], 'invoices');
      final rows = result['rows'] as List;
      expect(rows, hasLength(1));
      expect(rows.first['sync_id'], 'row-1');
    });

    test('push() returns true on success', () async {
      final ok = await client.push(
        table: 'invoices',
        rows: [
          {'sync_id': 'row-x', 'updated_at': '2026-03-17T11:00:00.000Z'},
        ],
      );
      expect(ok, isTrue);
    });

    test('request with wrong shared secret is rejected (403/401)', () async {
      final badClient = P2pClient(
        baseUrl: 'http://127.0.0.1:${P2pServer.instance.port}',
        identityId: 'unknown-peer',
        sharedSecret: Uint8List.fromList(List.generate(32, (_) => 0xFF)),
      );
      // The server returns 403 for unknown peers — pull returns null.
      final result = await badClient.pull(table: 'invoices', afterVersion: 0);
      expect(result, isNull);
      badClient.dispose();
    });
  });
}
