import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Task 6 — `K_device`, the device-level secret that
/// docs/roster-vault/Architecture/Multi-User Partitioning.md's
/// `K_user = HKDF(K_device, user_id)` is derived from.
///
/// Scoping decision (logged in the story checkpoint): the architecture
/// docs specify the *formula* precisely but not what `K_device` concretely
/// *is* -- Trust Anchors.md only defines two ECDSA keypairs (device,
/// per-user) and the KMS issuer key, none of which are directly usable as
/// symmetric HKDF input material. Defined here as a dedicated randomly-
/// generated 256-bit symmetric secret, generated once and persisted via
/// `flutter_secure_storage` -- the same placeholder-storage posture
/// already used for enrollment tokens (Task 4c), not yet PIN-wrapped
/// itself. Deliberately independent of the Trust Anchor 2 device ECDSA
/// keypair: mixing a signing key into a symmetric KDF as raw key material
/// is a well-known crypto smell (key reuse across purposes), so this is a
/// dedicated secret rather than a reinterpretation of an existing one.
class DeviceMasterKeyService {
  DeviceMasterKeyService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const _storageKey = 'roster_vault_device_master_key';

  /// Returns this device's master key, generating it once on first call.
  /// Safe to call every app start (idempotent, same pattern as
  /// [DeviceIdentityService]).
  Future<List<int>> ensureDeviceMasterKey() async {
    final existing = await _secureStorage.read(key: _storageKey);
    if (existing != null) return base64Decode(existing);

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    await _secureStorage.write(key: _storageKey, value: base64Encode(bytes));
    return bytes;
  }
}
