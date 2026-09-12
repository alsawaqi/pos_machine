import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/order_attention/order_attention.dart';
import 'package:pos_machine/order_attention/order_attention_host.dart';
import 'package:pos_machine/services/pos_api_service.dart';

Map<String, dynamic> snapshot([
  List<String> quick = const [],
  List<String> rounds = const [],
]) => {'version': 1, 'quick_order_keys': quick, 'table_round_keys': rounds};

class MemoryLedger implements AttentionLedger {
  final values = <String, Set<String>>{};
  int writes = 0;
  bool failRead = false;
  bool failWrite = false;
  Completer<void>? pending;
  @override
  Future<Set<String>?> read(String scope) async {
    await pending?.future;
    if (failRead) throw const FormatException('corrupt');
    final value = values[scope];
    return value == null ? null : {...value};
  }

  @override
  Future<void> write(String scope, Set<String> keys) async {
    if (failWrite) throw StateError('disk');
    writes++;
    values[scope] = {...keys};
  }
}

class AttentionAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'data': snapshot(['quick:new']),
        'meta': [],
        'errors': [],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryLedger ledger;
  late OrderAttentionController controller;
  AttentionIdentity? identity;
  Map<String, dynamic> response = snapshot();
  int calls = 0, sounds = 0, stops = 0;
  bool audioWorks = true;
  Object? networkError;
  Completer<Map<String, dynamic>>? request;
  OrderAttentionController create() => OrderAttentionController(
    identity: () => identity,
    fetch: () async {
      calls++;
      if (networkError != null) throw networkError!;
      return request == null ? response : await request!.future;
    },
    ledger: ledger,
    play: () async {
      sounds++;
      return audioWorks;
    },
    stop: () async {
      stops++;
    },
  );
  setUp(() {
    identity = const AttentionIdentity(
      'server/company/branch/device',
      'token|7',
    );
    ledger = MemoryLedger();
    response = snapshot();
    calls = sounds = stops = 0;
    audioWorks = true;
    networkError = request = null;
    controller = create();
  });
  tearDown(() => controller.dispose());

  test(
    'first snapshot shows waiting work silently; same IDs never ring',
    () async {
      response = snapshot(['quick:a'], ['round:1:r']);
      await controller.refresh();
      expect(controller.snapshot!.keys.length, 2);
      expect(sounds, 0);
      expect(ledger.writes, 1);
      await controller.refresh();
      expect(sounds, 0);
      expect(ledger.writes, 1);
    },
  );
  test(
    'new quick and customer rounds ring once per batch despite reordering',
    () async {
      await controller.refresh();
      response = snapshot(['quick:b', 'quick:a'], ['round:1:r']);
      await controller.refresh();
      expect(sounds, 1);
      expect(controller.newArrivals, 3);
      response = snapshot(['quick:a', 'quick:b'], ['round:1:r']);
      await controller.refresh();
      expect(sounds, 1);
      expect(controller.newArrivals, 0);
      expect(ledger.writes, 2);
    },
  );
  test(
    'disappearance then reappearance does not ring an old arrival',
    () async {
      await controller.refresh();
      response = snapshot(['quick:a']);
      await controller.refresh();
      response = snapshot();
      await controller.refresh();
      response = snapshot(['quick:a']);
      await controller.refresh();
      expect(sounds, 1);
    },
  );
  test(
    'restart preserves deduplication and rings new offline arrivals once',
    () async {
      await controller.refresh();
      response = snapshot(['quick:a']);
      await controller.refresh();
      final reopened = create();
      await reopened.refresh();
      expect(sounds, 1);
      response = snapshot(['quick:a', 'quick:b']);
      await reopened.refresh();
      expect(sounds, 2);
      reopened.dispose();
    },
  );
  test('network failure retains counts, warns and catches up once', () async {
    await controller.refresh();
    response = snapshot(['quick:a']);
    networkError = StateError('offline');
    await controller.refresh();
    expect(controller.stale, isTrue);
    expect(controller.snapshot!.keys, isEmpty);
    expect(sounds, 0);
    networkError = null;
    await controller.refresh();
    expect(controller.stale, isFalse);
    expect(sounds, 1);
    await controller.refresh();
    expect(sounds, 1);
  });
  test(
    'old server, malformed and duplicate snapshots do not seed or ring',
    () async {
      for (final invalid in [
        <String, dynamic>{},
        {...snapshot(), 'version': 2},
        snapshot(['quick:a', 'quick:a']),
        snapshot(['other:a']),
        {...snapshot(), 'table_round_keys': null},
      ]) {
        response = invalid;
        await controller.refresh();
        expect(controller.stale, isTrue);
        expect(sounds, 0);
        expect(ledger.writes, 0);
      }
      response = snapshot(['quick:a']);
      await controller.refresh();
      expect(sounds, 0);
      expect(controller.stale, isFalse);
    },
  );
  test(
    'failed initial storage never rings backlog; successful baseline is silent',
    () async {
      ledger.failWrite = true;
      response = snapshot(['quick:a']);
      await controller.refresh();
      expect(controller.storageFailed, isTrue);
      expect(controller.snapshot!.quick, {'quick:a'});
      expect(sounds, 0);
      ledger.failWrite = false;
      await controller.refresh();
      expect(controller.storageFailed, isFalse);
      expect(sounds, 0);
    },
  );
  test(
    'save failure retries without losing arrival or double ringing',
    () async {
      await controller.refresh();
      ledger.failWrite = true;
      response = snapshot(['quick:a']);
      await controller.refresh();
      expect(sounds, 0);
      ledger.failWrite = false;
      await controller.refresh();
      await controller.refresh();
      expect(sounds, 1);
    },
  );
  test('corrupt ledger is not replaced by an empty baseline', () async {
    ledger.failRead = true;
    response = snapshot(['quick:a']);
    await controller.refresh();
    expect(controller.storageFailed, isTrue);
    expect(ledger.writes, 0);
    expect(sounds, 0);
  });
  test('ledger capacity fails visibly instead of forgetting IDs', () async {
    ledger.values[identity!.scope] = {
      for (var i = 0; i < 50000; i++) 'quick:$i',
    };
    response = snapshot(['quick:new']);
    await controller.refresh();
    expect(controller.storageFailed, isTrue);
    expect(ledger.writes, 0);
    expect(sounds, 0);
  });
  test('muted audio still shows arrival and does not retry its bell', () async {
    await controller.refresh();
    audioWorks = false;
    response = snapshot(['quick:a']);
    await controller.refresh();
    expect(controller.soundUnavailable, isTrue);
    expect(controller.snapshot!.quick, {'quick:a'});
    expect(sounds, 1);
    await controller.refresh();
    expect(sounds, 1);
  });
  test('overlapping refreshes issue one request and one bell', () async {
    await controller.refresh();
    request = Completer<Map<String, dynamic>>();
    final first = controller.refresh();
    await controller.refresh();
    expect(calls, 2);
    request!.complete(snapshot(['quick:a']));
    await first;
    expect(sounds, 1);
  });
  test('overlapping consumers serialize the same durable ledger', () async {
    await controller.refresh();
    final other = create();
    response = snapshot(['quick:a']);
    await Future.wait([controller.refresh(), other.refresh()]);
    expect(sounds, 1);
    other.dispose();
  });
  test(
    'scope change discards late responses and silently seeds new scope',
    () async {
      await controller.refresh();
      request = Completer<Map<String, dynamic>>();
      final pending = controller.refresh();
      identity = const AttentionIdentity(
        'other-server/branch/device',
        'other-token|7',
      );
      controller.contextChanged();
      request!.complete(snapshot(['quick:old']));
      request = null;
      response = snapshot(['quick:new']);
      await pending;
      await Future<void>.delayed(Duration.zero);
      await controller.refresh();
      expect(sounds, 0);
      expect(ledger.values[identity!.scope], {'quick:new'});
      expect(ledger.values['server/company/branch/device'], isEmpty);
    },
  );
  test('logout during ledger read suppresses writes and audio', () async {
    await controller.refresh();
    ledger.pending = Completer<void>();
    response = snapshot(['quick:a']);
    final pending = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    identity = null;
    controller.contextChanged();
    ledger.pending!.complete();
    await pending;
    expect(sounds, 0);
    expect(ledger.writes, 1);
    expect(controller.snapshot, isNull);
  });
  test('no staff means no HTTP; pause stops audio and polling work', () async {
    identity = null;
    await controller.refresh();
    expect(calls, 0);
    identity = const AttentionIdentity('scope', 'token|7');
    controller.setActive(false);
    await controller.refresh();
    expect(calls, 0);
    expect(stops, 1);
    controller.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
  });
  test('response after backgrounding does not consume arrivals', () async {
    await controller.refresh();
    request = Completer<Map<String, dynamic>>();
    final pending = controller.refresh();
    controller.setActive(false);
    request!.complete(snapshot(['quick:a']));
    await pending;
    expect(sounds, 0);
    expect(ledger.writes, 1);
  });
  test(
    'preferences persist only version and arrival IDs under hashed scope',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = PreferencesAttentionLedger();
      expect(await store.read('private-server/company/device'), isNull);
      await store.write('private-server/company/device', {
        'quick:a',
        'round:1:b',
      });
      final again = PreferencesAttentionLedger();
      expect(await again.read('private-server/company/device'), {
        'quick:a',
        'round:1:b',
      });
      expect(await again.read('different-scope'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().single, startsWith('order_attention_v1_'));
      expect(prefs.getKeys().single, isNot(contains('private-server')));
      expect(jsonDecode(prefs.getString(prefs.getKeys().single)!), {
        'version': 1,
        'keys': ['quick:a', 'round:1:b'],
      });
      await prefs.setString(prefs.getKeys().single, 'broken');
      await expectLater(
        again.read('private-server/company/device'),
        throwsFormatException,
      );
    },
  );
  test(
    'sound bridge accepts play and stop; missing plugin fails visibly',
    () async {
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(OrderAttentionSound.channel, (call) async {
            methods.add(call.method);
            return call.method == 'play' ? true : null;
          });
      expect(await OrderAttentionSound.play(), isTrue);
      await OrderAttentionSound.stop();
      expect(methods, ['play', 'stop']);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(OrderAttentionSound.channel, null);
      expect(await OrderAttentionSound.play(), isFalse);
      await OrderAttentionSound.stop();
    },
  );
  test('API uses authenticated GET, never a write', () async {
    final adapter = AttentionAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://attention.invalid/api/v1',
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = adapter;
    final api = PosApiService(tokenGetter: () => 'synthetic-device', dio: dio);
    expect(await api.fetchOrderAttention(), snapshot(['quick:new']));
    final call = adapter.requests.single;
    expect(call.method, 'GET');
    expect(call.path, '/device/order-attention');
    expect(call.headers['Authorization'], 'Bearer synthetic-device');
    expect(call.data, isNull);
  });
  test('staff mount leases do not enable cold-start PIN screen', () {
    expect(staffAttentionHosts.value, isEmpty);
    final a = enterStaffAttention();
    final b = enterStaffAttention();
    leaveStaffAttention(a);
    expect(staffAttentionHosts.value, {b});
    leaveStaffAttention(b);
    expect(staffAttentionHosts.value, isEmpty);
  });
  test('native foreground bridge stops on pause without touching volume', () {
    final native = Directory('android/app/src/main/kotlin/com/example')
        .listSync()
        .whereType<Directory>()
        .singleWhere(
          (d) => File('${d.path}/OrderAttentionSound.kt').existsSync(),
        );
    final main = File('${native.path}/MainActivity.kt').readAsStringSync();
    final sound = File(
      '${native.path}/OrderAttentionSound.kt',
    ).readAsStringSync();
    expect(
      main,
      contains(
        'orderAttentionSound = OrderAttentionSound(this, flutterEngine.dartExecutor.binaryMessenger)',
      ),
    );
    expect(main, contains('override fun onPause()'));
    expect(main, contains('orderAttentionSound?.stop()'));
    expect(sound, contains('"mithqal/order_attention"'));
    expect(sound, contains('AudioAttributes.USAGE_NOTIFICATION'));
    expect(sound, contains('handler.postDelayed(stopSound, 2000)'));
    expect(sound, isNot(contains('setStreamVolume')));
    expect(sound, isNot(contains('FLAG_AUDIBILITY_ENFORCED')));
  });

  testWidgets(
    'bar appears on pushed route without mutating or replacing its form',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final field = TextEditingController(text: 'unchanged cart note');
      var pays = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          builder: (context, child) => OrderAttentionHost(
            createController: () => controller,
            child: child!,
          ),
          home: const Scaffold(body: Text('catalog')),
        ),
      );
      await tester.pumpAndSettle();
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: Column(
              children: [
                TextField(controller: field),
                TextButton(
                  onPressed: () {
                    pays++;
                  },
                  child: const Text('Pay'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      response = snapshot(['quick:a'], ['round:1:r']);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-attention-bar')), findsOneWidget);
      expect(
        find.textContaining('QR quick 1 · Table rounds 1'),
        findsOneWidget,
      );
      expect(field.text, 'unchanged cart note');
      expect(find.text('Pay'), findsOneWidget);
      expect(nav.currentState!.canPop(), isTrue);
      expect(pays, 0);
      expect(sounds, 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(sounds, 1);
      response = snapshot();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-attention-bar')), findsNothing);
      expect(find.text('Pay'), findsOneWidget);
      expect(field.text, 'unchanged cart note');
      expect(pays, 0);
      await tester.pumpWidget(const SizedBox());
      field.dispose();
    },
  );
  testWidgets('poll pauses in background and resumes without duplicate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => OrderAttentionHost(
          createController: () => controller,
          child: child!,
        ),
        home: const Scaffold(body: Text('staff')),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 1);
    response = snapshot(['quick:a']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(sounds, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('silent backlog visible and test bell explicit, not payment', (
    tester,
  ) async {
    response = snapshot(['quick:a']);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => OrderAttentionHost(
          createController: () => controller,
          child: child!,
        ),
        home: const Scaffold(body: Text('staff')),
      ),
    );
    await tester.pumpAndSettle();
    expect(sounds, 0);
    expect(find.textContaining('QR quick 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('order-attention-test-sound')));
    await tester.pumpAndSettle();
    expect(sounds, 1);
    expect(ledger.writes, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Arabic notification and RTL fit a narrow handheld', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    response = snapshot(['quick:a'], ['round:1:r']);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Localizations.override(
          context: context,
          locale: const Locale('ar'),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: OrderAttentionHost(
              createController: () => controller,
              child: child!,
            ),
          ),
        ),
        home: const Scaffold(body: Text('staff')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('بانتظار الموظف'), findsOneWidget);
    expect(find.bySemanticsLabel('اختبار صوت التنبيه'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });
}
