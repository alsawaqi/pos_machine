import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/order_sync_payload.dart' show uuidV4;
import '../services/session_service.dart';
import '../services/shift_service.dart';

/// Shown after staff login when the device has no open cash-drawer shift. The
/// cashier counts the opening float and opens the shift; on success the gate
/// flips into the POS. A shift is per-device, so once open the next cashier
/// inherits it (no re-prompt).
class ShiftOpenScreen extends ConsumerStatefulWidget {
  const ShiftOpenScreen({super.key});

  @override
  ConsumerState<ShiftOpenScreen> createState() => _ShiftOpenScreenState();
}

class _ShiftOpenScreenState extends ConsumerState<ShiftOpenScreen> {
  int _openingBaisas = 0;
  bool _busy = false;
  String? _error;

  String get _formatted => (_openingBaisas / 1000).toStringAsFixed(3);

  void _tap(String digit) {
    if (_busy) return;
    // Build the amount in baisas (3-dp currency): each digit shifts left.
    final next = _openingBaisas * 10 + int.parse(digit);
    if (next > 9999999999) return; // sane cap
    setState(() {
      _openingBaisas = next;
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _openingBaisas == 0) return;
    setState(() => _openingBaisas ~/= 10);
  }

  Future<void> _open() async {
    final staff = ref.read(sessionControllerProvider).staff;
    if (staff == null) {
      setState(() => _error = 'No staff session. Please log in again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final shift = OpenShiftData(
        uuid: uuidV4(),
        openingCashBaisas: _openingBaisas,
        openedAt: DateTime.now(),
        staffId: staff.id,
      );
      await ref.read(shiftServiceProvider).open(
            shiftUuid: shift.uuid,
            openingCashBaisas: shift.openingCashBaisas,
            staffId: shift.staffId,
          );
      await ref.read(sessionControllerProvider.notifier).markShiftOpen(shift);
      // Gate rebuilds into the POS.
    } on ShiftException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open the shift. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffName = ref.watch(sessionControllerProvider).staff?.name ?? '';
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
                const Text(
                  'Open shift',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  staffName.isEmpty
                      ? 'Count the opening cash float.'
                      : 'Welcome $staffName. Count the opening cash float.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16313B),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Opening cash (OMR)',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatted,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 14),
                  ),
                ],
                const SizedBox(height: 20),
                _keypad(),
                const SizedBox(height: 20),
                SizedBox(
                  width: 260,
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy ? null : _open,
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Open shift'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => ref
                          .read(sessionControllerProvider.notifier)
                          .logoutStaff(),
                  child: const Text(
                    'Log out',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _keypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', '<'];
    return SizedBox(
      width: 300,
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        physics: const NeverScrollableScrollPhysics(),
        children: keys.map((k) {
          return Material(
            color: const Color(0xFF1B3540),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (k == '<') {
                  _backspace();
                } else if (k == '00') {
                  _tap('0');
                  _tap('0');
                } else {
                  _tap(k);
                }
              },
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
    );
  }
}
