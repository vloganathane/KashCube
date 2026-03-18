import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/extensions/context_extensions.dart';
import '../../data/services/identity_service.dart';
import '../../data/services/p2p/p2p_auth_service.dart';
import '../../data/services/p2p/p2p_client.dart';
import '../../data/services/p2p/p2p_coordinator.dart';
import '../../data/services/p2p/p2p_discovery_service.dart';
import '../providers/identity_provider.dart';
import '../providers/p2p_provider.dart';
import '../providers/settings_provider.dart';
import 'pairing_state.dart';

// ── QR payload helpers ─────────────────────────────────────────────────────

/// Builds the URI string embedded in the pairing QR code.
///
/// Format:  `kashcube://<ip>:<port>?id=<uuid>&pk=<base64>&name=<display>`
///
/// Example:
///   kashcube://192.168.1.5:54321?id=67b5f0fe-...&pk=VzRqWl...&name=Loganathane+V
///
/// If [ip]/[port] are unavailable (LAN Sync not yet started), falls back to
///   `kashcube://0.0.0.0:0?id=...`  — peer will skip direct back-pair and
/// wait for mDNS resolution instead.
String _buildQrPayload({
  required String identityId,
  required String publicKeyBase64,
  required String displayName,
  String? ip,
  int?    port,
}) {
  final uri = Uri(
    scheme: 'kashcube',
    host:   ip   ?? '0.0.0.0',
    port:   port ?? 0,
    queryParameters: {
      'id':   identityId,
      'pk':   publicKeyBase64,
      'name': displayName,
    },
  );
  return uri.toString();
}

/// Parses a QR string produced by [_buildQrPayload].
///
/// Accepts the current `kashcube://` URI scheme.
/// Returns null for any unrecognised QR code.
/// [ip] and [port] are null when the host is `0.0.0.0` / port is `0`
/// (LAN Sync was off when the QR was generated — mDNS fallback applies).
({String id, String pk, String name, String? ip, int? port})? _parseQrPayload(String raw) {
  try {
    final uri = Uri.parse(raw.trim());
    if (uri.scheme != 'kashcube') return null;
    final id   = uri.queryParameters['id'];
    final pk   = uri.queryParameters['pk'];
    final name = uri.queryParameters['name'] ?? 'Unknown Device';
    if (id == null || pk == null) return null;
    final ip   = (uri.host.isNotEmpty && uri.host != '0.0.0.0') ? uri.host : null;
    final port = (uri.port > 0) ? uri.port : null;
    return (id: id, pk: pk, name: name, ip: ip, port: port);
  } catch (_) {
    return null;
  }
}

// ── PairScreen ─────────────────────────────────────────────────────────────

