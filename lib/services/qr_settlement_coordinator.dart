import '../data/order_sync_repository.dart';
import '../models/pos_models.dart';
import '../models/qr_till_models.dart';
import 'package:geolocator/geolocator.dart';
import 'mosambee_payment_service.dart';
import 'qr_till_service.dart';

enum QrSettlementResultKind {
  paid,
  cardCancelledBeforeCapture,
  cardFailedBeforeCapture,
  cardUncertain,
  cashRefusedAfterTender,
  cardRefusedAfterCapture,
  awaitingServerAcknowledgement,
}

class QrSettlementResult {
  const QrSettlementResult({
    required this.kind,
    required this.claim,
    this.clientEventId,
    this.serverError,
    this.releaseError,
  });

  final QrSettlementResultKind kind;
  final QrSettlementClaim claim;
  final String? clientEventId;
  final String? serverError;
  final Object? releaseError;

  bool get returnCash => kind == QrSettlementResultKind.cashRefusedAfterTender;

  bool get managerRequired => switch (kind) {
    QrSettlementResultKind.cardUncertain ||
    QrSettlementResultKind.cardRefusedAfterCapture ||
    QrSettlementResultKind.awaitingServerAcknowledgement => true,
    _ => false,
  };

  bool get mustNotRetryTender => switch (kind) {
    QrSettlementResultKind.paid ||
    QrSettlementResultKind.cardCancelledBeforeCapture ||
    QrSettlementResultKind.cardFailedBeforeCapture => false,
    _ => true,
  };
}

class QrPaymentAttemptUnresolved implements Exception {
  const QrPaymentAttemptUnresolved(this.orderUuid);

  final String orderUuid;
  String get code => 'qr_payment_attempt_unresolved';

  @override
  String toString() =>
      'A prior QR payment attempt is still unresolved for $orderUuid.';
}

class QrSettlementClaimNotHeld implements Exception {
  const QrSettlementClaimNotHeld(this.orderUuid);

  final String orderUuid;
  String get code => 'qr_settlement_claim_not_held';
}

class QrSettlementClaimExpired implements Exception {
  const QrSettlementClaimExpired(this.orderUuid, {this.releaseError});

  final String orderUuid;
  final Object? releaseError;
  String get code => 'qr_settlement_claim_expired';
}

class QrSettlementClaimChanged implements Exception {
  const QrSettlementClaimChanged(this.orderUuid, {this.releaseError});

  final String orderUuid;
  final Object? releaseError;
  String get code => 'qr_settlement_claim_changed';
}

class QrSettlementRevalidationFailed implements Exception {
  const QrSettlementRevalidationFailed(
    this.orderUuid, {
    required this.cause,
    this.releaseError,
  });

  final String orderUuid;
  final Object cause;
  final Object? releaseError;
  String get code => 'qr_settlement_revalidation_failed';
}

abstract interface class QrCardTerminalGateway {
  Future<MosambeePaymentResult> captureBaisas(int amountBaisas);
}

typedef QrGeoFix = ({double lat, double lng});

abstract interface class QrLocationGateway {
  Future<QrGeoFix?> currentFix();
}

class GeolocatorQrLocation implements QrLocationGateway {
  const GeolocatorQrLocation();

  @override
  Future<QrGeoFix?> currentFix() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 5));
      return (lat: position.latitude, lng: position.longitude);
    } catch (_) {
      // A cached fix may describe a different branch. Fenced branches fail
      // closed on the missing GPS; unfenced branches accept the omitted field.
      return null;
    }
  }
}

class MosambeeQrCardTerminal implements QrCardTerminalGateway {
  MosambeeQrCardTerminal(this._service);

  final MosambeePaymentService _service;

  @override
  Future<MosambeePaymentResult> captureBaisas(int amountBaisas) =>
      _service.payWithPreparedSessionBaisas(amountBaisas);
}

