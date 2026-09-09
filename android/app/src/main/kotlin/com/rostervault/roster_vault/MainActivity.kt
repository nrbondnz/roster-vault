package com.rostervault.roster_vault

import io.flutter.embedding.android.FlutterFragmentActivity

// biometric_signature requires a FragmentActivity (it uses androidx.biometric.BiometricPrompt
// internally, which itself requires one) -- see the plugin's README, "This plugin requires the
// use of a FragmentActivity instead of Activity." Without this, the plugin's own `activity`
// field (typed FlutterFragmentActivity?, populated via `binding.activity as? FlutterFragmentActivity`)
// silently stays null forever against a plain FlutterActivity, surfacing as
// BiometricError.unknown "Foreground activity required" even though the Activity is genuinely
// attached and drawn -- see docs/roster-vault/Troubleshooting/Known Issues.md.
class MainActivity : FlutterFragmentActivity()
