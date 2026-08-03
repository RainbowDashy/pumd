///|
fn native_macos_keychain_available() -> Bool {
  false
}

///|
fn native_macos_keychain_backend() -> MacOSKeychainBackend {
  {
    load: async fn() { Err(CredentialStoreError::Unsupported) },
    replace: async fn(_) { Err(CredentialStoreError::Unsupported) },
    delete: async fn() { Err(CredentialStoreError::Unsupported) },
  }
}
