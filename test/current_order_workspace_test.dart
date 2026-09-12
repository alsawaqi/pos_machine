import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'qr_quick_controller_test.dart'
    show FakeQuickGateway, MemoryQuickStore, quickJson;
import 'unified_dine_in_test.dart' show TableFake, TableMemory, tableFixture;
import 'qr_quick_evidence.dart';

const water = QuickProduct(7, 'Water', nameAr: 'ماء');
void main() {
  test(
    'display-only snapshot is deeply frozen, detached and privacy whitelisted',
    () {
      final source = quickJson()
        ..addAll({'phone': 'private', 'client_secret': 'secret'});
      final bill = WorkspaceBill(source);
      (source['items'] as List).clear();
      expect(bill.items.single['product_name'], 'Coffee');
      expect(
        () => (bill.json['items'] as List).clear(),
        throwsUnsupportedError,
      );
      expect(
        () => (bill.json['items'] as List).first['qty'] = 99,
        throwsUnsupportedError,
      );
      expect(bill.uuid, 'bill-1');
      expect(bill.total, 1000);
      final encoded = jsonEncode(bill.display(stale: false));
      for (final secret in [
        'private',
        'secret',
        'bill-1',
        '1234',
        'order_item_id',
      ]) {
        expect(encoded, isNot(contains(secret)));
      }
      expect(bill.display(stale: true)['stale'], true);
    },
  );
  test('stale, malformed and missing bills never enable payment', () {
    final workspace = CurrentOrderWorkspace(onExit: () {});
    final owner = Object();
    workspace.attach(
      owner,
      pick: (_) async {},
      leave: () async {},
      pay: () async {},
    );
    workspace.publish(
      owner,
      order: quickJson(),
      stale: true,
      canAdd: true,
      canPay: true,
    );
    expect(workspace.canAdd, false);
    expect(workspace.canPay, false);
    workspace.publish(
      owner,
      order: quickJson()..['grand_total_baisas'] = '1.000',
      stale: false,
      canAdd: true,
      canPay: true,
    );
    expect(workspace.bill, null);
    expect(workspace.stale, true);
    expect(workspace.canPay, false);
    workspace.publish(
      owner,
      order: null,
      stale: false,
      canAdd: true,
      canPay: true,
    );
    expect(workspace.canPay, false);
    workspace.dispose();
  });
  test(
    'one editor owns the workspace; obsolete owners cannot publish or detach',
    () {
      final workspace = CurrentOrderWorkspace(onExit: () {});
      final owner = Object(), other = Object();
      workspace.attach(
        owner,
        pick: (_) async {},
        leave: () async {},
        pay: () async {},
      );
      expect(
        () => workspace.attach(
          other,
          pick: (_) async {},
          leave: () async {},
          pay: () async {},
        ),
        throwsStateError,
      );
      workspace.publish(
        owner,
        order: quickJson(),
        stale: false,
        canAdd: true,
        canPay: true,
      );
      workspace.publish(
        other,
        order: null,
        stale: true,
        canAdd: false,
        canPay: false,
      );
      workspace.detach(other);
      expect(workspace.bill!.uuid, 'bill-1');
      expect(workspace.canPay, true);
      workspace.dispose();
      workspace.detach(owner);
    },
  );
  test(
    'product dialog excludes parallel add/pay/leave and tolerates late completion',
    () async {
      final blocker = Completer<void>();
      final workspace = CurrentOrderWorkspace(
        onExit: () => fail('Unexpected exit'),
      );
      final owner = Object();
      var picks = 0, pays = 0, leaves = 0;
      workspace.attach(
        owner,
        pick: (_) async {
          picks++;
          await blocker.future;
        },
        leave: () async {
          leaves++;
        },
        pay: () async {
          pays++;
        },
      );
      workspace.publish(
        owner,
        order: quickJson(),
        stale: false,
        canAdd: true,
        canPay: true,
      );
      await workspace.pick(const QuickProduct(9, 'Sold out', available: false));
      expect(picks, 0);
      final pending = workspace.pick(water);
      await workspace.pick(water);
      await workspace.requestPay();
      await workspace.requestClose();
      expect([picks, pays, leaves], [1, 0, 0]);
      workspace.dispose();
      blocker.complete();
      await pending;
    },
  );

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester,
    Widget editor, {
    bool arabic = false,
  }) async {
    tester.view.resetPhysicalSize();
    await tester.binding.setSurfaceSize(const Size(720, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await loadQuickEvidenceFonts(tester);
    await tester.pumpWidget(
      RepaintBoundary(
        key: quickEvidenceKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'QuickEvidence'),
          home: Directionality(
            textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
            child: editor,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final arabic in [false, true]) {
    testWidgets(
      'embedded quick main catalogue appends same bill and uses guarded pay ${arabic ? "AR" : "EN"}',
      (tester) async {
        final api = FakeQuickGateway();
        final c = QrQuickController(api, MemoryQuickStore());
        var exits = 0;
        final payments = <String>[];
        final workspace = CurrentOrderWorkspace(
          onExit: () {
            exits++;
          },
        );
        await mount(
          tester,
          QrQuickScreen(
            createController: () async => c,
            catalogue: () => [water],
            arabic: arabic,
            workspace: workspace,
            workspaceUuid: 'bill-1',
            onPay: (_, order) async {
              payments.add(order.uuid);
            },
          ),
          arabic: arabic,
        );
        expect(workspace.bill!.reference, 'Q-007');
        expect(workspace.canAdd, true);
        expect(workspace.canPay, true);
        final picking = workspace.pick(water);
        await tester.pumpAndSettle();
        await tap(tester, 'quick-option-add');
        await picking;
        expect(workspace.canPay, false);
        await workspace.requestPay();
        expect(payments, isEmpty);
        await tap(tester, 'quick-submit');
        expect(api.requests.single.orderUuid, 'bill-1');
        expect(api.requests.single.payload['lines'], [
          {'product_id': 7, 'qty': 1, 'addon_ids': [], 'notes': null},
        ]);
        expect(workspace.bill!.total, 1200);
        await captureQuickEvidence(
          tester,
          'workspace-quick-${arabic ? "ar" : "en"}',
        );
        await workspace.requestPay();
        await tester.pumpAndSettle();
        expect(payments, ['bill-1']);
        await workspace.requestClose();
        expect(exits, 1);
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
      },
    );
  }
  testWidgets(
    'embedded quick Back prompts only for unsent additions; no network mutation',
    (tester) async {
      final api = FakeQuickGateway();
      final c = QrQuickController(api, MemoryQuickStore());
      var exits = 0;
      final workspace = CurrentOrderWorkspace(
        onExit: () {
          exits++;
        },
      );
      await mount(
        tester,
        QrQuickScreen(
          createController: () async => c,
          catalogue: () => [water],
          workspace: workspace,
          workspaceUuid: 'bill-1',
        ),
      );
      final picking = workspace.pick(water);
      await tester.pumpAndSettle();
      await tap(tester, 'quick-option-add');
      await picking;
      final closing = workspace.requestClose();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsent additions?'), findsOneWidget);
      expect(exits, 0);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await closing;
      expect(exits, 1);
      expect(api.requests, isEmpty);
      expect(api.orders.single.total, 1000);
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    },
  );
  testWidgets(
    'embedded quick lost reply blocks footer payment and keeps retry identity',
    (tester) async {
      final api = FakeQuickGateway()..lostResponse = true;
      final store = MemoryQuickStore();
      final c = QrQuickController(api, store);
      final workspace = CurrentOrderWorkspace(onExit: () {});
      await mount(
        tester,
        QrQuickScreen(
          createController: () async => c,
          catalogue: () => [water],
          workspace: workspace,
          workspaceUuid: 'bill-1',
          onPay: (_, _) async {
            fail('Uncertain order cannot pay');
          },
        ),
      );
      final picking = workspace.pick(water);
      await tester.pumpAndSettle();
      await tap(tester, 'quick-option-add');
      await picking;
      await tap(tester, 'quick-submit');
      final id = api.requests.single.id;
      expect(workspace.canPay, false);
      expect(workspace.canAdd, false);
      await workspace.requestPay();
      api.lostResponse = false;
      await tap(tester, 'quick-retry');
      expect(api.requests.last.id, id);
      expect(api.mutations, 1);
      expect(workspace.canPay, true);
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    },
  );
  testWidgets(
    'quick list hands exact UUID to main host without pushing old details',
    (tester) async {
      final opened = <String>[];
      await mount(
        tester,
        QrQuickScreen(
          createController: () async =>
              QrQuickController(FakeQuickGateway(), MemoryQuickStore()),
          catalogue: () => [water],
          onOpen: (id) async {
            opened.add(id);
          },
        ),
      );
      await tap(tester, 'quick-review-bill-1');
      expect(opened, ['bill-1']);
      expect(find.byKey(const ValueKey('quick-add-items')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final arabic in [false, true]) {
    testWidgets(
      'embedded joined table preserves canonical bill, rounds and server total ${arabic ? "AR" : "EN"}',
      (tester) async {
        final api = TableFake();
        final c = DineInController(api, TableMemory(), 2, staffId: 5);
        final workspace = CurrentOrderWorkspace(onExit: () {});
        final payments = <String>[];
        await mount(
          tester,
          DineInScreen(
            createController: () async => c,
            catalogue: () => [water],
            label: 'T2',
            arabic: arabic,
            workspace: workspace,
            onPay: (id) async {
              payments.add(id);
            },
          ),
          arabic: arabic,
        );
        expect(workspace.bill!.reference, 'T-006');
        expect(workspace.bill!.total, 4750);
        final picking = workspace.pick(water);
        await tester.pumpAndSettle();
        await tap(tester, 'quick-option-add');
        await picking;
        expect(workspace.canPay, false);
        await tap(tester, 'dine-send');
        expect(api.requests.single.payload['table_id'], 1);
        expect(api.requests.single.billUuid, 'bill-1');
        expect(api.requests.single.payload['lines'], [
          {'product_id': 7, 'qty': 1, 'addon_ids': [], 'notes': null},
        ]);
        expect(
          workspace.bill!.total,
          4750,
        ); // No local price is added to the server snapshot.
        await captureQuickEvidence(
          tester,
          'workspace-table-${arabic ? "ar" : "en"}',
        );
        await workspace.requestPay();
        await tester.pumpAndSettle();
        expect(payments, ['bill-1']);
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
      },
    );
  }
  testWidgets('unsent table items cannot migrate to a new seating on refresh', (
    tester,
  ) async {
    final api = TableFake();
    final c = DineInController(api, TableMemory(), 2, staffId: 5);
    final workspace = CurrentOrderWorkspace(onExit: () {});
    await mount(
      tester,
      DineInScreen(
        createController: () async => c,
        catalogue: () => [water],
        label: 'T2',
        workspace: workspace,
        onPay: (_) async {
          fail('Unsent draft cannot pay');
        },
      ),
    );
    final picking = workspace.pick(water);
    await tester.pumpAndSettle();
    await tap(tester, 'quick-option-add');
    await picking;
    final changed = tableFixture();
    (changed['seating'] as Map)['uuid'] =
        '22222222-2222-4222-8222-222222222222';
    (changed['bill'] as Map)['uuid'] = 'another-bill';
    api.value = changed;
    await tap(tester, 'dine-send');
    expect(api.requests, isEmpty);
    expect(workspace.canPay, false);
    expect(
      find.text('The bill changed. Review it before sending.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    workspace.dispose();
  });
  testWidgets(
    'pending table review and stale reads block the main payment footer',
    (tester) async {
      final api = TableFake()..value = tableFixture(pending: true);
      final c = DineInController(api, TableMemory(), 2, staffId: 5);
      final workspace = CurrentOrderWorkspace(onExit: () {});
      await mount(
        tester,
        DineInScreen(
          createController: () async => c,
          catalogue: () => [water],
          label: 'T2',
          workspace: workspace,
          onPay: (_) async {
            fail('Pending review cannot pay');
          },
        ),
      );
      expect(find.text('Confirm round'), findsOneWidget);
      expect(workspace.canPay, false);
      api.failRead = true;
      await c.refresh();
      await tester.pumpAndSettle();
      expect(workspace.stale, true);
      expect(workspace.canAdd, false);
      expect(workspace.canPay, false);
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    },
  );
}
