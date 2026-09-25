// Real till, HTTP boundary gates, hardware channels, and file-backed SQLite.
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 't12_fix2_customer_harness.dart';
import 'real_io_wait.dart';

const lookupEn = 'Customer lookup in progress — wait a moment, then pay again';
const splitEn =
    'Part of this bill is already paid — the customer and discount can no longer change';
const savingEn =
    'The table is still being saved — wait a moment, then try again';
const giftEn = 'Remove the loyalty redemption before gifting the order';
const deletedEn =
    'This customer no longer exists — the customer and any loyalty redemption were removed';
const changedCustomerEn = 'The customer changed. Open Redeem again.';

class HttpGate {
  HttpGate(this.match);
  final bool Function(RequestOptions) match;
  final release = Completer<void>();
  int hits = 0, delivered = 0;
}

class Fix3Server extends CustomerServer {
  final gates = <HttpGate>[];
  int detailsStatus = 200;
  bool emptyDetails = false, failSearch = false;
  int? plateReplyId;
  @override
  Dio dio() {
    final base = super.dio();
    final d = Dio();
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          for (final g in gates.toList()) {
            if (!g.release.isCompleted && g.hits == 0 && g.match(o)) {
              g.hits++;
              await g.release.future;
              g.delivered++;
            }
          }
          final details = RegExp(r'/device/customers/\d+$').hasMatch(o.path);
          final id = details ? int.parse(o.path.split('/').last) : null;
          if (details && (!customers.containsKey(id) || detailsStatus != 200)) {
            h.reject(
              DioException(
                requestOptions: o,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: o,
                  statusCode: customers.containsKey(id) ? detailsStatus : 404,
                  data: {
                    'errors': [
                      {
                        'code': customers.containsKey(id)
                            ? 'temporary_error'
                            : 'customer_not_found',
                        'message': 'fixture',
                      },
                    ],
                  },
                ),
              ),
            );
            return;
          }
          if (details && emptyDetails) {
            h.resolve(
              Response(requestOptions: o, statusCode: 200, data: {'data': {}}),
            );
            return;
          }
          if (failSearch && o.path.endsWith('/search')) {
            h.reject(
              DioException(
                requestOptions: o,
                type: DioExceptionType.connectionError,
              ),
            );
            return;
          }
          try {
            final result = await base.fetch<dynamic>(o);
            if (o.method == 'POST' &&
                o.path.endsWith('/device/customers') &&
                plateReplyId != null) {
              result.data = {
                'data': {
                  'customer': {...profile(5), 'id': plateReplyId},
                },
              };
            }
            h.resolve(result);
          } on DioException catch (e) {
            h.reject(e);
          }
        },
      ),
    );
    return d;
  }
}

class Fix3Rig extends CustomerRig {
  Fix3Rig(super.tester, {super.arabic, super.stamps, this.online = false});
  final bool online;
  final Fix3Server _server = Fix3Server();
  @override
  Fix3Server get server => _server;
  @override
  bool get connectivityOnline => online;
  final notices = <String>[];
  final cardAmounts = <int>[];
  int managerCalls = 0;
  Completer<void>? cardGate, printGate;
  int cardHits = 0, printHits = 0;
  @override
  Future<void> settle([int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
    }
  }

