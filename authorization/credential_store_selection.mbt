///|
/// The supported production credential locations. File storage is explicit:
/// selecting the platform-native vault never falls back to a file.
pub(all) enum CredentialStoreKind {
  Native
  File(String)
}

///|
priv enum NativeCredentialVault {
  MacOSKeychain
  LinuxSecretService
  WindowsCredentialManager
  NativeVaultUnavailable
}

///|
fn detected_native_credential_vault() -> NativeCredentialVault {
  match native_credential_platform_code() {
    1 => MacOSKeychain
    2 => LinuxSecretService
    3 => WindowsCredentialManager
    _ => NativeVaultUnavailable
  }
}

///|
/// Select a production store without depending on the command package.
pub fn production_credential_store(
  kind : CredentialStoreKind,
) -> Result[CredentialStore, ProjectAuthorizationError] {
  match kind {
    Native =>
      match detected_native_credential_vault() {
        MacOSKeychain => macos_keychain_credential_store()
        LinuxSecretService => linux_secret_service_credential_store()
        WindowsCredentialManager =>
          windows_credential_manager_credential_store()
        NativeVaultUnavailable => Err(UnsupportedPlatform)
      }
    File(directory) => Ok(file_credential_store(directory))
  }
}

///|
/// Human-readable type of the selected platform-native vault. This contains no
/// credential state or native diagnostic text.
pub fn native_credential_store_label() -> String {
  match detected_native_credential_vault() {
    MacOSKeychain => "macOS Keychain"
    LinuxSecretService => "Linux Secret Service"
    WindowsCredentialManager => "Windows Credential Manager"
    NativeVaultUnavailable => "native OS credential vault"
  }
}
