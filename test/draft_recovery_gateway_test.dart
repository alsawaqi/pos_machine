import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/dine_in/dine_in_gateway.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'package:pos_machine/draft_recovery/recovery_controller.dart';
import 'package:pos_machine/draft_recovery/recovery_gateway.dart';
import 'package:pos_machine/draft_recovery/recovery_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_gateway.dart';
import 'package:pos_machine/qr_quick/qr_quick_gateway.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';

import 'draft_recovery_test.dart'
    show RecoveryHarness, billId, recoveryId, seatId;
import 'qr_checkout_fakes.dart' show snapshotJson;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late RecoveryHarness h;
  late _Adapter adapter;
  late Dio dio;
  late PosApiService api;
  late ApiRecoveryGateway gateway;
  late String scope;
  String? token;
  var unauthorized = 0;

  setUp(() async {
    h = RecoveryHarness();
    await h.init();
    adapter = _Adapter();
    token = 'saved-device-token';
    scope = 'scope';
    unauthorized = 0;
    dio = Dio(
      BaseOptions(
        baseUrl: 'https://recovery.test/api/v1',
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = adapter;
    api = PosApiService(
      tokenGetter: () => token,
      onUnauthorized: () => unauthorized++,
      dio: dio,
    );
    gateway = ApiRecoveryGateway(api, () => scope, h.store);
  });
  tearDown(() async {
    dio.close(force: true);
    await h.close();
  });

  RecoveryController controller() {
    final value = RecoveryController(
      store: h.store,
      gateway: gateway,
      dineIn: gateway,
      tableId: 1,
      loadLocal: h.local,
      checkIdle: () async {},
      admit: (operation) => operation(),
      onRetired: (_) async {},
    );
    addTearDown(value.dispose);
    return value;
  }

  test(
    'preview uses the exact authenticated GET without saving or editing copies',
    () async {
      final local = await h.local(1);
      final before = await _originals(h);
      adapter.data = {'data': h.api.previewJson, 'errors': <Object?>[]};

      final preview = await gateway.preview(1, local.query);

      expect(preview, h.api.previewJson);
      final wire = adapter.requests.single;
      expect(wire.method, 'GET');
      expect(wire.path, '/device/tables/1/draft-recovery');
      expect(wire.query, local.query);
      expect(wire.headers['Authorization'], 'Bearer saved-device-token');
      expect(wire.body, isNull);
      expect(await h.store.active(), isNull);
      expect(await _originals(h), before);
    },
  );

  test(
    'confirm cannot POST an intent before the immutable journal exists',
    () async {
      final attempt = await _attempt(h);
      final before = await _originals(h);

      await expectLater(gateway.confirm(1, attempt.payload), throwsStateError);

      expect(adapter.requests, isEmpty);
      expect(await h.store.active(), isNull);
      expect(await _originals(h), before);
    },
  );

  test(
    'production controller persists the exact intent before its POST',
    () async {
      RecoveryAttempt? persisted;
      adapter.reply = (wire) async {
        if (wire.method == 'GET') {
          return {'data': h.api.previewJson, 'errors': []};
        }
        persisted = await h.store.active();
        expect(persisted, isNotNull);
        expect(persisted!.state, 'pending');
        expect(wire.path, '/device/tables/1/draft-recovery');
        expect(wire.body, persisted!.payload);
        expect((await h.db.query('held_orders')), hasLength(1));
        expect((await h.db.query('dining_tables')), hasLength(1));
        return h.api.ack(Map<String, dynamic>.from(wire.body as Map));
      };
      final c = controller();

      await c.start();
      await c.confirm();

      expect(c.error, isNull);
      expect(persisted, isNotNull);
      expect(adapter.requests.map((wire) => wire.method), ['GET', 'POST']);
      final retained = (await h.store.active())!;
      expect(retained.state, 'delta_ready');
      expect(retained.id, persisted!.id);
      expect(retained.local.encoded, persisted!.local.encoded);
    },
  );

  for (final mismatch in [
    'payload',
    'table',
    'scope',
    'token',
    'store scope',
  ]) {
    test(
      'saved confirmation refuses mismatched $mismatch without POST',
      () async {
        final attempt = await _saveAttempt(h);
        final before = await h.db.query('draft_recovery_journal');
        final payload = attempt.payload;
        var tableId = 1;
        var target = gateway;
        switch (mismatch) {
          case 'payload':
            payload['local_snapshot_hash'] = 'different-local-snapshot';
          case 'table':
            tableId = 2;
          case 'scope':
            scope = 'another-device';
          case 'token':
            token = 'another-token';
          case 'store scope':
            target = ApiRecoveryGateway(api, () => 'another-device', h.store);
        }

        await expectLater(target.confirm(tableId, payload), throwsStateError);

        expect(adapter.requests, isEmpty);
        expect(await h.db.query('draft_recovery_journal'), before);
      },
    );
  }

  test(
    'confirm serializes durable payload despite caller mutation during interception',
    () async {
      final attempt = await _saveAttempt(h);
      final payload = attempt.payload;
      final intercepted = Completer<void>();
      final release = Completer<void>();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            intercepted.complete();
            await release.future;
            handler.next(options);
          },
        ),
      );
      adapter.data = h.api.ack(attempt.payload);
      final sent = gateway.confirm(1, payload);
      await intercepted.future;
      payload['local_snapshot_hash'] = 'caller-changed-after-validation';
      release.complete();

      await sent;

      expect(adapter.requests.single.body, attempt.payload);
      expect((await h.store.active())!.encoded, attempt.encoded);
    },
  );

  for (final identity in ['scope', 'token']) {
    test(
      '$identity change during a confirm response leaves its journal pending',
      () async {
        final attempt = await _saveAttempt(h);
        final entered = Completer<void>();
        final release = Completer<void>();
        adapter.reply = (_) async {
          entered.complete();
          await release.future;
          return h.api.ack(attempt.payload);
        };
        final response = expectLater(
          gateway.confirm(1, attempt.payload),
          throwsStateError,
        );
        await entered.future;
        if (identity == 'scope') {
          scope = 'other-device';
        } else {
          token = 'new-token';
        }
        release.complete();

        await response;

        expect((await h.store.active())!.encoded, attempt.encoded);
        expect(await h.db.query('draft_recovery_retired'), isEmpty);
      },
    );
  }

  for (final state in ['none', 'pending', 'delta_ready']) {
    test(
      'delta append without a saved delta_pending intent ($state) refuses HTTP',
      () async {
        if (state == 'pending') await _saveAttempt(h);
        if (state == 'delta_ready') {
          await h.controller.start();
          await h.controller.confirm();
        }
        final before = await h.db.query('draft_recovery_journal');
        final detail = await h.api.detail(1);
        final request = DineInRequest.create(detail, [
          QrQuickLine(7, 1, [], notes: 'Keep Exactly'),
        ], 1);

        await expectLater(gateway.append(request), throwsStateError);

        expect(adapter.requests, isEmpty);
        expect(await h.db.query('draft_recovery_journal'), before);
      },
    );
  }

  test(
    'delta append sends only the exact durable saved additions and replay identity',
    () async {
      final saved = await _saveDelta(h);
      final request = saved.request;
      final before = await h.db.query('draft_recovery_journal');
      const ack = {'outcome': 'replayed', 'round_id': 21};
      adapter.reply = (wire) async {
        final pending = (await h.store.active())!;
        expect(pending.state, 'delta_pending');
        expect(wire.body, pending.request.payload);
        return {'data': ack, 'errors': []};
      };

      expect(await gateway.append(request), ack);
      expect(await gateway.append(request), ack);

      expect(adapter.requests, hasLength(2));
      for (final wire in adapter.requests) {
        expect(wire.method, 'POST');
        expect(wire.path, '/device/tables/$seatId/round');
        expect(wire.headers['Authorization'], 'Bearer saved-device-token');
        expect(wire.body, request.payload);
        expect((wire.body as Map)['lines'], [
          {'product_id': 7, 'qty': 1, 'addon_ids': [], 'notes': 'Keep Exactly'},
        ]);
      }
      expect(await h.db.query('draft_recovery_journal'), before);
    },
  );

  for (final mismatch in ['table', 'seating', 'bill', 'request', 'quantity']) {
    test('delta append refuses mismatched $mismatch without HTTP', () async {
      final saved = await _saveDelta(h);
      final exact = saved.request;
      final payload = exact.payload;
      if (mismatch == 'request') payload['client_request_id'] = recoveryId;
      if (mismatch == 'quantity') {
        ((payload['lines'] as List).single as Map)['qty'] = 3;
      }
      final request = DineInRequest(
        tableId: mismatch == 'table' ? 2 : exact.tableId,
        seatingUuid: mismatch == 'seating' ? billId : exact.seatingUuid,
        billUuid: mismatch == 'bill' ? seatId : exact.billUuid,
        payload: payload,
      );

      await expectLater(gateway.append(request), throwsStateError);

      expect(adapter.requests, isEmpty);
      expect((await h.store.active())!.encoded, saved.encoded);
    });
  }

  test('recovery never exposes clear, reopen or review writes', () async {
    final detail = await h.api.detail(1);

    await expectLater(gateway.clear(1), throwsStateError);
    await expectLater(gateway.reopen(billId), throwsStateError);
    await expectLater(
      gateway.review(detail, {'id': 21}, true),
      throwsStateError,
    );

    expect(adapter.requests, isEmpty);
  });

  for (final acceptHttpErrors in [true, false]) {
    test(
      '409 final-no-write is preserved with validateStatus accepting errors=$acceptHttpErrors',
      () async {
        final saved = await _saveAttempt(h);
        final before = await _originals(h);
        dio.options.validateStatus = acceptHttpErrors
            ? (_) => true
            : (status) => status != null && status >= 200 && status < 300;
        final envelope = <String, dynamic>{
          'data': null,
          'errors': [
            {'code': 'draft_recovery_preview_stale', 'message': 'Review again'},
          ],
          'draft_recovery_final_no_write': {...saved.payload, 'table_id': 1},
          'meta': {'preserved': true},
        };
        adapter.status = 409;
        adapter.data = envelope;

        expect(await gateway.confirm(1, saved.payload), envelope);
        expect((await h.store.active())!.encoded, saved.encoded);
        final c = controller();
        await c.start();
        await c.confirm();

        expect(c.error, isNull);
        expect(c.attempt!.state, 'not_applied');
        expect(await h.store.active(), isNull);
        expect(
          c.attempt!.json['release'],
          envelope['draft_recovery_final_no_write'],
        );
        expect(await _originals(h), before);
        expect(await h.db.query('draft_recovery_retired'), isEmpty);
      },
    );
  }

  for (final status in [401, 500, 503]) {
    test(
      'HTTP $status retains pending intent and every original copy',
      () async {
        final saved = await _saveAttempt(h);
        final before = await _originals(h);
        adapter.status = status;
        adapter.data = status == 401
            ? {'message': 'Unauthenticated.'}
            : {
                'data': null,
                'errors': [
                  {
                    'code': 'draft_recovery_preview_stale',
                    'message': 'Service failed',
                  },
                ],
                // A non-409 transport must never turn a plausible release body
                // into authorization to abandon this durable attempt.
                'draft_recovery_final_no_write': {
                  ...saved.payload,
                  'table_id': 1,
                },
              };
        final c = controller();
        await c.start();

        await c.confirm();

        expect(c.error, isNotNull);
        expect((await h.store.active())!.encoded, saved.encoded);
        expect(await _originals(h), before);
        expect(await h.db.query('draft_recovery_retired'), isEmpty);
        expect(adapter.requests.single.body, saved.payload);
        expect(unauthorized, status == 401 ? 1 : 0);
      },
    );
  }

  test(
    'ordinary Dine-In guard blocks mutations while detail remains readable',
    () async {
      var guards = 0;
      final ordinary = ApiDineInGateway(
        api,
        () => scope,
        mutationGuard: () async {
          guards++;
          throw StateError('Finish recovery first.');
        },
      );
      final detail = await h.api.detail(1);
      adapter.data = {'data': detail.json, 'errors': []};
      expect((await ordinary.detail(1)).json, detail.json);
      final request = DineInRequest.create(detail, [QrQuickLine(7, 1, [])], 1);

      await expectLater(ordinary.append(request), throwsStateError);
      await expectLater(ordinary.clear(1), throwsStateError);
      await expectLater(ordinary.reopen(billId), throwsStateError);
      await expectLater(
        ordinary.review(detail, {'id': 21, 'entered_by': 'staff'}, true),
        throwsStateError,
      );

      expect(guards, 4);
      expect(adapter.requests.single.method, 'GET');
    },
  );

  test(
    'ordinary quick-order guard blocks mutations while inbox remains readable',
    () async {
      var guards = 0;
      final ordinary = ApiQrQuickGateway(
        api,
        () => scope,
        mutationGuard: () async {
          guards++;
          throw StateError('Finish recovery first.');
        },
      );
      adapter.data = {
        'data': {'orders': <Object?>[]},
        'errors': [],
      };
      expect(await ordinary.fetch(), isEmpty);

      await expectLater(ordinary.move(billId), throwsStateError);
      await expectLater(
        ordinary.append(
          QrQuickRequest(billId, recoveryId, [QrQuickLine(7, 1, [])]),
        ),
        throwsStateError,
      );

      expect(guards, 2);
      expect(adapter.requests.single.method, 'GET');
    },
  );

  test(
    'ordinary checkout guard blocks mutations while snapshot remains readable',
    () async {
      var guards = 0;
      final ordinary = ApiCheckoutGateway(
        api: api,
        currentScope: () => scope,
        location: () async => null,
        legacyGuard: (_) async {},
        mutationGuard: () async {
          guards++;
          throw StateError('Finish recovery first.');
        },
      );
      adapter.data = {'data': snapshotJson(), 'errors': []};
      expect(await ordinary.snapshot('qr-bill'), snapshotJson());

      await expectLater(ordinary.claim('qr-bill'), throwsStateError);
      await expectLater(
        ordinary.release('qr-bill', 'cancelled', []),
        throwsStateError,
      );
      await expectLater(
        ordinary.push({'event_type': 'order.pay'}),
        throwsStateError,
      );

      expect(guards, 3);
      expect(adapter.requests.single.method, 'GET');
    },
  );
}

