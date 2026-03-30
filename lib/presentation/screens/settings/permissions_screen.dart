import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/app_spacing.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  static const _localAuth = LocalAuthentication();
  static final bool _isAndroid =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _loading = true;
  PermissionStatus? _notifications;
  PermissionStatus? _sms;
  PermissionStatus? _camera;
  PermissionStatus? _contacts;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);

    final values = await Future.wait<dynamic>([
      Permission.notification.status,
      Permission.sms.status,
      Permission.camera.status,
      Permission.contacts.status,
      _localAuth.canCheckBiometrics,
    ]);

    if (!mounted) return;
    setState(() {
      _notifications = values[0] as PermissionStatus;
      _sms = values[1] as PermissionStatus;
      _camera = values[2] as PermissionStatus;
      _contacts = values[3] as PermissionStatus;
      _biometricAvailable = values[4] as bool;
      _loading = false;
    });
  }

  Future<void> _requestPermission(Permission permission) async {
    await permission.request();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions'),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                _PermissionTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Needed for reminders and due alerts',
                  status: _notifications!,
                  onRequest: () => _requestPermission(Permission.notification),
                  onOpenSettings: _isAndroid ? openAppSettings : null,
                ),
                _PermissionTile(
                  icon: Icons.sms_outlined,
                  title: 'SMS',
                  subtitle: 'Needed for auto-detecting financial SMS',
                  status: _sms!,
                  onRequest: () => _requestPermission(Permission.sms),
                  onOpenSettings: _isAndroid ? openAppSettings : null,
                ),
                _PermissionTile(
                  icon: Icons.camera_alt_outlined,
                  title: 'Camera',
                  subtitle: 'Needed for QR scan and bill capture',
                  status: _camera!,
                  onRequest: () => _requestPermission(Permission.camera),
                  onOpenSettings: _isAndroid ? openAppSettings : null,
                ),
                _PermissionTile(
                  icon: Icons.contacts_outlined,
                  title: 'Contacts',
                  subtitle: 'Needed for importing/saving contacts',
                  status: _contacts!,
                  onRequest: () => _requestPermission(Permission.contacts),
                  onOpenSettings: _isAndroid ? openAppSettings : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.fingerprint),
                    title: const Text('Biometric'),
                    subtitle: const Text('Device capability check'),
                    trailing: Text(
                      _biometricAvailable ? 'Available' : 'Unavailable',
                      style: TextStyle(
                        color: _biometricAvailable
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                Text(
                  'Tip: If a permission is permanently denied, open system app settings and enable it manually.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onRequest,
    this.onOpenSettings,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final PermissionStatus status;
  final VoidCallback onRequest;
  final Future<bool> Function()? onOpenSettings;

  bool get _isGranted => status.isGranted || status.isLimited;
  bool get _needsSettings => status.isPermanentlyDenied || status.isRestricted;

  String get _label {
    if (status.isGranted) return 'Granted';
    if (status.isDenied) return 'Denied';
    if (status.isPermanentlyDenied) return 'Permanently denied';
    if (status.isRestricted) return 'Restricted';
    if (status.isLimited) return 'Limited';
    if (status.isProvisional) return 'Provisional';
    return status.toString();
  }

  String get _actionLabel {
    if (_needsSettings && onOpenSettings != null) return 'Open settings';
    return 'Request';
  }

  VoidCallback get _action {
    if (_needsSettings && onOpenSettings != null) {
      return () {
        onOpenSettings!.call();
      };
    }
    return onRequest;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _label,
              style: TextStyle(
                color: _isGranted ? cs.primary : cs.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!_isGranted)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _action,
                    child: Text(_actionLabel),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
