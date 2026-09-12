import 'package:flutter/foundation.dart';
import '../dine_in/dine_in_controller.dart';
import '../dine_in/dine_in_models.dart';
import '../qr_quick/qr_quick_models.dart';
import 'recovery_models.dart';
import 'recovery_store.dart';

abstract interface class DraftRecoveryGateway {
  Future<Map<String, dynamic>> preview(int tableId, Map<String, dynamic> query);
  Future<Map<String, dynamic>> confirm(
    int tableId,
    Map<String, dynamic> payload,
  );
}

class RecoveryController extends ChangeNotifier {
  RecoveryController({
    required this.store,
    required this.gateway,
    required this.dineIn,
    required this.tableId,
    required this.loadLocal,
    required this.checkIdle,
    required this.admit,
    required this.onRetired,
    this.staffId,
  });
  final RecoveryStore store;
  final DraftRecoveryGateway gateway;
  final DineInGateway dineIn;
  final int tableId;
  final int? staffId;
  final Future<RecoveryLocal> Function(int) loadLocal;
  final Future<void> Function() checkIdle;
  final Future<void> Function(Future<void> Function()) admit;
  final Future<void> Function(RecoveryLocal) onRetired;
  RecoveryLocal? local;
  RecoveryPreview? preview;
  RecoveryAttempt? attempt;
  String? error;
  bool busy = false, foreground = true, ready = false, disposed = false;
  bool initializationFailed = false;
  bool get unresolved => attempt != null && !attempt!.terminal;
  bool get canLeave => !busy && !unresolved && (initializationFailed || ready);
  void changed() {
    if (!disposed) notifyListeners();
  }

  void setForeground(bool value) {
    foreground = value;
    changed();
  }

  void _foreground() {
    if (!foreground || disposed) {
      throw StateError('Return to the recovery screen to continue.');
    }
  }

  Future<void> _idle() async {
    _foreground();
    await store.assertOwn(attempt?.id);
    await checkIdle();
    _foreground();
  }

