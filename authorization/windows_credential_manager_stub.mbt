///|
fn native_windows_credential_manager_available() -> Bool {
  false
}

///|
fn native_windows_credential_manager_backend() -> CredentialDocumentBackend {
  {
    load: async fn() { Err(CredentialStoreError::Unsupported) },
    replace: async fn(_) { Err(CredentialStoreError::Unsupported) },
    delete: async fn() { Err(CredentialStoreError::Unsupported) },
  }
}
