import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/pos_api_service.dart';

/// One-time device setup: the installer/admin enters the terminal ID assigned
/// to this device's branch. The app claims the device (→ device token) and
/// binds it to that branch. After this, staff only ever enter their PIN.
class DeviceSetupScreen extends ConsumerStatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  ConsumerState<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends ConsumerState<DeviceSetupScreen> {
  final _terminalController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(sessionServiceProvider).terminalId;
    if (existing != null && existing.isNotEmpty) {
      _terminalController.text = existing;
    }
  }

  @override
  void dispose() {
    _terminalController.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    final terminalId = _terminalController.text.trim();
    if (terminalId.isEmpty) {
      setState(() => _error = 'Enter the terminal ID assigned to this device.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(apiServiceProvider).claimDevice(terminalId: terminalId);
      await ref.read(sessionControllerProvider.notifier).saveClaim(result);
      // The startup gate rebuilds into the staff PIN login automatically.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Device setup failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF102028),
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
                const Text(
                  'Set up this device',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Enter the terminal ID the admin assigned to this device's branch. You only do this once.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _terminalController,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _busy ? null : _claim(),
                  decoration: InputDecoration(
                    labelText: 'Terminal ID',
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
                const SizedBox(height: 28),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _busy ? null : _claim,
                    child: _busy
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue'),
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
