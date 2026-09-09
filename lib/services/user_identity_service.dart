import 'dart:convert';
import 'dart:typed_data';

import 'package:biometric_signature/biometric_signature.dart';

/// Trust Anchor 3 (docs/roster-vault/Security/Trust Anchors.md): the
/// per-user credential. One ECDSA P-256 keypair per enrolled person per
/// device, generated here in Task 4c but not yet gated by a local factor
/// (`requireAuthentication: false`, same as the device key) -- the PIN/
/// biometric gate is Task 6's own scope, layered on top of this mechanism
/// rather than built into it now. Only the public half is ever sent to the
/// server (Task 4a's `enroll` mutation); [BiometricSignature] never
/// exposes a private key to Dart at all.
///
/// Mirrors [DeviceIdentityService]'s exact pattern (see its doc comment for
/// why `getKeyInfo` must always be checked before `createKeys`), generalized
/// to a per-user key alias instead of a single fixed one.
class UserIdentityService {
  UserIdentityService({BiometricSignature? biometricSignature})
      : _biometricSignature = biometricSignature ?? BiometricSignature();

  final BiometricSignature _biometricSignature;

  static String _keyAliasFor(String userId) => 'roster_vault_user_key_$userId';

  /// Returns this user's public key on this device, generating the keypair
  /// on first call for this userId only. Safe to call every enrollment
  /// attempt.
  Future<String> ensureUserKeyPair(String userId) async {
    final alias = _keyAliasFor(userId);

    final existing = await _biometricSignature.getKeyInfo(
      keyAlias: alias,
      checkValidity: true,
      keyFormat: KeyFormat.pem,
    );
    if (existing.exists == true && (existing.isValid ?? true) && existing.publicKey != null) {
      return existing.publicKey!;
    }

    final result = await _biometricSignature.createKeys(
      keyAlias: alias,
      keyFormat: KeyFormat.pem,
      config: CreateKeysConfig(
        signatureType: SignatureType.ecdsa,
        requireAuthentication: false,
      ),
    );
    final publicKey = result.publicKey;
    if (publicKey == null) {
      throw StateError('User key generation failed for $userId: ${result.code} ${result.error}');
    }
    return publicKey;
  }

  /// [OfflineVerifier]'s production `ChallengeSigner` (Task 5) -- signs
  /// `{"nonce": nonce}` as an ES256 JWS using this user's on-device private
  /// key, which never leaves `biometric_signature`'s native layer.
  ///
  /// Resolves the exact format question [OfflineVerifier]'s doc comment
  /// left open: `biometric_signature`'s Android implementation signs via
  /// `java.security.Signature.getInstance("SHA256withECDSA")` (confirmed by
  /// reading the plugin's own source, not guessed), which is standard JCA
  /// and always DER-encoded -- there is no P1363 output path anywhere in
  /// that plugin. JWS ES256 (RFC 7518 3.4) requires the fixed-width raw
  /// `R‖S` concatenation instead, so this does the same DER-to-raw
  /// conversion `amplify/functions/enroll/handler.ts` already does for
  /// KMS's DER output -- same wire format problem, same fix, ported to Dart.
  Future<String> signChallenge(String userId, String nonce) async {
    final alias = _keyAliasFor(userId);
    final header = base64UrlNoPad(utf8.encode(jsonEncode({'alg': 'ES256', 'typ': 'JWT'})));
    final payload = base64UrlNoPad(utf8.encode(jsonEncode({'nonce': nonce})));
    final signingInput = '$header.$payload';

    final result = await _biometricSignature.createSignature(
      payload: signingInput,
      keyAlias: alias,
      signatureFormat: SignatureFormat.raw,
    );
    final derSignature = result.signatureBytes;
    if (derSignature == null) {
      throw StateError('Challenge signing failed for $userId: ${result.code} ${result.error}');
    }

    final rawSignature = _derToRawEcdsaSignature(derSignature);
    return '$signingInput.${base64UrlNoPad(rawSignature)}';
  }

  static String base64UrlNoPad(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  /// DER SEQUENCE{INTEGER r, INTEGER s} -> fixed-width 64-byte raw `r‖s`
  /// (32 bytes each, left-zero-padded), for P-256. Mirrors
  /// `derToRawEcdsaSignature` in `amplify/functions/enroll/handler.ts`
  /// exactly -- same conversion, same reason, different signer.
  static Uint8List _derToRawEcdsaSignature(Uint8List der) {
    var offset = 0;
    if (der[offset++] != 0x30) throw const FormatException('Invalid DER signature: expected SEQUENCE');
    var seqLen = der[offset++];
    if (seqLen & 0x80 != 0) {
      final numBytes = seqLen & 0x7f;
      seqLen = 0;
      for (var i = 0; i < numBytes; i++) {
        seqLen = (seqLen << 8) | der[offset++];
      }
    }

    Uint8List readInt() {
      if (der[offset++] != 0x02) throw const FormatException('Invalid DER signature: expected INTEGER');
      var len = der[offset++];
      if (len & 0x80 != 0) {
        final numBytes = len & 0x7f;
        len = 0;
        for (var i = 0; i < numBytes; i++) {
          len = (len << 8) | der[offset++];
        }
      }
      final bytes = der.sublist(offset, offset + len);
      offset += len;
      return bytes;
    }

    final r = readInt();
    final s = readInt();

    Uint8List fixTo32(Uint8List v) {
      var trimmed = v;
      while (trimmed.length > 32 && trimmed[0] == 0x00) {
        trimmed = trimmed.sublist(1);
      }
      if (trimmed.length > 32) throw const FormatException('Invalid DER signature: integer too long for P-256');
      if (trimmed.length < 32) {
        final padded = Uint8List(32);
        padded.setRange(32 - trimmed.length, 32, trimmed);
        trimmed = padded;
      }
      return trimmed;
    }

    return Uint8List.fromList([...fixTo32(r), ...fixTo32(s)]);
  }
}
