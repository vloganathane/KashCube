import 'dart:async';
import 'dart:ui';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'firebase_options.dart';

import 'core/theme/kash_cube_theme.dart';
import 'data/repositories/settings_repository_impl.dart';
import 'data/services/action_center_background_service.dart';
import 'data/services/app_logger.dart';
import 'data/services/database_helper.dart';
import 'data/services/db_factory.dart';
import 'data/services/fiscal_year_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/pdf_cache_manager.dart';
import 'data/services/web/web_companion_service.dart';
import 'presentation/app_shell.dart';
import 'presentation/providers/app_user_provider.dart';
import 'presentation/providers/notification_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/providers/sync_auto_refresh_provider.dart';
import 'presentation/providers/terms_provider.dart';
import 'presentation/screens/auth/setup_wizard_screen.dart';
import 'presentation/screens/auth/terms_gate_screen.dart';
import 'presentation/screens/auth/user_selection_screen.dart';
import 'presentation/screens/settings/pin_lock_screen.dart';
import 'presentation/web/web_connect_screen.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Set the correct SQLite backend (WASM on web, native on Android).
      // Fast no-op on Android; only does real work on web.
      await initDatabaseFactory();

      // ── Synchronous handler setup (no I/O) ─────────────────────────────
      // These are cheap assignments — register them before the first frame so
      // any widget-build errors or platform errors are captured from day 0.

      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        originalDebugPrint(message, wrapWidth: wrapWidth);
        if (message == null || AppLogger.shouldSkipTerminalCapture()) return;
        unawaited(
          AppLogger.instance.recordTerminalLine(message, source: 'debug_print'),
        );
      };

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        AppLogger.instance.recordFlutterError(details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        AppLogger.instance.fatal(
          'Unhandled platform dispatcher error',
          category: 'platform',
          error: error,
          stackTrace: stack,
        );
        return true;
      };

      // ── Web Companion disabled for Play Store release ──────────────────────
      // See docs/WEB_COMPANION_REENABLE.md for re-enablement steps
      // Attach the web companion stream listener before the first screen so
      // no browser-connection events are missed.
      // if (!kIsWeb) WebCompanionService.instance.attach();

      // ── runApp() — get the Flutter canvas visible immediately ───────────
      //
      // All heavy async I/O (DB open, VACUUM, integrity check, Firebase init,
      // notification scheduling) runs AFTER this point.  Because Dart's async
      // model is cooperative, each `await` below yields back to the event loop
      // which lets Flutter schedule and render frames concurrently.  The user
      // sees the loading spinner in _LockGate instead of the system's black
      // NormalTheme window background.
      runApp(const ProviderScope(child: KashCubeApp()));

      // ── Heavy async init — runs after first frame is scheduled ──────────

      // Firebase Analytics — initialised first (fast, no DB) so the SDK is
      // ready before any user interaction can trigger an event.
      // Privacy-first: analytics is immediately disabled after init so that
      // no events fire until the DB consent check below confirms opt-in.
      final firebaseSupported =
          kIsWeb || defaultTargetPlatform == TargetPlatform.android;
      if (firebaseSupported) {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
          // Disable collection by default; re-enabled below if user consented.
          if (!kIsWeb) {
            await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
              false,
            );
          }
        } catch (e) {
          // Not fatal — analytics simply stays disabled until configured.
          AppLogger.instance.warning(
            'Firebase init skipped (not configured)',
            category: 'startup',
            eventName: 'firebase_init_skipped',
            error: e,
          );
        }
      }

      // Open the database and warm the logger.  This is the first DB I/O;
      // on a fresh install it runs _onCreate + VACUUM + integrity check which
      // can take 1–3 s on real hardware — running it here (after runApp) means
      // the splash/loading spinner is visible rather than a black screen.
      await AppLogger.instance.initialize();

      await AppLogger.instance.event(
        'app_start',
        category: 'startup',
        context: {'platform': kIsWeb ? 'web' : defaultTargetPlatform.name},
      );

      // Now that the DB is open, check the user's analytics consent and
      // restore the correct collection state.
      if (firebaseSupported && !kIsWeb) {
        try {
          final repo = SettingsRepositoryImpl();
          final consentVal = await repo.get(SettingsKeys.analyticsConsent);
          await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
            consentVal == 'true',
          );
        } catch (e) {
          // Non-fatal — analytics stays disabled.
          AppLogger.instance.warning(
            'Analytics consent restore failed',
            category: 'startup',
            eventName: 'analytics_consent_restore_failed',
            error: e,
          );
        }
      }

      // All remaining post-runApp initialisation is wrapped in a try/catch so
      // that a failure never leaves the app stuck after the canvas is visible.
      try {
        if (!kIsWeb) {
          // Initialise local notifications (100% on-device, no network calls).
          await NotificationService.instance.initialize();
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
      } catch (e, st) {
        AppLogger.instance.error(
          'Post-init error (non-fatal)',
          category: 'startup',
          eventName: 'startup_postinit_error',
          error: e,
          stackTrace: st,
        );
      }
    },
    (error, stack) {
      AppLogger.instance.fatal(
        'Unhandled zone error',
        category: 'zone',
        eventName: 'zone_error',
        error: error,
        stackTrace: stack,
      );
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(zone, line);
        if (AppLogger.shouldSkipTerminalCapture(zone)) return;
        unawaited(AppLogger.instance.recordTerminalLine(line, source: 'print'));
      },
    ),
  );
}

