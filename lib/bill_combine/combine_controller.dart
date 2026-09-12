import 'package:flutter/foundation.dart';
import '../qr_quick/qr_quick_models.dart';
import 'combine_models.dart';
import 'combine_store.dart';

abstract interface class CombineGateway {
  Future<Map<String, dynamic>> preview(int tableId, String sourceUuid);
  Future<Map<String, dynamic>> confirm(
    int tableId,
    Map<String, dynamic> payload,
  );
}

class CombineController extends ChangeNotifier {
  CombineController({
    required this.store,
    required this.gateway,
    required this.tableId,
    required this.loadLocal,
    required this.checkIdle,
  });
  final CombineStore store;
  final CombineGateway gateway;
  final int tableId;
  final Future<CombineLocal> Function(int tableId) loadLocal;
  final Future<void> Function() checkIdle;
  CombineLocal? local;
  CombinePreview? preview;
  CombineAttempt? attempt;
  String? error;
  bool busy = false, foreground = true, disposed = false, ready = false;
  bool get unresolved => attempt != null && !attempt!.terminal;
  bool get canLeave => ready && !busy && !unresolved;
  void changed() {
    if (!disposed) notifyListeners();
  }

  void setForeground(bool value) {
    foreground = value;
    changed();
  }

  Future<void> start() async {
    if (busy) return;
    busy = true;
    changed();
    try {
      attempt = await store.active();
      ready = true;
      if (attempt != null) {
        local = attempt!.local;
        preview = attempt!.preview;
      } else {
        await checkIdle();
        final candidate = await loadLocal(tableId);
        final remote = CombinePreview(
          await gateway.preview(tableId, candidate.uuid),
        );
        candidate.matches(remote);
        await store.verifyLocal(candidate);
        local = candidate;
        preview = remote;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> confirm(String pin) async {
    if (busy ||
        !foreground ||
        !ready ||
        preview == null ||
        attempt?.terminal == true) {
      return;
    }
    if (attempt?.state != 'confirmed' && !RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      error = 'Manager PIN must contain 4–8 digits.';
      changed();
      return;
    }
    busy = true;
    error = null;
    changed();
    try {
      await checkIdle();
      if (!foreground || disposed) {
        throw StateError('Return to the combine screen and retry.');
      }
      if (attempt == null) {
        final current = await loadLocal(tableId);
        if (current.encoded != local!.encoded) {
          throw StateError('Local bill changed. Review again.');
        }
        final next = CombineAttempt({
          'id': QrQuickRequest.newId(),
          'state': 'pending',
          'local': local!.json,
          'preview': preview!.json,
        });
        // Storage is authoritative even when a save completed but its caller
        // lost the response. Reload before permitting the route to close.
        try {
          await store.create(next);
        } finally {
          attempt = await store.active();
        }
        if (attempt?.encoded != next.encoded) {
          throw StateError('Another combine is pending.');
        }
      }
      var current = attempt!;
      if (current.state == 'pending') {
        if (!foreground || disposed) {
          throw StateError('Request saved; return to approve it.');
        }
        final response = await gateway.confirm(current.local.tableId, {
          ...current.payload,
          'pin': pin,
        });
        final data = response['data'];
        final errors = response['errors'];
        if (data is Map &&
            data['status'] == 'processed' &&
            errors is List &&
            errors.isEmpty) {
          final ack = combineMap(data['result']);
          current.validateAck(ack);
          final confirmed = current.withState('confirmed', ack: ack);
          await store.replace(current, confirmed);
          attempt = current = confirmed;
        } else if (errors is List &&
            errors.isNotEmpty &&
            combineMap(errors.first)['code'] == 'combine_preview_stale' &&
            current.matchesRelease(response['combine_final_no_write'])) {
          final released = current.withState('not_applied');
          await store.replace(current, released);
          attempt = released;
          return;
        } else {
          throw StateError(
            errors is List && errors.isNotEmpty
                ? combineMap(errors.first)['message']?.toString() ??
                      'Combine refused'
                : 'Unrecognized reply. Keep the original request and retry.',
          );
        }
      }
      await checkIdle();
      if (!foreground || disposed) {
        throw StateError('Combine confirmed; return to finish local recovery.');
      }
      final latest = await loadLocal(current.local.tableId);
      if (latest.encoded != current.local.encoded) {
        throw StateError(
          'Local copies changed. Keep the confirmed recovery copy.',
        );
      }
      await store.retire(current);
      attempt = current.withState('done');
    } catch (e) {
      error = e.toString();
      // A failed local transition may nevertheless have committed. Do not
      // forget a durable intent or run a second combine after an unknown save.
      try {
        final saved =
            await store.active() ??
            (attempt == null ? null : await store.read(attempt!.id));
        if (saved != null) attempt = saved;
      } catch (_) {
        ready = false;
      }
    } finally {
      busy = false;
      changed();
    }
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
