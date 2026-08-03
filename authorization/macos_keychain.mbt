///|
/// The supported production credential locations. File storage is explicit: selecting
/// Keychain never falls back to a file if the platform service is unavailable.
pub(all) enum CredentialStoreKind {
  Keychain
  File(String)
}

///|
/// The narrow, injectable macOS Keychain boundary. Its values are serialized
/// authorization documents; errors intentionally contain no platform diagnostics.
pub(all) struct MacOSKeychainBackend {
  load : async () -> Result[String, CredentialStoreError]
  replace : async (String) -> Result[Unit, CredentialStoreError]
  delete : async () -> Result[Unit, CredentialStoreError]
}

///|
/// Adapt a macOS Keychain backend to the credential-store contract.
pub fn macos_keychain_credential_store_with_backend(
  backend : MacOSKeychainBackend,
) -> CredentialStore {
  {
    load: async fn() {
      match (backend.load)() {
        Ok(document) => stored_authorization_json(document)
        Err(error) => Err(error)
      }
    },
    replace: async fn(authorization) {
      (backend.replace)(authorization_json(authorization))
    },
    delete: async fn() { (backend.delete)() },
  }
}

///|
/// Create the native macOS Keychain store. Unsupported OSes and architectures are
/// rejected before a caller can accidentally choose a file fallback.
pub fn macos_keychain_credential_store() -> Result[
  CredentialStore,
  ProjectAuthorizationError,
] {
  production_credential_store_with_keychain(
    CredentialStoreKind::Keychain,
    native_macos_keychain_available(),
    macos_keychain_credential_store_with_backend(
      native_macos_keychain_backend(),
    ),
  )
}

///|
/// Injectable production selector seam. It keeps unsupported-platform behavior
/// testable and deliberately never substitutes a file for a Keychain request.
pub fn production_credential_store_with_keychain(
  kind : CredentialStoreKind,
  keychain_available : Bool,
  keychain : CredentialStore,
) -> Result[CredentialStore, ProjectAuthorizationError] {
  match kind {
    Keychain =>
      if keychain_available {
        Ok(keychain)
      } else {
        Err(StorageUnavailable)
      }
    File(directory) => Ok(file_credential_store(directory))
  }
}

///|
/// Select a production store without depending on the command package.
pub fn production_credential_store(
  kind : CredentialStoreKind,
) -> Result[CredentialStore, ProjectAuthorizationError] {
  match kind {
    Keychain => macos_keychain_credential_store()
    File(directory) => Ok(file_credential_store(directory))
  }
}
