import 'package:dio/dio.dart';
import 'business_identity.dart';

class TenancyInterceptor extends Interceptor {
  TenancyInterceptor({this.tokenGetter});
  final String? Function()? tokenGetter;
  bool _stale(RequestOptions options) =>
      options.extra['_p0_generation'] != BusinessBoundary.generation.value ||
      (tokenGetter != null &&
          options.extra['_p0_token'] != tokenGetter!()?.trim());
  DioException _discard(RequestOptions options) => DioException(
    requestOptions: options,
    type: DioExceptionType.cancel,
    error: 'Discarded a response carrying an obsolete device credential.',
  );
  bool _activation(String path) =>
      path.endsWith('/activate') || path.endsWith('/pair');
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_p0_token'] = tokenGetter?.call()?.trim();
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
    final code =
        (body is Map ? body['code']?.toString() : null) ??
        (first is Map ? first['code']?.toString() : null);
    BusinessBoundary.observeError(response?.statusCode, code);
    if (response?.statusCode == 401 && code == null) {
      BusinessBoundary.block('device_reactivation_required');
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (_stale(response.requestOptions)) {
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
    if (_stale(error.requestOptions)) {
      handler.next(_discard(error.requestOptions));
      return;
    }
    _observe(error.response);
    handler.next(error);
  }
}
