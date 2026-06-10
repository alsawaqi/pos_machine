import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/sentry.dart';
import 'l10n/l10n.dart';
import 'providers/providers.dart';
import 'services/session_service.dart';
import 'services/settings_service.dart';
import 'screens/staff_startup_gate.dart';
import 'screens/customer_display_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureKioskMode();
  developer.log('Launching staff display entrypoint.', name: 'POSBootstrap');

  final prefs = await SharedPreferences.getInstance();
  const secureStorage = FlutterSecureStorage();
  final session = SessionService(secureStorage, prefs);
  await session.load();

  final app = ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      sessionServiceProvider.overrideWithValue(session),
    ],
    child: const StaffApp(),
  );

  // Phase C5 (§9.12) — crash reporting. No DSN → run exactly as before.
  if (!SentryConfig.enabled) {
    runApp(app);
    return;
  }

  await SentryFlutter.init(
    (options) {
      options
        ..dsn = SentryConfig.dsn
        ..environment = SentryConfig.environment
        ..release = SentryConfig.release
        // PII discipline: customer phones/plates flow through this app and
        // the POS screen shows them — never auto-attach either.
        ..sendDefaultPii = false
        ..attachScreenshot = false
        ..tracesSampleRate = 0.1;
    },
    // The SDK installs FlutterError.onError + PlatformDispatcher.onError
    // around appRunner — uncaught Dart, JVM and NDK crashes all report.
    appRunner: () async {
      await Sentry.configureScope((scope) async {
        // Device identity (session is loaded pre-runApp). company_id matches
        // the tag AttachSentryContext sets on the Laravel side.
        await scope.setTag('device_code', session.kioskId ?? 'unpaired');
        await scope.setTag('company_id', '${session.companyId ?? ''}');
        await scope.setTag('branch_id', '${session.branchId ?? ''}');
        await scope.setTag('terminal_id', session.terminalId ?? '');
      });
      final staff = session.staff;
      if (staff != null) {
        await setSentryStaff(
          id: staff.id,
          name: staff.name,
          position: staff.position,
        );
      }
      runApp(app);
    },
  );
}

@pragma('vm:entry-point')
Future<void> secondaryDisplayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  developer.log(
    'Launching customer display entrypoint.',
    name: 'POSBootstrap',
  );
  // Phase C4 — this is a SEPARATE Flutter engine with no ProviderScope
  // overrides, so it reads the persisted language itself at startup (a live
  // switch reaches it the next time the rear display engine starts).
  Locale locale = const Locale('en');
  try {
    final prefs = await SharedPreferences.getInstance();
    locale = Locale(SettingsService(prefs).snapshot().language);
  } catch (_) {
    // keep English
  }
  // NO Sentry here: this entrypoint runs a SECOND Flutter engine in the same
  // Android process — initializing the SDK again would double-init the native
  // layer. The staff engine's native SDK still catches process-level crashes.
  runApp(CustomerDisplayApp(locale: locale));
}

Future<void> _configureKioskMode() async {
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
}

class StaffApp extends ConsumerWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phase C4 (§9.8) — the watched locale flips strings AND direction (the
    // global delegates wrap the app in the right Directionality for Arabic).
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: const _FullscreenShell(child: StaffStartupGate()),
    );
  }
}

class CustomerDisplayApp extends StatelessWidget {
  const CustomerDisplayApp({super.key, this.locale = const Locale('en')});

  /// Resolved from prefs in [secondaryDisplayMain] (separate engine — it
  /// cannot watch the staff engine's Riverpod state).
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: const _FullscreenShell(child: CustomerDisplayScreen()),
    );
  }
}

class _FullscreenShell extends StatefulWidget {
  final Widget child;

  const _FullscreenShell({required this.child});

  @override
  State<_FullscreenShell> createState() => _FullscreenShellState();
}

class _FullscreenShellState extends State<_FullscreenShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreFullscreen();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restoreFullscreen();
    }
  }

  Future<void> _restoreFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
