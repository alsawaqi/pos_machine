import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/draft_recovery/recovery_controller.dart';
import 'package:pos_machine/draft_recovery/recovery_models.dart';
import 'package:pos_machine/draft_recovery/recovery_screen.dart';
import 'package:pos_machine/draft_recovery/recovery_store.dart';
import 'bill_combine_screen_test.dart' show NoDatabase;
import 'draft_recovery_test.dart'
    show RecoveryHarness, RecoveryFake, previewValue, recoveryId;

/// Only the view is isolated here; model validation uses the exact same
/// synthetic original/ACK evidence as the real SQLite controller tests.
class RecoveryViewController extends RecoveryController {
  RecoveryViewController(
    this.snapshot, {
    this.pending = false,
    this.blocked = false,
    this.legacy = false,
  }) : super(
         store: RecoveryStore(NoDatabase(), 'screen'),
         gateway: RecoveryFake(),
         dineIn: RecoveryFake(),
         tableId: 1,
         loadLocal: (_) async => snapshot,
         checkIdle: () async {},
         admit: (operation) => operation(),
         onRetired: (_) async {},
       );
  final RecoveryLocal snapshot;
  final bool pending, blocked, legacy;
  int confirms = 0, sends = 0;
  final confirmedIds = <String>[];

  RecoveryAttempt intent() => RecoveryAttempt({
    'id': recoveryId,
    'state': 'pending',
    'local': snapshot.json,
    'preview': previewValue(legacy: legacy),
    'delta': snapshot.delta(RecoveryPreview(previewValue(legacy: legacy))),
  });

  @override
  Future<void> start() async {
    ready = true;
    if (blocked) {
      error = 'The original draft cannot be proved. Keep every original copy.';
    } else {
      local = snapshot;
      preview = RecoveryPreview(previewValue(legacy: legacy));
      if (pending) attempt = intent();
    }
    changed();
  }

  @override
  Future<void> confirm() async {
    confirms++;
    final original = attempt ?? intent();
    confirmedIds.add(original.id);
    final ack = recoveryMap(
      recoveryMap(RecoveryFake().ack(original.payload)['data'])['result'],
    );
    attempt = original.change(original.delta.isEmpty ? 'done' : 'delta_ready', {
      'ack': ack,
    });
    changed();
  }

  @override
  Future<void> sendSavedAdditions() async {
    sends++;
    // Wire identity, persistence and replay are checked by controller tests.
    changed();
  }
}

