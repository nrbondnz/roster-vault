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
/// Current key: alias/roster-vault-issuer-signing-key-amplify-d1263eo28hwyl9-main-branch-5fdf7f036d-RosterVaultCore54E70145-196PIC7Q92J9O
/// (the deployed `main-branch` environment, matching this repo's checked-in
/// amplify_outputs.json), key id b0b14a86-46bd-43f6-a076-a726354b6150,
/// ECC_NIST_P256 / SIGN_VERIFY. See docs/roster-vault/Backend/Backend
/// Index.md for the deployed identifiers.
///
/// 2026-09-10: this constant had drifted to a stale *sandbox* key
/// (fdf9ab21-2884-4a88-9e1c-1b10a3d8f103) left over from before the
/// `main-branch` environment existed, while amplify_outputs.json had moved
/// on to the key above -- every enrollment verified as `Signature: INVALID`
/// as a result, first caught on real iOS hardware. Not an iOS bug; would
/// have failed identically on Android against this same deployment. Fixed
/// by regenerating from the currently deployed key. If this drifts again,
/// treat amplify_outputs.json's `custom.issuerSigningKeyId` as the source
/// of truth, not this file's own doc comment.
const String issuerPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEyW1X2rrB+K9PKlrKne+wwOxTx7Ri
d4YN1Eez8ffW75mj5rHweutxudxbcJiatxak8vbeeJ9CaHzpTtcc8JQNmw==
-----END PUBLIC KEY-----
''';
