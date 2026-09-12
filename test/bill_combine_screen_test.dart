import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pos_machine/bill_combine/combine_controller.dart';
import 'package:pos_machine/bill_combine/combine_models.dart';
import 'package:pos_machine/bill_combine/combine_screen.dart';
import 'package:pos_machine/bill_combine/combine_store.dart';
import 'bill_combine_test.dart'
    show Gateway, localSnapshot, previewJson, seatingId, ack;

class NoDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('UI must not access a database directly');
}

class ScreenController extends CombineController {
  ScreenController({this.pending = false})
    : super(
        store: CombineStore(NoDatabase(), 'screen'),
        gateway: Gateway(),
        tableId: 1,
        loadLocal: (_) async => localSnapshot(),
        checkIdle: () async {},
      );
  final bool pending;
  final pins = <String>[];
  @override
  Future<void> start() async {
    ready = true;
    local = localSnapshot();
    preview = CombinePreview(previewJson());
    if (pending) {
      attempt = CombineAttempt({
        'id': seatingId,
        'state': 'pending',
        'local': local!.json,
        'preview': preview!.json,
      });
    }
    changed();
  }

  @override
  Future<void> confirm(String pin) async {
    pins.add(pin);
    attempt = CombineAttempt({
      'id': seatingId,
      'state': 'done',
      'ack': ack(),
      'local': local!.json,
      'preview': preview!.json,
    });
    changed();
  }
}

void main() {
  Future<void> open(
    WidgetTester tester,
    ScreenController controller, {
    bool arabic = false,
  }) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CombineScreen(
                    arabic: arabic,
                    createController: () async => controller,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows both frozen bills, retained QR reference and combined total',
    (tester) async {
      final controller = ScreenController();
      await open(tester, controller);
      expect(find.text('Original staff bill'), findsOneWidget);
      expect(find.text('QR bill to keep'), findsOneWidget);
      expect(find.text('OLD'), findsOneWidget);
      expect(find.text('T-001'), findsOneWidget);
      expect(find.text('Combined total: OMR 2.000'), findsOneWidget);
      expect(find.text('1 × Coffee'), findsNWidgets(2));
      expect(controller.pins, isEmpty);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
    },
  );
  testWidgets(
    'PIN is obscured, passed only on approval and immediately cleared',
    (tester) async {
      final controller = ScreenController();
      await open(tester, controller);
      final field = find.byKey(const ValueKey('combine-pin'));
      expect(tester.widget<TextField>(field).obscureText, true);
      await tester.enterText(field, '4321');
      await tester.ensureVisible(find.byKey(const ValueKey('combine-confirm')));
      await tester.tap(find.byKey(const ValueKey('combine-confirm')));
      await tester.pumpAndSettle();
      expect(controller.pins, ['4321']);
      expect(find.text('4321'), findsNothing);
      expect(find.byKey(const ValueKey('combine-result')), findsOneWidget);
    },
  );
  testWidgets(
    'pending recovery blocks back navigation and cannot silently discard intent',
    (tester) async {
      final controller = ScreenController(pending: true);
      await open(tester, controller);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('combine-review')), findsOneWidget);
      expect(find.byKey(const ValueKey('combine-pending')), findsOneWidget);
      expect(controller.pins, isEmpty);
      expect(controller.attempt!.state, 'pending');
    },
  );
  testWidgets('Arabic review has the same bills and amount in RTL', (
    tester,
  ) async {
    await open(tester, ScreenController(), arabic: true);
    expect(find.text('فاتورة الموظف الأصلية'), findsOneWidget);
    expect(find.text('فاتورة QR التي ستبقى'), findsOneWidget);
    expect(find.text('الإجمالي بعد الدمج: OMR 2.000'), findsOneWidget);
    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('combine-total'))),
      ),
      TextDirection.rtl,
    );
  });
}
