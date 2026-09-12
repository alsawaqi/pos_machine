import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/order_workspace/workspace_void.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'qr_quick_gateway_test.dart' show QuickAdapter;
import 'qr_quick_controller_test.dart' show FakeQuickGateway, MemoryQuickStore;
import 'unified_dine_in_test.dart' show TableFake, TableMemory;

Map<String, dynamic> voidPreview() => {
  'order': {
    'uuid': 'bill-1',
    'status': 'held',
    'temp_reference': 'Q-007',
    'grand_total_baisas': 1000,
    'items': [
      {'name': 'Coffee', 'qty': 1, 'line_total_baisas': 1000},
    ],
  },
  'pending_rounds': 1,
  'preview_token': 'synthetic-signed-preview',
};

class VoidFake implements WorkspaceVoidGateway {
  final requests = <Map<String, dynamic>>[];
  Object? failure;
  Completer<void>? wait;
  @override
  Future<WorkspaceVoidPreview> preview(String uuid) async =>
      WorkspaceVoidPreview(uuid, voidPreview());
  @override
  Future<void> cancel(
    WorkspaceVoidPreview preview,
    String pin,
    String reason,
  ) async {
    requests.add({'uuid': preview.uuid, 'pin': pin, 'reason': reason});
    await wait?.future;
    if (failure != null) throw failure!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'identity uncertainty never claims a server-side refusal or success',
    () {
      expect(
        workspaceVoidError(StateError('identity changed after reply'), false),
        startsWith('Cancellation is not confirmed.'),
      );
      expect(
        workspaceVoidError(StateError('identity changed after reply'), true),
        startsWith('لم يتم تأكيد الإلغاء.'),
      );
    },
  );
  test(
    'old managed 004 and active evidence remain blocked without journal mutation',
    () {
      for (final state in [
        'claiming',
        'uncertain',
        'releasing',
        'managed',
        'paid',
      ]) {
        final attempt = CheckoutAttempt(
          id: 'intent',
          orderUuid: '004',
          state: state,
          createdAt: DateTime.utc(2026),
        );
        final rows = [
          {
            'id': attempt.id,
            'state': state,
            'payload': jsonEncode(attempt.json),
          },
        ];
        final before = jsonEncode(rows);
        expect(
          () => assertWorkspaceVoidAttempts(rows, '004'),
          throwsStateError,
        );
        expect(jsonEncode(rows), before);
        if (const ['paid', 'managed'].contains(state)) {
          assertWorkspaceVoidAttempts(rows, 'unrelated');
        } else {
          expect(
            () => assertWorkspaceVoidAttempts(rows, 'unrelated'),
            throwsStateError,
          );
        }
      }
    },
  );
  test('released evidence stays read-only; corrupt journal is fail-closed', () {
    final a = CheckoutAttempt(
      id: 'intent',
      orderUuid: 'bill-1',
      state: 'released',
      createdAt: DateTime.utc(2026),
    );
    final rows = [
      {'id': a.id, 'state': a.state, 'payload': jsonEncode(a.json)},
    ];
    assertWorkspaceVoidAttempts(rows, 'bill-1');
    rows.single['state'] = 'managed';
    expect(() => assertWorkspaceVoidAttempts(rows, 'bill-1'), throwsStateError);
  });
  test(
    'preview is frozen and refuses wrong UUID, terminal status and malformed money',
    () {
      final data = voidPreview();
      final p = WorkspaceVoidPreview('bill-1', data);
      ((data['order'] as Map)['items'] as List).clear();
      expect(p.items.single['name'], 'Coffee');
      expect(() => (p.order['items'] as List).clear(), throwsUnsupportedError);
      expect(
        () => WorkspaceVoidPreview('other', voidPreview()),
        throwsFormatException,
      );
      for (final change in [
        {'status': 'paid'},
        {'grand_total_baisas': '1.000'},
      ]) {
        final malformed = voidPreview();
        (malformed['order'] as Map).addAll(change);
        expect(
          () => WorkspaceVoidPreview('bill-1', malformed),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'authenticated online preview/post uses only exact UUID, proof, PIN and reason',
    () async {
      final adapter = QuickAdapter()
        ..data = {'data': voidPreview(), 'errors': []};
      final dio = Dio(BaseOptions(baseUrl: 'http://synthetic.invalid/api/v1'))
        ..httpClientAdapter = adapter;
      final api = PosApiService(tokenGetter: () => 'device-token', dio: dio);
      var guards = 0;
      final gateway = ApiWorkspaceVoidGateway(api, () => 'scope', (uuid) async {
        expect(uuid, 'bill-1');
        guards++;
      });
      final preview = await gateway.preview('bill-1');
      adapter.data = {
        'data': {
          'order_uuid': 'bill-1',
          'status': 'void',
          'already_void': false,
        },
        'errors': [],
      };
      await gateway.cancel(preview, '4321', 'Customer cancelled');
      expect(guards, 2);
      expect(adapter.requests.map((r) => r.path), [
        '/device/qr/orders/bill-1/void-preview',
        '/device/qr/orders/bill-1/void',
      ]);
      expect(adapter.requests.last.data, {
        'preview_token': preview.token,
        'pin': '4321',
        'reason': 'Customer cancelled',
      });
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer device-token',
      );
    },
  );
  test(
    'scope and local guard changes block POST; malformed ACK cannot report success',
    () async {
      final adapter = QuickAdapter()
        ..data = {'data': voidPreview(), 'errors': []};
      final dio = Dio(BaseOptions(baseUrl: 'http://synthetic.invalid/api/v1'))
        ..httpClientAdapter = adapter;
      final api = PosApiService(tokenGetter: () => 'device-token', dio: dio);
      var scope = 'scope', blocked = false;
      final gateway = ApiWorkspaceVoidGateway(api, () => scope, (_) async {
        if (blocked) throw StateError('pending payment');
      });
      final preview = await gateway.preview('bill-1');
      blocked = true;
      await expectLater(
        gateway.cancel(preview, '4321', 'reason'),
        throwsStateError,
      );
      blocked = false;
      scope = 'other';
      await expectLater(
        gateway.cancel(preview, '4321', 'reason'),
        throwsStateError,
      );
      expect(adapter.requests.length, 1);
      scope = 'scope';
      adapter.data = {
        'data': {
          'order_uuid': 'other',
          'status': 'void',
          'already_void': false,
        },
        'errors': [],
      };
      await expectLater(
        gateway.cancel(preview, '4321', 'reason'),
        throwsFormatException,
      );
      expect(adapter.requests.length, 2);
    },
  );
  for (final ar in [false, true]) {
    testWidgets(
      'review ${ar ? "AR" : "EN"}: Back writes nothing, explicit approval once, busy blocks dismiss',
      (tester) async {
        final fake = VoidFake();
        final results = <bool>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => results.add(
                    await showWorkspaceVoid(
                      context,
                      fake,
                      'bill-1',
                      arabic: ar,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Q-007'), findsOneWidget);
        expect(find.text('1 × Coffee'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('void-keep')));
        await tester.pumpAndSettle();
        expect(fake.requests, isEmpty);
        expect(results, [false]);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('void-confirm')));
        await tester.pumpAndSettle();
        expect(fake.requests, isEmpty);
        await tester.enterText(find.byKey(const ValueKey('void-pin')), '4321');
        await tester.enterText(
          find.byKey(const ValueKey('void-reason')),
          'Customer cancelled',
        );
        fake.wait = Completer<void>();
        await tester.tap(find.byKey(const ValueKey('void-confirm')));
        await tester.pump();
        expect(
          tester
              .widget<TextButton>(find.byKey(const ValueKey('void-keep')))
              .onPressed,
          null,
        );
        expect(fake.requests, [
          {'uuid': 'bill-1', 'pin': '4321', 'reason': 'Customer cancelled'},
        ]);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byKey(const ValueKey('void-reference')), findsOneWidget);
        fake.wait!.complete();
        await tester.pumpAndSettle();
        expect(results, [false, true]);
        expect(fake.requests.length, 1);
      },
    );
  }
  testWidgets('lost reply never says success and disables another send', (
    tester,
  ) async {
    final fake = VoidFake()..failure = const FormatException('lost reply');
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showWorkspaceVoid(
                context,
                fake,
                'bill-1',
                arabic: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('void-pin')), '4321');
    await tester.enterText(
      find.byKey(const ValueKey('void-reason')),
      'Customer cancelled',
    );
    await tester.tap(find.byKey(const ValueKey('void-confirm')));
    await tester.pumpAndSettle();
    expect(result, null);
    expect(
      find.textContaining('Cancellation is not confirmed'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('void-confirm')))
          .onPressed,
      null,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('void-pin')))
          .controller!
          .text,
      '',
    );
    await tester.tap(find.byKey(const ValueKey('void-keep')));
    await tester.pumpAndSettle();
    expect(result, false);
    expect(fake.requests.length, 1);
  });
  for (final table in [false, true]) {
    testWidgets(
      '${table ? "table" : "quick"} workspace void excludes pay/add/exit and targets existing bill',
      (tester) async {
        final gate = Completer<bool>();
        final ids = <String>[];
        var exits = 0;
        final workspace = CurrentOrderWorkspace(onExit: () => exits++);
        final quick = QrQuickController(FakeQuickGateway(), MemoryQuickStore());
        final dine = DineInController(TableFake(), TableMemory(), 2);
        Future<bool> cancel(String id) {
          ids.add(id);
          return gate.future;
        }

        final child = table
            ? DineInScreen(
                workspace: workspace,
                label: 'T2',
                createController: () async => dine,
                catalogue: () => [],
                onPay: (_) async => fail('unexpected pay'),
                onVoid: cancel,
              )
            : QrQuickScreen(
                workspace: workspace,
                workspaceUuid: 'bill-1',
                createController: () async => quick,
                catalogue: () => [],
                onPay: (_, _) async => fail('unexpected pay'),
                onVoid: cancel,
              );
        await tester.pumpWidget(MaterialApp(home: child));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextButton>(find.byKey(const ValueKey('workspace-void')))
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(const ValueKey('workspace-void')));
        await tester.pump();
        expect(ids, ['bill-1']);
        expect(workspace.canAdd, false);
        expect(workspace.canPay, false);
        await workspace.requestPay();
        await workspace.requestClose();
        expect(exits, 0);
        gate.complete(false);
        await tester.pumpAndSettle();
        expect(exits, 0);
        expect(workspace.bill!.uuid, 'bill-1');
        await tester.pumpWidget(const SizedBox.shrink());
        workspace.dispose();
        if (table) {
          quick.dispose();
        } else {
          dine.dispose();
        }
      },
    );
    testWidgets(
      '${table ? "table" : "quick"} unsent draft and stale read disable void',
      (tester) async {
        final workspace = CurrentOrderWorkspace(onExit: () {});
        final quick = QrQuickController(FakeQuickGateway(), MemoryQuickStore());
        final dine = DineInController(TableFake(), TableMemory(), 2);
        Future<bool> cancel(String _) async => fail('Unexpected cancellation');
        final child = table
            ? DineInScreen(
                workspace: workspace,
                label: 'T2',
                createController: () async => dine,
                catalogue: () => [const QuickProduct(7, 'Water')],
                onPay: (_) async {},
                onVoid: cancel,
              )
            : QrQuickScreen(
                workspace: workspace,
                workspaceUuid: 'bill-1',
                createController: () async => quick,
                catalogue: () => [const QuickProduct(7, 'Water')],
                onVoid: cancel,
              );
        await tester.pumpWidget(MaterialApp(home: child));
        await tester.pumpAndSettle();
        if (table) {
          dine.setForeground(false);
        } else {
          quick.invalidate();
        }
        await tester.pump();
        expect(
          tester
              .widget<TextButton>(find.byKey(const ValueKey('workspace-void')))
              .onPressed,
          null,
        );
        if (table) {
          dine.setForeground(true);
          await dine.refresh();
        } else {
          await quick.refresh();
        }
        await tester.pumpAndSettle();
        final picking = workspace.pick(const QuickProduct(7, 'Water'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('quick-option-add')));
        await tester.pumpAndSettle();
        await picking;
        expect(
          tester
              .widget<TextButton>(find.byKey(const ValueKey('workspace-void')))
              .onPressed,
          null,
        );
        if (table) {
          dine.setForeground(false);
        } else {
          quick.invalidate();
        }
        await tester.pump();
        expect(
          tester
              .widget<TextButton>(find.byKey(const ValueKey('workspace-void')))
              .onPressed,
          null,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        workspace.dispose();
        if (table) {
          quick.dispose();
        } else {
          dine.dispose();
        }
      },
    );
  }
}
