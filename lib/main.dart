import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/providers.dart';
import 'services/session_service.dart';
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

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionServiceProvider.overrideWithValue(session),
      ],
      child: const StaffApp(),
    ),
  );
}

@pragma('vm:entry-point')
Future<void> secondaryDisplayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  developer.log(
    'Launching customer display entrypoint.',
    name: 'POSBootstrap',
  );
  runApp(const CustomerDisplayApp());
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

class StaffApp extends StatelessWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const _FullscreenShell(child: StaffStartupGate()),
    );
  }
}

class CustomerDisplayApp extends StatelessWidget {
  const CustomerDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
