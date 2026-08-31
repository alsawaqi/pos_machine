import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/widgets/qr_round_print_status_indicator.dart';

void main() {
  testWidgets('English indicator is persistent, accessible, and LTR', (
    tester,
  ) async {
    await tester.pumpWidget(_host(arabic: false));

    const message =
        'QR kitchen printing cannot reach the server. '
        'New round printing may be delayed; retrying automatically.';
    final indicator = find.byKey(qrRoundPrintStatusIndicatorKey);

    expect(indicator, findsOneWidget);
    expect(find.text(message), findsOneWidget);
    expect(
      tester
          .widget<Directionality>(
            find.descendant(
              of: indicator,
              matching: find.byType(Directionality),
            ),
          )
          .textDirection,
      TextDirection.ltr,
    );
    final semantics = tester.getSemantics(indicator).getSemanticsData();
    expect(semantics.label, message);
    expect(semantics.flagsCollection.isLiveRegion, isTrue);
    expect(semantics.textDirection, TextDirection.ltr);

    await tester.pump(const Duration(seconds: 30));
    expect(indicator, findsOneWidget);
  });

  testWidgets('Arabic indicator is accessible and RTL', (tester) async {
    await tester.pumpWidget(_host(arabic: true));

    const message =
        'تعذّر اتصال طباعة طلبات QR للمطبخ بالخادم. '
        'قد تتأخر طباعة الجولات الجديدة؛ '
        'ستتم إعادة المحاولة تلقائيًا.';
    final indicator = find.byKey(qrRoundPrintStatusIndicatorKey);

    expect(find.text(message), findsOneWidget);
    expect(
      tester
          .widget<Directionality>(
            find.descendant(
              of: indicator,
              matching: find.byType(Directionality),
            ),
          )
          .textDirection,
      TextDirection.rtl,
    );
    final semantics = tester.getSemantics(indicator).getSemanticsData();
    expect(semantics.label, message);
    expect(semantics.flagsCollection.isLiveRegion, isTrue);
    expect(semantics.textDirection, TextDirection.rtl);
  });

  test('cursor-reset warning has explicit English and Arabic translations', () {
    expect(
      qrRoundPrintPositionResetMessage(arabic: false),
      'QR print position was reset. '
      'Rounds accepted before the reset may not have printed.',
    );
    expect(
      qrRoundPrintPositionResetMessage(arabic: true),
      'تمت إعادة ضبط موضع طباعة QR. '
      'قد لا تكون الجولات المقبولة قبل إعادة الضبط قد طُبعت.',
    );
  });

  testWidgets('healthy feed renders no status surface', (tester) async {
    await tester.pumpWidget(_host(arabic: false, unavailable: false));

    expect(find.byKey(qrRoundPrintStatusIndicatorKey), findsNothing);
  });
}

Widget _host({required bool arabic, bool unavailable = true}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: QrRoundPrintStatusIndicator(
        unavailable: unavailable,
        arabic: arabic,
      ),
    ),
  ),
);
