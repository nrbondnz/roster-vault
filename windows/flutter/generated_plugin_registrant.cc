//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <biometric_signature/biometric_signature_plugin.h>
#include <flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  BiometricSignaturePluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("BiometricSignaturePlugin"));
  FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterSecureStorageWindowsPlugin"));
}
