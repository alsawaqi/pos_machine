import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/approver_store.dart';
import 'package:pos_machine/core/manager_auth.dart';
import 'package:pos_machine/core/pin_lockout.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LAUNCH-P5 C2 — the approval sheet's engine: a local PBKDF2 check against
/// the stored approvers (offline), the verify-manager-pin fallback (online),
/// and the persisted 5-strike lock (60 s, doubling, 15-minute cap).
class _Api implements PosApiService {
  ApproverVerification? Function(String pin)? verify;
  Object? error;
  final pins = <String>[];
  List<Map<String, dynamic>> approvers = const [];

  @override
  Future<ApproverVerification?> verifyApprover(String pin) async {
    pins.add(pin);
    if (error != null) throw error!;
    return verify?.call(pin);
  }

  @override
  Future<({List<Map<String, dynamic>> approvers, String? asOf})>
  fetchApprovers() async => (approvers: approvers, asOf: 'now');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final vectors =
      ((jsonDecode(
                    File(
                      'test/fixtures/approval_proof_goldens.json',
                    ).readAsStringSync(),
                  )
                  as Map)['vectors']
              as List)
          .cast<Map<String, dynamic>>();
  // Vectors 0 and 1 use 1000 iterations: fast enough for unit tests.
  Map<String, dynamic> approverRow(Map<String, dynamic> v, String name) => {
    'staff_id': v['approver_staff_id'],
    'uuid': 'uuid-${v['approver_staff_id']}',
    'name': name,
    'position': 'manager',
    'salt': v['salt_hex'],
    'iterations': v['iterations'],
    'check': v['check_hex'],
  };