abstract interface class QrSettlementOutbox {
  Future<bool> hasUnresolvedPayment(String orderUuid);
  Future<StandaloneQrPayResult> enqueuePayment({
    required String orderUuid,
    required int frozenAmountBaisas,
    required QrTender tender,
    CardCharge? cardCharge,
    double? lat,
    double? lng,
  });
  Future<void> retirePayment(String orderUuid, {required String reason});
  Future<void> enqueueVoid(
    String orderUuid, {
    String? reason,
    int? voidReasonId,
    int? staffId,
    String? authorizedBy,
  });
}

class OrderSyncQrSettlementOutbox implements QrSettlementOutbox {
  OrderSyncQrSettlementOutbox(this._repository);

  final OrderSyncRepository _repository;

  @override
  Future<bool> hasUnresolvedPayment(String orderUuid) =>
      _repository.hasUnresolvedStandaloneQrPay(orderUuid);

  @override
  Future<StandaloneQrPayResult> enqueuePayment({
    required String orderUuid,
    required int frozenAmountBaisas,
    required QrTender tender,
    CardCharge? cardCharge,
    double? lat,
    double? lng,
  }) => _repository.enqueueStandaloneQrPay(
    orderUuid: orderUuid,
    frozenAmountBaisas: frozenAmountBaisas,
    method: tender.name,
    cardCharge: cardCharge,
    lat: lat,
    lng: lng,
  );

  @override
  Future<void> retirePayment(String orderUuid, {required String reason}) =>
      _repository.retireStandaloneQrPay(orderUuid, reason: reason);

  @override
  Future<void> enqueueVoid(
    String orderUuid, {
    String? reason,
    int? voidReasonId,
    int? staffId,
    String? authorizedBy,
  }) => _repository.enqueueVoid(
    orderUuid,
    reason: reason,
    voidReasonId: voidReasonId,
    staffId: staffId,
    authorizedBy: authorizedBy,
  );
}

abstract interface class QrSettlementFlow {
  Future<QrSettlementClaim> claim(String orderUuid);
  Future<QrSettlementResult> settleClaim(
    QrSettlementClaim claim,
    QrTender tender,
  );
  Future<void> releaseClaim(
    QrSettlementClaim claim,
    QrReleaseOutcome outcome, {
    MosambeePaymentResult? terminalResult,
  });
  Future<void> voidOrder(
    String orderUuid, {
    String? reason,
    int? voidReasonId,
    int? staffId,
    String? authorizedBy,
  });
}

/// Claim-first QR settlement. This service has no access to PosController,
/// local cart/drafts/held orders/history, or client-side pricing.
class QrSettlementCoordinator implements QrSettlementFlow {
  QrSettlementCoordinator({
    required QrTillGateway till,
    required QrSettlementOutbox outbox,
    required QrCardTerminalGateway terminal,
    required QrLocationGateway location,
    DateTime Function()? now,
  }) : _till = till,
       _outbox = outbox,
       _terminal = terminal,
       _location = location,
       _now = now ?? DateTime.now;

  final QrTillGateway _till;
  final QrSettlementOutbox _outbox;
  final QrCardTerminalGateway _terminal;
  final QrLocationGateway _location;
  final DateTime Function() _now;
  final Map<String, QrSettlementClaim> _heldClaims =
      <String, QrSettlementClaim>{};
  final Map<String, QrGeoFix?> _heldClaimFixes = <String, QrGeoFix?>{};
  final Set<String> _settling = <String>{};

  @override
  Future<QrSettlementClaim> claim(String orderUuid) async {
    if (await _outbox.hasUnresolvedPayment(orderUuid)) {
      throw QrPaymentAttemptUnresolved(orderUuid);
    }
    final fix = await _location.currentFix();
    final claim = await _till.claimSettlement(
      orderUuid,
      lat: fix?.lat,
      lng: fix?.lng,
    );
    _heldClaims[claim.orderUuid] = claim;
    _heldClaimFixes[claim.orderUuid] = fix;
    return claim;
  }

  @override
  Future<QrSettlementResult> settleClaim(
    QrSettlementClaim claim,
    QrTender tender,
  ) async {
    if (!identical(_heldClaims[claim.orderUuid], claim) ||
        !_settling.add(claim.orderUuid)) {
      throw QrSettlementClaimNotHeld(claim.orderUuid);
    }

    try {
      return await _settleHeldClaim(claim, tender);
    } finally {
      _settling.remove(claim.orderUuid);
    }
  }

