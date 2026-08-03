///|
/// Adapt a macOS Keychain backend to the credential-store contract.
pub fn macos_keychain_credential_store_with_backend(
  backend : CredentialDocumentBackend,
) -> CredentialStore {
  credential_store_with_document_backend(backend)
}

///|
/// Create the native macOS Keychain store. Unsupported OSes and architectures are
/// rejected before a caller can accidentally choose a file fallback.
pub fn macos_keychain_credential_store() -> Result[
  CredentialStore,
  ProjectAuthorizationError,
] {
  production_credential_store_with_keychain(
    CredentialStoreKind::Native,
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
    Native =>
      if keychain_available {
        Ok(keychain)
      } else {
        Err(StorageUnavailable)
      }
    File(directory) => Ok(file_credential_store(directory))
  }
}
