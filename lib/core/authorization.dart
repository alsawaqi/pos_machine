import 'dart:typed_data';

import 'approval_proof.dart';

/// One approval: who approved, when and how. Keeps the approver's key in
/// memory only (never stored, never logged) so an approval given before its
/// subject exists (a cart discount, before the order uuid) can be signed
/// when the sale completes. [forget] wipes it.
class ApprovalGrant {
  ApprovalGrant({
    required this.approverStaffId,
    required this.name,
    required this.approvedAt,
    required this.method,
    this.position,
    Uint8List? key,
  }) : _key = key;

  final int approverStaffId;
  final String name;
  final String? position;
  final DateTime approvedAt;

  /// `offline` (stored verifier) or `online` (verify-manager-pin).
  final String method;
  Uint8List? _key;

  bool get canSign => _key != null;
  String get approvedAtText => approvalTimestamp(approvedAt);

  String? proofFor({
    required String action,
    required String deviceUuid,
    String? subjectUuid,
    int? amountBaisas,
    String? ref,
  }) {
    final key = _key;
    if (key == null) return null;
    return approvalProof(
      key,
      approvalCanonical(
        action: action,
        deviceUuid: deviceUuid,
        approverStaffId: approverStaffId,
        approvedAt: approvedAtText,
        subjectUuid: subjectUuid,
        amountBaisas: amountBaisas,
        ref: ref,
      ),
    );
  }

  /// Wipe the key from memory once every block of the approval is signed.
  void forget() {
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
  }
}

/// The outcome of a gate: allowed by the person's own tick (`position`) or
/// by an approver's PIN (`approval`). [block] is the wire's authorization
/// block.
class ActionAuthorization {
  ActionAuthorization.position({
    required this.action,
    required this.actorStaffId,
    required this.actorName,
    this.deviceUuid = '',
  }) : mode = 'position',
       grant = null;

  ActionAuthorization.approval({
    required this.action,
    required this.actorStaffId,
    required this.actorName,
    required ApprovalGrant this.grant,
    required this.deviceUuid,
  }) : mode = 'approval';

  final String action;
  final String mode;
  final int? actorStaffId;
  final String actorName;
  final ApprovalGrant? grant;
  final String deviceUuid;

  bool get isApproval => mode == 'approval';

  /// The name to show / journal as "authorized by" (never the fixed word
  /// "Manager").
  String get authorizedByName => grant?.name ?? actorName;

  /// The staff id that allowed it: the approver, or the actor's own tick.
  int? get authorizerStaffId => grant?.approverStaffId ?? actorStaffId;

  /// The authorization block (work order "Device sync wire"). An approval
  /// is signed over [subjectUuid], [amountBaisas] and [ref]; those values
  /// also ride in the block (additive) so the server can see what was
  /// signed.
  Map<String, dynamic> block({
    String? subjectUuid,
    int? amountBaisas,
    String? ref,
  }) {
    final out = <String, dynamic>{
      'action': action,
      'ref': ref,
      'mode': mode,
      'actor_staff_id': actorStaffId,
    };
    final g = grant;
    if (g != null) {
      out['approver_staff_id'] = g.approverStaffId;
      out['approved_at'] = g.approvedAtText;
      out['method'] = g.method;
      final proof = g.proofFor(
        action: action,
        deviceUuid: deviceUuid,
        subjectUuid: subjectUuid,
        amountBaisas: amountBaisas,
        ref: ref,
      );
      if (proof != null) out['proof'] = proof;
      if (subjectUuid != null && subjectUuid.isNotEmpty) {
        out['subject_uuid'] = subjectUuid;
      }
      if (amountBaisas != null) out['amount_baisas'] = amountBaisas;
    }
    return out;
  }
}
