import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../services/pos_api_service.dart';
import 'qr_scanner_screen.dart';
import 'settings_screen.dart';

/// Layer 1 (one-time, admin): scan OR type the single activation code generated
/// in the admin portal for this device. The app activates → stores the device
/// token + kiosk ID + terminal ID (for the Soft POS) → and moves on to the staff
/// PIN. Done once by the admin/installer before the machine is handed over.
class DeviceSetupScreen extends ConsumerStatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  ConsumerState<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends ConsumerState<DeviceSetupScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final l10n = L10n.of(context);
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = l10n.deviceSetupErrorEnterCode);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiServiceProvider).activateDevice(code: code);
      await ref.read(sessionControllerProvider.notifier).saveActivation(result);
      // Layer 1 immediately pulls this device's branch config from the API —
      // including the branch latitude / longitude / geofence radius the admin
      // set for the assigned branch — so the fence is cached and ready to be
      // compared against live GPS, straight after entering the code. Offline or
      // transient failures are retried by the PIN login + the geofence gate.
      try {
        await ref.read(configRepositoryProvider).fetchAndCache();
      } catch (_) {}
      // The startup gate rebuilds into the staff PIN login automatically.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.deviceSetupErrorFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final l10n = L10n.of(context);
    // Ask for camera access up front so we don't open a black scanner screen
    // if it's denied.
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _error = status.isPermanentlyDenied
          ? l10n.deviceSetupErrorCameraBlocked
          : l10n.deviceSetupErrorCameraPermission);
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
      return;
    }

    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    _codeController.text = code.trim();
    await _activate();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF102028),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white54),
            tooltip: l10n.deviceSetupSettingsTooltip,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.point_of_sale, size: 64, color: Colors.white70),
                const SizedBox(height: 16),
                Text(
                  l10n.deviceSetupTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.deviceSetupSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(l10n.deviceSetupScanQrButton),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Divider(color: Colors.white24)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        l10n.deviceSetupOrEnterManually,
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
                    const Expanded(child: Divider(color: Colors.white24)),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _codeController,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) => _busy ? null : _activate(),
                  decoration: InputDecoration(
                    labelText: l10n.deviceSetupActivationCodeLabel,
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: const Color(0xFF1B3540),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 14),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _activate,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.commonContinue),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
