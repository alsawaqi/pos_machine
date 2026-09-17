import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'qr_quick_controller_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'accepted item addition does not wait for another inbox request',
    () async {
      final api = FakeQuickGateway();
      final c = QrQuickController(api, MemoryQuickStore());
      await c.start();
      expect(await c.add('bill-1', [QrQuickLine(7, 1, [])]), true);
      expect(api.fetches, 1);
      expect(c.find('bill-1')!.total, 1200);
      expect(c.canPay('bill-1'), true);
      c.dispose();
    },
  );
}
