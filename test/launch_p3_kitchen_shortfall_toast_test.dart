// LAUNCH-P3 (review L6, device side): when a kitchen batch starts although
// the books could not cover it, the server's start answer lists the short
// ingredients (`data.ingredient_shortfalls`); the till names them after
// Start instead of saying only "ingredients deducted".
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/kitchen_production.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/kitchen_production_screen.dart';
import 'package:pos_machine/services/pos_api_service.dart';

void main() {
  test(
    'startProduction carries the short ingredients of the start answer',
    () async {
      final api = PosApiService(
        tokenGetter: () => 'token',
        dio: Dio(BaseOptions(baseUrl: 'https://pos.test/api/v1'))
          ..httpClientAdapter = _StartAnswer(),
      );

      final batch = await api.startProduction(productId: 1, quantity: 11);

      expect(batch.uuid, 'p-1');
      expect(batch.shortIngredientNames, ['Flour']);
    },
  );

  test('an answer without shortfalls (older servers) means none', () {
    final batch = ProductionBatch.fromJson({'uuid': 'p-1', 'status': 'x'});
    expect(batch.shortIngredientNames, isEmpty);
  });

  testWidgets('after Start the till names what the books were short on', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The test font draws every glyph as a full square, so the existing
    // extras header row of the fixed-width dialog overflows here (not with
    // the device font). Ignore only that layout warning.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiServiceProvider.overrideWithValue(_KitchenApi())],
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const KitchenProductionScreen(staffId: 7, staffName: 'Sami'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Cake'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Start batch'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(
        'Batch started. The books were short on: Flour. Those balances are '
        'now below zero.',
      ),
      findsOneWidget,
    );
  });
}

class _StartAnswer implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'data': {
        'production': {
          'uuid': 'p-1',
          'status': 'in_progress',
          'product_id': 1,
          'product_name': 'Cake',
          'quantity': 11,
          'lines': <Object>[],
        },
        'ingredient_shortfalls': [
          {
            'ingredient_id': 1,
            'name': 'Flour',
            'unit': 'kg',
            'needed': '5.5000',
            'available': '5.0000',
          },
        ],
      },
      'errors': <Object>[],
    }),
    201,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _KitchenApi implements PosApiService {
  @override
  Future<KitchenData> fetchKitchen() async => KitchenData.fromJson({
    'products': [
      {
        'id': 1,
        'uuid': 'u-1',
        'name': 'Cake',
        'name_ar': null,
        'category_id': 7,
        'branch_stock_qty': 0.0,
        'max_producible': 0,
        'recipe': [
          {
            'ingredient_id': 1,
            'name': 'Flour',
            'name_ar': null,
            'quantity': 0.5,
            'unit': 'kg',
            'branch_balance': 0.2,
          },
        ],
      },
    ],
    'ingredients': [
      {'id': 1, 'name': 'Flour', 'unit': 'kg', 'branch_balance': 0.2},
    ],
    'active': <Object>[],
  });

  @override
  Future<ProductionBatch> startProduction({
    required int productId,
    required int quantity,
    int? staffId,
    List<({int ingredientId, double quantity})> extras = const [],
  }) async => ProductionBatch.fromJson({
    'uuid': 'p-1',
    'status': 'in_progress',
    'product_id': productId,
    'product_name': 'Cake',
    'quantity': quantity,
    'lines': <Object>[],
    'ingredient_shortfalls': [
      {'ingredient_id': 1, 'name': 'Flour'},
    ],
  });

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
