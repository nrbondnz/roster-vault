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

/// Task 6 — implements "Real Partitioning, Not Just a UI Filter"
/// (docs/roster-vault/Architecture/Multi-User Partitioning.md): each
/// enrolled person's local data in its own encrypted SQLite file, keyed by
/// that person's `K_user` ([PartitionKeyService]'s output).
///
/// **Encryption is confirmed active — verified directly, not assumed.**
/// `sqlcipher_flutter_libs` (the obvious first choice) is now EOL upstream;
/// its own pub.dev listing points at `package:sqlite3` 3.x instead, which
/// bundles cipher support natively via Dart's native-asset build hooks.
/// `pubspec.yaml`'s `hooks.user_defines.sqlite3.source: sqlite3mc` selects
/// SQLite3MultipleCiphers specifically — deliberately not `sqlcipher`,
/// since sqlite3.dart's own docs state the sqlcipher build "links OpenSSL
/// on Windows, Linux and Android" (the exact dependency this project
/// doesn't have installed), while sqlite3mc is self-contained. Verified on
/// Windows: a file written through this class is neither the plaintext
/// `"SQLite format 3\0"` header nor does it contain the plaintext value
/// anywhere in its raw bytes; a wrong key fails to read it; the right key
/// still can. See docs/roster-vault/Troubleshooting/Known Issues.md and
/// the story checkpoint's Task 6 entry for the full history, including the
/// dead-end first attempt.
///
/// Uses `package:sqlite3` directly rather than `drift`'s query builder --
/// a scoping choice to keep this class focused on the key-management
/// mechanism, not an ORM layer.
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
        db.close();
        throw WrongPartitionKeyException(dbPath);
      }
    } else {
      db.execute('CREATE TABLE IF NOT EXISTS partition_data (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    }

    return db;
  }
}
