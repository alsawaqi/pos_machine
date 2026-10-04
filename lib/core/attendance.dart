import '../data/order_sync_repository.dart';
import '../services/order_sync_payload.dart' show uuidV4;
import 'auth_wire.dart';

/// LAUNCH-P5 C6 — clock in / clock out.
///
/// `staff.clock_in` / `staff.clock_out` `{attendance_uuid, staff_id, at}`
/// go through the durable outbox (they work offline and are idempotent by
/// the attendance uuid on the server). A clock-out names the open
/// attendance's uuid when the device knows it; otherwise a fresh uuid, and
/// the server closes the person's one open attendance (or records a flagged
/// row when none is open).
Map<String, dynamic> buildClockEvent({
  required bool clockIn,
  required String attendanceUuid,
  required int staffId,
  required DateTime at,
  String Function()? newUuid,
}) {
  final ts = at.toUtc().toIso8601String();
  return {
    'client_event_id': (newUuid ?? uuidV4)(),
    'event_type': clockIn ? 'staff.clock_in' : 'staff.clock_out',
    'client_timestamp': ts,
    'payload': {
      'attendance_uuid': attendanceUuid,
      'staff_id': staffId,
      'at': ts,
      'auth_v': authWireVersion,
    },
  };
}

class AttendanceService {
  AttendanceService(this._outbox, {DateTime Function()? clock, this.newUuid})
    : _clock = clock ?? DateTime.now;

  final OrderSyncRepository _outbox;
  final DateTime Function() _clock;
  final String Function()? newUuid;

  /// Clock [staffId] in. Returns the new attendance uuid and time.
  Future<({String uuid, DateTime at})> clockIn(int staffId) async {
    final uuid = (newUuid ?? uuidV4)();
    final at = _clock();
    await _queue(
      'attendance:$uuid:in',
      buildClockEvent(
        clockIn: true,
        attendanceUuid: uuid,
        staffId: staffId,
        at: at,
        newUuid: newUuid,
      ),
      at,
    );
    return (uuid: uuid, at: at);
  }

  /// Clock [staffId] out of [attendanceUuid] (null = the open one, unknown
  /// to this device).
  Future<DateTime> clockOut(int staffId, {String? attendanceUuid}) async {
    final uuid = attendanceUuid ?? (newUuid ?? uuidV4)();
    final at = _clock();
    await _queue(
      'attendance:$uuid:out',
      buildClockEvent(
        clockIn: false,
        attendanceUuid: uuid,
        staffId: staffId,
        at: at,
        newUuid: newUuid,
      ),
      at,
    );
    return at;
  }

  /// Durable first (the outbox row is written before any network I/O); an
  /// offline send stays queued for the next flush.
  Future<void> _queue(String key, Map<String, dynamic> event, DateTime at) =>
      _outbox.enqueueEvent(key, event, createdAt: at);
}
