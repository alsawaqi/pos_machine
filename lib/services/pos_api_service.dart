import 'package:dio/dio.dart';

import '../core/api_config.dart';
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
