import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('staff reconciliation adopts that staff shared shift first', () async {
    final ownShift = _shift('shift-b', staffId: 8);
    final harness = await _harness(
      localShift: _shift('shift-a', staffId: 7),
      responses: [ownShift],
    );

    await harness.container.read(shiftReconciliationProvider(8).future);

    expect(
      harness.container.read(sessionControllerProvider).openShift?.uuid,
      'shift-b',
    );
    expect(harness.api.calls, [(staffId: 8, sharedStaffOnly: true)]);
  });

  test('no staff shift retains a foreign device drawer for handover', () async {
    final foreignShift = _shift('shift-a', staffId: 7);
    final harness = await _harness(
      localShift: foreignShift,
      responses: [null, foreignShift],
    );

    await harness.container.read(shiftReconciliationProvider(8).future);

    expect(
      harness.container.read(sessionControllerProvider).openShift?.uuid,
      'shift-a',
    );
    expect(harness.api.calls, [
      (staffId: 8, sharedStaffOnly: true),
      (staffId: null, sharedStaffOnly: false),
    ]);
  });

  test('authoritative absence clears a stale same-staff shift', () async {
    final harness = await _harness(
      localShift: _shift('stale-shift-b', staffId: 8),
      responses: [null, null],
    );

    await harness.container.read(shiftReconciliationProvider(8).future);

    expect(harness.container.read(sessionControllerProvider).openShift, isNull);
  });

  test(
    'a foreign result from an older API is retained but never made owned',
    () async {
      final foreignShift = _shift('old-api-shift-a', staffId: 7);
      final harness = await _harness(
        localShift: null,
        responses: [foreignShift],
      );

      await harness.container.read(shiftReconciliationProvider(8).future);

      final state = harness.container.read(sessionControllerProvider);
      expect(state.openShift?.uuid, 'old-api-shift-a');
      expect(state.openShift?.staffId, isNot(state.staff?.id));
      expect(harness.api.calls, [(staffId: 8, sharedStaffOnly: true)]);
    },
  );

  test(
    'a stale response cannot mutate a later login with the same ID',
    () async {
      final staleResponse = Completer<OpenShiftData?>();
      final harness = await _harness(
        localShift: _shift('old-local', staffId: 8),
        responses: [staleResponse.future],
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );

      final staleProbe = controller.reconcileShiftForStaff(8);
      expect(harness.api.calls, [(staffId: 8, sharedStaffOnly: true)]);

      await controller.logoutStaff();
      await controller.saveStaff(
        const StaffSessionData(id: 8, name: 'Replacement Cashier B'),
      );
      await controller.markShiftOpen(_shift('replacement-shift', staffId: 8));

      staleResponse.complete(_shift('stale-server-shift', staffId: 8));
      await staleProbe;

      expect(
        harness.container.read(sessionControllerProvider).openShift?.uuid,
        'replacement-shift',
      );
    },
  );

  test(
    'logging out and back in with the same ID starts a fresh probe',
    () async {
      final harness = await _harness(
        localShift: _shift('first-local', staffId: 8),
        responses: [
          _shift('first-server', staffId: 8),
          _shift('second-server', staffId: 8),
        ],
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );

      await harness.container.read(shiftReconciliationProvider(8).future);
      await controller.logoutStaff();
      await controller.saveStaff(
        const StaffSessionData(id: 8, name: 'Cashier B'),
      );
      await harness.container.read(shiftReconciliationProvider(8).future);

      expect(
        harness.api.calls,
        List.filled(2, (staffId: 8, sharedStaffOnly: true)),
      );
      expect(
        harness.container.read(sessionControllerProvider).openShift?.uuid,
        'second-server',
      );
    },
  );
}

Future<_Harness> _harness({
  required OpenShiftData? localShift,
  required List<FutureOr<OpenShiftData?>> responses,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final session = SessionService(const FlutterSecureStorage(), prefs);
  await session.saveStaff(const StaffSessionData(id: 8, name: 'Cashier B'));
  if (localShift != null) await session.saveOpenShift(localShift);

  final api = _FakeShiftApi(responses);
  final container = ProviderContainer(
    overrides: [
      sessionServiceProvider.overrideWithValue(session),
      apiServiceProvider.overrideWithValue(api),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(container, api);
}

OpenShiftData _shift(String uuid, {required int staffId}) => OpenShiftData(
  uuid: uuid,
  openingCashBaisas: 10000,
  openedAt: DateTime.utc(2026, 8, 8, 8),
  staffId: staffId,
);

class _FakeShiftApi extends PosApiService {
  _FakeShiftApi(List<FutureOr<OpenShiftData?>> responses)
    : _responses = List.of(responses),
      super(tokenGetter: () => 'device-token');

  final List<FutureOr<OpenShiftData?>> _responses;
  final List<({int? staffId, bool sharedStaffOnly})> calls = [];

  @override
  Future<OpenShiftData?> fetchCurrentShift({
    int? staffId,
    bool sharedStaffOnly = false,
  }) async {
    calls.add((staffId: staffId, sharedStaffOnly: sharedStaffOnly));
    return Future<OpenShiftData?>.value(_responses.removeAt(0));
  }
}

class _Harness {
  const _Harness(this.container, this.api);

  final ProviderContainer container;
  final _FakeShiftApi api;
}
