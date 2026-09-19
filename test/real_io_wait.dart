import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

/// Pump UI frames while real SQLite/HTTP-fixture work completes. Unlike a fixed
/// frame count, load on other test isolates does not consume the wait budget.
Future<void> pumpUntilRealCondition(
  WidgetTester tester,
  FutureOr<bool> Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final elapsed = Stopwatch()..start();
  while (elapsed.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 20));
    if (await tester.runAsync(() async => await condition()) == true) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Timed out waiting for $reason after ${elapsed.elapsed}');
}
