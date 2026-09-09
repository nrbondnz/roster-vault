import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_vault/services/offline_verifier.dart';

/// Task 5 — table-driven tests across all four offline checks
/// (signature, expiry, device-id, epoch) plus challenge-response,
/// independently and in combination, per the story checkpoint's Task 5
/// scope and the Story Agent's "Spawns: Test Agent" directive for this
/// task specifically.
///
/// Real P-256 keypairs (openssl-generated, test-only -- these are not and
/// must never be the real issuer key) stand in for Trust Anchor 1 (issuer)
/// and Trust Anchor 3 (per-user credential) so every test exercises real
/// ECDSA sign/verify, not a mocked crypto layer.
const _issuerPrivPem = '''
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIAU2WetdT9ED/lwImH3A4f1aFEAfx618cVrDBoRubkjZoAoGCCqGSM49
AwEHoUQDQgAEbh7uG5CWFHeN+tzRffqGwWLqpG2KBWBCQKk3/ljbFZKv4/ueLtXi
WmSINr2IQtaO9uRfRYQVAKEdyAQ8e3cIrw==
-----END EC PRIVATE KEY-----
''';
const _issuerPubPem = '''
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEbh7uG5CWFHeN+tzRffqGwWLqpG2K
BWBCQKk3/ljbFZKv4/ueLtXiWmSINr2IQtaO9uRfRYQVAKEdyAQ8e3cIrw==
-----END PUBLIC KEY-----
''';
const _userPrivPem = '''
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIIJ6brcG0Z5OO3H5y4IHb6jsqIuJUW+OJ+HaZ7Hf8sZ4oAoGCCqGSM49
AwEHoUQDQgAEtkiOud1ue6FMu+GiaMvvPkaGPsZfX8vAbWvw4p8rmzFZVD4CW6Fj
+6xJsKtMwWpByvZSTHpjgTKQPb4J2nGSMQ==
-----END EC PRIVATE KEY-----
''';
const _userPubPem = '''
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtkiOud1ue6FMu+GiaMvvPkaGPsZf
X8vAbWvw4p8rmzFZVD4CW6Fj+6xJsKtMwWpByvZSTHpjgTKQPb4J2nGSMQ==
-----END PUBLIC KEY-----
''';
// Deliberately a different keypair than issuer or user -- used to prove
// "wrong signer" is actually detected, not just "any well-formed
// signature accepted."
const _otherPrivPem = '''
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIK4hQIb5Brgmnze1+66D6G5VCONLd5wGHf3lqgoWw7WqoAoGCCqGSM49
AwEHoUQDQgAE3KEcdXQNbNsqnziFPXPCqfgn40NiS+mbhaJhwKfIgwx0MfnbIOYc
NMQXQzc1eh2sof2dTv39xqQva7JYsWsb5g==
-----END EC PRIVATE KEY-----
''';

const _deviceId = 'offline-test-device-001';

String _issueToken({
  String signerPem = _issuerPrivPem,
  String deviceId = _deviceId,
  int epoch = 0,
  int? expiresAtEpochSeconds,
}) {
  final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final exp = expiresAtEpochSeconds ?? (nowSeconds + 3600);
  final jwt = JWT({
    'user_id': 'test-user-sub',
    'device_id': deviceId,
    'scopes': ['offline_signin'],
    'epoch': epoch,
    'iat': nowSeconds,
    'exp': exp,
  });
  // dart_jsonwebtoken's own expiresIn/notBefore machinery would overwrite
  // our explicit exp -- sign with noIssueAt-equivalent defaults off and
  // let the explicit claim stand by not passing expiresIn at all.
  return jwt.sign(ECPrivateKey(signerPem), algorithm: JWTAlgorithm.ES256, noIssueAt: true);
}

ChallengeSigner _signerUsing(String privPem) {
  return (nonce) async {
    final jwt = JWT({'nonce': nonce});
    return jwt.sign(ECPrivateKey(privPem), algorithm: JWTAlgorithm.ES256);
  };
}

