import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/live_sync.dart';

/// Phase C3 — the pure Pusher-protocol helpers behind the device's Reverb
/// subscription (url building, frames, frame parsing).
void main() {
  group('WebsocketEndpoint.fromJson', () {
    test('parses the /device/config meta.websocket shape', () {
      final ep = WebsocketEndpoint.fromJson({
        'app_key': 'key1',
        'host': null,
        'port': 8085,
        'scheme': 'http',
      });

      expect(ep, isNotNull);
      expect(ep!.appKey, 'key1');
      expect(ep.host, isNull);
      expect(ep.port, 8085);
      expect(ep.scheme, 'http');
    });

    test('null meta or a missing app key disables the socket', () {
      expect(WebsocketEndpoint.fromJson(null), isNull);
      expect(WebsocketEndpoint.fromJson({'host': 'x', 'port': 1}), isNull);
    });
  });

  group('buildWebsocketUrl', () {
    test('explicit host + https scheme → wss', () {
      final url = buildWebsocketUrl(
        const WebsocketEndpoint(
            appKey: 'k', host: 'pos.example.om', port: 443, scheme: 'https'),
        apiBaseUrl: 'https://api.example.om/api/v1',
      );

      expect(
        url,
        'wss://pos.example.om:443/app/k'
        '?protocol=7&client=pos_machine&version=1.0&flash=false',
      );
    });

    test('null host falls back to the API host (dev LAN)', () {
      final url = buildWebsocketUrl(
        const WebsocketEndpoint(appKey: 'k', port: 8085, scheme: 'http'),
        apiBaseUrl: 'http://192.168.1.20:8088/api/v1',
      );

      expect(url, startsWith('ws://192.168.1.20:8085/app/k'));
    });

    test('unresolvable host returns null (never dials a blank)', () {
      expect(
        buildWebsocketUrl(
          const WebsocketEndpoint(appKey: 'k', port: 8085, scheme: 'http'),
          apiBaseUrl: '',
        ),
        isNull,
      );
    });
  });

  group('channelFor', () {
    test('branch first, company fallback, null when unactivated', () {
      expect(channelFor(branchId: 6, companyId: 9), 'private-branch.6');
      expect(channelFor(branchId: null, companyId: 9), 'private-company.9');
      expect(channelFor(branchId: null, companyId: null), isNull);
    });
  });

  group('frames', () {
    test('subscribe frame carries channel + auth', () {
      final frame = jsonDecode(
        buildSubscribeFrame(channel: 'private-branch.6', auth: 'k:sig'),
      ) as Map<String, dynamic>;

      expect(frame['event'], 'pusher:subscribe');
      expect(frame['data'], {'channel': 'private-branch.6', 'auth': 'k:sig'});
    });

    test('ping/pong frames', () {
      expect(jsonDecode(buildPingFrame())['event'], 'pusher:ping');
      expect(jsonDecode(buildPongFrame())['event'], 'pusher:pong');
    });
  });

  group('PusherMessage.parse', () {
    test('connection_established with double-encoded data', () {
      // Reverb double-encodes `data` as a JSON string — the parser normalizes.
      final msg = PusherMessage.parse(jsonEncode({
        'event': 'pusher:connection_established',
        'data': jsonEncode({'socket_id': '123.456', 'activity_timeout': 30}),
      }));

      expect(msg, isNotNull);
      expect(msg!.isConnectionEstablished, isTrue);
      expect(msg.isInternal, isTrue);
      expect(msg.socketId, '123.456');
      expect(msg.activityTimeoutSeconds, 30);
    });

    test('a domain broadcast surfaces its event name + channel', () {
      final msg = PusherMessage.parse(jsonEncode({
        'event': 'order.pay',
        'channel': 'private-branch.6',
        'data': jsonEncode({'type': 'order.pay', 'event_id': 'e1'}),
      }));

      expect(msg!.isInternal, isFalse);
      expect(msg.event, 'order.pay');
      expect(msg.channel, 'private-branch.6');
      expect(msg.data['event_id'], 'e1');
    });

    test('ping + subscription ack are internal', () {
      expect(
        PusherMessage.parse('{"event":"pusher:ping","data":{}}')!.isPing,
        isTrue,
      );
      final ack = PusherMessage.parse(
        '{"event":"pusher_internal:subscription_succeeded","channel":"private-branch.6","data":"{}"}',
      );
      expect(ack!.isInternal, isTrue);
    });

    test('garbage frames parse to null, never throw', () {
      expect(PusherMessage.parse('not json'), isNull);
      expect(PusherMessage.parse('[]'), isNull);
      expect(PusherMessage.parse('{"data":{}}'), isNull);
    });

    test('activity_timeout defaults to 120 when absent', () {
      final msg = PusherMessage.parse(
        '{"event":"pusher:connection_established","data":"{\\"socket_id\\":\\"1.2\\"}"}',
      );
      expect(msg!.activityTimeoutSeconds, 120);
    });
  });
}