/// Root widget for Kash Cube.
class KashCubeApp extends ConsumerWidget {
  const KashCubeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep UI providers in sync with DB rows merged from P2P/WebSocket writes.
    ref.watch(syncAutoRefreshInstallerProvider);

    // Activate the scheduler so notifications stay in sync with upcoming items.
    // Skip on web — flutter_local_notifications and timezone db are mobile-only.
    if (!kIsWeb) ref.watch(notificationSchedulerProvider);

    // ── Web Companion disabled for Play Store release ──────────────────────
    // See docs/WEB_COMPANION_REENABLE.md for re-enablement steps
    // Start HTTP server at app init so /health & other endpoints are always available.
    // Server persists for the app lifetime, not tied to screen visibility.
    // if (!kIsWeb) ref.watch(httpServerInitProvider);

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
  DateTime? _lastPausedTime;
  AppLifecycleState? _lastState;

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
    if (state == AppLifecycleState.paused && !kIsWeb) {
      // Only track pause time if coming from resumed state (not inactive).
      // This filters out keyboard/dialog events which go: resumed → inactive → paused.
      // Real backgrounding goes: resumed → paused directly.
      if (_lastState == AppLifecycleState.resumed) {
        _lastPausedTime = DateTime.now();
      }
      // Checkpoint WAL before the app is backgrounded so Android Auto Backup
      // always captures a fully-consistent main DB file (not a partial WAL).
      DatabaseHelper.instance.withDatabase(
        (db) => db.rawQuery('PRAGMA wal_checkpoint(PASSIVE)'),
      );
      // Keep the CPU awake while a browser tab is connected to the LAN server.
      WebCompanionService.instance.onAppPaused();
    }
    if (state == AppLifecycleState.resumed && !kIsWeb) {
      // Release wake lock if browser is no longer connected.
      // Called unconditionally (independent of lock state).
      WebCompanionService.instance.onAppResumed();
    }
    if (state == AppLifecycleState.resumed && _checkedLock && !_isLocked) {
      // Only re-lock if the app was genuinely paused (not just inactive states)
      // and the pause duration was >= 2 seconds.
      if (_lastPausedTime != null) {
        final pauseDuration = DateTime.now().difference(_lastPausedTime!);

        if (pauseDuration.inSeconds >= 2) {
          // Evict stale/excess PDFs whenever the app comes back to foreground.
          // PdfCacheManager uses getTemporaryDirectory() — unavailable on web.
          if (!kIsWeb) PdfCacheManager.instance.evict();
          // Re-lock when app comes back from background
          _checkLock();
        }
        _lastPausedTime = null; // Reset after handling
      }
    }