/// Two-phase pairing screen:
///
///  **Phase 1 — Show Your QR** (default tab)
///    Displays this device's pairing QR code for the peer to scan.
///
///  **Phase 2 — Scan Peer's QR**
///    Opens the camera via [MobileScanner].  When a valid KashCube QR is
///    detected, the pairing progress overlay animates through:
///    `scanning → validating → saving → success` (or `error`).
///
/// After success, the screen auto-pops after a brief delay so the user
/// returns to [DevicesScreen] which will now show the new trusted peer.
class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key});

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen>
    with SingleTickerProviderStateMixin {
  // ── Tabs: 0 = show QR, 1 = scan QR ────────────────────────────────────
  late final TabController _tabs;
  final _scannerController = MobileScannerController();
  bool _scanHandled = false; // guard against duplicate detections

  // ── Pairing progress ───────────────────────────────────────────────────
  PairingState _pairingState = const PairingState(phase: PairingPhase.idle);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  // ── QR detection ─────────────────────────────────────────────────────

  void _onBarcode(BarcodeCapture capture) {
    if (_scanHandled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final parsed = _parseQrPayload(raw);
    if (parsed == null) return; // ignore non-KashCube QR
    _scanHandled = true;
    _scannerController.stop();
    _performPairing(parsed.id, parsed.pk, parsed.name,
        peerIp: parsed.ip, peerPort: parsed.port);
  }

  // ── Pairing flow ──────────────────────────────────────────────────────

  Future<void> _performPairing(
    String peerIdentityId,
    String peerPublicKeyBase64,
    String peerDisplayName, {
    String? peerIp,
    int?    peerPort,
  }) async {
    // Step 1 — Validate
    _setPhase(const PairingState(phase: PairingPhase.validating));

    try {
      await ref.read(identityInitProvider.future);
      final localPubKeyBytes  = base64.decode(IdentityService.instance.identityPublicKeyBase64);
      final remotePubKeyBytes = base64.decode(peerPublicKeyBase64);

      final sharedSecret = await P2pAuthService.instance.deriveSharedSecret(
        localPubKey:  Uint8List.fromList(localPubKeyBytes),
        remotePubKey: Uint8List.fromList(remotePubKeyBytes),
      );

      // Step 2 — Save
      _setPhase(PairingState(
        phase:    PairingPhase.saving,
        peerName: peerDisplayName,
      ));

      await P2pCoordinator.instance.pairWithPeer(
        peerIdentityId:  peerIdentityId,
        peerDisplayName: peerDisplayName,
        sharedSecret:    sharedSecret,
      );

      // Step 3 — If the QR contained a direct address, immediately notify
      // the peer so it stores us as trusted (back-pair over direct IP).
      // This works even when mDNS discovery hasn't resolved the peer yet.
      if (peerIp != null && peerPort != null) {
        final client = P2pClient(
          baseUrl:      'http://$peerIp:$peerPort',
          identityId:   IdentityService.instance.identityId,
          sharedSecret: sharedSecret,
        );
        try {
          // Read our own display name so the peer shows it correctly.
          final myName = await ref.read(settingsRepositoryProvider)
              .get(SettingsKeys.ownerName);
          await client.pair(
            myIdentityId:      IdentityService.instance.identityId,
            myPublicKeyBase64: IdentityService.instance.identityPublicKeyBase64,
            myDisplayName: (myName == null || myName.trim().isEmpty)
                ? 'KashCube'
                : myName.trim(),
          );
        } catch (_) {
          // Non-fatal — back-pair will retry when mDNS resolves the peer.
        } finally {
          client.dispose();
        }
      }

      // Step 4 — Success
      _setPhase(PairingState(
        phase:    PairingPhase.success,
        peerName: peerDisplayName,
      ));

      // Auto-pop after a short celebration pause.
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) {
        // Refresh the paired devices list on the Devices screen.
        ref.invalidate(trustedPeersProvider);
        Navigator.pop(context);
      }
    } catch (e) {
      _setPhase(PairingState(
        phase:        PairingPhase.error,
        errorMessage: 'Pairing failed. Please try again.',
      ));
    }
  }

  void _setPhase(PairingState s) {
    if (!mounted) return;
    setState(() => _pairingState = s);
  }

  void _retryPairing() {
    _scanHandled = false;
    _scannerController.start();
    setState(() => _pairingState = const PairingState(phase: PairingPhase.idle));
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final identityAsync = ref.watch(identityInitProvider);
    final settingsRepo  = ref.read(settingsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair a Device'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code), text: 'Your QR'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan Peer'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            children: [
              // ── Tab 0: Show own QR ─────────────────────────────────────
              identityAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:   (e, _) => Center(child: Text('$e')),
                data:    (_) => _YourQrTab(
                  identity:    IdentityService.instance,
                  settingsRepo: settingsRepo,
                ),
              ),

              // ── Tab 1: Scan peer QR ────────────────────────────────────
              _ScanTab(
                controller: _scannerController,
                onBarcode:  _onBarcode,
              ),
            ],
          ),

          // ── Pairing progress overlay ───────────────────────────────────
          if (_pairingState.phase != PairingPhase.idle)
            _PairingProgressOverlay(
              state:   _pairingState,
              onRetry: _retryPairing,
            ),
        ],
      ),
    );
  }
}

// ── YourQrTab ──────────────────────────────────────────────────────────────

class _YourQrTab extends StatefulWidget {
  const _YourQrTab({
    required this.identity,
    required this.settingsRepo,
  });

  final dynamic identity;          // IdentityService
  final dynamic settingsRepo;      // SettingsRepository

  @override
  State<_YourQrTab> createState() => _YourQrTabState();
}

class _YourQrTabState extends State<_YourQrTab> {
  String? _qrPayload;

  @override
  void initState() {
    super.initState();
    _buildPayload();
  }

