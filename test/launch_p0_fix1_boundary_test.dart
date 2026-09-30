import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/tenant_preferences.dart';
import 'package:pos_machine/tenancy/tenancy_gate.dart';
import 'package:pos_machine/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = BusinessIdentity(11, 21, 'legacy-device');
  setUp(() {
    BusinessBoundary.resetForTest();
  });
  tearDown(BusinessBoundary.resetForTest);

  test(
    'B1 actual legacy session loader adopts without quarantining held data or outbox',
    () async {
      SharedPreferences.setMockInitialValues({
        'company_id': 11,
        'branch_id': 21,
        'device_uuid': 'legacy-device',
        'kiosk_id': 'OLD-01',
        'held_orders': '[{"order_uuid":"held"}]',
        'order_outbox_v1':
            '[{"order_uuid":"paid","events":[{"client_event_id":"evt","event_type":"order.pay","payload":{"amount":1200}}]}]',
        'terminal_pin': '1234',
      });
      FlutterSecureStorage.setMockInitialValues({
        'device_token': 'existing-release-token',
      });
      final raw = await SharedPreferences.getInstance();
      await BusinessBoundary.initialize(raw);
      await SessionService(
        const FlutterSecureStorage(),
        TenantPreferences(raw),
      ).load();
      expect(BusinessBoundary.current?.encoded, owner.encoded);
      expect(BusinessBoundary.canWork, isTrue);
      final prefs = await businessPreferences();
      expect(prefs.getString('held_orders'), contains('held'));
      expect(prefs.getString('order_outbox_v1'), contains('paid'));
      expect(BusinessBoundary.quarantinedCount, 0);
      await BusinessBoundary.accept(owner);
      expect(prefs.getString('held_orders'), contains('held'));
      expect(prefs.getString('order_outbox_v1'), contains('paid'));
      expect(BusinessBoundary.quarantinedCount, 0);
    },
  );

  test(
    'B1 same identity activation with an interrupted install never wipes',
    () async {
      SharedPreferences.setMockInitialValues({
        BusinessBoundary.identityKey: owner.encoded,
        BusinessBoundary.transitionKey: owner.encoded,
      });
      final raw = await SharedPreferences.getInstance();
      await BusinessBoundary.initialize(raw);
      var wipes = 0;
      BusinessBoundary.registerWiper(() async {
        wipes++;
      });
      await BusinessBoundary.accept(owner);
      expect(wipes, 0);
      expect(BusinessBoundary.canWork, isTrue);
    },
  );

  test(
    'B12a preferences persist identity and value atomically, concurrent loaders retain every write',
    () async {
      SharedPreferences.setMockInitialValues({
        BusinessBoundary.identityKey: owner.encoded,
      });
      final raw = await SharedPreferences.getInstance();
      await BusinessBoundary.initialize(raw);
      final prefs = await businessPreferences();
      for (var i = 0; i < 20; i++) {
        await Future.wait([
          prefs.setString('order_outbox_v1', '[{"amount":$i}]'),
          businessPreferences(),
        ]);
        expect(
          (await businessPreferences()).getString('order_outbox_v1'),
          '[{"amount":$i}]',
        );
        final record = raw
            .getKeys()
            .map(raw.get)
            .whereType<String>()
            .map((value) {
              try {
                return jsonDecode(value);
              } catch (_) {
                return null;
              }
            })
            .whereType<Map>()
            .firstWhere(
              (record) => record['value'] == '[{"amount":$i}]',
              orElse: () => {},
            );
        expect(record, isA<Map>());
        expect(record['identity'], owner.toJson());
        expect(record['value'], '[{"amount":$i}]');
      }
      expect(BusinessBoundary.quarantinedCount, 0);
    },
  );

  testWidgets('B2 block hides but never disposes the in-flight card flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      BusinessBoundary.identityKey: owner.encoded,
    });
    await BusinessBoundary.initialize(await SharedPreferences.getInstance());
    var disposed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: TenancyGate(
          activation: (_) => const Text('activate'),
          child: _Payment(() {
            disposed = true;
          }),
        ),
      ),
    );
    BusinessBoundary.block('device_reactivation_required');
    await tester.pump();
    expect(find.text('payment'), findsNothing);
    expect(disposed, false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('B12d suspended unactivated device offers retry activation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await BusinessBoundary.initialize(await SharedPreferences.getInstance());
    BusinessBoundary.block('company_suspended');
    await tester.pumpWidget(
      MaterialApp(
        home: TenancyGate(
          activation: (_) => const Scaffold(body: Text('activation retry')),
          child: const SizedBox(),
        ),
      ),
    );
    expect(find.text('Activate device'), findsOneWidget);
    await tester.tap(find.text('Activate device'));
    await tester.pumpAndSettle();
    expect(find.text('activation retry'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('B3 suspension 503 pauses new work without deleting data', () async {
    SharedPreferences.setMockInitialValues({
      BusinessBoundary.identityKey: owner.encoded,
    });
    await BusinessBoundary.initialize(await SharedPreferences.getInstance());
    BusinessBoundary.observeError(503, 'company_suspended');
    expect(BusinessBoundary.blocked.value, 'company_suspended');
  });
}

class _Payment extends StatefulWidget {
  const _Payment(this.onDispose);
  final VoidCallback onDispose;
  @override
  State<_Payment> createState() => _PaymentState();
}

class _PaymentState extends State<_Payment> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('payment');
}
