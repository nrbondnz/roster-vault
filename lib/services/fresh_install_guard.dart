import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// **iOS-specific gap, found while scoping iOS support (2026-09-10), not yet
/// verified on real hardware -- no Mac available in this environment.** iOS
/// Keychain items survive app deletion by design (Apple's own documented
/// behavior) -- unlike Android, where an uninstall wipes all app-scoped
/// storage including everything [DeviceMasterKeyService], [EnrollmentService],
/// and [LocalUnlockService] write via `flutter_secure_storage`. For a project
/// whose entire premise is a shared, unmanaged device with no MDM to fall
/// back on, that is a real behavioral surprise, not a cosmetic one: deleting
/// and reinstalling Roster Vault on an iPhone would silently keep the old
/// device key (`K_device`), every enrolled token, and every PIN-wrapped
/// partition key from before the reinstall -- none of Task 3/4c/6's "this
/// device" guarantees would actually reset the way they visibly do on
/// Android. See docs/roster-vault/Troubleshooting/Known Issues.md.
///
/// Detects a fresh install (not merely a fresh *launch* -- an app upgrade or
/// an ordinary relaunch must NOT trigger this) via a marker file in the
/// app's own support directory. That directory, unlike Keychain, genuinely
/// is removed by iOS on uninstall (part of the app sandbox contract), so its
/// absence alongside populated Keychain data is a reliable fresh-install
/// signal on iOS specifically. A harmless no-op on Android/Windows, where
/// secure storage already starts clean on install without any help from
/// this class -- the marker file still gets created there for consistency,
/// but the wipe branch below should never actually fire on those platforms.
class FreshInstallGuard {
  FreshInstallGuard({FlutterSecureStorage? secureStorage, Future<Directory> Function()? appSupportDirectory})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _appSupportDirectory = appSupportDirectory ?? getApplicationSupportDirectory;

  final FlutterSecureStorage _secureStorage;

  /// Injectable so tests can point this at a real temp directory instead
  /// of `path_provider`'s platform channel (unavailable under `flutter
  /// test`) -- same reasoning as `EncryptedPartitionStore` taking an
  /// explicit `dbPath` rather than resolving one internally.
  final Future<Directory> Function() _appSupportDirectory;

  static const _markerFileName = '.roster_vault_installed';
  static const _partitionFileInfix = 'roster_vault_partition_';

  /// Call once, at app startup, before anything reads or writes secure
  /// storage or opens an [EncryptedPartitionStore] partition.
  Future<void> ensureCleanSlateOnFreshInstall() async {
    final dir = await _appSupportDirectory();
    final marker = File('${dir.path}/$_markerFileName');
    if (await marker.exists()) return;

    // Marker absent. Only treat this as "stale data from a previous
    // install" -- and wipe -- if there's actually something to be stale;
    // a marker missing for some unrelated reason on a device that's
    // otherwise a genuine first-ever install must not destroy anything.
    final existing = await _secureStorage.readAll();
    if (existing.isNotEmpty) {
      await _secureStorage.deleteAll();
      if (await dir.exists()) {
        for (final entry in dir.listSync()) {
          if (entry is File && entry.path.contains(_partitionFileInfix)) {
            await entry.delete();
          }
        }
      }
    }

    await marker.create(recursive: true);
  }
}
