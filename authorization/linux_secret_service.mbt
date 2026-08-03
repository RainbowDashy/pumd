///|
/// Adapt a Linux Secret Service backend to the credential-store contract.
pub fn linux_secret_service_credential_store_with_backend(
  backend : CredentialDocumentBackend,
) -> CredentialStore {
  credential_store_with_document_backend(backend)
}

///|
/// Injectable production selector seam. An unavailable Secret Service is an
/// error and is never replaced with a file-backed credential store.
pub fn linux_secret_service_credential_store_with_availability(
  available : Bool,
  secret_service : CredentialStore,
) -> Result[CredentialStore, ProjectAuthorizationError] {
  if available {
    Ok(secret_service)
  } else {
    Err(StorageUnavailable)
  }
}

///|
/// Create the native Linux x64 Secret Service credential store.
pub fn linux_secret_service_credential_store() -> Result[
  CredentialStore,
  ProjectAuthorizationError,
] {
  linux_secret_service_credential_store_with_availability(
    native_linux_secret_service_available(),
    linux_secret_service_credential_store_with_backend(
      native_linux_secret_service_backend(),
    ),
  )
}
