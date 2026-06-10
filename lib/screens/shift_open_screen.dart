import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
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
  bool _checking = true; // probing the server for an existing open shift

  String get _formatted => (_openingBaisas / 1000).toStringAsFixed(3);

  @override
  void initState() {
    super.initState();
    _probeExistingShift();
  }

  /// On entry, ask the server whether this device already has an open shift —
  /// the local record can be lost on re-pair / cleared storage / a second
  /// device at the branch. If so, ADOPT it (the gate then flips into the POS).
  /// Offline or none → fall through to the manual open keypad.
  Future<void> _probeExistingShift() async {
    final adopted = await _adoptExistingShift(silent: true);
    if (!adopted && mounted) setState(() => _checking = false);
  }

  /// Fetch the server's current open shift and adopt it locally. Returns true if
  /// adopted (the gate rebuilds into the POS and this screen is disposed). When
  /// not [silent], a failure surfaces a help message.
  Future<bool> _adoptExistingShift({bool silent = false}) async {
    try {
      final existing = await ref.read(apiServiceProvider).fetchCurrentShift();
      if (existing != null) {
        await ref.read(sessionControllerProvider.notifier).markShiftOpen(existing);
        return true;
      }
    } catch (_) {
      // offline / transient — fall through.
    }
    if (!silent && mounted) {
      // Safe: inside the file's mounted guard. (L10n cannot be captured before
      // the await here — this method also runs from initState via
      // _probeExistingShift, where inherited lookups are not allowed.)
      setState(() => _error = L10n.of(context).shiftOpenErrorAdoptFailed);
    }
    return false;
  }

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
    // Captured before the first await: needed again in the catch branch below.
    final l10n = L10n.of(context);
    final staff = ref.read(sessionControllerProvider).staff;
    if (staff == null) {
      setState(() => _error = l10n.shiftOpenErrorNoStaffSession);
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
      // Desync: the server already has an open shift for this device — adopt it
      // instead of dead-ending the cashier on this screen.
      if (e.message.toLowerCase().contains('already has an open shift')) {
        if (await _adoptExistingShift()) return;
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.shiftOpenErrorOpenFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    if (_checking) {
      return Scaffold(
        backgroundColor: const Color(0xFF102028),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                l10n.shiftOpenCheckingExisting,
                style: const TextStyle(color: Colors.white60, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
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
                Text(
                  l10n.shiftOpenTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  staffName.isEmpty
                      ? l10n.shiftOpenSubtitle
                      : l10n.shiftOpenWelcomeSubtitle(staffName),
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
                      Text(
                        l10n.shiftOpenOpeningCashLabel,
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
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
                        : Text(l10n.shiftOpenSubmitButton),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => ref
                          .read(sessionControllerProvider.notifier)
                          .logoutStaff(),
                  child: Text(
                    l10n.commonLogout,
                    style: const TextStyle(color: Colors.white54),
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
