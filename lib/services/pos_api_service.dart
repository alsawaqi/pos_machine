import 'package:dio/dio.dart';

import '../core/api_config.dart';
import '../models/branch_report.dart';
import '../models/kitchen_production.dart';
import '../models/pos_models.dart';
import 'api_models.dart';
import 'session_service.dart' show OpenShiftData;

typedef TokenGetter = String? Function();
typedef UnauthorizedCallback = void Function();

/// Thin wrapper over pos_api `/api/v1`. Attaches the device Bearer token,
/// unwraps the `{ data, meta, errors }` envelope, and maps failures to
/// [ApiException]. A 401 fires [onUnauthorized] so the gate can drop to pairing.
class PosApiService {
  PosApiService({
    required this.tokenGetter,
    this.onUnauthorized,
    this.baseUrlGetter,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: ApiConfig.baseUrl,
              connectTimeout: ApiConfig.connectTimeout,
              receiveTimeout: ApiConfig.receiveTimeout,
              // We never throw on non-2xx ourselves; let _unwrap inspect the body.
              validateStatus: (_) => true,
              headers: {'Accept': 'application/json'},
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // Resolve the server URL per request so an operator change in Settings
        // takes effect without rebuilding the client. Falls back to the
        // compile-time default.
        final base = baseUrlGetter?.call();
        if (base != null && base.isNotEmpty) {
          options.baseUrl = base;
        }
        final token = tokenGetter();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  final Dio _dio;
  final TokenGetter tokenGetter;
  final UnauthorizedCallback? onUnauthorized;
  final String Function()? baseUrlGetter;

  /// Lightweight reachability check for [baseUrl] (Settings "Test connection").
  /// Any HTTP response — even a 401/404 — means the server is reachable; only a
  /// transport failure (no route, refused, timeout) returns false.
  Future<bool> pingBaseUrl(String baseUrl) async {
    final probe = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
      validateStatus: (_) => true,
    ));
    try {
      await probe.get('/');
      return true;
    } on DioException {
      return false;
    } catch (_) {
      return false;
    } finally {
      probe.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Endpoints
  // ---------------------------------------------------------------------------

  /// POST /auth/device/activate — one-time device setup: the device exchanges
  /// the single admin-generated activation code for a device token + its kiosk
  /// ID + terminal ID.
  Future<PairResult> activateDevice({required String code}) async {
    final body = await _send(() => _dio.post('/auth/device/activate', data: {
          'code': code,
        }));
    return PairResult.fromJson(body.dataMap);
  }

  /// POST /auth/pos/login — staff PIN login (Bearer device token). [lat]/[lng]
  /// carry the device's live GPS for the server-side login geofence check; at a
  /// fenced branch the server rejects the sign-in when they're missing/outside.
  Future<StaffSessionData> staffLogin({
    required String pin,
    double? lat,
    double? lng,
  }) async {
    final body = await _send(() => _dio.post('/auth/pos/login', data: {
          'pin': pin,
          'lat': ?lat,
          'lng': ?lng,
        }));
    final staff = body.dataMap['staff'] as Map<String, dynamic>;
    return StaffSessionData.fromJson(staff);
  }

  /// POST /device/auth/verify-manager-pin — P-F1 manager PIN fallback for the
  /// fingerprint gates. The server checks the PIN against ACTIVE staff of
  /// this company whose position is in the merchant's
  /// manager_approval_positions policy (default managers only) — any such
  /// staff member, not necessarily the logged-in operator. Returns the
  /// approver's display name, or null when the PIN is rejected (the server
  /// deliberately never reveals WHY). Throttled server-side with the staff
  /// login bucket; network errors rethrow so the caller can say "offline".
  Future<String?> verifyManagerPin(String pin) async {
    try {
      final body = await _send(
        () => _dio.post('/device/auth/verify-manager-pin', data: {'pin': pin}),
      );
      if (body.body['ok'] == true) {
        final staff = (body.body['staff'] as Map?)?.cast<String, dynamic>();
        return staff?['name']?.toString() ?? '';
      }
      return null;
    } on ApiException catch (e) {
      if (e.code == 'invalid_pin') return null;
      rethrow;
    }
  }

  /// POST /device/auth/verify-kitchen-pin — P-G1.6 the Kitchen walk-up
  /// gate: when the logged-in staff member can't open the Kitchen screen,
  /// a kitchen staff member punches THEIR code and the Kitchen session
  /// runs as them. Returns the verified staff identity (for batch
  /// attribution), or null on a rejected PIN. Same conventions as
  /// [verifyManagerPin].
  Future<({int id, String name})?> verifyKitchenPin(String pin) async {
    try {
      final body = await _send(
        () => _dio.post('/device/auth/verify-kitchen-pin', data: {'pin': pin}),
      );
      if (body.body['ok'] == true) {
        final staff = (body.body['staff'] as Map?)?.cast<String, dynamic>();
        final id = (staff?['id'] as num?)?.toInt();
        if (id == null) return null;
        return (id: id, name: staff?['name']?.toString() ?? '');
      }
      return null;
    } on ApiException catch (e) {
      if (e.code == 'invalid_pin') return null;
      rethrow;
    }
  }

  /// GET /device/config — full branch-scoped config bundle. Returns the raw
  /// `data` map, the device's terminal_id, `meta.generated_at` (the server
  /// cursor the device persists + replays as `?since=` on the next delta
  /// call), and `meta.websocket` (Phase C3 — where to dial Reverb; null =
  /// live push not configured server-side).
  Future<({Map<String, dynamic> data, String? terminalId, String? generatedAt, Map<String, dynamic>? websocket})> fetchConfig() async {
    final body = await _send(() => _dio.get('/device/config'));
    return (
      data: body.dataMap,
      terminalId: body.metaMap['terminal_id'] as String?,
      generatedAt: body.metaMap['generated_at'] as String?,
      websocket: (body.metaMap['websocket'] as Map?)?.cast<String, dynamic>(),
    );
  }

  /// GET `/device/config/delta?since=...` — only rows changed since the cursor,
  /// plus `data.deleted{}` (per-entity ids to purge). `meta.generated_at` is the
  /// next cursor. `since` is the previous sync's generated_at (ISO-8601).
  Future<({Map<String, dynamic> data, String? terminalId, String? generatedAt, Map<String, dynamic>? websocket})> fetchConfigDelta(String since) async {
    final body = await _send(
      () => _dio.get('/device/config/delta', queryParameters: {'since': since}),
    );
    return (
      data: body.dataMap,
      terminalId: body.metaMap['terminal_id'] as String?,
      generatedAt: body.metaMap['generated_at'] as String?,
      websocket: (body.metaMap['websocket'] as Map?)?.cast<String, dynamic>(),
    );
  }

  /// POST /broadcasting/auth — sign a private-channel subscription for this
  /// device (Phase C3). Reverb's response is a bare `{auth: "key:signature"}`
  /// (no data envelope). The signature binds to the socket_id, so it must be
  /// re-requested on every reconnect.
  Future<String> authorizeBroadcast({
    required String socketId,
    required String channelName,
  }) async {
    final body = await _send(() => _dio.post('/broadcasting/auth', data: {
          'socket_id': socketId,
          'channel_name': channelName,
        }));
    final auth = body.body['auth'];
    if (auth is! String || auth.isEmpty) {
      throw ApiException(
        message: 'Broadcast subscription was not authorized.',
        code: 'broadcast_auth',
      );
    }
    return auth;
  }

  /// POST /device/sync/push — push a batch of offline sync events (order.create
  /// / order.pay / donation.record …). Idempotent on client_event_id, so a
  /// re-push of the same batch settles exactly once. Returns the `data` map:
  /// { results: [ per-event ACK {client_event_id, status, duplicate, result} ],
  ///   summary: {total, accepted, duplicates} }.
  Future<Map<String, dynamic>> pushSync(List<Map<String, dynamic>> events) async {
    final body = await _send(
      () => _dio.post('/device/sync/push', data: {'events': events}),
    );
    return body.dataMap;
  }

  /// POST /device/customers — register a customer (find-or-create on phone) and,
  /// when given, attach a vehicle plate for drive-thru lookup. Returns the
  /// customer's server id, or null if the response had none.
  Future<int?> saveCustomer({
    required String name,
    required String phone,
    String? plateNumber,
  }) async {
    final body = await _send(() => _dio.post('/device/customers', data: {
          'name': name,
          'phone': phone,
          'plate_number': ?plateNumber,
        }));
    final customer = body.dataMap['customer'];
    return customer is Map ? (customer['id'] as num?)?.toInt() : null;
  }

  /// GET /device/customers/search?q= — live customer lookup (phone/name/plate),
  /// including each customer's loyalty balances. Online-only (the full book is
  /// beyond the cached slice).
  Future<List<CustomerSearchResult>> searchCustomers(String query) async {
    final body = await _send(
      () => _dio.get('/device/customers/search', queryParameters: {'q': query}),
    );
    final list = body.dataMap['customers'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => CustomerSearchResult.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// POST /device/orders/next-number — P-F8: atomically allocate the next
  /// merchant order number (per the company's numbering config: branch or
  /// company scope, optional daily reset). Returns the server-formatted
  /// receipt number, or null when numbering is disabled server-side.
  /// Network failures rethrow — the caller falls back to the local number.
  Future<({int number, String formatted})?> allocateOrderNumber() async {
    try {
      final body =
          await _send(() => _dio.post('/device/orders/next-number'));
      final number = (body.dataMap['number'] as num?)?.toInt();
      final formatted = body.dataMap['formatted']?.toString();
      if (number == null || formatted == null || formatted.isEmpty) {
        return null;
      }
      return (number: number, formatted: formatted);
    } on ApiException catch (e) {
      if (e.code == 'numbering_disabled') return null;
      rethrow;
    }
  }

  /// POST /device/messages/read — P-G6: record read receipts for staff
  /// announcements ("sent is not the same as seen"). Idempotent server-side
  /// (firstOrCreate per message+staff), so re-sending after an offline spell
  /// is harmless. Returns how many NEW receipts were recorded.
  Future<int> markMessagesRead({
    required int staffId,
    required List<int> messageIds,
  }) async {
    final body = await _send(() => _dio.post('/device/messages/read', data: {
          'staff_id': staffId,
          'message_ids': messageIds,
        }));
    return (body.dataMap['marked'] as num?)?.toInt() ?? 0;
  }

  /// GET /device/reports/branch — P-F6: the branch report bundle for the
  /// device's Reports dashboard (branch-scoped aggregates, money in baisas;
  /// the model converts to OMR). Online-only by nature.
  Future<BranchReport> fetchBranchReport({
    required DateTime from,
    required DateTime to,
  }) async {
    String d(DateTime v) =>
        '${v.year.toString().padLeft(4, '0')}-'
        '${v.month.toString().padLeft(2, '0')}-'
        '${v.day.toString().padLeft(2, '0')}';
    final body = await _send(
      () => _dio.get('/device/reports/branch', queryParameters: {
        'from': d(from),
        'to': d(to),
      }),
    );
    final report = (body.dataMap['report'] as Map?)?.cast<String, dynamic>();
    return BranchReport.fromJson(report ?? const {});
  }

  /// GET /device/customers/{id} — P-F2: the full customer profile for the
  /// details dialog (plates + per-rule loyalty balances + wallet), same shape
  /// as a search hit. Returns null on 404 (deleted / foreign customer).
  Future<CustomerSearchResult?> fetchCustomerDetails(int id) async {
    try {
      final body = await _send(() => _dio.get('/device/customers/$id'));
      final customer = body.dataMap['customer'];
      if (customer is! Map) return null;
      return CustomerSearchResult.fromJson(customer.cast<String, dynamic>());
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// GET /device/orders/history — the branch's terminal (paid/void/refunded)
  /// orders, newest first, so a freshly-paired or second device shows prior
  /// sales rung at the branch (not just its own local store). Online-only.
  Future<List<OrderHistoryRecord>> fetchBranchOrders({int perPage = 50}) async {
    final body = await _send(
      () => _dio.get('/device/orders/history', queryParameters: {'per_page': perPage}),
    );
    final list = body.dataMap['orders'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => OrderHistoryRecord.fromServerJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// GET /device/shift/current — the device's currently-open shift on the server,
  /// or null. Lets the open-shift screen ADOPT an existing shift (recovering from
  /// a local↔server desync) instead of failing to open a duplicate.
  Future<OpenShiftData?> fetchCurrentShift() async {
    final body = await _send(() => _dio.get('/device/shift/current'));
    final shift = body.dataMap['shift'];
    if (shift is! Map) return null;
    final m = shift.cast<String, dynamic>();
    return OpenShiftData(
      uuid: m['uuid'].toString(),
      openingCashBaisas: (m['opening_cash_baisas'] as num?)?.toInt() ?? 0,
      openedAt: DateTime.tryParse(m['opened_at']?.toString() ?? '') ?? DateTime.now(),
      staffId: (m['staff_id'] as num?)?.toInt() ?? 0,
    );
  }

  /// GET /device/kitchen — P-G1: the Kitchen screen's data (cooked products
  /// with live "can make up to N", the extras ingredient picker, and this
  /// branch's in-progress batches). Online-only by design — production
  /// validates against fresh balances, so the screen shows fresh numbers.
  Future<KitchenData> fetchKitchen() async {
    final body = await _send(() => _dio.get('/device/kitchen'));
    return KitchenData.fromJson(body.dataMap);
  }

  /// POST /device/productions — P-G1: start a batch. The recipe amounts are
  /// locked server-side (quantity x recipe); [extras] are the declared
  /// beyond-recipe lines. The server deducts the ingredients immediately.
  Future<ProductionBatch> startProduction({
    required int productId,
    required int quantity,
    int? staffId,
    List<({int ingredientId, double quantity})> extras = const [],
  }) async {
    final body = await _send(() => _dio.post('/device/productions', data: {
          'product_id': productId,
          'quantity': quantity,
          'staff_id': ?staffId,
          'extras': [
            for (final e in extras)
              {'ingredient_id': e.ingredientId, 'quantity': e.quantity},
          ],
        }));
    final production = (body.dataMap['production'] as Map?)?.cast<String, dynamic>();
    return ProductionBatch.fromJson(production ?? const {});
  }

  /// POST /device/productions/{uuid}/finish — P-G1: the pieces land in the
  /// branch shelf stock; the server records the duration.
  ///
  /// P-G1.5: [expiresAtIso] is the chef's batch expiry from the Finish
  /// dialog — always sent explicitly (null = "this batch never expires");
  /// the dialog prefilled it from the product's shelf life.
  Future<ProductionBatch> finishProduction({
    required String uuid,
    int? staffId,
    String? expiresAtIso,
  }) async {
    final body = await _send(() => _dio.post('/device/productions/$uuid/finish', data: {
          'staff_id': ?staffId,
          'expires_at': expiresAtIso,
        }));
    final production = (body.dataMap['production'] as Map?)?.cast<String, dynamic>();
    return ProductionBatch.fromJson(production ?? const {});
  }

  /// GET /device/disposition — P-G1.5: the expired cooked pieces at this
  /// branch awaiting a day-end decision. Online-only by nature.
  Future<List<DispositionItem>> fetchDisposition() async {
    final body = await _send(() => _dio.get('/device/disposition'));
    final list = body.dataMap['items'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => DispositionItem.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// POST /device/disposition — P-G1.5: apply the closer's split (waste /
  /// give-away / carry-over) for expired pieces. The manager [pin] is
  /// required server-side when any give-away or carry-over is present.
  /// Returns false on a bad PIN (code invalid_pin), true on success.
  Future<bool> applyDisposition({
    required List<Map<String, dynamic>> items,
    String? pin,
    int? staffId,
  }) async {
    try {
      await _send(() => _dio.post('/device/disposition', data: {
            'items': items,
            'pin': ?pin,
            'staff_id': ?staffId,
          }));
      return true;
    } on ApiException catch (e) {
      if (e.code == 'invalid_pin') return false;
      rethrow;
    }
  }

  /// POST /device/productions/{uuid}/cancel — P-G1: manager-gated; the PIN is
  /// verified SERVER-SIDE (manager_approval_positions policy) and the
  /// ingredients return to the branch shelf. Returns null on a bad PIN
  /// (code invalid_pin), mirroring [verifyManagerPin].
  Future<ProductionBatch?> cancelProduction({
    required String uuid,
    required String pin,
    int? staffId,
  }) async {
    try {
      final body = await _send(() => _dio.post('/device/productions/$uuid/cancel', data: {
            'pin': pin,
            'staff_id': ?staffId,
          }));
      final production = (body.dataMap['production'] as Map?)?.cast<String, dynamic>();
      return ProductionBatch.fromJson(production ?? const {});
    } on ApiException catch (e) {
      if (e.code == 'invalid_pin') return null;
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<_Envelope> _send(Future<Response<dynamic>> Function() request) async {
    final Response<dynamic> resp;
    try {
      resp = await request();
    } on DioException catch (e) {
      // Transport-level failure (no/again-unreachable server, timeout, ...).
      if (e.response != null) {
        return _interpret(e.response!);
      }
      throw ApiException(
        message: 'Cannot reach the server. Check the connection and try again.',
        code: 'network',
        isNetwork: true,
      );
    }
    return _interpret(resp);
  }

  _Envelope _interpret(Response<dynamic> resp) {
    final status = resp.statusCode ?? 0;
    final body = resp.data;

    if (body is Map) {
      final map = body.cast<String, dynamic>();
      final errors = map['errors'];
      // An application-level error (a populated `errors[]`) is a deliberate,
      // structured rejection — surface it as-is, even at 401. A wrong staff PIN
      // comes back as 401 { errors: [{ code: 'invalid_pin' }] } and MUST NOT
      // clear the device pairing (that would wrongly kick the operator back to
      // the admin's device-setup screen). Likewise a geofence 422. Only a BARE
      // 401 ({ "message": "Unauthenticated." }, no errors[]) means the device
      // token itself was rejected → drop back to device setup.
      if (errors is List && errors.isNotEmpty) {
        throw ApiException.fromErrors(errors, status);
      }
      if (status == 401) {
        onUnauthorized?.call();
        throw ApiException(
          message: 'This device is no longer authorized. Please set it up again.',
          statusCode: 401,
          code: 'unauthorized',
        );
      }
      if (status >= 200 && status < 300) {
        return _Envelope(map);
      }
      // Non-2xx without a populated errors[] — surface a generic message.
      throw ApiException(
        message: 'Request failed (HTTP $status).',
        statusCode: status,
      );
    }

    // Non-map body: a 401 here is still a device-token rejection.
    if (status == 401) {
      onUnauthorized?.call();
      throw ApiException(
        message: 'This device is no longer authorized. Please set it up again.',
        statusCode: 401,
        code: 'unauthorized',
      );
    }

    throw ApiException(
      message: 'Unexpected response from the server (HTTP $status).',
      statusCode: status,
    );
  }
}

class _Envelope {
  _Envelope(this.body);
  final Map<String, dynamic> body;
  Map<String, dynamic> get dataMap =>
      (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get metaMap =>
      (body['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
}

class ApiException implements Exception {
  ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.isNetwork = false,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final bool isNetwork;

  bool get isUnauthorized => statusCode == 401;

  factory ApiException.fromErrors(List<dynamic> errors, int? status) {
    final first = errors.first;
    if (first is Map) {
      return ApiException(
        message: (first['message'] ?? 'Request failed.').toString(),
        code: first['code']?.toString(),
        statusCode: status,
      );
    }
    return ApiException(message: first.toString(), statusCode: status);
  }

  @override
  String toString() => 'ApiException($statusCode${code != null ? ', $code' : ''}): $message';
}
