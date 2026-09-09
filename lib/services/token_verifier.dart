import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Decoded, verified claims from an offline capability token issued by
/// Task 4a's `enroll` mutation. Verification here is signature-only —
/// expiry/device-id/epoch checks are Task 5's job
/// (docs/roster-vault/Architecture/Offline Sign-In Flow.md); this exists in
/// Task 4c only to make the freshly-issued token's validity visible on
/// screen, not to be the real offline verifier.
class VerifiedTokenClaims {
  const VerifiedTokenClaims({required this.signatureValid, required this.claims});

  final bool signatureValid;
  final Map<String, dynamic> claims;
}

/// Verifies the ES256 JWS produced by amplify/functions/enroll/handler.ts
/// against the issuer's public key baked into the app
/// (lib/services/issuer_public_key.dart, Trust Anchor 1). Pure local math,
/// no network call — this is the actual point of baking the key in.
///
/// Uses `dart_jsonwebtoken` (the library docs/roster-vault/Backend/Tech
/// Stack Mapping.md originally specified for this job), not
/// `package:cryptography`'s `Ecdsa`, which was tried first and found to be
/// a hard dead end on this platform: its pure-Dart P-256 implementation is
/// entirely unimplemented and unconditionally throws `UnimplementedError`
/// (`package:cryptography/src/dart/ecdsa.dart` -- every method, including
/// `verify`, is a stub). `dart_jsonwebtoken` verifies via `pointycastle`
/// underneath, which has a real pure-Dart P-256 implementation and works
/// with no platform channel of any kind.
class TokenVerifier {
  const TokenVerifier();

  Future<VerifiedTokenClaims> verify(String token, {required String issuerPublicKeyPem}) async {
    try {
      final jwt = JWT.verify(token, ECPublicKey(issuerPublicKeyPem));
      return VerifiedTokenClaims(signatureValid: true, claims: jwt.payload as Map<String, dynamic>);
    } on JWTException {
      // Still surface the (unverified) claims for display purposes -- the
      // debug view wants to show *what* was rejected, not just that it was.
      final parts = token.split('.');
      Map<String, dynamic> claims = const {};
      if (parts.length == 3) {
        try {
          final padded = base64Url.normalize(parts[1]);
          claims = jsonDecode(utf8.decode(base64Url.decode(padded))) as Map<String, dynamic>;
        } catch (_) {
          // Leave claims empty if even that fails (malformed token).
        }
      }
      return VerifiedTokenClaims(signatureValid: false, claims: claims);
    }
  }
}
