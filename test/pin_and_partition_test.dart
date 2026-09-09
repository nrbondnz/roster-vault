import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roster_vault/services/encrypted_partition_store.dart';
import 'package:roster_vault/services/partition_key_service.dart';
import 'package:roster_vault/services/pin_service.dart';

/// Task 6 — proves the two mechanisms that actually carry this task's
/// security property: PIN-derived wrapping (Argon2id + authenticated
/// AES-GCM) and per-user partition key derivation/isolation (HKDF +
/// SQLCipher-encrypted SQLite). Real cryptography and a real encrypted
/// file on disk throughout -- nothing mocked.
void main() {
  group('PinService', () {
    const pinService = PinService();

    test('correct PIN unwraps the original plaintext', () async {
      final plaintext = 'super-secret-token-blob'.codeUnits;
      final wrapped = await pinService.wrap(pin: '1234', plaintext: plaintext);
      final result = await pinService.unwrap(pin: '1234', data: wrapped);
      expect(result, plaintext);
    });

    test('wrong PIN returns null, not garbage', () async {
      final plaintext = 'super-secret-token-blob'.codeUnits;
      final wrapped = await pinService.wrap(pin: '1234', plaintext: plaintext);
      final result = await pinService.unwrap(pin: '9999', data: wrapped);
      expect(result, isNull);
    });

    test('wrapped data round-trips through JSON (as it would through storage)', () async {
      final plaintext = 'roundtrip-me'.codeUnits;
      final wrapped = await pinService.wrap(pin: '0000', plaintext: plaintext);
      final rehydrated = PinWrappedData.fromJson(wrapped.toJson());
      final result = await pinService.unwrap(pin: '0000', data: rehydrated);
      expect(result, plaintext);
    });
  });

  group('PartitionKeyService', () {
    const partitionKeyService = PartitionKeyService();

    test('same device key + user id always derives the same partition key', () async {
      final deviceKey = List<int>.filled(32, 7);
      final k1 = await partitionKeyService.deriveUserPartitionKey(deviceMasterKey: deviceKey, userId: 'user-a');
      final k2 = await partitionKeyService.deriveUserPartitionKey(deviceMasterKey: deviceKey, userId: 'user-a');
      expect(k1, k2);
    });

    test('different users on the same device get different partition keys', () async {
      final deviceKey = List<int>.filled(32, 7);
      final kA = await partitionKeyService.deriveUserPartitionKey(deviceMasterKey: deviceKey, userId: 'user-a');
      final kB = await partitionKeyService.deriveUserPartitionKey(deviceMasterKey: deviceKey, userId: 'user-b');
      expect(kA, isNot(kB));
    });
  });

  // Real encryption is active here (Task 6, resolved 2026-09-10): sqlite3
  // 3.x + the sqlite3mc build selected via pubspec.yaml's `hooks.user_defines`
  // (self-contained, no OpenSSL dependency, unlike sqlcipher_flutter_libs'
  // Windows build) -- see EncryptedPartitionStore's doc comment and the
  // story checkpoint's Task 6 entry for the full story of how this was
  // found and verified, not just configured.
  group('EncryptedPartitionStore -- real encryption verified', () {
    const store = EncryptedPartitionStore();
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('roster_vault_partition_test_'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('data written under one key is readable back with the same key', () {
      final key = List<int>.filled(32, 1);
      final path = '${tempDir.path}/user_a.db';

      final db1 = store.open(dbPath: path, partitionKey: key);
      db1.execute("INSERT INTO partition_data (key, value) VALUES ('name', 'Alice')");
      db1.close();

      final db2 = store.open(dbPath: path, partitionKey: key);
      final rows = db2.select("SELECT value FROM partition_data WHERE key = 'name'");
      db2.close();

      expect(rows.single['value'], 'Alice');
    });

    test('the same file cannot be opened with a different user\'s key', () {
      final correctKey = List<int>.filled(32, 1);
      final wrongKey = List<int>.filled(32, 2);
      final path = '${tempDir.path}/user_b.db';

      final db1 = store.open(dbPath: path, partitionKey: correctKey);
      db1.execute("INSERT INTO partition_data (key, value) VALUES ('secret', 'only-user-b-should-read-this')");
      db1.close();

      expect(
        () => store.open(dbPath: path, partitionKey: wrongKey),
        throwsA(anything),
        reason: 'opening an encrypted partition with the wrong key must fail, not silently succeed',
      );
    });

    test('two different users\' partitions on the same device are independent files with independent data', () {
      final keyA = List<int>.filled(32, 1);
      final keyB = List<int>.filled(32, 2);

      final dbA = store.open(dbPath: '${tempDir.path}/user_a2.db', partitionKey: keyA);
      dbA.execute("INSERT INTO partition_data (key, value) VALUES ('name', 'Alice')");
      dbA.close();

      final dbB = store.open(dbPath: '${tempDir.path}/user_b2.db', partitionKey: keyB);
      final rowsInB = dbB.select('SELECT * FROM partition_data');
      dbB.close();

      expect(rowsInB, isEmpty, reason: "user B's fresh partition must not see user A's data");
    });
  });
}