void main() {
  const verifier = OfflineVerifier();

  test('valid token, correct device, fresh epoch, correct challenge response -> valid', () async {
    final token = _issueToken();
    final result = await verifier.verify(
      token: token,
      issuerPublicKeyPem: _issuerPubPem,
      expectedDeviceId: _deviceId,
      currentKnownEpoch: 0,
      userPublicKeyPem: _userPubPem,
      signChallenge: _signerUsing(_userPrivPem),
    );
    expect(result.isValid, isTrue);
    expect(result.claims['device_id'], _deviceId);
  });

  test('token signed by the wrong key -> badSignature', () async {
    final token = _issueToken(signerPem: _otherPrivPem);
    final result = await verifier.verify(
      token: token,
      issuerPublicKeyPem: _issuerPubPem,
      expectedDeviceId: _deviceId,
      currentKnownEpoch: 0,
      userPublicKeyPem: _userPubPem,
      signChallenge: _signerUsing(_userPrivPem),
    );
    expect(result.failure, OfflineVerificationFailure.badSignature);
  });

  test('expired token -> expired', () async {
    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final token = _issueToken(expiresAtEpochSeconds: nowSeconds - 60);
    final result = await verifier.verify(
      token: token,
      issuerPublicKeyPem: _issuerPubPem,
      expectedDeviceId: _deviceId,
      currentKnownEpoch: 0,
      userPublicKeyPem: _userPubPem,
      signChallenge: _signerUsing(_userPrivPem),
    );
    expect(result.failure, OfflineVerificationFailure.expired);
  });

  test('token issued for a different device -> wrongDevice', () async {
    final token = _issueToken(deviceId: 'some-other-device');
    final result = await verifier.verify(
      token: token,
      issuerPublicKeyPem: _issuerPubPem,
      expectedDeviceId: _deviceId,
      currentKnownEpoch: 0,
      userPublicKeyPem: _userPubPem,
      signChallenge: _signerUsing(_userPrivPem),
    );
    expect(result.failure, OfflineVerificationFailure.wrongDevice);
  });

  test('token epoch older than the on-device known epoch -> staleEpoch', () async {
    final token = _issueToken(epoch: 0);
    final result = await verifier.verify(
      token: token,
      issuerPublicKeyPem: _issuerPubPem,
      expectedDeviceId: _deviceId,
      currentKnownEpoch: 1, // this device refreshed since this token was issued
      userPublicKeyPem: _userPubPem,
      signChallenge: _signerUsing(_userPrivPem),
    );
    expect(result.failure, OfflineVerificationFailure.staleEpoch);
  });

  test('token epoch equal to known epoch -> not staleEpoch (comparison direction)', () async {
    final token = _issueToken(epoch: 1);
    final result = await verifier.verify(
      token: token,
      issuerPublicKeyPem: _issuerPubPem,
      expectedDeviceId: _deviceId,
      currentKnownEpoch: 1,
      userPublicKeyPem: _userPubPem,
      signChallenge: _signerUsing(_userPrivPem),
    );
    expect(result.isValid, isTrue, reason: 'equal epoch must not be rejected -- only strictly older');
  });

  test('token epoch newer than known epoch -> not staleEpoch (comparison direction)', () async {
    final token = _issueToken(epoch: 5);
    final result = await verifier.verify(
      token: token,
      issuerPublicKeyPem: _issuerPubPem,
      expectedDeviceId: _deviceId,
      currentKnownEpoch: 1,
      userPublicKeyPem: _userPubPem,
      signChallenge: _signerUsing(_userPrivPem),
    );
    expect(
      result.isValid,
      isTrue,
      reason: 'a device that already refreshed successfully must never be locked out by its own newer token',
    );
  });

  test('challenge signed by the wrong private key -> challengeFailed', () async {
    final token = _issueToken();
    final result = await verifier.verify(
      token: token,
      issuerPublicKeyPem: _issuerPubPem,
      expectedDeviceId: _deviceId,
      currentKnownEpoch: 0,
      userPublicKeyPem: _userPubPem,
      signChallenge: _signerUsing(_otherPrivPem), // not this user's actual key
    );
    expect(result.failure, OfflineVerificationFailure.challengeFailed);
  });

  test('challenge response echoes the wrong nonce -> challengeFailed', () async {
    final token = _issueToken();
    final result = await verifier.verify(
      token: token,
      issuerPublicKeyPem: _issuerPubPem,
      expectedDeviceId: _deviceId,
      currentKnownEpoch: 0,
      userPublicKeyPem: _userPubPem,
      signChallenge: (nonce) async {
        // Signs a *different* nonce than the one it was asked to -- e.g. a
        // replayed old response -- with the otherwise-correct key.
        final jwt = JWT({'nonce': 'not-the-real-nonce'});
        return jwt.sign(ECPrivateKey(_userPrivPem), algorithm: JWTAlgorithm.ES256);
      },
    );
    expect(result.failure, OfflineVerificationFailure.challengeFailed);
  });

  test('combination: expired AND wrong device -> reports expired first (short-circuit order)', () async {
    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final token = _issueToken(deviceId: 'some-other-device', expiresAtEpochSeconds: nowSeconds - 60);
    final result = await verifier.verify(
      token: token,
      issuerPublicKeyPem: _issuerPubPem,
      expectedDeviceId: _deviceId,
      currentKnownEpoch: 0,
      userPublicKeyPem: _userPubPem,
      signChallenge: _signerUsing(_userPrivPem),
    );
    expect(result.failure, OfflineVerificationFailure.expired);
  });

  test('combination: wrong device AND stale epoch -> reports wrongDevice first (short-circuit order)', () async {
    final token = _issueToken(deviceId: 'some-other-device', epoch: 0);
    final result = await verifier.verify(
      token: token,
      issuerPublicKeyPem: _issuerPubPem,
      expectedDeviceId: _deviceId,
      currentKnownEpoch: 5,
      userPublicKeyPem: _userPubPem,
      signChallenge: _signerUsing(_userPrivPem),
    );
    expect(result.failure, OfflineVerificationFailure.wrongDevice);
  });
}
