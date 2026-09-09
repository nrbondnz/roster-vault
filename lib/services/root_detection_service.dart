import 'dart:io';

/// Task 9 — Risk Register row 3 ("Rooted or jailbroken hardware"):
/// "Best-effort integrity check; degrade to software-wrapped keys rather
/// than hard-block -- 'unmanaged' is the brief, not optional, so refusing
/// to run at all would violate the actual requirement."
///
/// Deliberately a pure filesystem-existence check (`File.existsSync`
/// against well-known root/jailbreak artefact paths) rather than a new
/// native plugin dependency. This project has twice already (Task 3's
/// `biometric_signature`, Task 6's `sqlcipher_flutter_libs`) hit real,
/// time-costly native-build breakage from added plugins -- a third one, for
/// a best-effort check whose entire premise is "don't hard-block on this,"
/// is not worth that risk. The tradeoff is real and stated plainly, not
/// hidden: this catches unmodified stock root tooling (Magisk's default
/// install layout, common su binary locations, known root-manager
/// packages) and nothing that specifically hides from userspace path
/// checks (Magisk's own "Hide" / Zygisk-based concealment defeats this
/// trivially). That is what "best-effort" means in the Risk Register's own
/// wording -- a real deterrent against casual tampering, not a security
/// boundary.
///
/// iOS/jailbreak paths are included for completeness per the Risk
/// Register's wording, but this project's real verification target this
/// story is Android hardware (see the story checkpoint) -- unverified on
/// an actual jailbroken iOS device.
class RootDetectionService {
  /// [checkPaths] defaults to the real list below; a test can override it
  /// with a path it actually creates, to exercise the true-positive branch
  /// deterministically without needing an actually-rooted device.
  const RootDetectionService({List<String>? checkPaths}) : _checkPaths = checkPaths ?? _suspiciousPaths;

  final List<String> _checkPaths;

  static const _suspiciousPaths = <String>[
    // Common su binary locations across root implementations.
    '/system/xbin/su',
    '/system/bin/su',
    '/sbin/su',
    '/su/bin/su',
    '/system/app/Superuser.apk',
    // Magisk's default install layout.
    '/sbin/.magisk',
    '/data/adb/magisk',
    // Other common root-management app data directories.
    '/data/data/com.topjohnwu.magisk',
    '/data/data/eu.chainfire.supersu',
    '/data/data/com.noshufou.android.su',
    // iOS jailbreak tooling (Cydia et al.) -- present for completeness,
    // unverified on real hardware; see class doc.
    '/Applications/Cydia.app',
    '/Library/MobileSubstrate/MobileSubstrate.dylib',
    '/bin/bash',
    '/usr/sbin/sshd',
  ];

  /// Best-effort only -- see class doc for exactly what this can and
  /// cannot detect. A `true` result should change what the UI *shows*
  /// (a visible warning), never what it *allows* -- this device class is
  /// explicitly unmanaged by design, so a hard block here would be wrong,
  /// not just unimplemented.
  bool isLikelyCompromised() {
    for (final path in _checkPaths) {
      try {
        if (File(path).existsSync()) return true;
      } catch (_) {
        // A permission-denied or platform-specific stat failure is not
        // evidence of anything -- treat it as "couldn't check this one",
        // not as a positive signal either way.
      }
    }
    return false;
  }
}
