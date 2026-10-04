import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/approval_proof.dart';

/// LAUNCH-P5 C2 — the shared golden vectors (Claude's file, generated with
/// PHP and cross-checked with Node). The Dart PBKDF2 → check → HMAC proof
/// must match byte for byte, or the server can never verify a till approval.
void main() {
  final goldens =
      jsonDecode(
            File('test/fixtures/approval_proof_goldens.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final vectors = (goldens['vectors'] as List).cast<Map<String, dynamic>>();

  test('the fixture is present and has vectors', () {
    expect(vectors, hasLength(3));
  });

  for (final (index, v) in vectors.indexed) {
    test('vector $index: K, check, canonical and proof match', () {
      final key = approverKey(
        v['pin'] as String,
        v['salt_hex'] as String,
        v['iterations'] as int,
      );
      expect(
        key.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        v['k_hex'],
      );
      expect(approverCheck(key), v['check_hex']);
      final canonical = approvalCanonical(
        action: v['action'] as String,
        deviceUuid: v['device_uuid'] as String,
        approverStaffId: v['approver_staff_id'] as int,
        approvedAt: v['approved_at'] as String,
        subjectUuid: (v['subject_uuid'] as String?)?.isEmpty == true
            ? null
            : v['subject_uuid'] as String?,
        amountBaisas: v['amount_baisas'] as int?,
        ref: v['ref'] as String?,
      );
      expect(canonical, v['canonical']);
      expect(approvalProof(key, canonical), v['proof_hex']);
    });

    test('vector $index: a wrong PIN gives the wrong-PIN check', () {
      final wrong = approverKey(
        v['wrong_pin'] as String,
        v['salt_hex'] as String,
        v['iterations'] as int,
      );
      final check = approverCheck(wrong);
      expect(check, v['wrong_pin_check_hex']);
      expect(sameHex(check, v['check_hex'] as String), isFalse);
    });
  }

  test('approved_at is UTC ISO-8601 with milliseconds and a Z', () {
    expect(
      approvalTimestamp(DateTime.utc(2026, 10, 4, 9, 15, 30, 123, 456)),
      '2026-10-04T09:15:30.123Z',
    );
    expect(
      approvalTimestamp(DateTime.utc(2026, 1, 1)),
      '2026-01-01T00:00:00.000Z',
    );
    // A local time is converted to UTC first.
    final local = DateTime(2026, 10, 4, 13, 0, 0, 7);
    expect(approvalTimestamp(local), endsWith('Z'));
    expect(approvalTimestamp(local), contains('.007Z'));
  });

  test('sameHex compares without regard to case', () {
    expect(sameHex('ABcd', 'abCD'), isTrue);
    expect(sameHex('abcd', 'abce'), isFalse);
    expect(sameHex('abcd', 'abc'), isFalse);
  });
}
