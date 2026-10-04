import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// LAUNCH-P5 C2 — the approval proof shared by pos_api, the till and the
/// handheld (work order "Approval proof"; golden vectors in
/// test/fixtures/approval_proof_goldens.json).
///
///   K       = PBKDF2-HMAC-SHA256(PIN as UTF-8, salt bytes, iterations, 32)
///   check   = hex(SHA-256("mithqal-approver-check-v1" ‖ K))
///   proof   = hex(HMAC-SHA256(K, canonical))
///
/// K never leaves the device and is never stored or logged: the device keeps
/// only `{salt, iterations, check}` per approver.
const approverCheckLabel = 'mithqal-approver-check-v1';

/// PBKDF2-HMAC-SHA256 with a 32-byte output (one block), built on the
/// `crypto` package's HMAC.
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations) {
  if (iterations < 1) {
    throw ArgumentError.value(iterations, 'iterations', 'must be positive');
  }
  final hmac = Hmac(sha256, password);
  // Block 1: U1 = HMAC(P, S ‖ INT(1)).
  final first = Uint8List(salt.length + 4)
    ..setAll(0, salt)
    ..[salt.length + 3] = 1;
  var u = Uint8List.fromList(hmac.convert(first).bytes);
  final result = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = Uint8List.fromList(hmac.convert(u).bytes);
    for (var j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return result;
}

/// The device-side key for [pin] under an approver's [saltHex].
Uint8List approverKey(String pin, String saltHex, int iterations) => (_isWeb
    ? pbkdf2Sha256
    : pbkdf2Sha256Fast)(utf8.encode(pin), hexToBytes(saltHex), iterations);

/// Web compiles ints to JavaScript numbers; the fast path needs 64-bit ints.
const bool _isWeb = identical(0, 0.0);

/// `check` for a key: what the device compares to find the approver.
String approverCheck(List<int> key) =>
    sha256.convert([...utf8.encode(approverCheckLabel), ...key]).toString();

/// `proof` over [canonical] with the approver's key.
String approvalProof(List<int> key, String canonical) =>
    Hmac(sha256, key).convert(utf8.encode(canonical)).toString();

/// UTC ISO-8601 with exactly millisecond precision and a Z.
String approvalTimestamp(DateTime at) {
  final u = at.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final ms = u.millisecond.toString().padLeft(3, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}.${ms}Z';
}

/// The canonical string the proof signs.
String approvalCanonical({
  required String action,
  required String deviceUuid,
  required int approverStaffId,
  required String approvedAt,
  String? subjectUuid,
  int? amountBaisas,
  String? ref,
}) => [
  'v1',
  action,
  deviceUuid,
  '$approverStaffId',
  approvedAt,
  subjectUuid ?? '',
  amountBaisas == null ? '' : '$amountBaisas',
  ref ?? '',
].join('|');

/// Constant-time comparison of two hex strings.
bool sameHex(String a, String b) {
  final x = a.toLowerCase(), y = b.toLowerCase();
  if (x.length != y.length) return false;
  var diff = 0;
  for (var i = 0; i < x.length; i++) {
    diff |= x.codeUnitAt(i) ^ y.codeUnitAt(i);
  }
  return diff == 0;
}

Uint8List hexToBytes(String hex) {
  final clean = hex.trim();
  if (clean.length.isOdd) throw const FormatException('Odd-length hex');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// PBKDF2-HMAC-SHA256 (32-byte output) — the fast path used on the device.
///
/// Same result as [pbkdf2Sha256] (cross-checked in tests and by the shared
/// golden vectors), but every iteration costs two SHA-256 compressions on
/// precomputed HMAC inner/outer states instead of four plus allocations, so
/// the T3 meets the ≤ 300 ms target at 100 000 iterations more easily. The
/// first block and every check/proof still use the `crypto` package.
Uint8List pbkdf2Sha256Fast(List<int> password, List<int> salt, int iterations) {
  if (iterations < 1) {
    throw ArgumentError.value(iterations, 'iterations', 'must be positive');
  }
  // HMAC key block.
  final key = Uint8List(64);
  if (password.length > 64) {
    key.setAll(0, sha256.convert(password).bytes);
  } else {
    key.setAll(0, password);
  }
  final ipad = Uint32List(16), opad = Uint32List(16);
  for (var i = 0; i < 16; i++) {
    final w =
        (key[i * 4] << 24) |
        (key[i * 4 + 1] << 16) |
        (key[i * 4 + 2] << 8) |
        key[i * 4 + 3];
    ipad[i] = w ^ 0x36363636;
    opad[i] = w ^ 0x5c5c5c5c;
  }
  final inner = Uint32List.fromList(_sha256Init);
  _sha256Compress(inner, ipad, Uint32List(64));
  final outer = Uint32List.fromList(_sha256Init);
  _sha256Compress(outer, opad, Uint32List(64));

  // U1 = HMAC(P, S ‖ INT(1)) with the crypto package.
  final first = Uint8List(salt.length + 4)
    ..setAll(0, salt)
    ..[salt.length + 3] = 1;
  final u1 = Hmac(sha256, password).convert(first).bytes;
  final u = Uint32List(8), acc = Uint32List(8);
  for (var i = 0; i < 8; i++) {
    u[i] =
        (u1[i * 4] << 24) |
        (u1[i * 4 + 1] << 16) |
        (u1[i * 4 + 2] << 8) |
        u1[i * 4 + 3];
    acc[i] = u[i];
  }
  // One 64-byte block: 32 bytes of message, 0x80, zeros, bit length 768
  // (the 64-byte pad block + 32 bytes).
  final block = Uint32List(16)
    ..[8] = 0x80000000
    ..[15] = 768;
  final state = Uint32List(8), w = Uint32List(64);
  for (var n = 1; n < iterations; n++) {
    for (var i = 0; i < 8; i++) {
      block[i] = u[i];
    }
    state.setAll(0, inner);
    _sha256Compress(state, block, w);
    for (var i = 0; i < 8; i++) {
      block[i] = state[i];
    }
    state.setAll(0, outer);
    _sha256Compress(state, block, w);
    for (var i = 0; i < 8; i++) {
      u[i] = state[i];
      acc[i] ^= state[i];
    }
  }
  final out = Uint8List(32);
  for (var i = 0; i < 8; i++) {
    out[i * 4] = acc[i] >> 24;
    out[i * 4 + 1] = (acc[i] >> 16) & 0xff;
    out[i * 4 + 2] = (acc[i] >> 8) & 0xff;
    out[i * 4 + 3] = acc[i] & 0xff;
  }
  return out;
}

const List<int> _sha256Init = [
  0x6a09e667,
  0xbb67ae85,
  0x3c6ef372,
  0xa54ff53a,
  0x510e527f,
  0x9b05688c,
  0x1f83d9ab,
  0x5be0cd19,
];

const List<int> _sha256K = [
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

/// One SHA-256 compression of the 16-word [block] into [h] (in place).
void _sha256Compress(Uint32List h, Uint32List block, Uint32List w) {
  for (var t = 0; t < 16; t++) {
    w[t] = block[t];
  }
  for (var t = 16; t < 64; t++) {
    final a = w[t - 15], b = w[t - 2];
    final s0 = _rotr(a, 7) ^ _rotr(a, 18) ^ (a >> 3);
    final s1 = _rotr(b, 17) ^ _rotr(b, 19) ^ (b >> 10);
    w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xffffffff;
  }
  var a = h[0], b = h[1], c = h[2], d = h[3];
  var e = h[4], f = h[5], g = h[6], hh = h[7];
  for (var t = 0; t < 64; t++) {
    final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
    final ch = (e & f) ^ (~e & 0xffffffff & g);
    final t1 = (hh + s1 + ch + _sha256K[t] + w[t]) & 0xffffffff;
    final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
    final maj = (a & b) ^ (a & c) ^ (b & c);
    final t2 = (s0 + maj) & 0xffffffff;
    hh = g;
    g = f;
    f = e;
    e = (d + t1) & 0xffffffff;
    d = c;
    c = b;
    b = a;
    a = (t1 + t2) & 0xffffffff;
  }
  h[0] = (h[0] + a) & 0xffffffff;
  h[1] = (h[1] + b) & 0xffffffff;
  h[2] = (h[2] + c) & 0xffffffff;
  h[3] = (h[3] + d) & 0xffffffff;
  h[4] = (h[4] + e) & 0xffffffff;
  h[5] = (h[5] + f) & 0xffffffff;
  h[6] = (h[6] + g) & 0xffffffff;
  h[7] = (h[7] + hh) & 0xffffffff;
}
