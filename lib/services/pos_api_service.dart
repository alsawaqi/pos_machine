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

  /// POST /auth/device/pair — one-time device setup: the device pairs with its
  /// kiosk ID + a one-time activation token and receives a device token.
  Future<PairResult> pairDevice({
    required String kioskId,
    required String activationToken,
  }) async {
    final body = await _send(() => _dio.post('/auth/device/pair', data: {
          'kiosk_id': kioskId,
          'activation_token': activationToken,
        }));
    return PairResult.fromJson(body.dataMap);
  }

  /// POST /auth/pos/login — staff PIN login (Bearer device token).
  Future<StaffSessionData> staffLogin({required String pin}) async {
    final body = await _send(() => _dio.post('/auth/pos/login', data: {'pin': pin}));
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

    if (status == 401) {
      onUnauthorized?.call();
      throw ApiException(
        message: 'This device is no longer authorized. Please pair it again.',
        statusCode: 401,
        code: 'unauthorized',
      );
    }

    if (body is Map) {
      final map = body.cast<String, dynamic>();
      final errors = map['errors'];
      if (errors is List && errors.isNotEmpty) {
        throw ApiException.fromErrors(errors, status);
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
