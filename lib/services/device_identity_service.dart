import 'dart:math';

import 'package:biometric_signature/biometric_signature.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The result of [DeviceIdentityService.ensureDeviceIdentity].
class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.publicKeyPem});

  final String deviceId;
  final String publicKeyPem;
}

/// Trust Anchor 2 (docs/roster-vault/Security/Trust Anchors.md): the
/// per-device keypair. Generated once, on first run, hardware-backed via
/// Android Keystore/StrongBox or iOS Secure Enclave through the
/// `biometric_signature` plugin. `requireAuthentication: false` is
/// deliberate — this key isn't gated by a person's local factor, only by
/// the hardware itself. Trust Anchor 3 (the per-user credential, gated by
/// PIN/biometric) is added per enrolled person in Task 6, under a
/// different key alias.
///
/// The plugin's `createKeys` silently replaces an existing key under the
/// same alias when called again (see its `failIfExists` doc). Every call
/// site here must check [_keyExists] first — never call `createKeys`
/// unconditionally — or a routine app relaunch would rotate the device key
/// out from under every token already issued against the old one.
class DeviceIdentityService {
  DeviceIdentityService({
    BiometricSignature? biometricSignature,
    FlutterSecureStorage? secureStorage,
  })  : _biometricSignature = biometricSignature ?? BiometricSignature(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _deviceKeyAlias = 'roster_vault_device_key';
  static const _deviceIdStorageKey = 'roster_vault_device_id';

  final BiometricSignature _biometricSignature;
  final FlutterSecureStorage _secureStorage;

  /// Returns the device's identity, generating the keypair and deviceId on
  /// first call only. Safe to call every app start.
  Future<DeviceIdentity> ensureDeviceIdentity() async {
    final deviceId = await _ensureDeviceId();
    final publicKeyPem = await _ensureDeviceKeyPair();
    return DeviceIdentity(deviceId: deviceId, publicKeyPem: publicKeyPem);
  }

  Future<String> _ensureDeviceId() async {
    final existing = await _secureStorage.read(key: _deviceIdStorageKey);
    if (existing != null) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final deviceId = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _secureStorage.write(key: _deviceIdStorageKey, value: deviceId);
    return deviceId;
  }

  Future<String> _ensureDeviceKeyPair() async {
    final existingKey = await _existingPublicKey();
    if (existingKey != null) return existingKey;

    final result = await _biometricSignature.createKeys(
      keyAlias: _deviceKeyAlias,
      keyFormat: KeyFormat.pem,
      config: CreateKeysConfig(
        signatureType: SignatureType.ecdsa,
        requireAuthentication: false,
      ),
    );
    final publicKey = result.publicKey;
    if (publicKey == null) {
      throw StateError('Device key generation failed: ${result.code} ${result.error}');
    }
    return publicKey;
  }

  /// Returns the existing device public key, or null if no key has been
  /// generated yet for this alias.
  Future<String?> _existingPublicKey() async {
    final info = await _biometricSignature.getKeyInfo(
      keyAlias: _deviceKeyAlias,
      checkValidity: true,
      keyFormat: KeyFormat.pem,
    );
    if (info.exists == true && (info.isValid ?? true)) {
      return info.publicKey;
    }
    return null;
  }
}
