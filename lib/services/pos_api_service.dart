import 'package:dio/dio.dart';

import '../core/api_config.dart';
import 'api_models.dart';

typedef TokenGetter = String? Function();
typedef UnauthorizedCallback = void Function();

/// Thin wrapper over pos_api `/api/v1`. Attaches the device Bearer token,
/// unwraps the `{ data, meta, errors }` envelope, and maps failures to
/// [ApiException]. A 401 fires [onUnauthorized] so the gate can drop to pairing.
class PosApiService {
  PosApiService({
    required this.tokenGetter,
    this.onUnauthorized,
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
  /// `data` map plus the device's terminal_id from `meta` (for the Soft POS).
  Future<({Map<String, dynamic> data, String? terminalId})> fetchConfig() async {
    final body = await _send(() => _dio.get('/device/config'));
    return (data: body.dataMap, terminalId: body.metaMap['terminal_id'] as String?);
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
