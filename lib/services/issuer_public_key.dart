/// Trust Anchor 1 (docs/roster-vault/Security/Trust Anchors.md) — the
/// issuer's public key, baked into the app at build time so offline
/// signature verification (Task 5) is pure local math with no network call.
///
/// This is the **public** half only. The matching private key never leaves
/// AWS KMS; signing happens exclusively via `kms:Sign` from the enrollment
/// Lambda (amplify/functions/enroll/handler.ts, Task 4a).
///
/// Regenerate if the issuer key is ever rotated:
/// ```
/// aws kms get-public-key --key-id KEY_ID --query PublicKey --output text \
///   | base64 -d | openssl pkey -pubin -inform DER -pubout
/// ```
///
/// Current key: alias/roster-vault-issuer-signing-key-* (sandbox), key id
/// fdf9ab21-2884-4a88-9e1c-1b10a3d8f103, ECC_NIST_P256 / SIGN_VERIFY. See
/// docs/roster-vault/Backend/Backend Index.md for the deployed identifiers.
const String issuerPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEVvErMroREUN8sHT8DcaGX7DG7P+8
SxlIbjoCy5kdds08Zt2NiVbmHYot1osVTvj5uhbuZXXmbLM382Xz3YN98Q==
-----END PUBLIC KEY-----
''';
