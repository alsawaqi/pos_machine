/// Phase C3 — device-side Reverb subscription (blueprint §9.3 / §11.5).
///
/// Reverb speaks Pusher protocol 7, and the subset a POS terminal needs is
/// tiny, so this is a small hand-rolled client over dart:io WebSocket (no new
/// dependencies) rather than the native Pusher SDK wrapper. The device joins
/// its `private-branch.{id}` channel (auth = POST /broadcasting/auth with the
/// device Bearer token) and, on ANY domain event, the provider layer runs a
/// DEBOUNCED delta config sync — mandatory, because the dispatcher echoes the
/// device's own pushed events back to it.
///
/// The protocol helpers (url/frames/parsing) are pure and unit-tested;
/// [LiveSyncService] owns the socket lifecycle: connect → authorize →
/// subscribe, ping/pong keep-alive, exponential backoff + jitter reconnect,
/// offline gating from connectivity.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// The websocket endpoint served in /device/config meta.websocket.
class WebsocketEndpoint {
  const WebsocketEndpoint({
    required this.appKey,
    this.host,
    required this.port,
    required this.scheme,
  });

  final String appKey;

  /// Null/empty = "dial the host you already reach the API on" (dev LAN).
  final String? host;
  final int port;

  /// 'http' | 'https' — mapped to ws/wss.
  final String scheme;

  static WebsocketEndpoint? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final key = json['app_key']?.toString() ?? '';
    if (key.isEmpty) return null;
    return WebsocketEndpoint(
      appKey: key,
      host: json['host']?.toString(),
      port: (json['port'] as num?)?.toInt() ?? 8080,
      scheme: json['scheme']?.toString() ?? 'http',
    );
  }
}

/// ws(s)://host:port/app/{key}?protocol=7… — the Pusher handshake URL. The
/// endpoint's null host falls back to [apiBaseUrl]'s host (the LAN/proxy the
/// operator already configured).
String? buildWebsocketUrl(WebsocketEndpoint endpoint, {required String apiBaseUrl}) {
  var host = endpoint.host;
  if (host == null || host.isEmpty) {
    host = Uri.tryParse(apiBaseUrl)?.host;
  }
  if (host == null || host.isEmpty) return null;

  final wsScheme = endpoint.scheme == 'https' ? 'wss' : 'ws';
  return '$wsScheme://$host:${endpoint.port}/app/${endpoint.appKey}'
      '?protocol=7&client=pos_machine&version=1.0&flash=false';
}

/// The private channel a device listens on: its branch when assigned, else its
/// company (DeviceSyncBroadcast publishes branch-first with a company
/// fallback). Null = the device isn't activated enough to subscribe.
String? channelFor({int? branchId, int? companyId}) {
  if (branchId != null) return 'private-branch.$branchId';
  if (companyId != null) return 'private-company.$companyId';
  return null;
}

String buildSubscribeFrame({required String channel, required String auth}) =>
    jsonEncode({
      'event': 'pusher:subscribe',
      'data': {'channel': channel, 'auth': auth},
    });

String buildPingFrame() => jsonEncode({'event': 'pusher:ping', 'data': {}});

String buildPongFrame() => jsonEncode({'event': 'pusher:pong', 'data': {}});

/// One parsed incoming Pusher frame. `data` may arrive double-encoded (a JSON
/// string) — normalized to a map here.
class PusherMessage {
  const PusherMessage({required this.event, this.channel, this.data = const {}});

  final String event;
  final String? channel;
  final Map<String, dynamic> data;

  static PusherMessage? parse(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final event = map['event']?.toString() ?? '';
      if (event.isEmpty) return null;

      var data = map['data'];
      if (data is String) {
        data = data.isEmpty ? const <String, dynamic>{} : jsonDecode(data);
      }

      return PusherMessage(
        event: event,
        channel: map['channel']?.toString(),
        data: data is Map ? data.cast<String, dynamic>() : const {},
      );
    } catch (_) {
      return null;
    }
  }

  bool get isConnectionEstablished =>
      event == 'pusher:connection_established';
  bool get isPing => event == 'pusher:ping';

  /// Protocol-internal frames (handshake, subscription acks, errors) — never
  /// surfaced as domain events.
  bool get isInternal =>
      event.startsWith('pusher:') || event.startsWith('pusher_internal:');

  String? get socketId => data['socket_id']?.toString();

  /// Reverb's idle window; we ping at ~80% of it to keep NAT mappings alive.
  int get activityTimeoutSeconds =>
      (data['activity_timeout'] as num?)?.toInt() ?? 120;
}

