import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/screens/customer_display_screen.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/order_workspace/server_workspace_display.dart';
import 'package:pos_machine/services/presentation_service.dart';
import 'qr_quick_controller_test.dart' show quickJson;
import 'qr_quick_evidence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'rear display fences staff-cart updates until the owning server workspace exits',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final sent = <Map>[];
      const channel = MethodChannel('pos_machine/rear_display_host');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'transferDataToRear') {
              sent.add(call.arguments as Map);
            }
            return null;
          });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final display = PresentationService.forTest();
      final owner = Object();
      final staff = OrderSnapshot.initial();
      await display.sendOrder(staff);
      final original = Map.of(sent.last);
      await display.showWorkspaceBill(
        owner,
        WorkspaceBill(quickJson()),
        stale: false,
      );
      expect(sent.last['type'], 'server_bill_snapshot');
      expect(sent.last['total_baisas'], 1000);
      expect((sent.last['items'] as List).single['name'], 'Coffee');
      await display.sendOrder(staff);
      expect(sent.last['type'], 'server_bill_snapshot');
      final count = sent.length;
      await display.clearWorkspaceBill(Object());
      expect(sent.length, count);
      await display.showWorkspaceBill(
        owner,
        WorkspaceBill(quickJson()..['status'] = 'paid'),
        stale: false,
      );
      expect(sent.last['status'], 'paid');
      await display.clearWorkspaceBill(owner);
      expect(sent.last, original);
    },
  );
  test(
    'unavailable server display never leaks the cached staff cart',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final sent = <Map>[];
      const channel = MethodChannel('pos_machine/rear_display_host');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            sent.add(call.arguments as Map);
            return null;
          });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final display = PresentationService.forTest();
      final owner = Object();
      await display.showWorkspaceBill(owner, null, stale: true);
      await display.sendOrder(OrderSnapshot.initial());
      expect(sent.last['type'], 'server_bill_snapshot');
      expect(sent.last['stale'], true);
      expect(sent.last['items'], isEmpty);
    },
  );
  testWidgets(
    'real rear channel selects the server bill overlay and restores the ordinary view',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: L10n.localizationsDelegates,
          home: CustomerDisplayScreen(),
        ),
      );
      Future<void> send(Map<String, dynamic> data) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'pos_machine/rear_display_channel',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('updateOrder', data),
          ),
          (_) {},
        );
        await tester.pump();
      }

      await send(WorkspaceBill(quickJson()).display(stale: false));
      expect(find.byType(ServerWorkspaceDisplay), findsOneWidget);
      expect(find.text('Q-007'), findsOneWidget);
      await send({'type': 'slider_set', 'slides': []});
      expect(find.byType(ServerWorkspaceDisplay), findsOneWidget);
      await send({
        'type': 'order_snapshot',
        ...OrderSnapshot.initial().toMap(),
      });
      expect(find.byType(ServerWorkspaceDisplay), findsNothing);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final arabic in [false, true]) {
    testWidgets(
      'customer server bill ${arabic ? "AR" : "EN"} renders frozen lines, total and paid state',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadQuickEvidenceFonts(tester);
        final data = WorkspaceBill(quickJson()).display(stale: false)
          ..['language'] = arabic ? 'ar' : 'en';
        Future<void> show() async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: quickEvidenceKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(fontFamily: 'QuickEvidence'),
                home: Scaffold(
                  body: ServerWorkspaceDisplay(data: Map.of(data)),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await show();
        expect(find.text('1.0 × Coffee'), findsOneWidget);
        expect(find.text('Q-007'), findsOneWidget);
        expect(
          find.text(arabic ? 'الإجمالي: OMR 1.000' : 'Total: OMR 1.000'),
          findsOneWidget,
        );
        await captureQuickEvidence(
          tester,
          'customer-workspace-${arabic ? "ar" : "en"}',
        );
        data['status'] = 'paid';
        await show();
        expect(
          find.text(arabic ? 'اكتمل الدفع' : 'Payment complete'),
          findsOneWidget,
        );
        data['stale'] = true;
        await show();
        expect(
          find.text(
            arabic ? 'بانتظار تحديث الفاتورة' : 'Waiting for a bill update',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), null);
      },
    );
  }
}
