import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/draft_recovery/checkout_recovery_dialog.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/screens/settings_screen.dart';
import 'package:pos_machine/core/manager_auth.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

class _Api implements PosApiService {
  int pins = 0;
  @override
  String Function() get tokenGetter =>
      () => 'fixture';
  @override
  String get quickOrderBaseUrl => 'http://fixture.invalid/api/v1';
  @override
  Future<List<Map<String, dynamic>>> fetchIncomingTransfers() async => [];
  bool approve = false;
  @override
  Future<ApproverVerification?> verifyApprover(String pin) async {
    pins++;
    return approve
        ? const ApproverVerification(staffId: 3, name: 'Mona')
        : null;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected API ${i.memberName}');
}

Future<void> tick(WidgetTester tester, [int count = 20]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  // LAUNCH-P5 C2 — the archive step uses the approval sheet (PIN only).
  // An old "manager fingerprint" flag left on the device is ignored: the
  // biometric channel is never called (H2).
  for (final scenario in ['denied', 'cancelled', 'approved']) {
    testWidgets('archive real manager gate $scenario', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var biometrics = 0;
      const bio = MethodChannel('com.example.manager_biometrics');
      const secure = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const rear = MethodChannel('pos_machine/rear_display_host');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(bio, (_) async {
        biometrics++;
        if (scenario == 'cancelled') throw PlatformException(code: 'cancelled');
        return scenario == 'approved';
      });
      messenger.setMockMethodCallHandler(
        secure,
        (c) async => c.method == 'read' ? 'fixture' : null,
      );
      messenger.setMockMethodCallHandler(
        rear,
        (_) async => <Map<String, dynamic>>[],
      );
      addTearDown(() {
        for (final channel in [bio, secure, rear]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
        debugOrderStorageOverride = null;
      });
      late SqliteCheckoutStore journal;
      late Map<String, Object?> original;
      await tester.runAsync(() async {
        databaseFactory = databaseFactoryFfi;
        final temp = await Directory.systemTemp.createTemp(
          'archive-manager-test-',
        );
        await databaseFactory.setDatabasesPath(temp.path);
        journal = await SqliteCheckoutStore.open(
          '["http://fixture.invalid/api/v1",9,6,"KIOSK-T7"]',
        );
        final attempt = CheckoutAttempt(
          id: 'old',
          orderUuid: 'old-bill',
          state: 'releasing',
          createdAt: DateTime.utc(2026, 9, 12),
          tenderMayHaveStarted: false,
        );
        original = {
          'id': attempt.id,
          'scope': '["http://retired.invalid/api/v1",100,10,"OLD"]',
          'state': attempt.state,
          'payload': jsonEncode(attempt.json),
        };
        await journal.db.insert('qr_checkout_attempts', original);
      });
      debugOrderStorageOverride = FakeOrderStorage();
      final api = _Api()..approve = scenario == 'approved';
      final harness = await pumpWorkspaceMachine(
        tester,
        mode: 'off',
        toggle: false,
        api: api,
        catalog: const CatalogSnapshot(
          categories: [],
          products: [],
          floors: [],
          tables: [],
          taxes: [],
        ),
      );
      await harness.preferences.setBool('manager_biometric_registered', true);
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      // The Settings route's existing action dispatches the real private gate.
      Navigator.of(
        tester.element(find.byType(SettingsScreen)),
      ).pop('checkout_recovery');
      await tick(tester);
      expect(find.byType(CheckoutRecoveryDialog), findsOneWidget);
      await tester.tap(find.text('Archive old reservation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tick(tester);
      final pin = find.byType(ManagerApprovalSheet);
      expect(pin, findsOneWidget);
      if (scenario == 'approved') {
        for (final digit in ['6', '5', '4', '3']) {
          await tester.tap(find.descendant(of: pin, matching: find.text(digit)));
          await tester.pump();
        }
        await tester.tap(
          find.descendant(of: pin, matching: find.byIcon(Icons.check_rounded)),
        );
        await tick(tester, 6);
        expect(api.pins, 1);
      }
      if (scenario != 'approved') {
        if (scenario == 'denied') {
          for (final digit in ['1', '2', '3', '4']) {
            await tester.tap(
              find.descendant(of: pin, matching: find.text(digit)),
            );
            await tester.pump();
          }
          await tester.tap(
            find.descendant(
              of: pin,
              matching: find.byIcon(Icons.check_rounded),
            ),
          );
          await tick(tester, 3);
          expect(api.pins, 1);
          expect(pin, findsOneWidget);
        }
        Navigator.of(tester.element(pin)).pop();
        await tick(tester);
        expect(
          await tester.runAsync(() => journal.db.query('qr_checkout_attempts')),
          [original],
        );
        expect(
          await tester.runAsync(
            () => journal.db.rawQuery(
              "SELECT name FROM sqlite_master WHERE name='qr_checkout_recovery_archive'",
            ),
          ),
          isEmpty,
        );
      } else {
        final rows = await tester.runAsync(
          () => journal.db.query('qr_checkout_recovery_archive'),
        );
        expect(rows, hasLength(1));
        expect(rows!.single['authority'], 'existing_manager_approval');
        expect(jsonDecode(rows.single['original_row'] as String), original);
      }
      expect(biometrics, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
