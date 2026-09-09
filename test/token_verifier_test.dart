import 'package:flutter_test/flutter_test.dart';
import 'package:roster_vault/services/issuer_public_key.dart';
import 'package:roster_vault/services/token_verifier.dart';

/// Task 4c — TokenVerifier is pure Dart (no Amplify, no platform channels),
/// so it's tested directly against a real token captured from Task 4a's
/// own CLI verification (a genuine `enroll` mutation call against the
/// deployed sandbox, signed by the real KMS issuer key) -- not a
/// synthetic/mocked signature. See docs/roster-vault/stories/story-
/// checkpoint-mvp.md Task 4c for why EnrollmentService itself is verified
/// separately via CLI rather than through this test file: signing in
/// through amplify_auth_cognito inside `flutter test` (as opposed to a
/// real `flutter run`) hung indefinitely -- a second, independent instance
/// of the same class of problem as the biometric_signature Windows Hello
/// hang, both stemming from platform-channel-backed plugins behaving
/// differently outside a real running app.
void main() {
  // Captured from a real `enroll` mutation call during Task 4a/4c
  // verification against the deployed sandbox (see
  // .claude/skills/run-roster-vault/.artifacts/task4a-verify/response2.json,
  // gitignored). Valid until its exp claim, ~48h from issuance.
  const realCapturedToken =
      'eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.'
      'eyJ1c2VyX2lkIjoiMjk2ZWY0ZjgtOTBmMS03MDRjLTZjYzQtMjNmMWQ1M2RjZDc4IiwiZGV2aWNlX2lkIjoidGFzazRhLXZlcmlmaWNhdGlvbi1kZXZpY2UtMDAxIiwic2NvcGVzIjpbIm9mZmxpbmVfc2lnbmluIl0sImVwb2NoIjowLCJpYXQiOjE3ODg5NTM3ODAsImV4cCI6MTc4OTEyNjU4MH0.'
      'oB_wekUKr79QSst-Jm5aYZ5-2yn2LlVipP-6pego_m6d76BqrWwmdc-Mkxw6gqVikMzPK97MxBtRMZTGZmCurg';

  test('verifies a real KMS-signed token against the baked-in issuer public key', () async {
    final result = await const TokenVerifier().verify(realCapturedToken, issuerPublicKeyPem: issuerPublicKeyPem);

    expect(result.signatureValid, isTrue);
    expect(result.claims['user_id'], '296ef4f8-90f1-704c-6cc4-23f1d53dcd78');
    expect(result.claims['device_id'], 'task4a-verification-device-001');
    expect(result.claims['scopes'], ['offline_signin']);
    expect(result.claims['epoch'], 0);
  });

  test('rejects a token with a tampered payload', () async {
    final parts = realCapturedToken.split('.');
    // Flip one character in the payload -- same signature, different claims.
    final tamperedPayload = parts[1].substring(0, parts[1].length - 1) +
        (parts[1][parts[1].length - 1] == 'A' ? 'B' : 'A');
    final tampered = '${parts[0]}.$tamperedPayload.${parts[2]}';

    final result = await const TokenVerifier().verify(tampered, issuerPublicKeyPem: issuerPublicKeyPem);

    expect(result.signatureValid, isFalse);
  });
}
