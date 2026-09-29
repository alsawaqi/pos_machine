import '../tenancy/business_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:mithqal_softpos/mithqal_softpos.dart';
import 'package:uuid/uuid.dart';

typedef ReversalRequest =
    Future<Map<String, dynamic>> Function(
      String method,
      String path,
      Map<String, dynamic>? body,
    );
typedef ReversalBankCall =
    Future<SoftPosOutcome> Function(
      String method,
      Map<String, dynamic> arguments,
    );
typedef ReversalPrinter = Future<bool> Function(List<SlipLine> lines);

/// Online only. The server reservation is the durable recovery record.
class CardReversalController extends ChangeNotifier {
  CardReversalController({
    required this.request,
    required this.bank,
    required this.printSlip,
    required this.verifyManager,
    required this.profile,
    this.header = const [],
    this.orderReference = '',
    this.originalReceipt = '',
    this.originalCard,
    this.originalAuth,
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v4;
  final _identityGeneration = BusinessBoundary.generation.value;
  final ReversalRequest request;
  final ReversalBankCall bank;
  final ReversalPrinter printSlip;
  final Future<String?> Function(String pin) verifyManager;
  final SoftPosProfile profile;
  final List<String> header;
  final String orderReference, originalReceipt;
  final String? originalCard, originalAuth;
  final String Function() _newId;
  List<Map<String, dynamic>> payments = [], pending = [];
  Map<String, dynamic>? reservation, result;
  List<SlipLine> slip = [];
  bool busy = false, needsRecovery = false, printFailed = false;
  String? error, _orderUuid;
  String _approver = '';
  bool _disposed = false, _attemptedReserve = false;
  final Set<String> _launched = {}, _printAttempted = {};
  Map<String, dynamic>? _report;
  SoftPosOutcome? _outcome;
  Future<Map<String, dynamic>> _ownedRequest(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) {
    BusinessBoundary.assertWritable();
    BusinessBoundary.assertGeneration(_identityGeneration);
    return request(method, path, body);
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load(String orderUuid) async {
    _orderUuid = orderUuid;
    final data = await _ownedRequest(
      'GET',
      '/device/orders/$orderUuid/payments',
      null,
    );
    payments = _rows(data['payments']);
    _emit();
  }

  Future<void> recover() async {
    final data = await _ownedRequest(
      'GET',
      '/device/payments/reversals?status=pending,uncertain',
      null,
    );
    pending = _rows(data['reversals']);
    _emit();
  }

  static List<Map<String, dynamic>> _rows(Object? value) =>
      (value is List ? value : const [])
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList();

  Future<void> execute({
    required Map<String, dynamic> payment,
    required String kind,
    required String managerPin,
    int? voidReasonId,
    List<Map<String, dynamic>>? lines,
    int? customAmountBaisas,
    required Future<bool> Function(int baisas, String currency) confirmAmount,
  }) async {
    BusinessBoundary.assertWritable();
    BusinessBoundary.assertGeneration(_identityGeneration);
    if (busy || _attemptedReserve || needsRecovery) {
      throw StateError('reversal_in_progress');
    }
    if (kind != 'void' && kind != 'refund') throw ArgumentError.value(kind);
    if (payment[kind == 'void' ? 'can_void' : 'can_refund'] != true) {
      throw StateError(
        payment['unavailable_reason']?.toString() ?? 'reversal_unavailable',
      );
    }
    if (kind == 'void' && (voidReasonId == null || voidReasonId <= 0)) {
      throw StateError('void_reason_required');
    }
    if (kind == 'refund') {
      if ((lines?.isNotEmpty ?? false) == (customAmountBaisas != null)) {
        throw StateError('choose_refund_amount');
      }
      for (final line in lines ?? <Map<String, dynamic>>[]) {
        final available = _rows(payment['refundable_lines'])
            .where((item) => item['order_item_id'] == line['order_item_id'])
            .firstOrNull;
        final text = line['qty'].toString();
        final qty = num.tryParse(text);
        final remaining = num.tryParse(
          available?['remaining_qty']?.toString() ?? '',
        );
        if (qty == null ||
            remaining == null ||
            qty <= 0 ||
            qty > remaining ||
            !RegExp(r'^[0-9]+(?:\.[0-9]{1,3})?$').hasMatch(text)) {
          throw StateError('invalid_remaining_quantity');
        }
      }
    }
    busy = true;
    error = null;
    _emit();
    try {
      final name = await verifyManager(managerPin);
      if (name == null) throw StateError('invalid_manager_pin');
      _approver = name;
      _attemptedReserve = true;
      final data = await _ownedRequest(
        'POST',
        '/device/payments/${payment['payment_uuid']}/reversals',
        {
          'kind': kind,
          'manager_pin': managerPin,
          'client_request_id': _newId(),
          'reason_code': kind == 'void' ? 'void' : 'customer_request',
          'void_reason_id': ?voidReasonId,
          if (lines != null && lines.isNotEmpty) 'lines': lines,
          'custom_amount_baisas': ?customAmountBaisas,
        },
      );
      reservation = data;
      needsRecovery = true;
      _emit();
      final uuid = data['reversal_uuid'] as String;
      final amount = data['amount_baisas'] as int;
      baisasToOmr(amount);
      final currency = data['currency'] as String;
      SoftPosOutcome outcome;
      if (!await confirmAmount(amount, currency)) {
        outcome = SoftPosOutcome.fromPayload({
          'status': 'cancelled',
          'dispatchFailed': true,
          'description':
              'Operator cancelled before the bank application opened',
        });
      } else {
        BusinessBoundary.assertWritable();
        BusinessBoundary.assertGeneration(_identityGeneration);
        if (!_launched.add(uuid)) throw StateError('reversal_already_launched');
        final contract = softPosObject(data['softpos']);
        final args = <String, dynamic>{
          ...profile.channelArguments,
          'packageName': contract['package'],
          'needsSession': contract['needs_session'] == true,
          'needsTransactionId': contract['needs_transaction_id'] == true,
          'amountBaisas': amount,
          'currency': currency,
          'description': data['description'],
          if (kind == 'void' || contract['needs_transaction_id'] == true)
            'transactionId': data['original_transaction_id'],
        };
        SoftPosOutcome? login;
        if (contract['needs_session'] == true) {
          login = await bank('prepareLogin', args);
          if (login.sessionId != null) args['sessionId'] = login.sessionId;
        }
        outcome = login != null && login.sessionId == null
            ? SoftPosOutcome.fromPayload({
                'status': 'cancelled',
                'dispatchFailed': true,
                'code': login.payload['code'],
                'description': login.description,
                'login_response_code': login.responseCode,
                'login_response': login.payload,
              })
            : await bank(
                kind == 'void' ? 'voidTransaction' : 'refundTransaction',
                args,
              );
      }
      await _submit(data, outcome, _approver);
      if (_orderUuid != null) await load(_orderUuid!);
    } catch (failure) {
      error = failure.toString();
      if (_attemptedReserve && result == null) needsRecovery = true;
      rethrow;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> _submit(
    Map<String, dynamic> reserved,
    SoftPosOutcome outcome,
    String approver,
  ) async {
    reservation = reserved;
    _outcome = outcome;
    _approver = approver;
    final ids = outcome.identifiers;
    _report = {
      'client_request_id': _newId(),
      'status': outcome.verdict.name,
      'response_code':
          outcome.responseCode ?? outcome.payload['login_response_code'],
      'description': outcome.description,
      'receipt_json': outcome.payload,
      'reversal_transaction_id': ids.transactionId,
      'rrn': ids.rrn,
      'auth_code': ids.authCode,
    };
    await _sendReport();
  }

  Future<void> _sendReport() async {
    final reserved = reservation!;
    final uuid = reserved['reversal_uuid'] as String;
    result = await _ownedRequest(
      'POST',
      '/device/payments/reversals/$uuid/result',
      _report!,
    );
    _report = null;
    needsRecovery =
        result!['status'] == 'uncertain' || result!['status'] == 'pending';
    final outcome = _outcome!;
    if (outcome.verdict != SoftPosVerdict.approved &&
        outcome.verdict != SoftPosVerdict.declined) {
      slip = [];
      printFailed = false;
      _emit();
      return;
    }
    slip = buildReversalSlipLines(
      header: header,
      kind: reserved['kind'] as String,
      orderReference: reserved['order_reference']?.toString() ?? orderReference,
      originalReceiptNumber:
          reserved['original_receipt_number']?.toString() ??
          (originalReceipt.isEmpty ? '—' : originalReceipt),
      originalMaskedCard:
          reserved['original_masked_card']?.toString() ?? originalCard,
      originalAuthCode:
          reserved['original_auth_code']?.toString() ?? originalAuth,
      amountBaisas: reserved['amount_baisas'] as int,
      currency: reserved['currency'] as String,
      receipt: outcome.identifiers,
      responseCode: outcome.responseCode ?? '',
      description: outcome.description ?? outcome.verdict.name,
      occurredAt: DateTime.now().toLocal().toString(),
      approverName: reserved['approver_name']?.toString() ?? _approver,
    );
    if (_printAttempted.add(uuid)) printFailed = !await printSlip(slip);
    _emit();
  }

  /// Reuses the result idempotency key without another bank call.
  Future<void> retryReport() async {
    if (busy || _report == null) return;
    busy = true;
    _emit();
    try {
      await _sendReport();
    } finally {
      busy = false;
      _emit();
    }
  }

  /// Evidence entered from bank history; this path never calls the bank bridge.
  Future<void> reportObserved(
    Map<String, dynamic> reserved,
    SoftPosOutcome evidence, {
    required String operatorName,
  }) async {
    if (busy) return;
    if (evidence.verdict != SoftPosVerdict.approved &&
        evidence.verdict != SoftPosVerdict.declined) {
      throw StateError('authoritative_receipt_required');
    }
    if (evidence.identifiers.transactionId == null &&
        evidence.identifiers.rrn == null) {
      throw StateError('receipt_reference_required');
    }
    busy = true;
    _emit();
    try {
      await _submit(reserved, evidence, operatorName);
      await recover();
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> reprint() async {
    if (busy || slip.isEmpty) return;
    printFailed = !await printSlip(slip);
    _emit();
  }
}