  Future<void> _buildPayload() async {
    final name = await (widget.settingsRepo.get(SettingsKeys.ownerName) as Future<String?>);
    final ip   = await P2pDiscoveryService.getLocalIp();
    final port = P2pCoordinator.instance.serverPort;
    if (!mounted) return;
    setState(() {
      _qrPayload = _buildQrPayload(
        identityId:      widget.identity.identityId as String,
        publicKeyBase64: widget.identity.identityPublicKeyBase64 as String,
        displayName:     (name == null || name.trim().isEmpty)
            ? 'KashCube'
            : name.trim(),
        ip:   ip,
        port: port,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final payload = _qrPayload;
    if (payload == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.base),
          Text(
            'Show this QR code to the other device',
            style: context.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Both devices must scan each other\'s QR code to complete pairing.',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          LayoutBuilder(
            builder: (context, constraints) {
              final qrSize = (constraints.maxWidth - AppSpacing.base * 2)
                  .clamp(200.0, 320.0);
              return Container(
                decoration: BoxDecoration(
                  color:        Colors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.base),
                  boxShadow: [
                    BoxShadow(
                      color:      Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(AppSpacing.base),
                child: QrImageView(
                  data:                 payload,
                  version:              QrVersions.auto,
                  size:                 qrSize,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                  backgroundColor:      Colors.white,
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color:    context.colorScheme.primary,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color:           Colors.black87,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _QrUrlRow(url: payload),
          const SizedBox(height: AppSpacing.base),
          _InfoRow(
            icon:  Icons.privacy_tip_outlined,
            label: 'Data never leaves your local network',
          ),
          _InfoRow(
            icon:  Icons.lock_outline,
            label: 'Encrypted with Ed25519 + AES-256-GCM',
          ),
        ],
      ),
    );
  }
}

// ── ScanTab ────────────────────────────────────────────────────────────────

class _ScanTab extends StatelessWidget {
  const _ScanTab({required this.controller, required this.onBarcode});

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onBarcode;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          controller: controller,
          onDetect:   onBarcode,
        ),
        // Scan-guide overlay
        Center(
          child: Container(
            width:       240,
            height:      240,
            decoration: BoxDecoration(
              border: Border.all(
                color: context.colorScheme.primary,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(AppSpacing.base),
            ),
          ),
        ),
        Positioned(
          bottom: AppSpacing.xxl,
          left:   0,
          right:  0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical:   AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color:        Colors.black54,
                borderRadius: BorderRadius.circular(AppSpacing.xl),
              ),
              child: Text(
                'Point camera at the other device\'s QR code',
                style: context.textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── PairingProgressOverlay ─────────────────────────────────────────────────

/// Full-screen overlay shown while pairing is in progress.
///
/// States:
///  - [PairingPhase.validating] / [PairingPhase.saving] — spinner + label
///  - [PairingPhase.success]  — green check + peer name
///  - [PairingPhase.error]    — red icon + error message + Retry button
class _PairingProgressOverlay extends StatelessWidget {
  const _PairingProgressOverlay({
    required this.state,
    required this.onRetry,
  });

  final PairingState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(AppSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.xl),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: _OverlayContent(state: state, onRetry: onRetry),
          ),
        ),
      ),
    );
  }
}

class _OverlayContent extends StatelessWidget {
  const _OverlayContent({required this.state, required this.onRetry});

  final PairingState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (state.phase) {
      PairingPhase.validating => _SpinnerStep(
          label: 'Verifying peer…',
        ),
      PairingPhase.saving => _SpinnerStep(
          label: 'Saving ${state.peerName ?? 'device'}…',
        ),
      PairingPhase.success => _SuccessStep(
          peerName: state.peerName ?? 'Device',
        ),
      PairingPhase.error => _ErrorStep(
          message: state.errorMessage ?? 'Unknown error',
          onRetry: onRetry,
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _SpinnerStep extends StatelessWidget {
  const _SpinnerStep({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(label, style: context.textTheme.titleMedium),
      ],
    );
  }
}

class _SuccessStep extends StatelessWidget {
  const _SuccessStep({required this.peerName});

  final String peerName;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle,
          size:  64,
          color: context.kashColors.income,
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          'Paired!',
          style: context.textTheme.titleLarge?.copyWith(
            color: context.kashColors.income,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Now syncing with $peerName',
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ErrorStep extends StatelessWidget {
  const _ErrorStep({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline,
          size:  64,
          color: context.colorScheme.error,
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          'Pairing Failed',
          style: context.textTheme.titleMedium?.copyWith(
            color: context.colorScheme.error,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.tonal(
          onPressed: onRetry,
          child: const Text('Try Again'),
        ),
      ],
    );
  }
}

// ── QR URL row ────────────────────────────────────────────────────────────

/// Shows the raw QR payload URL with a copy button.
/// Helps verify QR data and acts as a manual fallback if scanning fails.
class _QrUrlRow extends StatefulWidget {
  const _QrUrlRow({required this.url});
  final String url;
  @override
  State<_QrUrlRow> createState() => _QrUrlRowState();
}

class _QrUrlRowState extends State<_QrUrlRow> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        context.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical:   AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.url,
              style: context.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color:      context.colorScheme.onSurfaceVariant,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            icon: Icon(
              _copied ? Icons.check : Icons.copy_outlined,
              size: 16,
              color: _copied
                  ? context.colorScheme.primary
                  : context.colorScheme.onSurfaceVariant,
            ),
            tooltip:  'Copy QR URL',
            onPressed: _copy,
            visualDensity: VisualDensity.compact,
            padding:       EdgeInsets.zero,
            constraints:   const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

// ── Small reusable info row ────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String   label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
