import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_kitchen_android/mithqal_kitchen_android.dart';
import 'package:pos_machine/kitchen/kitchen_orders_page.dart';
import 'package:pos_machine/providers/providers.dart';

class EmptyVault implements CredentialVault {
  @override
  Future<String?> read(String id) async => null;
  @override
  Future<void> put(String id, String value) async {}
  @override
  Future<void> remove(String id) async {}
}

class NoOrders implements KitchenDomainStore {
  @override
  Future<void> persist(String id, String originalJson) async {}
  @override
  Future<DomainEvidence> evidence(String id, String originalHash) async =>
      DomainEvidence.absent;
}

KitchenPosController controller() => KitchenPosController(
  apiUrl: 'https://unused.invalid',
  deviceToken: 'test-only',
  staffToken: 'test-only',
  staffId: 1,
  scope: {
    'company_id': 1,
    'branch_id': 2,
    'device_id': 3,
    'assignment': 'test',
  },
  domain: NoOrders(),
  isCurrent: () => true,
  credentials: EmptyVault(),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('net.mithqal.kitchen/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(
    () => messenger.setMockMethodCallHandler(
      channel,
      (call) async =>
          call.method == 'identity' ? {'thumbprint': 'Y2VydA'} : null,
    ),
  );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  testWidgets(
    'open kitchen route follows settings-driven session replacement and revocation',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final first = controller(), second = controller();
      final current = StateProvider<KitchenPosController?>((ref) => first);
      final container = ProviderContainer(
        overrides: [
          kitchenPosProvider.overrideWith((ref) {
            final value = ref.watch(current);
            if (value != null) ref.onDispose(value.dispose);
            return value;
          }),
        ],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: KitchenOrdersPage()),
          ),
        );
        await tester.pump();
        expect(
          tester
              .widget<KitchenPosScreen>(find.byType(KitchenPosScreen))
              .controller,
          same(first),
        );
        container.read(current.notifier).state = second;
        await tester.pump();
        await tester.pump();
        expect(
          tester
              .widget<KitchenPosScreen>(find.byType(KitchenPosScreen))
              .controller,
          same(second),
        );
        container.read(current.notifier).state = null;
        await tester.pump();
        await tester.pump();
        expect(find.byType(KitchenPosScreen), findsNothing);
        expect(find.text('Connect kitchen'), findsNothing);
        expect(find.text('Sign in to open kitchen orders.'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        first.dispose();
        second.dispose();
        await tester.pump(const Duration(seconds: 1));
      }
    },
  );
}
