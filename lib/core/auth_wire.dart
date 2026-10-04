/// LAUNCH-P5 C3 — the authorization wire version. Every event a P5 build
/// creates carries `auth_v: 1` at the top level of its payload; an event
/// without it comes from an older build and the server keeps its legacy
/// behaviour for it.
///
/// Stamped when the event is created or first made durable (the outbox
/// insert), never at push time: an event an older build queued must stay
/// "legacy" when this build sends it.
const authWireVersion = 1;

/// LAUNCH-P5 fix order 1 (F1) — the signed staff token of the person who
/// is logged in on this till (the login reply's `staff_token`).
///
/// [SessionService] sets it when a login is saved or a session is restored
/// and clears it at logout. Event builders read it to stamp the maker's
/// token into each P5 event (so a queued event keeps its maker's token
/// after the next person logs in), and the API client sends it as the
/// `X-Staff-Token` header. The token is opaque: it is never decoded,
/// printed or logged.
abstract final class StaffTokenHolder {
  static String? _token;
  static int? _staffId;

  /// The logged-in person's token, or null (nobody, or an older server).
  static String? get token => _token;

  /// The staff id the token belongs to.
  static int? get staffId => _staffId;

  static void set(int? staffId, String? token) {
    final clean = token?.trim();
    if (clean == null || clean.isEmpty) {
      clear();
      return;
    }
    _token = clean;
    _staffId = staffId;
  }

  static void clear() {
    _token = null;
    _staffId = null;
  }
}

/// The P5 wire stamp of an event payload: `auth_v` and, when known, the
/// maker's `staff_token`.
///
/// [staffToken] names the maker's token explicitly (a clock in or out from
/// the PIN screen, where nobody is logged in). Otherwise the logged-in
/// person's token is used, unless [staffId] names somebody else (an event
/// attributed to another person never carries this person's token).
Map<String, Object> authStamp({int? staffId, String? staffToken}) {
  String? token = staffToken?.trim();
  if (token == null || token.isEmpty) {
    token = StaffTokenHolder.token;
    final owner = StaffTokenHolder.staffId;
    if (staffId != null && owner != null && staffId != owner) token = null;
  }
  return {
    'auth_v': authWireVersion,
    if (token != null && token.isNotEmpty) 'staff_token': token,
  };
}

/// [event] with `payload.auth_v` (and the maker's `staff_token`) set (a
/// copy; the input is not changed). A payload that already carries
/// `auth_v` is left as it is.
Map<String, dynamic> withAuthV(Map<String, dynamic> event) {
  final payload = event['payload'];
  if (payload is! Map || payload.containsKey('auth_v')) return event;
  final staffId = payload['staff_id'];
  return {
    ...event,
    'payload': <String, dynamic>{
      ...payload.cast<String, dynamic>(),
      ...authStamp(staffId: staffId is int ? staffId : null),
    },
  };
}
