import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Task 6 — implements `K_user = HKDF(K_device, user_id)` exactly as
/// specified in docs/roster-vault/Architecture/Multi-User Partitioning.md.
/// Pure computation, no storage of its own: callers persist [DeviceMasterKeyService]'s
/// output, not this derived key.
class PartitionKeyService {
  const PartitionKeyService();

  Future<List<int>> deriveUserPartitionKey({required List<int> deviceMasterKey, required String userId}) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(secretKey: SecretKey(deviceMasterKey), info: utf8.encode(userId));
    return derived.extractBytes();
  }
}
