///|
/// Adapt Windows Credential Manager to the shared credential-store contract.
pub fn windows_credential_manager_credential_store_with_backend(
  backend : CredentialDocumentBackend,
) -> CredentialStore {
  credential_store_with_document_backend(backend)
}

///|
/// Select the Windows vault only when it is available. This helper deliberately
/// has no file-store branch, so an unavailable vault cannot reduce protection.
pub fn windows_credential_manager_credential_store_with_availability(
  available : Bool,
  backend : CredentialDocumentBackend,
) -> Result[CredentialStore, ProjectAuthorizationError] {
  if available {
    Ok(windows_credential_manager_credential_store_with_backend(backend))
  } else {
    Err(StorageUnavailable)
  }
}

///|
/// Create the native Windows x64 Credential Manager store.
pub fn windows_credential_manager_credential_store() -> Result[
  CredentialStore,
  ProjectAuthorizationError,
] {
  windows_credential_manager_credential_store_with_availability(
    native_windows_credential_manager_available(),
    native_windows_credential_manager_backend(),
  )
}
