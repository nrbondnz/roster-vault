import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'device_master_key_service.dart';
import 'encrypted_partition_store.dart';
import 'partition_key_service.dart';
import 'pin_service.dart';

/// Task 6 — "Local unlock factor and per-user encrypted storage" ties
/// together the pieces already built and independently proven:
/// [DeviceMasterKeyService] + [PartitionKeyService] (the database-level
/// `K_user = HKDF(K_device, user_id)` from
/// docs/roster-vault/Architecture/Multi-User Partitioning.md, protecting
/// against raw file access with no device secrets at all -- the "lost
/// tablet" threat model the architecture doc names explicitly) and
/// [PinService] (protecting against someone who *does* have device access,
/// i.e. `K_device` itself, but not this specific person's PIN).
///
/// **A deliberate, documented design choice, not silently assumed:** the
/// architecture doc's `K_user = HKDF(K_device, user_id)` formula has no PIN
/// in it -- taken literally, database-level encryption alone doesn't
/// actually require a person's local factor, since anyone who can read
/// `K_device` (itself only OS-encrypted, not PIN-gated) can derive the same
/// `K_user` without ever entering a PIN. That's a real tension against the
/// same doc's prose ("can't read another profile's data without that
/// profile's own local factor"). Resolved here by giving the PIN a genuine,
/// separate cryptographic job instead of a redundant one: it wraps the
/// enrollment token itself (via [PinService], Argon2id-derived, so the PIN
/// is real key material, not a UI-only gate) as a row *inside* the
/// K_user-encrypted partition. The two layers combine to cover both named
/// threats -- raw file theft alone (needs `K_device`) and device
/// compromise alone (needs the PIN) both fail; only both together succeed.
class LocalUnlockService {
  LocalUnlockService({
    DeviceMasterKeyService? deviceMasterKeyService,
    PartitionKeyService? partitionKeyService,
    PinService? pinService,
    EncryptedPartitionStore? partitionStore,
  })  : _deviceMasterKeyService = deviceMasterKeyService ?? DeviceMasterKeyService(),
        _partitionKeyService = partitionKeyService ?? const PartitionKeyService(),
        _pinService = pinService ?? const PinService(),
        _partitionStore = partitionStore ?? const EncryptedPartitionStore();

  final DeviceMasterKeyService _deviceMasterKeyService;
  final PartitionKeyService _partitionKeyService;
  final PinService _pinService;
  final EncryptedPartitionStore _partitionStore;

  static const _tokenRowKey = 'wrapped_enrollment_token';

  Future<String> _dbPathFor(String userId) async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/roster_vault_partition_$userId.db';
  }

  /// Whether this person has ever set up a PIN (and therefore a partition)
  /// on this device. Checking the file's existence rather than trying to
  /// read a stored marker separately -- [setUpPin] is the only thing that
  /// ever creates this file.
  Future<bool> isSetUp(String userId) async {
    final path = await _dbPathFor(userId);
    return File(path).existsSync();
  }

  /// First-time setup for this person on this device (or re-run to change
  /// their PIN, which re-wraps the same token under the new one).
  /// [enrollmentToken] is the value Task 4c's `EnrollmentService` already
  /// obtained and stored via `flutter_secure_storage` -- stored a second
  /// time here, PIN-wrapped, inside the encrypted partition. Deliberately
  /// additive rather than replacing Task 4c/5's already-proven flow (which
  /// doesn't require a PIN at all): see the story checkpoint's Task 6 entry
  /// for why this scoping choice was made instead of a riskier rewrite of
  /// already-working code.
  Future<void> setUpPin({required String userId, required String pin, required String enrollmentToken}) async {
    final deviceMasterKey = await _deviceMasterKeyService.ensureDeviceMasterKey();
    final partitionKey = await _partitionKeyService.deriveUserPartitionKey(
      deviceMasterKey: deviceMasterKey,
      userId: userId,
    );
    final wrapped = await _pinService.wrap(pin: pin, plaintext: utf8.encode(enrollmentToken));

    final path = await _dbPathFor(userId);
    final db = _partitionStore.open(dbPath: path, partitionKey: partitionKey);
    try {
      db.execute(
        'INSERT OR REPLACE INTO partition_data (key, value) VALUES (?, ?)',
        [_tokenRowKey, jsonEncode(wrapped.toJson())],
      );
    } finally {
      db.close();
    }
  }

  /// Returns the unwrapped enrollment token if [pin] is correct, `null` if
  /// it's wrong. Opening the partition itself always succeeds regardless of
  /// [pin] -- `K_user` doesn't depend on it, by design (see class doc) --
  /// the actual gate is entirely in the PIN-unwrap step.
  ///
  /// Throws [StateError] if [userId] has no partition on this device yet
  /// ([isSetUp] returned `false`) -- a distinct, non-PIN-related outcome
  /// the UI should check for separately rather than showing as "wrong PIN".
  Future<String?> unlock({required String userId, required String pin}) async {
    if (!await isSetUp(userId)) {
      throw StateError('No local profile set up for $userId on this device yet -- call setUpPin first.');
    }
    final deviceMasterKey = await _deviceMasterKeyService.ensureDeviceMasterKey();
    final partitionKey = await _partitionKeyService.deriveUserPartitionKey(
      deviceMasterKey: deviceMasterKey,
      userId: userId,
    );
    final path = await _dbPathFor(userId);
    final db = _partitionStore.open(dbPath: path, partitionKey: partitionKey);
    try {
      final rows = db.select('SELECT value FROM partition_data WHERE key = ?', [_tokenRowKey]);
      if (rows.isEmpty) return null;
      final wrapped = PinWrappedData.fromJson(jsonDecode(rows.first['value'] as String) as Map<String, dynamic>);
      final plaintext = await _pinService.unwrap(pin: pin, data: wrapped);
      return plaintext == null ? null : utf8.decode(plaintext);
    } finally {
      db.close();
    }
  }
}
