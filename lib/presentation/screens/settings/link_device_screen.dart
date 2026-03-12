import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/linked_device.dart';
import '../../providers/sync_provider.dart';

/// Shown on the PRIMARY device to let a secondary scan and pair.
///
/// On open → starts the TCP sync server + registers mDNS service.
/// Displays a QR code encoding the pairing payload.
/// The secondary scans this QR to discover IP:port and initiate pairing.
class LinkDeviceScreen extends ConsumerStatefulWidget {
  const LinkDeviceScreen({super.key});

  @override
  ConsumerState<LinkDeviceScreen> createState() => _LinkDeviceScreenState();
}

class _LinkDeviceScreenState extends ConsumerState<LinkDeviceScreen> {
  DevicePreset _preset = DevicePreset.ownerMirror;
  String? _localIp;

  @override
  void initState() {
    super.initState();
    _fetchLocalIp();
    // Start server immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(linkHostProvider.notifier).start();
    });
  }

  Future<void> _fetchLocalIp() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) {
          if (mounted) setState(() => _localIp = addr.address);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hostAsync = ref.watch(linkHostProvider);
    final cs        = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Link a Device')),
      body: hostAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: AppSpacing.md),
              Text('Starting sync server…'),
            ],
          ),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: cs.error, size: 48),
              const SizedBox(height: AppSpacing.md),
              Text('Failed to start server: $e', textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => ref.read(linkHostProvider.notifier).start(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (port) {
          final ip      = _localIp ?? '...';
          final qrData  = _buildQrPayload(ip, port);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Preset selector ─────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical:   AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.admin_panel_settings_outlined),
                        const SizedBox(width: AppSpacing.md),
                        const Text('Access level'),
                        const Spacer(),
                        DropdownButton<DevicePreset>(
                          value: _preset,
                          underline: const SizedBox(),
                          onChanged: (v) {
                            if (v != null) setState(() => _preset = v);
                          },
                          items: DevicePreset.values
                              .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p.label),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── QR ───────────────────────────────────────────────────
                Text(
                  'Show this QR to the other device',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  decoration: BoxDecoration(
                    color:        Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 260,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    eyeStyle: const QrEyeStyle(
                      eyeShape:  QrEyeShape.square,
                      color:     Color(0xFF000000),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color:           Color(0xFF000000),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── Status / IP info ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color:        cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_rounded, size: 18, color: cs.primary),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            '$ip : $port',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'RobotoMono',
                                ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: '$ip:$port'));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Copied!')),
                              );
                            },
                            padding:    EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Both devices must be on the same Wi-Fi network',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── Instruction list ─────────────────────────────────────
                _InstructionStep(
                  step: '1',
                  text: 'Open Kash Cube on the other device',
                ),
                _InstructionStep(
                  step: '2',
                  text: 'Go to Settings → Linked Devices',
                ),
                _InstructionStep(
                  step: '3',
                  text: 'Tap "Link Device" and scan this QR code',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _buildQrPayload(String ip, int port) {
    return jsonEncode({
      'type':              'kashcube_pair_v1',
      'ip':                ip,
      'port':              port,
      'preset':            _preset.dbValue,
    });
  }
}

// ---------------------------------------------------------------------------
// Instruction step widget
// ---------------------------------------------------------------------------

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({required this.step, required this.text});

  final String step;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: cs.primaryContainer,
            child: Text(
              step,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