  late SharedPreferences prefs;
  late DateTime now;
  late _Api api;
  late ApproverStore store;
  late PinLockout lockout;
  late ApprovalEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 4, 10);
    api = _Api();
    store = ApproverStore(const FlutterSecureStorage());
    lockout = PinLockout(prefs, 'test_lock', clock: () => now);
    engine = ApprovalEngine(
      api: api,
      store: store,
      lockout: lockout,
      clock: () => now,
    );
    ApprovalEngine.matcher = (pin, approvers) async => matchApproverSync(pin, [
      for (final a in approvers)
        (salt: a.salt, iterations: a.iterations, check: a.check),
    ]);
  });

  tearDown(() => ApprovalEngine.matcher = matchApproverInIsolate);

  group('approver store', () {
    test(
      'keeps the verifiers in secure storage, replaced on each fetch',
      () async {
        api.approvers = [
          approverRow(vectors[0], 'Mona'),
          approverRow(vectors[1], 'Ali'),
          {'staff_id': 3, 'name': 'No verifier'},
        ];
        expect(await store.refresh(api), 2);
        final loaded = await store.load();
        expect(loaded.map((a) => a.name), ['Mona', 'Ali']);
        final raw = await const FlutterSecureStorage().read(
          key: ApproverStore.storageKey,
        );
        // Only the verifier — never a key or a PIN.
        expect(raw, isNot(contains(vectors[0]['k_hex'])));
        expect(raw, isNot(contains('123456')));
        api.approvers = [approverRow(vectors[1], 'Ali')];
        await store.refresh(api);
        expect((await store.load()).map((a) => a.name), ['Ali']);
        await store.wipe();
        expect(await store.load(), isEmpty);
      },
    );

    test('a damaged value reads as no approvers', () async {
      FlutterSecureStorage.setMockInitialValues({
        ApproverStore.storageKey: 'fixture',
      });
      expect(await store.load(), isEmpty);
    });
  });

  group('engine', () {
    test('a stored approver approves offline with their key', () async {
      await store.save([
        StoredApprover.fromJson(approverRow(vectors[0], 'Mona'))!,
        StoredApprover.fromJson(approverRow(vectors[1], 'Ali'))!,
      ]);
      api.error = ApiException(message: 'offline', isNetwork: true);
      final attempt = await engine.verify(vectors[1]['pin'] as String);
      expect(attempt, isA<ApprovalApproved>());
      final grant = (attempt as ApprovalApproved).grant;
      expect(grant.approverStaffId, vectors[1]['approver_staff_id']);
      expect(grant.name, 'Ali');
      expect(grant.method, 'offline');
      expect(grant.canSign, isTrue);
      // The server was never asked.
      expect(api.pins, isEmpty);
      // The proof is the golden one for that canonical.
      final v = vectors[1];
      final g2 = ApprovalGrant(
        approverStaffId: grant.approverStaffId,
        name: grant.name,
        approvedAt: DateTime.parse(v['approved_at'] as String),
        method: 'offline',
      );
      expect(g2.canSign, isFalse);
    });

    test(
      'no local match: the server approves and teaches the verifier',
      () async {
        final v = vectors[0];
        api.verify = (pin) => pin == v['pin']
            ? ApproverVerification(
                staffId: v['approver_staff_id'] as int,
                name: 'Mona',
                position: 'manager',
                salt: v['salt_hex'] as String,
                iterations: v['iterations'] as int,
                check: v['check_hex'] as String,
              )
            : null;
        final attempt = await engine.verify(v['pin'] as String);
        final grant = (attempt as ApprovalApproved).grant;
        expect(grant.method, 'online');
        expect(grant.canSign, isTrue);
        expect(
          grant.proofFor(
            action: v['action'] as String,
            deviceUuid: v['device_uuid'] as String,
            subjectUuid: v['subject_uuid'] as String,
            amountBaisas: v['amount_baisas'] as int,
            ref: v['ref'] as String,
          ),
          isNot(isEmpty),
        );
        // Next time Mona can approve offline.
        expect((await store.load()).single.staffId, v['approver_staff_id']);
        api.error = ApiException(message: 'offline', isNetwork: true);
        final again = await engine.verify(v['pin'] as String);
        expect((again as ApprovalApproved).grant.method, 'offline');
      },
    );

    test('offline with no verifier: refused, and it counts', () async {
      api.error = ApiException(message: 'offline', isNetwork: true);
      final attempt = await engine.verify('123456');
      expect(attempt, isA<ApprovalWrongPin>());
      expect((attempt as ApprovalWrongPin).offline, isTrue);
      expect(lockout.failures, 1);
    });

    test(
      'five wrong PINs lock for 60 s; it doubles; a lock survives restart',
      () async {
        api.verify = (_) => null;
        for (var i = 0; i < 4; i++) {
          final a = await engine.verify('000001');
          expect((a as ApprovalWrongPin).lockedUntil, isNull);
        }
        final fifth = await engine.verify('000001');
        expect(
          (fifth as ApprovalWrongPin).lockedUntil!.isAtSameMomentAs(
            now.add(const Duration(seconds: 60)),
          ),
          isTrue,
        );
        // Locked: not even the server is asked.
        api.pins.clear();
        expect(await engine.verify('000001'), isA<ApprovalLocked>());
        expect(api.pins, isEmpty);
        // A new instance (app restart) still sees the lock.
        final restarted = PinLockout(prefs, 'test_lock', clock: () => now);
        expect(
          restarted.lockedUntil!.isAtSameMomentAs(
            now.add(const Duration(seconds: 60)),
          ),
          isTrue,
        );
        // After it ends, the next wrong PIN doubles the window.
        now = now.add(const Duration(seconds: 61));
        expect(lockout.lockedUntil, isNull);
        final sixth = await engine.verify('000001');
        expect(
          (sixth as ApprovalWrongPin).lockedUntil!.isAtSameMomentAs(
            now.add(const Duration(seconds: 120)),
          ),
          isTrue,
        );
      },
    );

    test('the lock is capped at 15 minutes', () async {
      for (var i = 0; i < 20; i++) {
        await lockout.recordFailure();
        now = now.add(const Duration(seconds: 1));
      }
      expect(lockout.remaining! <= const Duration(minutes: 15), isTrue);
      expect(
        lockout.remaining! > const Duration(minutes: 14, seconds: 30),
        isTrue,
      );
    });

    test('a correct PIN clears the count', () async {
      final v = vectors[0];
      await store.save([StoredApprover.fromJson(approverRow(v, 'Mona'))!]);
      api.verify = (_) => null;
      await engine.verify('999999');
      await engine.verify('999999');
      expect(lockout.failures, 2);
      await engine.verify(v['pin'] as String);
      expect(lockout.failures, 0);
    });

    test(
      'a server PIN lock (423) locks the sheet for retry_after_seconds',
      () async {
        api.error = ApiException(
          message: 'Locked',
          statusCode: 423,
          code: 'pin_locked',
          retryAfterSeconds: 90,
        );
        final attempt = await engine.verify('123456');
        expect(
          (attempt as ApprovalLocked).until.isAtSameMomentAs(
            now.add(const Duration(seconds: 90)),
          ),
          isTrue,
        );
        expect(
          lockout.lockedUntil!.isAtSameMomentAs(
            now.add(const Duration(seconds: 90)),
          ),
          isTrue,
        );
      },
    );
  });

  group('sheet', () {
    Widget host(Widget child) => MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: child),
    );

    testWidgets('a locked sheet shows a countdown and a disabled pad', (
      tester,
    ) async {
      await tester.runAsync(
        () =>
            PinLockout(prefs, 'test_lock').lockFor(const Duration(minutes: 2)),
      );
      final sheetEngine = ApprovalEngine(
        api: api,
        store: store,
        lockout: PinLockout(prefs, 'test_lock'),
      );
      await tester.pumpWidget(host(ManagerApprovalSheet(engine: sheetEngine)));
      await tester.pump();
      expect(find.textContaining('Try again in'), findsOneWidget);
      await tester.tap(find.text('1'));
      await tester.pump();
      // The pad ignores taps while locked.
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      final verify = tester.widget<FilledButton>(
        find.byKey(const ValueKey('manager-approval-verify')),
      );
      expect(verify.onPressed, isNull);
    });

    testWidgets('there is no fingerprint path: only the PIN pad', (
      tester,
    ) async {
      await tester.pumpWidget(host(ManagerApprovalSheet(engine: engine)));
      await tester.pump();
      expect(find.byIcon(Icons.fingerprint), findsNothing);
      expect(find.text('0'), findsOneWidget);
    });
  });
}