  Future<void> start() async {
    if (busy) return;
    initializationFailed = false;
    busy = true;
    changed();
    try {
      attempt = await store.active();
      ready = true;
      await store.assertOwn(attempt?.id);
      if (attempt != null) {
        local = attempt!.local;
        preview = attempt!.preview;
      } else {
        await _idle();
        final candidate = await loadLocal(tableId);
        final response = RecoveryPreview(
          await gateway.preview(tableId, candidate.query),
        );
        candidate.delta(response);
        await store.verifyLocal(candidate);
        local = candidate;
        preview = response;
      }
    } catch (e) {
      // Navigation is not business admission. Allow a failed initial read to
      // return to settings/session restoration; durable mutation guards stay.
      initializationFailed = true;
      error = e.toString();
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> _reloadAfterFailure() async {
    try {
      final saved =
          await store.active() ??
          (attempt == null ? null : await store.read(attempt!.id));
      if (saved != null) attempt = saved;
    } catch (_) {
      ready = false;
    }
  }

  Future<void> confirm() async {
    if (busy ||
        !ready ||
        !foreground ||
        preview == null ||
        attempt?.terminal == true ||
        const {'delta_ready', 'delta_pending'}.contains(attempt?.state)) {
      return;
    }
    busy = true;
    error = null;
    changed();
    try {
      await _idle();
      if (attempt == null) {
        final current = await loadLocal(tableId);
        if (current.encoded != local!.encoded) {
          throw StateError('Local draft changed. Review it again.');
        }
        final next = RecoveryAttempt({
          'id': QrQuickRequest.newId(),
          'state': 'pending',
          'local': current.json,
          'preview': preview!.json,
          'delta': current.delta(preview!),
        });
        try {
          await admit(() async {
            _foreground();
            await store.create(next);
          });
        } finally {
          attempt = await store.active();
        }
        if (attempt?.encoded != next.encoded) {
          throw StateError('Another recovery is already saved.');
        }
      }
      var current = attempt!;
      if (current.state == 'pending') {
        _foreground();
        final response = await gateway.confirm(
          current.local.tableId,
          current.payload,
        );
        final data = response['data'], errors = response['errors'];
        if (data is Map &&
            data['status'] == 'processed' &&
            errors is List &&
            errors.isEmpty) {
          final ack = recoveryMap(data['result']);
          current.validateAck(ack);
          final next = current.change('confirmed', {'ack': ack});
          await store.replace(current, next);
          attempt = current = next;
        } else if (errors is List &&
            errors.isNotEmpty &&
            recoveryMap(errors.first)['code'] ==
                'draft_recovery_preview_stale' &&
            current.matchesRelease(response['draft_recovery_final_no_write'])) {
          final next = current.change('not_applied', {
            'release': response['draft_recovery_final_no_write'],
          });
          await store.replace(current, next);
          attempt = next;
          return;
        } else {
          throw StateError(
            'Recovery is not acknowledged. Retry this saved request; keep all original copies.',
          );
        }
      }
      await _idle();
      final latest = await loadLocal(current.local.tableId);
      if (latest.encoded != current.local.encoded) {
        throw StateError('The confirmed recovery copies changed. Keep them.');
      }
      attempt = await store.retire(current);
      await onRetired(current.local);
    } catch (e) {
      error = e.toString();
      await _reloadAfterFailure();
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> sendSavedAdditions() async {
    if (busy ||
        !ready ||
        !foreground ||
        !const {'delta_ready', 'delta_pending'}.contains(attempt?.state)) {
      return;
    }
    busy = true;
    error = null;
    changed();
    try {
      await _idle();
      var current = attempt!;
      final detail = await dineIn.detail(current.local.tableId);
      final ownSavedRound =
          current.state == 'delta_pending' &&
          detail.rounds.any(
            (r) =>
                r['client_request_id'] == current.request.id &&
                r['entered_by'] == 'staff',
          );
      if (detail.tableId != current.local.tableId ||
          detail.seatingUuid != current.preview.proof['table_session_uuid'] ||
          detail.billUuid != current.local.uuid ||
          !detail.qrBill ||
          detail.orphaned ||
          detail.coveredTableIds.length != 1 ||
          (detail.pendingReview && !ownSavedRound) ||
          !detail.canAppend) {
        throw StateError(
          'The saved additions still need this same open bill and seating. Keep the saved request.',
        );
      }
      _foreground();
      if (current.state == 'delta_ready') {
        final lines = current.delta.map((slice) {
          final local = recoveryLocalLine(recoveryMap(slice['original']));
          return QrQuickLine.fromJson(
            recoveryWire({
              ...local,
              'qty': slice['qty'],
              'addon_ids': recoveryMaps(
                local['addons'],
              ).map((a) => a['id']).toList(),
            }),
          );
        }).toList();
        final request = DineInRequest.create(detail, lines, staffId);
        final next = current.change('delta_pending', {
          'delta_request': {
            'table_id': request.tableId,
            'seating_uuid': request.seatingUuid,
            'bill_uuid': request.billUuid,
            'payload': request.payload,
          },
        });
        await store.replace(current, next);
        attempt = current = next;
      }
      _foreground();
      final ack = await dineIn.append(current.request);
      current.validateDeltaAck(ack);
      // Independently correlate the returned round to this immutable request.
      final after = await dineIn.detail(current.local.tableId);
      final round = after.rounds
          .where((r) => r['id'] == ack['round_id'])
          .firstOrNull;
      if (after.billUuid != current.local.uuid ||
          after.seatingUuid != current.request.seatingUuid ||
          round == null) {
        throw StateError(
          'The received round still needs exact confirmation. Retry the saved request.',
        );
      }
      current.validateDeltaRound(round, ack);
      final next = current.change('done', {
        'delta_ack': ack,
        'delta_round': round,
      });
      await store.replace(current, next);
      attempt = next;
      // Printing stays on the canonical screen's established retry-print path.
    } catch (e) {
      error = e.toString();
      await _reloadAfterFailure();
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
