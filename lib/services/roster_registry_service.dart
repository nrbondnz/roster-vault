import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Task 7 — the on-device list of who has ever been enrolled here, so the
/// roster screen has something real to show instead of a debug list.
///
/// **Deliberately not derived by scanning [LocalUnlockService]'s partition
/// files on disk.** That would work (the files exist, named by userId) but
/// would silently lose each person's display name -- Cognito's `username`
/// for this pool is the opaque `sub` UUID (see Task 4b), not anything a
/// roster should show a real person. This registry is the one place that
/// captures the human-readable label at the moment it's actually known
/// (enrollment time, while still signed in and able to call
/// `Amplify.Auth.fetchUserAttributes()`), rather than trying to reconstruct
/// it later from a UUID alone.
///
/// A device-wide list (not per-user), so intentionally stored via
/// `flutter_secure_storage` rather than inside any one person's
/// PIN-gated partition -- the roster itself (names, not the data behind
/// them) is not the thing this project's threat model protects; Trust
/// Anchor 3 / [PinService]'s wrapping of each person's actual token is.
class RosterEntry {
  const RosterEntry({required this.userId, required this.displayName});

  final String userId;
  final String displayName;

  Map<String, dynamic> toJson() => {'userId': userId, 'displayName': displayName};

  factory RosterEntry.fromJson(Map<String, dynamic> json) =>
      RosterEntry(userId: json['userId'] as String, displayName: json['displayName'] as String);
}

class RosterRegistryService {
  RosterRegistryService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const _storageKey = 'roster_vault_roster_registry';

  Future<List<RosterEntry>> listProfiles() async {
    final stored = await _secureStorage.read(key: _storageKey);
    if (stored == null) return const [];
    final list = jsonDecode(stored) as List<dynamic>;
    return list.map((e) => RosterEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Adds [userId] to the roster (or updates their [displayName] if
  /// they're already on it -- e.g. re-enrolling after an email change).
  /// Idempotent: safe to call every time a PIN is set up, not just the
  /// first time.
  Future<void> addOrUpdateProfile({required String userId, required String displayName}) async {
    final current = await listProfiles();
    final withoutThisUser = current.where((e) => e.userId != userId).toList();
    final updated = [...withoutThisUser, RosterEntry(userId: userId, displayName: displayName)];
    await _secureStorage.write(key: _storageKey, value: jsonEncode(updated.map((e) => e.toJson()).toList()));
  }
}
