import 'package:dio/dio.dart';
import 'business_identity.dart';

class TenancyInterceptor extends Interceptor {
  bool _activation(String path) =>
      path.endsWith('/activate') || path.endsWith('/pair');
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_p0_generation'] = BusinessBoundary.generation.value;
    if (!BusinessBoundary.canWork &&
        !_activation(options.path) &&
        !options.path.endsWith('/heartbeat')) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'Device business access is blocked.',
        ),
      );
      return;
    }
    handler.next(options);
  }

  void _observe(Response? response) {
    final body = response?.data;
    final errors = body is Map ? body['errors'] : null;
    final first = errors is List && errors.isNotEmpty ? errors.first : null;
    final code = first is Map ? first['code']?.toString() : null;
    BusinessBoundary.observeError(response?.statusCode, code);
    if (response?.statusCode == 401 && code == null) {
      BusinessBoundary.block('device_reactivation_required');
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.extra['_p0_generation'] !=
        BusinessBoundary.generation.value) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          type: DioExceptionType.cancel,
          error: 'Discarded a response from the previous device identity.',
        ),
      );
      return;
    }
    _observe(response);
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    if (error.requestOptions.extra['_p0_generation'] ==
        BusinessBoundary.generation.value)
      _observe(error.response);
    handler.next(error);
  }
}