void main() {
  sqfliteFfiInit();

  Future<RecoveryLocal> snapshot({bool legacy = false}) async {
    final harness = RecoveryHarness();
    await harness.init(qty: legacy ? 2 : 3, legacy: legacy);
    try {
      return await harness.local(1);
    } finally {
      await harness.close();
    }
  }

  Future<void> open(
    WidgetTester tester,
    RecoveryViewController controller, {
    bool arabic = false,
  }) async {
    tester.view.physicalSize = const Size(1000, 1800);
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
                  builder: (_) => RecoveryScreen(
                    createController: () async => controller,
                    arabic: arabic,
                  ),
                ),
              ),
              child: const Text('Open recovery'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open recovery'));
    await tester.pumpAndSettle();
  }

  testWidgets('review separates original, received and unsent quantities', (
    tester,
  ) async {
    final local = await tester.runAsync(() => snapshot());
    final c = RecoveryViewController(local!);
    await open(tester, c);
    expect(find.text('Original local draft'), findsOneWidget);
    expect(find.text('Already received from this device'), findsOneWidget);
    expect(find.text('Saved unsent additions'), findsOneWidget);
    expect(find.text('3 × Coffee'), findsOneWidget);
    expect(find.text('2 × Coffee'), findsOneWidget);
    expect(find.text('1 × Coffee'), findsOneWidget);
    expect(find.text('T-1'), findsOneWidget);
    expect(c.confirms, 0);
    expect(c.sends, 0);
    expect(c.attempt, isNull);
  });

  testWidgets('confirmed recovery never automatically sends saved additions', (
    tester,
  ) async {
    final local = await tester.runAsync(() => snapshot());
    final c = RecoveryViewController(local!);
    await open(tester, c);
    await tester.tap(find.byKey(const ValueKey('draft-recovery-confirm')));
    await tester.pumpAndSettle();
    expect(c.confirms, 1);
    expect(c.attempt!.state, 'delta_ready');
    expect(c.sends, 0);
    expect(find.text('Send saved additions'), findsOneWidget);
    expect(
      find.textContaining('received items are not sent again'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('draft-recovery-send')));
    await tester.pumpAndSettle();
    expect(c.sends, 1);
    expect(c.confirms, 1);
  });

  testWidgets('pending recovery blocks back and retries the saved identity', (
    tester,
  ) async {
    final local = await tester.runAsync(() => snapshot());
    final c = RecoveryViewController(local!, pending: true);
    await open(tester, c);
    final originalId = c.attempt!.id;
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draft-recovery-review')), findsOneWidget);
    expect(c.confirms, 0);
    expect(find.text('Retry saved recovery'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('draft-recovery-confirm')));
    await tester.pumpAndSettle();
    expect(c.confirmedIds, [originalId]);
    expect(c.attempt!.id, originalId);
    expect(c.sends, 0);
  });

  testWidgets(
    'zero-delta confirmation returns to same-bill host without send',
    (tester) async {
      final local = await tester.runAsync(() => snapshot(legacy: true));
      final c = RecoveryViewController(local!, legacy: true);
      await open(tester, c);
      await tester.tap(find.byKey(const ValueKey('draft-recovery-confirm')));
      await tester.pumpAndSettle();
      expect(c.attempt!.state, 'done');
      expect(find.byKey(const ValueKey('draft-recovery-send')), findsNothing);
      expect(c.sends, 0);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Open recovery'), findsOneWidget);
    },
  );

  testWidgets('Arabic review retains exact quantities and RTL actions', (
    tester,
  ) async {
    final local = await tester.runAsync(() => snapshot());
    final c = RecoveryViewController(local!);
    await open(tester, c, arabic: true);
    expect(find.text('المسودة المحلية الأصلية'), findsOneWidget);
    expect(find.text('تم الاستلام من هذا الجهاز'), findsOneWidget);
    expect(find.text('إضافات محفوظة غير مرسلة'), findsOneWidget);
    expect(find.text('3 × Coffee'), findsOneWidget);
    expect(find.text('2 × Coffee'), findsOneWidget);
    expect(find.text('1 × Coffee'), findsOneWidget);
    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('draft-recovery-confirm'))),
      ),
      TextDirection.rtl,
    );
    expect(c.confirms, 0);
    expect(c.sends, 0);
  });

  testWidgets('background disables confirmation without discarding originals', (
    tester,
  ) async {
    final local = await tester.runAsync(() => snapshot());
    final c = RecoveryViewController(local!);
    await open(tester, c);
    c.setForeground(false);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('draft-recovery-confirm')),
          )
          .onPressed,
      isNull,
    );
    expect(c.local!.encoded, local.encoded);
    expect(c.confirms, 0);
    expect(c.sends, 0);
  });

  testWidgets('unprovable draft has explanation and no archive action', (
    tester,
  ) async {
    final local = await tester.runAsync(() => snapshot());
    final c = RecoveryViewController(local!, blocked: true);
    await open(tester, c);
    expect(find.textContaining('Keep every original copy'), findsOneWidget);
    expect(find.byKey(const ValueKey('draft-recovery-confirm')), findsNothing);
    expect(find.byKey(const ValueKey('draft-recovery-send')), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Open recovery'), findsOneWidget);
    expect(c.confirms, 0);
    expect(c.sends, 0);
  });
}