  Future<QrSettlementResult> _settleHeldClaim(
    QrSettlementClaim claim,
    QrTender tender,
  ) async {
    // Never begin a physical tender at the edge of a lapsed reservation. The
    // server replay below is the authoritative same-holder revalidation; this
    // local margin avoids launching a terminal while that request is doomed by
    // obvious clock expiry.
    if (!claim.deadlineAt.isAfter(_now().add(const Duration(seconds: 5)))) {
      final releaseError = await _releaseCapturingError(
        claim,
        QrReleaseOutcome.cancelled,
        null,
      );
      throw QrSettlementClaimExpired(
        claim.orderUuid,
        releaseError: releaseError,
      );
    }
    final fix = _heldClaimFixes[claim.orderUuid];
    final QrSettlementClaim verified;
    try {
      verified = await _till.claimSettlement(
        claim.orderUuid,
        lat: fix?.lat,
        lng: fix?.lng,
      );
    } catch (error) {
      final releaseError = await _releaseCapturingError(
        claim,
        QrReleaseOutcome.cancelled,
        null,
      );
      throw QrSettlementRevalidationFailed(
        claim.orderUuid,
        cause: error,
        releaseError: releaseError,
      );
    }
    if (verified.orderUuid != claim.orderUuid ||
        verified.status != 'awaiting_payment' ||
        !verified.alreadyClaimedByThisDevice ||
        verified.frozenAmountBaisas != claim.frozenAmountBaisas) {
      final releaseError = await _releaseCapturingError(
        claim,
        QrReleaseOutcome.cancelled,
        null,
      );
      throw QrSettlementClaimChanged(
        claim.orderUuid,
        releaseError: releaseError,
      );
    }
    if (!verified.deadlineAt.isAfter(_now().add(const Duration(seconds: 5)))) {
      final releaseError = await _releaseCapturingError(
        claim,
        QrReleaseOutcome.cancelled,
        null,
      );
      throw QrSettlementClaimExpired(
        claim.orderUuid,
        releaseError: releaseError,
      );
    }
    _heldClaims[claim.orderUuid] = verified;
    claim = verified;

    CardCharge? cardCharge;
    MosambeePaymentResult? terminalResult;

    if (tender == QrTender.card) {
      try {
        terminalResult = await _terminal.captureBaisas(
          claim.frozenAmountBaisas,
        );
      } catch (error) {
        // Once a terminal launch was attempted, a thrown transport/plugin
        // error cannot prove that the card was untouched. Treat it as unknown,
        // release uncertain, and never offer an automatic second tap.
        final releaseError = await _releaseCapturingError(
          claim,
          QrReleaseOutcome.uncertain,
          null,
        );
        return QrSettlementResult(
          kind: QrSettlementResultKind.cardUncertain,
          claim: claim,
          serverError: error.toString(),
          releaseError: releaseError,
        );
      }
      if (terminalResult.isCanceled) {
        final releaseError = await _releaseCapturingError(
          claim,
          QrReleaseOutcome.cancelled,
          terminalResult,
        );
        return QrSettlementResult(
          kind: QrSettlementResultKind.cardCancelledBeforeCapture,
          claim: claim,
          releaseError: releaseError,
        );
      }
      if (terminalResult.neverReachedTerminal) {
        final releaseError = await _releaseCapturingError(
          claim,
          QrReleaseOutcome.cancelled,
          terminalResult,
        );
        return QrSettlementResult(
          kind: QrSettlementResultKind.cardFailedBeforeCapture,
          claim: claim,
          serverError: terminalResult.userMessage,
          releaseError: releaseError,
        );
      }
      if (terminalResult.isUncertain) {
        final releaseError = await _releaseCapturingError(
          claim,
          QrReleaseOutcome.uncertain,
          terminalResult,
        );
        return QrSettlementResult(
          kind: QrSettlementResultKind.cardUncertain,
          claim: claim,
          serverError: terminalResult.userMessage,
          releaseError: releaseError,
        );
      }
      cardCharge = CardCharge(
        softposReference: terminalResult.softposReference,
        softposAuthCode: terminalResult.softposAuthCode,
        bankResponse: terminalResult.payload,
      );
    }

    final StandaloneQrPayResult pushed;
    try {
      pushed = await _outbox.enqueuePayment(
        orderUuid: claim.orderUuid,
        frozenAmountBaisas: claim.frozenAmountBaisas,
        tender: tender,
        cardCharge: cardCharge,
        lat: _heldClaimFixes[claim.orderUuid]?.lat,
        lng: _heldClaimFixes[claim.orderUuid]?.lng,
      );
    } catch (error) {
      final outcome = tender == QrTender.cash
          ? QrReleaseOutcome.cancelled
          : QrReleaseOutcome.uncertain;
      final releaseError = await _releaseCapturingError(
        claim,
        outcome,
        terminalResult,
      );
      return QrSettlementResult(
        kind: tender == QrTender.cash
            ? QrSettlementResultKind.cashRefusedAfterTender
            : QrSettlementResultKind.cardRefusedAfterCapture,
        claim: claim,
        serverError: error.toString(),
        releaseError: releaseError,
      );
    }

    switch (pushed.state) {
      case StandaloneQrPayState.processed:
        _heldClaims.remove(claim.orderUuid);
        _heldClaimFixes.remove(claim.orderUuid);
        return QrSettlementResult(
          kind: QrSettlementResultKind.paid,
          claim: claim,
          clientEventId: pushed.clientEventId,
        );
      case StandaloneQrPayState.pending:
        // No ACK is not a refusal. Keep the durable event and claim intact; a
        // reconnect replays the SAME event UUID. A second tender is blocked.
        return QrSettlementResult(
          kind: QrSettlementResultKind.awaitingServerAcknowledgement,
          claim: claim,
          clientEventId: pushed.clientEventId,
          serverError: pushed.error,
        );
      case StandaloneQrPayState.refused:
        final outcome = tender == QrTender.cash
            ? QrReleaseOutcome.cancelled
            : QrReleaseOutcome.uncertain;
        final releaseError = await _releaseCapturingError(
          claim,
          outcome,
          terminalResult,
        );
        if (releaseError == null) {
          await _outbox.retirePayment(
            claim.orderUuid,
            reason: tender == QrTender.cash
                ? 'Cash returned after QR payment refusal.'
                : 'Card payment refused after capture; manager recovery.',
          );
        }
        return QrSettlementResult(
          kind: tender == QrTender.cash
              ? QrSettlementResultKind.cashRefusedAfterTender
              : QrSettlementResultKind.cardRefusedAfterCapture,
          claim: claim,
          clientEventId: pushed.clientEventId,
          serverError: pushed.error,
          releaseError: releaseError,
        );
    }
  }

  Future<Object?> _releaseCapturingError(
    QrSettlementClaim claim,
    QrReleaseOutcome outcome,
    MosambeePaymentResult? terminalResult,
  ) async {
    try {
      await releaseClaim(claim, outcome, terminalResult: terminalResult);
      return null;
    } catch (error) {
      return error;
    }
  }

  @override
  Future<void> releaseClaim(
    QrSettlementClaim claim,
    QrReleaseOutcome outcome, {
    MosambeePaymentResult? terminalResult,
  }) async {
    await _till.releaseSettlement(
      claim.orderUuid,
      outcome,
      softposReference: terminalResult?.softposReference,
      softposAuthCode: terminalResult?.softposAuthCode,
      bankResponse: terminalResult?.payload,
    );
    _heldClaims.remove(claim.orderUuid);
    _heldClaimFixes.remove(claim.orderUuid);
  }

  @override
  Future<void> voidOrder(
    String orderUuid, {
    String? reason,
    int? voidReasonId,
    int? staffId,
    String? authorizedBy,
  }) => _outbox.enqueueVoid(
    orderUuid,
    reason: reason,
    voidReasonId: voidReasonId,
    staffId: staffId,
    authorizedBy: authorizedBy,
  );
}
