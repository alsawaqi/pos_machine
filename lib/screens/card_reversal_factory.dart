import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../state/card_reversal_controller.dart';
import '../services/mosambee_payment_service.dart';
import '../services/sunmi_receipt_service.dart';

CardReversalController createMachineReversalController(
  WidgetRef ref, {
  List<String> header = const [],
  String reference = '',
  String receipt = '',
  String? originalCard,
  String? originalAuth,
}) {
  final api = ref.read(apiServiceProvider);
  final session = ref.read(sessionServiceProvider);
  return CardReversalController(
    request: api.reversalRequest,
    bank: MosambeePaymentService().invokeBank,
    printSlip: SunmiReceiptService.printReversalSlip,
    verifyManager: api.verifyManagerPin,
    profile: session.softpos,
    header: header.isNotEmpty
        ? header
        : ref
                  .read(catalogProvider)
                  .asData
                  ?.value
                  .receiptTemplate
                  ?.headerLines ??
              const [],
    orderReference: reference,
    originalReceipt: receipt,
    originalCard: originalCard,
    originalAuth: originalAuth,
  );
}