    _lastState = state; // Track for next transition
  }

  Future<void> _checkLock() async {
    debugPrint('[LockGate] Checking lock state...');
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final lockEnabled = await settingsRepo
        .get(SettingsKeys.appLockEnabled)
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            debugPrint(
              '[LockGate] Timeout reading app lock setting; defaulting to unlocked',
            );
            return null;
          },
        );
    debugPrint('[LockGate] Lock enabled: $lockEnabled');

    if (mounted) {
      setState(() {
        _isLocked = lockEnabled == 'true';
        _checkedLock = true;
        _ownerChosen = false; // reset on re-lock
      });
      debugPrint(
        '[LockGate] State updated: isLocked=$_isLocked, checkedLock=$_checkedLock',
      );
    }

    // Try biometric first if enabled
    if (_isLocked) {
      debugPrint('[LockGate] Attempting biometric unlock...');
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
      final canAuth =
          await localAuth.canCheckBiometrics ||
          await localAuth.isDeviceSupported();

      if (!canAuth) return;

      final authenticated = await localAuth.authenticate(
        localizedReason: 'Unlock Kash Cube',
      );

      if (authenticated && mounted) {
        setState(() => _isLocked = false);
      }
    } catch (e) {
      // Biometric failed or cancelled — user can enter PIN manually
      AppLogger.instance.debug(
        'Biometric unlock attempt failed or cancelled',
        category: 'biometric_auth',
        error: e,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for switch-user requests from anywhere in the app.
    ref.listen<int>(switchUserProvider, (_, _) {
      ref.read(activeAppUserProvider.notifier).state = null;
      setState(() => _ownerChosen = false);
    });

    debugPrint('[LockGate] Build called: checkedLock=$_checkedLock');

    if (!_checkedLock) {
      // Splash / loading while we check lock state
      debugPrint('[LockGate] Showing loading spinner (checking lock)');
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // ── Web platform: bypass all lock/user gates — auth via session token ───
    if (kIsWeb) return const WebConnectScreen();

    // Kick off both reads together so setup status doesn't wait on terms.
    final termsState = ref.watch(termsAcceptedProvider);
    final wizardState = ref.watch(setupWizardDoneProvider);

    // ── Terms & Conditions gate ──────────────────────────────────────────────
    // Must be accepted before any other screen is shown.
    debugPrint('[LockGate] Watching termsAcceptedProvider...');
    debugPrint(
      '[LockGate] termsState: ${termsState.isLoading
          ? "loading"
          : termsState.hasValue
          ? termsState.value
          : termsState.hasError
          ? "error: ${termsState.error}"
          : "unknown"}',
    );
    if (termsState.isLoading) {
      debugPrint('[LockGate] Showing loading spinner (terms loading)');
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final termsAccepted = termsState.valueOrNull ?? false;
    if (!termsAccepted) {
      debugPrint('[LockGate] Showing TermsGateScreen');
      return TermsGateScreen(
        onAccepted: () => ref.invalidate(termsAcceptedProvider),
      );
    }

    // ── First-run setup wizard ───────────────────────────────────────────────
    debugPrint('[LockGate] Watching setupWizardDoneProvider...');
    debugPrint(
      '[LockGate] wizardState: ${wizardState.isLoading
          ? "loading"
          : wizardState.hasValue
          ? wizardState.value
          : wizardState.hasError
          ? "error: ${wizardState.error}"
          : "unknown"}',
    );
    if (wizardState.isLoading) {
      debugPrint('[LockGate] Showing loading spinner (wizard loading)');
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!(wizardState.valueOrNull ?? false)) {
      debugPrint('[LockGate] Showing SetupWizardScreen');
      return SetupWizardScreen(
        onComplete: () => ref.invalidate(setupWizardDoneProvider),
      );
    }

    if (_isLocked) {
      debugPrint('[LockGate] Showing PinLockScreen');
      return PinLockScreen(
        mode: PinScreenMode.unlock,
        onSuccess: () {
          setState(() => _isLocked = false);
        },
      );
    }

    // After owner unlocks, check whether any staff users have been added.
    // If there are staff users, show the selection screen so either the owner
    // or a staff member can choose who is operating the device.
    // If no staff users exist, go straight to AppShell (owner flow).
    final activeUser = ref.watch(activeAppUserProvider);
    final hasUsers = ref.watch(hasAnyAppUserProvider);
    return hasUsers.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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