  @override
  Future<void> closeNotice() async {
    final banner = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('staff-popup-'),
    );
    final close = find
        .descendant(of: banner, matching: find.byIcon(Icons.close_rounded))
        .hitTestable();
    if (close.evaluate().isNotEmpty) await tap(close.last);
  }

  Future<void> boot() async {
    await start();
    void channel(String name, Future<dynamic> Function(MethodCall) action) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), action);
    }

    channel('com.example.mosambee', (call) async {
      if (call.method != 'prepareLogin' &&
          call.method != 'cancelPendingOperation') {
        cardCalls++;
        cardHits++;
        final a = call.arguments as Map?;
        cardAmounts.add(
          (a?['amountBaisas'] as num?)?.toInt() ??
              ((a?['amount'] as num? ?? 0) * 1000).round(),
        );
        if (cardGate != null) await cardGate!.future;
      }
      return jsonEncode({
        'status': 'success',
        'responseCode': '00',
        'rrn': 'TEST',
      });
    });
    channel('sunmi_printer_plus', (call) async {
      printerCalls++;
      printHits++;
      if (printGate != null) await printGate!.future;
      return true;
    });
    channel('com.example.manager_biometrics', (call) async {
      managerCalls++;
      return true;
    });
    final original = c.onDraftRedemptionCleared;
    c.onDraftRedemptionCleared = (m) {
      notices.add(m);
      original?.call(m);
    };
    addTearDown(() {
      for (final g in [
        ...server.gates.map((g) => g.release),
        cardGate,
        printGate,
      ]) {
        if (g != null && !g.isCompleted) g.complete();
      }
    });
  }

  Future<void> ready({bool redeem = true, int customer = 5}) async {
    await boot();
    await add();
    await payPage();
    await attach(customer);
    if (redeem) await this.redeem();
    await closeNotice();
  }

  HttpGate gate(String kind, {String? query}) {
    final g = HttpGate(
      (o) => kind == 'details'
          ? RegExp(r'/device/customers/\d+$').hasMatch(o.path)
          : o.path.endsWith('/search') &&
                (query == null || o.queryParameters['q'] == query),
    );
    server.gates.add(g);
    return g;
  }

  Finder dialog(Finder f) =>
      find.descendant(of: find.byType(Dialog).last, matching: f);
  Future<void> keyboard(String digits) async {
    final field = find.byKey(const ValueKey('payment-customer-number'));
    await pumpUntilRealCondition(
      tester,
      () => field.hitTestable().evaluate().isNotEmpty,
      reason: 'customer keypad field ready',
    );
    // The parent contains trailing action buttons; tap its phone icon area.
    await tester.tapAt(tester.getTopLeft(field) + const Offset(20, 20));
    await settle();
    await tap(dialog(find.text(l.posKeyboardClear)));
    for (final ch in digits.split('')) {
      await tap(
        dialog(
          find.ancestor(
            of: find.text(ch),
            matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_KeyboardKey',
            ),
          ),
        ),
      );
    }
    await tap(dialog(find.text(l.commonDone)));
  }

  Future<void> plate(String plate) async {
    await tap(find.byKey(const ValueKey('payment-plate-search')));
    await tap(dialog(find.text(l.posKeyboardClear)));
    for (final ch in plate.split('')) {
      await tap(
        dialog(
          find.ancestor(
            of: find.text(ch),
            matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_KeyboardKey',
            ),
          ),
        ),
      );
    }
    await tap(dialog(find.text(l.commonDone)));
  }

  Future<void> lookup(String kind, {String query = '96890000002'}) async {
    if (kind == 'details') {
      await tap(find.byKey(const ValueKey('payment-customer-details')));
    } else if (kind == 'plate') {
      await plate(query == '96890000002' ? 'B123' : query);
    } else {
      await keyboard(query);
    }
  }

  Future<void> method(String label) => tap(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_PaymentMethodActionButton',
      ),
    ),
  );
  Future<void> amount(String value) async {
    await tap(find.text('10 OMR'));
    for (var i = 0; i < 6; i++) {
      await tap(find.byKey(const ValueKey('payment-key-backspace')));
    }
    for (final ch in value.split('')) {
      await tap(
        find.byKey(
          ValueKey(ch == '.' ? 'payment-key-decimal' : 'payment-key-$ch'),
        ),
      );
    }
  }

  Future<void> finishCash({double? expected}) async {
    await closeNotice();
    if (expected != null) {
      await amount(expected.toStringAsFixed(3));
      await method(l.posPaymentCash);
    } else {
      await cash();
    }
  }

  Future<void> finishCard() async {
    await method(l.posPaymentCard);
    await pumpUntilRealCondition(
      tester,
      () => c.showCharityRoundUpPrompt || cardHits > 0,
      reason: 'card prompt or launch',
    );
    if (c.showCharityRoundUpPrompt) {
      await tap(find.text(l.posCharityKeepOriginalTotal));
    }
  }

  Future<void> released(HttpGate g) async {
    g.release.complete();
    await pumpUntilRealCondition(
      tester,
      () => g.delivered > 0 && !lookupBusy,
      reason: 'lookup released',
    );
    await settle(2);
  }

  bool clearCustomer() {
    try {
      return (c as dynamic).clearAttachedCustomer() as bool;
    } on NoSuchMethodError {
      c.setCustomerReferenceNumber('');
      return true;
    }
  }

  Map<String, dynamic> identity() => {
    'customer': c.selectedCustomer?.id,
    'reference': c.customerReferenceNumber,
    'earn': c.selectedEarnRuleIds,
    'rule': c.loyaltyRedeemRuleId,
    'points': c.loyaltyRedeemPoints,
    'stamps': c.loyaltyRedeemStamps,
    'owner': c.loyaltyRedeemCustomerId,
    'discount': c.discount.toMap(),
    'plate': c.vehiclePlateNumber,
    'items': c.snapshot().items,
  };
  Future<Map<String, int>> effects() async => {
    'card': cardCalls,
    'printer': printerCalls,
    'manager': managerCalls,
    'number': server.allocations,
    'outbox': (await drive(
      () => driftDb.select(driftDb.orderOutbox).get(),
    ))!.length,
    'history': (await drive(() => localDb.query('order_history')))!.length,
  };
  Future<void> noEffects(String name, Map<String, int> before) async {
    final after = await effects();
    expect(after, before);
    expect(c.isProcessingPayment, false);
    // ignore: avoid_print
    print(
      'FIX3_REFUSAL ${jsonEncode({'case': name, 'counts': after, 'before': before, 'message': c.lastPaymentMessage, 'identity': identity()})}',
    );
  }

  Future<Completer<void>> holdDb() async {
    final release = Completer<void>(), entered = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    await tester.runAsync(() async {
      unawaited(
        localDb.transaction((txn) async {
          entered.complete();
          await release.future;
        }),
      );
    });
    await pumpUntilRealCondition(
      tester,
      () => entered.isCompleted,
      reason: 'SQLite transaction held',
    );
    return release;
  }

  Future<void> tableOpen(String id) async {
    await tap(find.text('Table $id').first);
    await pumpUntilRealCondition(
      tester,
      () => c.activeDiningTableId == id && !tableBusy && !lookupBusy,
      reason: 'table open completed',
    );
  }

  Future<void> floor() async {
    await tap(find.text('Back To Floor').first);
    await pumpUntilRealCondition(
      tester,
      () => c.activeDiningTableId == null && !tableBusy,
      reason: 'table save completed',
    );
  }

  Future<void> quickFromFloor() async {
    await tap(find.byIcon(Icons.arrow_back_rounded).first);
    await pumpUntilRealCondition(
      tester,
      () => c.selectedOrderType == OrderType.quickOrder && !tableBusy,
      reason: 'floor back completed',
    );
  }

  void inject({bool wrongLabel = false}) {
    c.loyaltyRedeemRuleId = 11;
    c.loyaltyRedeemPoints = wrongLabel ? 0 : 100;
    c.loyaltyRedeemStamps = wrongLabel ? 5 : 0;
    c.loyaltyRedeemCustomerId = c.selectedCustomer?.id;
    c.discount = const DiscountConfiguration(
      kind: DiscountKind.fixedAmount,
      value: 0.5,
      label: 'Loyalty redemption',
    );
    c.setVehiclePlateNumber(c.vehiclePlateNumber);
  }

  Future<void> measured(
    String name, {
    int? customer = 5,
    bool redeem = true,
    int posts = 0,
    bool delivery = false,
    List<int>? earn,
    double checked = 2.2,
  }) async {
    await checkMoney(
      name,
      customer: customer,
      redeem: redeem,
      posts: posts,
      delivery: delivery,
      earn: earn,
    );
    final order = server.orders.values.single;
    expect(order['grand_total_baisas'], (checked * 1000).round());
    if (!delivery) {
      final pay = server.events.singleWhere(
        (e) => e['event_type'] == 'order.pay',
      )['payload'];
      final parts = (pay['payments'] as List).cast<Map>();
      expect(
        parts.fold<int>(
          0,
          (sum, p) => sum + (p['amount_baisas'] as num).toInt(),
        ),
        (checked * 1000).round(),
      );
      if (cardAmounts.isNotEmpty) {
        expect(
          parts
              .where((p) => p['method'] == 'card')
              .fold<int>(
                0,
                (sum, p) => sum + (p['amount_baisas'] as num).toInt(),
              ),
          cardAmounts.reduce((a, b) => a + b),
        );
      }
    }
    // ignore: avoid_print
    print(
      'FIX3_MONEY ${jsonEncode({'case': name, 'checked_baisas': (checked * 1000).round(), 'order': order, 'payments': server.events.where((e) => e['event_type'] == 'order.pay' || e['event_type'] == 'order.deliver').toList(), 'acks': server.acknowledgements, 'posts': server.posts, 'balances': server.balances.map((id, rules) => MapEntry(id.toString(), rules.map((id, balance) => MapEntry(id.toString(), balance)))), 'plates': server.customers.map((k, v) => MapEntry(k.toString(), v['plates'])), 'card_baisas': cardAmounts})}',
    );
  }
}
