import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Task 6 — "PIN entry UI with Argon2id-derived key wrapping"
/// (story checkpoint). The PIN itself is never stored, hashed-and-compared,
/// or transmitted anywhere -- it only ever exists transiently as Argon2id
/// input. Correctness is verified by whether AES-GCM decryption succeeds
/// (an authenticated cipher, so a wrong key fails loudly via
/// [SecretBoxAuthenticationError] rather than silently producing garbage),
/// which avoids storing a separate PIN hash that would itself be an
/// offline-crackable artifact if a device were compromised.
///
/// Parameters (memory/iterations) match OWASP's current Argon2id minimum
/// guidance for a low-entropy secret like a PIN: 19 MiB memory, 2
/// iterations, single-lane. These are a policy knob, not fixed by the
/// architecture -- revisit once there's a sense of real device performance
/// constraints, the same way the token TTL is flagged as revisitable.
class PinWrappedData {
  const PinWrappedData({required this.salt, required this.nonce, required this.cipherText, required this.mac});

  final List<int> salt;
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  Map<String, dynamic> toJson() => {
        'salt': base64Encode(salt),
        'nonce': base64Encode(nonce),
        'cipherText': base64Encode(cipherText),
        'mac': base64Encode(mac),
      };

  factory PinWrappedData.fromJson(Map<String, dynamic> json) => PinWrappedData(
        salt: base64Decode(json['salt'] as String),
        nonce: base64Decode(json['nonce'] as String),
        cipherText: base64Decode(json['cipherText'] as String),
        mac: base64Decode(json['mac'] as String),
      );
}

class PinService {
  const PinService();

  static const _saltLength = 16;

  Future<PinWrappedData> wrap({required String pin, required List<int> plaintext}) async {
    final salt = _randomBytes(_saltLength);
    final key = await _deriveKeyFromPin(pin, salt);
    final aesGcm = AesGcm.with256bits();
    final nonce = aesGcm.newNonce();
    final box = await aesGcm.encrypt(plaintext, secretKey: key, nonce: nonce);
    return PinWrappedData(salt: salt, nonce: nonce, cipherText: box.cipherText, mac: box.mac.bytes);
  }

  /// Returns the unwrapped plaintext if [pin] is correct, or `null` if it's
  /// wrong. Never throws for a wrong PIN -- that's an expected, common
  /// outcome, not an exceptional one; callers wire lockout-after-N-attempts
  /// (Task 9) around this return value.
  Future<List<int>?> unwrap({required String pin, required PinWrappedData data}) async {
    final key = await _deriveKeyFromPin(pin, data.salt);
    final aesGcm = AesGcm.with256bits();
    final box = SecretBox(data.cipherText, nonce: data.nonce, mac: Mac(data.mac));
    try {
      return await aesGcm.decrypt(box, secretKey: key);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  Future<SecretKey> _deriveKeyFromPin(String pin, List<int> salt) {
    final argon2id = Argon2id(parallelism: 1, memory: 19456, iterations: 2, hashLength: 32);
    return argon2id.deriveKeyFromPassword(password: pin, nonce: salt);
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
