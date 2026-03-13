import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'core/theme/kash_cube_theme.dart';
import 'data/services/action_center_background_service.dart';
import 'data/services/db_factory.dart';
import 'data/services/fiscal_year_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/pdf_cache_manager.dart';
import 'presentation/app_shell.dart';
import 'presentation/providers/app_user_provider.dart';
import 'presentation/providers/iap_provider.dart';
import 'presentation/providers/identity_provider.dart';
import 'presentation/providers/notification_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/providers/sync_provider.dart';
import 'presentation/screens/auth/user_selection_screen.dart';
import 'presentation/screens/onboarding/identity_setup_screen.dart';
import 'presentation/screens/settings/pin_lock_screen.dart';
import 'presentation/screens/web_connect/web_connect_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set the correct SQLite backend (WASM on web, native on Android).
  await initDatabaseFactory();

  if (!kIsWeb) {
    // Initialise local notifications before the first frame.
    // 100% on-device — no network calls.
    await NotificationService.instance.initialize();
    await NotificationService.instance.requestPermission();
  }

  // Ensure current_fy_start is in sync with today's FY.
  // This also triggers isResetDue() to return true if the FY has flipped
  // since the last launch, so invoice numbers reset correctly.
  await FiscalYearService.instance.ensureCurrentFYStart();

  if (!kIsWeb) {
    // Show year-end notifications if the FY is within 7 days of ending
    // or if the old FY was never closed after the new year started.
    await NotificationService.instance.checkAndShowYearEndAlerts();

    // Backup reminder if no encrypted backup in 30 days (or ever).
    await NotificationService.instance.checkAndShowBackupReminder();

    // Register daily Action Center background task (fires ~9 AM via WorkManager).
    // Non-fatal if WorkManager is unavailable on this device.
    await registerActionCenterDailyTask();

    // Register daily low-stock inventory alert task.
    await registerLowStockDailyTask();

    // Re-register auto-backup task if the user had it enabled.
    // WorkManager tasks can be cleared by OS updates; this restores the schedule.
    await maybeRestoreAutoBackupTask();
  }

  runApp(const ProviderScope(child: KashCubeApp()));
}

/// Root widget for Kash Cube.
class KashCubeApp extends ConsumerWidget {
  const KashCubeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activate the scheduler so notifications stay in sync with upcoming items.
    ref.watch(notificationSchedulerProvider);
    // Initialise Play Billing so the subscription listener is live from startup.
    ref.watch(iapServiceProvider);

    return MaterialApp(
      title: 'Kash Cube',
      debugShowCheckedModeBanner: false,
      theme: KashCubeTheme.light,
      darkTheme: KashCubeTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      home: const _LockGate(),
    );
  }
}

/// Checks if app lock is enabled and shows PIN screen before the main app.
class _LockGate extends ConsumerStatefulWidget {
  const _LockGate();

  @override
  ConsumerState<_LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<_LockGate>
    with WidgetsBindingObserver {
  bool _isLocked = true;
  bool _checkedLock = false;
  bool _ownerChosen = false; // set when owner tile is tapped

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _checkedLock && !_isLocked) {
      // Evict stale/excess PDFs whenever the app comes back to foreground.
      PdfCacheManager.instance.evict();
      // Re-lock when app comes back from background
      _checkLock();
    }
  }

  Future<void> _checkLock() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final lockEnabled = await settingsRepo.get(SettingsKeys.appLockEnabled);

    if (mounted) {
      setState(() {
        _isLocked = lockEnabled == 'true';
        _checkedLock = true;
        _ownerChosen = false; // reset on re-lock
      });
    }

    // Try biometric first if enabled
    if (_isLocked) {
      await _attemptBiometric();
    }
  }

  Future<void> _attemptBiometric() async {
    if (kIsWeb) return; // web auth = session token; no biometric

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final bioEnabled = await settingsRepo.get(SettingsKeys.biometricEnabled);

    if (bioEnabled != 'true') return;

    try {
      final localAuth = LocalAuthentication();
      final canAuth = await localAuth.canCheckBiometrics ||
          await localAuth.isDeviceSupported();

      if (!canAuth) return;

      final authenticated = await localAuth.authenticate(
        localizedReason: 'Unlock Kash Cube',
      );

      if (authenticated && mounted) {
        setState(() => _isLocked = false);
      }
    } catch (_) {
      // Biometric failed or cancelled — user can enter PIN manually
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Web entry point ───────────────────────────────────────────────────
    // On web there is no lock screen, no on-device identity, and no mDNS.
    // Instead we gate on whether the browser has an active paired session.
    if (kIsWeb) {
      final sessionAsync = ref.watch(activeDeviceSessionProvider);
      return sessionAsync.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, __) => WebConnectScreen(
          onConnected: () => ref.invalidate(activeDeviceSessionProvider),
        ),
        data: (session) => session == null
            ? WebConnectScreen(
                onConnected: () => ref.invalidate(activeDeviceSessionProvider),
              )
            : const AppShell(),
      );
    }

    // Listen for switch-user requests from anywhere in the app.
    ref.listen<int>(switchUserProvider, (_, __) {
      ref.read(activeAppUserProvider.notifier).state = null;
      setState(() => _ownerChosen = false);
    });

    if (!_checkedLock) {
      // Splash / loading while we check lock state
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isLocked) {
      return PinLockScreen(
        mode: PinScreenMode.unlock,
        onSuccess: () {
          setState(() => _isLocked = false);
        },
      );
    }

    // After owner unlocks, check whether identity has been set up.
    // Fresh installs need to enter a display name first.
    final hasIdentity = ref.watch(hasIdentityProvider);
    if (hasIdentity.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final identityReady = hasIdentity.valueOrNull ?? false;
    if (!identityReady) {
      return IdentitySetupScreen(
        onComplete: () => ref.invalidate(hasIdentityProvider),
      );
    }

    // After owner unlocks, check whether any staff users have been added.
    // If there are staff users, show the selection screen so either the owner
    // or a staff member can choose who is operating the device.
    // If no staff users exist, go straight to AppShell (owner flow).
    final activeUser = ref.watch(activeAppUserProvider);
    final hasUsers = ref.watch(hasAnyAppUserProvider);
    return hasUsers.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => const AppShell(),
      data: (has) {
        // No staff, owner tapped, or staff already authenticated → go straight in.
        if (!has || _ownerChosen || activeUser != null) return const AppShell();
        return UserSelectionScreen(
          onOwnerSelected: () => setState(() => _ownerChosen = true),
        );
      },
    );
  }
}

/// Creates a [LocalAuthentication] instance.

