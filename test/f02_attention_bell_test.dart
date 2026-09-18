import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/order_attention/order_attention.dart';
import 'package:pos_machine/order_attention/order_attention_host.dart';
import 'order_attention_test.dart' show MemoryLedger, snapshot;
import 'package:flutter/services.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

void main() {
  testWidgets(
    'F-02 normal staff header shows and clears live attention without duplicate bells',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugOrderStorageOverride = FakeOrderStorage();
      addTearDown(() => debugOrderStorageOverride = null);
      for (final name in [
        'plugins.it_nomads.com/flutter_secure_storage',
        'pos_machine/rear_display_host',
        'sunmi_printer_plus',
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              MethodChannel(name),
              (call) async => call.method == 'read'
                  ? 'synthetic'
                  : call.method == 'getPresentationDisplays'
                  ? <Map<String, dynamic>>[]
                  : null,
            );
      }

      var response = snapshot();
      var sounds = 0;
      final controller = OrderAttentionController(
        identity: () => const AttentionIdentity('f02', 'synthetic'),
        fetch: () async => response,
        ledger: MemoryLedger(),
        play: () async {
          sounds++;
          return true;
        },
        stop: () async {},
      );
      Widget wrap(Widget child) => OrderAttentionHost(
        showBanner: false,
        createController: () => controller,
        child: child,
      );
      await pumpWorkspaceMachine(
        tester,
        mode: 'live',
        toggle: false,
        catalog: const CatalogSnapshot(
          categories: [],
          products: [],
          floors: [],
          tables: [],
          taxes: [],
        ),
        wrapStaff: wrap,
      );

      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('order-attention-bell')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('order-attention-bar')), findsNothing);
      response = snapshot(['quick:a'], ['round:1:r']);
      await controller.refresh();
      await tester.pumpAndSettle();
      Badge badge() => tester.widget<Badge>(
        find.byKey(const ValueKey('order-attention-count')),
      );
      expect(badge().isLabelVisible, isTrue);
      expect((badge().label! as Text).data, '2');
      expect(sounds, 1);
      await tester.tap(find.byKey(const ValueKey('order-attention-bell')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('order-attention-quick')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('order-attention-tables')),
        findsOneWidget,
      );
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(sounds, 1);
      response = snapshot([], ['round:1:r']);
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-attention-quick')), findsNothing);
      expect(
        find.byKey(const ValueKey('order-attention-tables')),
        findsOneWidget,
      );
      response = snapshot();
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('No orders need attention'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(badge().isLabelVisible, isFalse);
      response = snapshot(['quick:b']);
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(sounds, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
