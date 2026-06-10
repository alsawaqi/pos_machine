import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../services/pos_api_service.dart';

/// Staff PIN login. On success it fetches + caches the branch config (first
/// login needs network) and then completes the session, which flips the gate
/// into the POS.
class StaffPinLoginScreen extends ConsumerStatefulWidget {
  const StaffPinLoginScreen({super.key});

  @override
  ConsumerState<StaffPinLoginScreen> createState() => _StaffPinLoginScreenState();
}

class _StaffPinLoginScreenState extends ConsumerState<StaffPinLoginScreen> {
  static const int _minLen = 4;
  static const int _maxLen = 6;

  String _pin = '';
  bool _busy = false;
  String? _error;

  void _tap(String digit) {
    if (_busy || _pin.length >= _maxLen) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    // Captured before the first await so the catch blocks below never touch
    // the context across an async gap.
    final l10n = L10n.of(context);
    if (_pin.length < _minLen) {
      setState(() => _error = l10n.pinLoginPinLengthError(_minLen, _maxLen));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Geofence at sign-in (blueprint §9.4): if this device's branch has a
      // fence, capture the live GPS and send it with the PIN — the server
      // rejects the login when the device is outside the branch area
      // (fail-closed). An unfenced branch needs no location.
      final branch = await ref.read(configRepositoryProvider).getBranch();
      final fenced = branch?.latitude != null && branch?.longitude != null;
      ({double? lat, double? lng}) gps = (lat: null, lng: null);
      if (fenced) {
        gps = await _currentGps();
      }

      final staff = await ref.read(apiServiceProvider).staffLogin(
            pin: _pin,
            lat: gps.lat,
            lng: gps.lng,
          );
      // First login needs the network: pull the branch config before completing.
      await ref.read(configRepositoryProvider).fetchAndCache();
      await ref.read(sessionControllerProvider.notifier).saveStaff(staff);
      // Gate rebuilds into the POS (behind the geofence gate).
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _pin = '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = l10n.pinLoginFailedError;
          _pin = '';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Best-effort current GPS for the login-time geofence check. Returns nulls
  /// if location is off / denied / times out; the server then fail-closes for a
  /// fenced branch, prompting the operator to enable location and retry.
  Future<({double? lat, double? lng})> _currentGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return (lat: null, lng: null);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (lat: null, lng: null);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return (lat: null, lng: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF102028),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.pinLoginTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.pinLoginSubtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 24),
                _dots(),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 14),
                  ),
                ],
                const SizedBox(height: 24),
                _keypad(),
                const SizedBox(height: 20),
                SizedBox(
                  width: 240,
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.pinLoginButton),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_maxLen, (i) {
        final filled = i < _pin.length;
        return Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? Colors.white : Colors.white24,
          ),
        );
      }),
    );
  }

  Widget _keypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];
    // Numeric keypads keep the 1-2-3 order in every locale: pin the grid to
    // LTR so it does not mirror when the app runs RTL (Arabic).
    return SizedBox(
      width: 300,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          physics: const NeverScrollableScrollPhysics(),
          children: keys.map((k) {
            if (k.isEmpty) return const SizedBox.shrink();
            return Material(
              color: const Color(0xFF1B3540),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => k == '<' ? _backspace() : _tap(k),
                child: Center(
                  child: k == '<'
                      ? const Icon(Icons.backspace_outlined, color: Colors.white70)
                      : Text(
                          k,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
