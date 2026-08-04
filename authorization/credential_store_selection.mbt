///|
/// The supported production credential locations. File storage is explicit:
/// selecting the platform-native vault never falls back to a file.
pub(all) enum CredentialStoreKind {
  Native
  File(String)
}

///|
/// Secret-free reasons a credential store cannot safely accept setup.
pub(all) enum CredentialStoreUnavailableReason {
  MissingEntitlement
  Locked
  PermissionDenied
  ServiceUnavailable
  CleanupFailed
  UnsupportedPlatform
  UnknownFailure
}

///|
/// Setup capability is based on a safe write/read/delete probe, not on whether
/// loading the active authorization happens to report an empty store.
pub(all) enum CredentialStoreCapability {
  Usable
  Unavailable(CredentialStoreUnavailableReason)
}

///|
/// One user-visible setup choice at the Project Authorization boundary.
pub(all) struct CredentialStoreCatalogEntry {
  identifier : CredentialStoreIdentifier
  label : String
  protection : String
  capability : CredentialStoreCapability
}

///|
pub fn credential_store_capability_catalog(
  native_label : String,
  native_capability : CredentialStoreCapability,
) -> Array[CredentialStoreCatalogEntry] {
  [
    {
      identifier: CredentialStoreIdentifier::Native,
      label: native_label,
      protection: "protected by the operating system credential vault",
      capability: native_capability,
    },
    {
      identifier: CredentialStoreIdentifier::File,
      label: "file",
      protection: "reduced protection in a permission-hardened local file",
      capability: CredentialStoreCapability::Usable,
    },
  ]
}

///|
pub(all) enum CredentialStoreMenuChoice {
  Native
  File
}

///|
pub(all) enum CredentialStoreMenuError {
  Cancelled
  Recheck
  Invalid
  Disabled(CredentialStoreUnavailableReason)
}

///|
/// Resolve the two-option setup menu. File storage is never selected by an
/// empty response, including when the native option is disabled.
pub fn credential_store_menu_choice(
  input : String?,
  native_capability : CredentialStoreCapability,
) -> Result[CredentialStoreMenuChoice, CredentialStoreMenuError] {
  match input {
    None | Some("q") | Some("Q") => Err(Cancelled)
    Some("r") | Some("R") => Err(Recheck)
    Some("2") => Ok(File)
    Some("") | Some("1") =>
      match native_capability {
        Usable => Ok(Native)
        Unavailable(reason) =>
          if input == Some("") {
            Err(Cancelled)
          } else {
            Err(Disabled(reason))
          }
      }
    Some(_) => Err(Invalid)
  }
}

///|
pub async fn credential_store_capability(
  store : CredentialStore,
) -> CredentialStoreCapability {
  match (store.probe)() {
    Ok(_) => Usable
    Err(CredentialStoreError::MissingEntitlement) =>
      Unavailable(MissingEntitlement)
    Err(CredentialStoreError::Locked) => Unavailable(Locked)
    Err(CredentialStoreError::Denied) => Unavailable(PermissionDenied)
    Err(CredentialStoreError::Unavailable) => Unavailable(ServiceUnavailable)
    Err(CredentialStoreError::CleanupFailed) => Unavailable(CleanupFailed)
    Err(CredentialStoreError::Unsupported) => Unavailable(UnsupportedPlatform)
    Err(CredentialStoreError::NotConfigured)
    | Err(CredentialStoreError::Malformed) => Unavailable(UnknownFailure)
  }
}

///|
pub fn CredentialStoreUnavailableReason::user_message(
  self : CredentialStoreUnavailableReason,
) -> String {
  match self {
    MissingEntitlement =>
      "this pumd executable lacks the entitlement required by its macOS Keychain implementation; install a correctly signed build"
    Locked => "the credential vault is locked; unlock it, then recheck"
    PermissionDenied =>
      "permission to use the credential vault was denied; allow pumd, then recheck"
    ServiceUnavailable =>
      "the credential-vault service, session, or collection is unavailable"
    CleanupFailed =>
      "the credential vault could not remove its non-secret capability probe; clean up the probe and recheck"
    UnsupportedPlatform =>
      "this platform has no supported native credential vault"
    UnknownFailure =>
      "the credential vault failed its safe write, read, and delete check"
  }
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
