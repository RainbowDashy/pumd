///|
fn native_linux_secret_service_available() -> Bool {
  false
}

///|
fn native_linux_secret_service_backend() -> CredentialDocumentBackend {
  {
    load: async fn() { Err(CredentialStoreError::Unsupported) },
    replace: async fn(_) { Err(CredentialStoreError::Unsupported) },
    delete: async fn() { Err(CredentialStoreError::Unsupported) },
  }
}
