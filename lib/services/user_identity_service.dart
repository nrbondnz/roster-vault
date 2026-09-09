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
}
