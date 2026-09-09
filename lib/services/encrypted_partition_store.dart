import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Thrown when [EncryptedPartitionStore.open] is given the wrong key for
/// an existing, already-populated partition file.
class WrongPartitionKeyException implements Exception {
  const WrongPartitionKeyException(this.dbPath);
  final String dbPath;
  @override
  String toString() => 'WrongPartitionKeyException: key does not match the existing partition at $dbPath';
}

/// Task 6 — intended to implement "Real Partitioning, Not Just a UI
/// Filter" (docs/roster-vault/Architecture/Multi-User Partitioning.md):
/// each enrolled person's local data in its own SQLCipher-encrypted SQLite
/// file, keyed by that person's `K_user` ([PartitionKeyService]'s output).
///
/// **Encryption is NOT currently active on this dev machine -- confirmed,
/// not assumed.** `PRAGMA key` is only meaningful if the loaded native
/// `sqlite3` library actually has cipher support compiled in
/// (`sqlcipher_flutter_libs`, which patches which native library Flutter's
/// Windows build links against). That package's Windows CMake build
/// requires OpenSSL dev headers, which aren't installed here, and
/// installing system-wide dev tools is outside this project's authorized
/// scope. Verified directly: with the dependency reverted, `PRAGMA
/// cipher_version` returns no rows (no cipher support at all), and a file
/// written through this class starts with the plaintext `"SQLite format
/// 3\0"` header -- i.e. genuinely unencrypted, not merely unverified.
///
/// What *is* real: the wrong-key detection control flow below (the
/// `alreadyExists` check and the "read real data, not just open the file"
/// verification) is correct logic, exercised by real tests -- it was
/// actually what caught the missing encryption in the first place, when a
/// "wrong key" open unexpectedly succeeded. Once `sqlcipher_flutter_libs`
/// (or a working replacement) is actually linked, this same code path
/// should correctly reject wrong keys; that specific claim just can't be
/// backed by real ciphertext on this machine yet. See the story
/// checkpoint's Task 6 entry for what unblocking this needs.
///
/// Uses `package:sqlite3` directly rather than `drift`'s query builder --
/// unrelated to the encryption gap above, just a scoping choice to keep
/// this class focused on the key-management mechanism, not an ORM layer.
class EncryptedPartitionStore {
  const EncryptedPartitionStore();

  /// Opens (creating if necessary) the encrypted database file for one
  /// person at [dbPath], keyed by [partitionKey] (expected to be
  /// [PartitionKeyService]'s 32-byte output). Raw-key `PRAGMA key`
  /// syntax is used deliberately -- passing `partitionKey` as a
  /// passphrase would run it through SQLCipher's *own* KDF on top of the
  /// HKDF derivation already done, which is redundant and muddies which
  /// derivation is actually load-bearing.
  Database open({required String dbPath, required List<int> partitionKey}) {
    // Whether the file already exists matters: SQLCipher accepts any key
    // without complaint at PRAGMA-key time (it only fails once it actually
    // has to decrypt a real page), and *creating* a brand-new table with
    // the wrong key "succeeds" too -- it just silently starts a fresh,
    // differently-keyed database over whatever encrypted bytes were
    // already there. That was caught by this class's own test suite,
    // not assumed: `CREATE TABLE IF NOT EXISTS` immediately after
    // `PRAGMA key` does NOT reliably detect a wrong key. Only reading
    // real, already-encrypted content proves the key.
    final alreadyExists = File(dbPath).existsSync();

    final db = sqlite3.open(dbPath);
    final hexKey = partitionKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    db.execute("PRAGMA key = \"x'$hexKey'\";");

    if (alreadyExists) {
      try {
        db.select('SELECT count(*) FROM partition_data;');
      } on SqliteException {
        db.dispose();
        throw WrongPartitionKeyException(dbPath);
      }
    } else {
      db.execute('CREATE TABLE IF NOT EXISTS partition_data (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    }

    return db;
  }
}
