//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <amplify_db_common/amplify_db_common_plugin.h>
#include <biometric_signature/biometric_signature_plugin.h>
#include <flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h>
#include <local_auth_windows/local_auth_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AmplifyDbCommonPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AmplifyDbCommonPlugin"));
  BiometricSignaturePluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("BiometricSignaturePlugin"));
  FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterSecureStorageWindowsPlugin"));
  LocalAuthPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("LocalAuthPlugin"));
}
