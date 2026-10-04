import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/approver_store.dart';
import 'package:pos_machine/core/manager_auth.dart';
import 'package:pos_machine/core/pin_lockout.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LAUNCH-P5 fix order 2b (T14), found on the real T3: a manager with no
/// verifier at login approved ONLINE (the till learned their verifier); a
/// later offline approval with the same PIN said "PIN not recognised on
/// this till". A refresh that was under way (or whose reply was older) had
/// saved the server's list over the learned verifier. The store now merges
/// by staff id, keeps a verifier learned after the refresh started (and one
/// the server lists without a verifier), drops people the server no longer
/// lists, and leaves breadcrumbs with no secrets.
class _Api implements PosApiService {
  ApproverVerification? Function(String pin)? verify;
  Object? error;
  List<Map<String, dynamic>> approvers = const [];

  /// When set, fetchApprovers waits for it (a slow refresh).
  Completer<void>? gate;

  @override
  Future<ApproverVerification?> verifyApprover(String pin) async {
    if (error != null) throw error!;
    return verify?.call(pin);
  }

  @override
  Future<({List<Map<String, dynamic>> approvers, String? asOf})>
  fetchApprovers() async {
    // The reply is what the server held when it was asked.
    final reply = List<Map<String, dynamic>>.of(approvers);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return (approvers: reply, asOf: '2026-10-04T16:15:00Z');
  }

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
  // Vectors 0 and 1 use 1000 iterations.
  final mona = vectors[0], ali = vectors[1];
  Map<String, dynamic> row(
    Map<String, dynamic> v,
    String name, {
    bool verifier = true,
  }) => {
    'staff_id': v['approver_staff_id'],
    'uuid': 'uuid-${v['approver_staff_id']}',
    'name': name,
    'position': 'manager',
    'salt': verifier ? v['salt_hex'] : null,
    'iterations': verifier ? v['iterations'] : null,
    'check': verifier ? v['check_hex'] : null,
  };
  ApproverVerification online(Map<String, dynamic> v, String name) =>
      ApproverVerification(
        staffId: v['approver_staff_id'] as int,
        name: name,
        position: 'manager',
        salt: v['salt_hex'] as String,
        iterations: v['iterations'] as int,
        check: v['check_hex'] as String,
      );