Future<RecoveryAttempt> _attempt(RecoveryHarness h) async {
  final local = await h.local(1);
  final preview = RecoveryPreview(h.api.previewJson);
  return RecoveryAttempt({
    'id': recoveryId,
    'state': 'pending',
    'local': local.json,
    'preview': preview.json,
    'delta': local.delta(preview),
  });
}

Future<RecoveryAttempt> _saveAttempt(RecoveryHarness h) async {
  final value = await _attempt(h);
  await h.store.create(value);
  return value;
}

Future<RecoveryAttempt> _saveDelta(RecoveryHarness h) async {
  await h.controller.start();
  await h.controller.confirm();
  h.api.roundReply = (_) async =>
      throw StateError('Synthetic lost append response');
  await h.controller.sendSavedAdditions();
  final saved = (await h.store.active())!;
  expect(saved.state, 'delta_pending');
  return saved;
}

Future<List<List<Map<String, Object?>>>> _originals(RecoveryHarness h) async =>
    [
      await h.db.query('held_orders'),
      await h.db.query('dining_tables'),
      await h.db.query('local_table_rounds'),
      await h.db.query('local_line_cancellations'),
    ];

class _Request {
  _Request(RequestOptions options)
    : method = options.method,
      path = options.path,
      query = Map<String, dynamic>.from(options.queryParameters),
      headers = Map<String, dynamic>.from(options.headers),
      body = options.data == null ? null : jsonDecode(jsonEncode(options.data));
  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Map<String, dynamic> headers;
  final Object? body;
}

class _Adapter implements HttpClientAdapter {
  final requests = <_Request>[];
  int status = 200;
  Map<String, dynamic> data = {
    'data': <String, dynamic>{},
    'errors': <Object?>[],
  };
  FutureOr<Map<String, dynamic>> Function(_Request)? reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = _Request(options);
    requests.add(request);
    final body = reply == null ? data : await reply!(request);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