typedef BroadcastAuthorizer = Future<String> Function({
  required String socketId,
  required String channelName,
});

/// Owns the websocket lifecycle. All collaborators are injected as getters so
/// a branch/server change between reconnects is picked up automatically.
class LiveSyncService {
  LiveSyncService({
    required this.endpointGetter,
    required this.apiBaseUrlGetter,
    required this.channelGetter,
    required this.authorize,
    required this.onLiveEvent,
  });

  final WebsocketEndpoint? Function() endpointGetter;
  final String Function() apiBaseUrlGetter;
  final String? Function() channelGetter;
  final BroadcastAuthorizer authorize;

  /// Fired with the broadcastAs event name ('order.create', 'shift.close', …)
  /// for every DOMAIN event on the channel — including echoes of this
  /// device's own pushes, so the consumer MUST debounce.
  final void Function(String eventType) onLiveEvent;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _frames;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _running = false;
  bool _online = true;
  int _attempt = 0;
  final Random _rng = Random();

  bool get isConnected => _socket != null;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_connect());
  }

  Future<void> stop() async {
    _running = false;
    _reconnectTimer?.cancel();
    await _teardownSocket();
  }

  /// Connectivity gating: offline drops the socket immediately (no point
  /// burning backoff cycles); back-online reconnects right away.
  void notifyOnline() {
    _online = true;
    if (_running && _socket == null) {
      _attempt = 0;
      _reconnectTimer?.cancel();
      unawaited(_connect());
    }
  }

  void notifyOffline() {
    _online = false;
    _reconnectTimer?.cancel();
    unawaited(_teardownSocket());
  }

  Future<void> _connect() async {
    if (!_running || !_online || _socket != null) return;

    final endpoint = endpointGetter();
    final channel = channelGetter();
    final url = endpoint == null
        ? null
        : buildWebsocketUrl(endpoint, apiBaseUrl: apiBaseUrlGetter());
    if (url == null || channel == null) {
      // Not configured (yet) — the next config sync may populate the endpoint;
      // keep retrying on the slow end of the backoff.
      _attempt = 5;
      _scheduleReconnect();
      return;
    }

    try {
      final socket =
          await WebSocket.connect(url).timeout(const Duration(seconds: 10));
      _socket = socket;
      _frames = socket.listen(
        _onFrame,
        onDone: _onSocketClosed,
        onError: (_) => _onSocketClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  Future<void> _onFrame(dynamic raw) async {
    if (raw is! String) return;
    final msg = PusherMessage.parse(raw);
    if (msg == null) return;

    if (msg.isConnectionEstablished) {
      _attempt = 0;
      _startPing(msg.activityTimeoutSeconds);
      final socketId = msg.socketId;
      final channel = channelGetter();
      if (socketId == null || channel == null) return;
      try {
        // The signature binds to THIS socket_id — re-authorized per connect.
        final auth =
            await authorize(socketId: socketId, channelName: channel);
        _socket?.add(buildSubscribeFrame(channel: channel, auth: auth));
      } catch (e) {
        // 403 = branch changed / token revoked; transport = server down.
        // Either way: drop and retry with fresh state.
        debugPrint('Live sync subscribe failed: $e');
        await _teardownSocket();
        _scheduleReconnect();
      }
      return;
    }

    if (msg.isPing) {
      _socket?.add(buildPongFrame());
      return;
    }
    if (msg.isInternal) return;

    onLiveEvent(msg.event);
  }

  void _onSocketClosed() {
    unawaited(_teardownSocket());
    _scheduleReconnect();
  }

  Future<void> _teardownSocket() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    final frames = _frames;
    _frames = null;
    await frames?.cancel();
    final socket = _socket;
    _socket = null;
    try {
      await socket?.close();
    } catch (_) {}
  }

  /// 1s → 2s → 4s → … capped at 30s, plus 0–1s jitter so a fleet that lost
  /// the server together doesn't reconnect in lockstep.
  void _scheduleReconnect() {
    if (!_running || !_online) return;
    _reconnectTimer?.cancel();
    final seconds = min(30, 1 << min(_attempt, 5));
    _attempt++;
    _reconnectTimer = Timer(
      Duration(seconds: seconds, milliseconds: _rng.nextInt(1000)),
      () => unawaited(_connect()),
    );
  }

  void _startPing(int activityTimeoutSeconds) {
    _pingTimer?.cancel();
    final interval = max(15, (activityTimeoutSeconds * 0.8).floor());
    _pingTimer = Timer.periodic(Duration(seconds: interval), (_) {
      _socket?.add(buildPingFrame());
    });
  }
}