  late _Api api;
  late ApproverStore store;
  late ApprovalEngine engine;
  late DateTime now;
  final crumbs = <(String, Map<String, dynamic>)>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 4, 16, 10);
    api = _Api();
    store = ApproverStore(const FlutterSecureStorage(), clock: () => now);
    engine = ApprovalEngine(
      api: api,
      store: store,
      lockout: PinLockout(prefs, 'test_lock', clock: () => now),
      clock: () => now,
    );
    ApprovalEngine.matcher = (pin, approvers) async => matchApproverSync(pin, [
      for (final a in approvers)
        (salt: a.salt, iterations: a.iterations, check: a.check),
    ]);
    crumbs.clear();
    ApproverStore.debugBreadcrumb = (m, d) => crumbs.add((m, d));
  });
  tearDown(() {
    ApprovalEngine.matcher = matchApproverInIsolate;
    ApproverStore.debugBreadcrumb = null;
  });

  Future<ApprovalAttempt> offline(String pin) {
    api.error = ApiException(message: 'offline', isNetwork: true);
    return engine.verify(pin);
  }

  test(
    'the T3 incident: a slow refresh never drops the learned verifier',
    () async {
      // At login Mona (a manager) has no verifier yet: the server lists her
      // with nulls. The login-time refresh is slow.
      api.approvers = [row(ali, 'Ali'), row(mona, 'Mona', verifier: false)];
      api.gate = Completer<void>();
      final loginRefresh = store.refresh(api);
      await Future<void>.delayed(Duration.zero);

      // 16:16:06 — a 15 % discount; Mona's PIN is verified ONLINE and the
      // reply carries her new verifier (the server made it lazily).
      now = DateTime.utc(2026, 10, 4, 16, 16, 6);
      api.verify = (pin) => pin == mona['pin'] ? online(mona, 'Mona') : null;
      final first = await engine.verify(mona['pin'] as String);
      expect(first, isA<ApprovalApproved>());
      expect((first as ApprovalApproved).grant.method, 'online');

      // The older refresh finishes after it.
      api.gate!.complete();
      await loginRefresh;

      // Cut off: the same PIN approves offline.
      now = DateTime.utc(2026, 10, 4, 16, 19, 40);
      final second = await offline(mona['pin'] as String);
      expect(second, isA<ApprovalApproved>());
      expect((second as ApprovalApproved).grant.method, 'offline');
      expect(second.grant.approverStaffId, mona['approver_staff_id']);
    },
  );

  test(
    'a refresh after the approval keeps it while the server lists her without a verifier',
    () async {
      api.verify = (pin) => online(mona, 'Mona');
      await engine.verify(mona['pin'] as String);
      // The resume refresh: the server still sends no verifier for her.
      now = now.add(const Duration(minutes: 3));
      api.approvers = [row(ali, 'Ali'), row(mona, 'Mona', verifier: false)];
      expect(await store.refresh(api), 2);
      expect(await offline(mona['pin'] as String), isA<ApprovalApproved>());
    },
  );

  test(
    'the server\'s own verifier replaces a learned one once it is newer',
    () async {
      api.verify = (pin) => online(mona, 'Mona');
      await engine.verify(mona['pin'] as String);
      expect((await store.load()).single.learnedAt, isNotNull);
      now = now.add(const Duration(minutes: 5));
      api.approvers = [row(mona, 'Mona Renamed')];
      await store.refresh(api);
      final stored = (await store.load()).single;
      expect(stored.name, 'Mona Renamed');
      expect(stored.learnedAt, isNull);
    },
  );

  test('a person the server no longer lists is dropped', () async {
    api.verify = (pin) => online(mona, 'Mona');
    await engine.verify(mona['pin'] as String);
    now = now.add(const Duration(minutes: 5));
    api.approvers = [row(ali, 'Ali')];
    await store.refresh(api);
    expect((await store.load()).map((a) => a.name), ['Ali']);
    expect(await offline(mona['pin'] as String), isA<ApprovalWrongPin>());
  });

  test(
    'breadcrumbs carry counts, as_of and a reason — never a secret',
    () async {
      // An offline check with nothing stored.
      final empty = await offline(mona['pin'] as String);
      expect(empty, isA<ApprovalWrongPin>());
      final noMatch = crumbs.where(
        (c) => c.$1 == 'approver PIN matched no stored verifier',
      );
      expect(noMatch.single.$2['reason'], 'empty');
      expect(noMatch.single.$2['count'], 0);
      expect(noMatch.single.$2['verified_online'], isFalse);

      // A refresh save, then a wrong PIN offline.
      api.error = null;
      api.approvers = [row(ali, 'Ali')];
      await store.refresh(api);
      final saved = crumbs.lastWhere((c) => c.$1 == 'approver verifiers saved');
      expect(saved.$2, {
        'source': 'refresh',
        'count': 1,
        'learned': 0,
        'as_of': '2026-10-04T16:15:00Z',
      });
      crumbs.clear();
      await offline(mona['pin'] as String);
      expect(crumbs.single.$2['reason'], 'no_match');
      expect(crumbs.single.$2['count'], 1);

      // An online approval of someone not stored, then learned.
      crumbs.clear();
      api.error = null;
      api.verify = (pin) => online(mona, 'Mona');
      await engine.verify(mona['pin'] as String);
      expect(crumbs.map((c) => c.$1), [
        'approver PIN matched no stored verifier',
        'approver verifiers saved',
      ]);
      expect(crumbs.first.$2['verified_online'], isTrue);
      expect(crumbs.last.$2['source'], 'learned');
      expect(crumbs.last.$2['learned'], 1);

      final everything = crumbs.map((c) => jsonEncode(c.$2)).join();
      for (final secret in [
        mona['pin'],
        mona['salt_hex'],
        mona['check_hex'],
        mona['k_hex'],
      ]) {
        expect(everything, isNot(contains(secret as String)));
      }
    },
  );
}
