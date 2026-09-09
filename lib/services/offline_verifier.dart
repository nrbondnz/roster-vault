import 'dart:convert';
import 'dart:math';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Task 5 — the actual hard requirement. Implements every step of
/// docs/roster-vault/Architecture/Offline Sign-In Flow.md steps 4-6
/// (signature, expiry/device-id/epoch, challenge-response). No step in
/// this class makes a network call — that is the entire point of it, and
/// is enforced by construction: nothing here imports `http` or Amplify.
///
/// Per the Story Agent's directive ("never claim offline without proving
/// it"), this class being network-call-free by inspection is necessary
/// but not sufficient proof on its own — see the story checkpoint's Task 5
/// entry for how this was actually demonstrated with the app's network
/// access physically cut off.
enum OfflineVerificationFailure {
  /// Signature doesn't verify against the issuer's public key -- forged,
  /// corrupted, or signed by a different key entirely.
  badSignature,

  /// Token's `exp` claim has passed.
  expired,

  /// Token's `device_id` claim doesn't match this device's own id --
  /// Trust Anchor 2, stops a copied token+credential pair from working on
  /// a different physical device.
  wrongDevice,

  /// Token's `epoch` claim is older than the epoch recorded on this device
  /// from its last successful enrollment/refresh -- see
  /// docs/roster-vault/Security/Token Lifecycle and Revocation.md. Comparison
  /// direction matters: reject only when `token.epoch < currentKnownEpoch`.
  staleEpoch,

  /// The local private key couldn't prove possession of the credential the
  /// token's `userPubKey` was registered with -- Trust Anchor 3. Stops a
  /// copied token blob (without the matching private key) from working.
  challengeFailed,
}

class OfflineVerificationResult {
  const OfflineVerificationResult.valid(this.claims) : failure = null;

  const OfflineVerificationResult.invalid(OfflineVerificationFailure this.failure, {this.claims = const {}});

  final OfflineVerificationFailure? failure;
  final Map<String, dynamic> claims;

  bool get isValid => failure == null;
}

/// Signs [challengeNonce] with the person's local private key and returns
/// a JWS asserting it (payload `{"nonce": challengeNonce}`, ES256). In
/// production this is backed by `biometric_signature`'s per-user key alias
/// (Trust Anchor 3, `UserIdentityService`'s alias convention); tests inject
/// a fake signer instead, since exercising the real one requires
/// hardware-backed key material this module has no business depending on
/// directly -- verification logic and "how the local key happens to be
/// stored" are deliberately separate concerns.
typedef ChallengeSigner = Future<String> Function(String challengeNonce);

class OfflineVerifier {
  const OfflineVerifier();

  /// Runs every check in docs/roster-vault/Architecture/Offline Sign-In
  /// Flow.md steps 4-6, in order, short-circuiting on the first failure --
  /// all four checks matter, but there is no reason to run a challenge
  /// round trip against a token that's already expired.
  Future<OfflineVerificationResult> verify({
    required String token,
    required String issuerPublicKeyPem,
    required String expectedDeviceId,
    required int currentKnownEpoch,
    required String userPublicKeyPem,
    required ChallengeSigner signChallenge,
  }) async {
    final JWT jwt;
    try {
      jwt = JWT.verify(token, ECPublicKey(issuerPublicKeyPem));
    } on JWTExpiredException {
      return OfflineVerificationResult.invalid(OfflineVerificationFailure.expired, claims: _unsafeDecodeClaims(token));
    } on JWTException {
      return OfflineVerificationResult.invalid(
        OfflineVerificationFailure.badSignature,
        claims: _unsafeDecodeClaims(token),
      );
    }
    final claims = jwt.payload as Map<String, dynamic>;

    if (claims['device_id'] != expectedDeviceId) {
      return OfflineVerificationResult.invalid(OfflineVerificationFailure.wrongDevice, claims: claims);
    }

    // Comparison direction matters -- see Token Lifecycle and Revocation.md
    // "Comparison Direction Matters". Reject only strictly-older tokens;
    // a token epoch equal to or newer than what's on record is fine (a
    // freshly refreshed token should never be rejected by the device's own
    // just-updated record of itself).
    final tokenEpoch = claims['epoch'] as int;
    if (tokenEpoch < currentKnownEpoch) {
      return OfflineVerificationResult.invalid(OfflineVerificationFailure.staleEpoch, claims: claims);
    }

    final nonce = _randomNonce();
    final String challengeResponse;
    try {
      challengeResponse = await signChallenge(nonce);
    } catch (_) {
      return OfflineVerificationResult.invalid(OfflineVerificationFailure.challengeFailed, claims: claims);
    }
    try {
      final challengeJwt = JWT.verify(challengeResponse, ECPublicKey(userPublicKeyPem));
      final echoedNonce = (challengeJwt.payload as Map<String, dynamic>)['nonce'];
      if (echoedNonce != nonce) {
        return OfflineVerificationResult.invalid(OfflineVerificationFailure.challengeFailed, claims: claims);
      }
    } on JWTException {
      return OfflineVerificationResult.invalid(OfflineVerificationFailure.challengeFailed, claims: claims);
    }

    return OfflineVerificationResult.valid(claims);
  }

  String _randomNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Best-effort claim decode for display purposes when signature/expiry
  /// verification already failed -- so a rejected token's debug view can
  /// still show *what* was rejected, not just that it was. Never trust
  /// these claims for any decision; only [verify]'s return value does that.
  Map<String, dynamic> _unsafeDecodeClaims(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return const {};
      return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }
}
