import '../services/pos_api_service.dart';
import 'combine_controller.dart';

class ApiCombineGateway implements CombineGateway {
  ApiCombineGateway(this.api, this.currentScope)
    : scope = currentScope(),
      token = api.tokenGetter();
  final PosApiService api;
  final String Function() currentScope;
  final String scope;
  final String? token;
  void check() {
    if (token == null ||
        token!.isEmpty ||
        api.tokenGetter() != token ||
        currentScope() != scope) {
      throw StateError(
        'Device context changed. Restore the original device session to recover.',
      );
    }
  }

  Future<T> call<T>(Future<T> Function() operation) async {
    check();
    final result = await operation();
    check();
    return result;
  }

  @override
  Future<Map<String, dynamic>> preview(int tableId, String sourceUuid) =>
      call(() => api.combinePreview(tableId, sourceUuid));
  @override
  Future<Map<String, dynamic>> confirm(
    int tableId,
    Map<String, dynamic> payload,
  ) => call(() => api.combineBill(tableId, payload));
}
