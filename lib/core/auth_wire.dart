/// LAUNCH-P5 C3 — the authorization wire version. Every event a P5 build
/// creates carries `auth_v: 1` at the top level of its payload; an event
/// without it comes from an older build and the server keeps its legacy
/// behaviour for it.
///
/// Stamped when the event is created or first made durable (the outbox
/// insert), never at push time: an event an older build queued must stay
/// "legacy" when this build sends it.
const authWireVersion = 1;

/// [event] with `payload.auth_v` set (a copy; the input is not changed).
Map<String, dynamic> withAuthV(Map<String, dynamic> event) {
  final payload = event['payload'];
  if (payload is! Map || payload.containsKey('auth_v')) return event;
  return {
    ...event,
    'payload': <String, dynamic>{
      ...payload.cast<String, dynamic>(),
      'auth_v': authWireVersion,
    },
  };
}
