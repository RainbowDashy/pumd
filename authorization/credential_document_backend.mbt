///|
/// A narrow, injectable native-vault boundary. Values are serialized
/// authorization documents and failures are restricted to secret-free classes.
pub(all) struct CredentialDocumentBackend {
  load : async () -> Result[String, CredentialStoreError]
  replace : async (String) -> Result[Unit, CredentialStoreError]
  delete : async () -> Result[Unit, CredentialStoreError]
}

///|
fn credential_store_with_document_backend(
  backend : CredentialDocumentBackend,
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
/// Stable status mapping shared by native vault FFIs. Platform diagnostics are
/// deliberately collapsed before they cross the credential-store boundary.
fn native_credential_store_error(status : Int) -> CredentialStoreError {
  match status {
    -1 => CredentialStoreError::NotConfigured
    -2 => CredentialStoreError::Denied
    -4 => CredentialStoreError::Malformed
    -5 => CredentialStoreError::Unsupported
    _ => CredentialStoreError::Unavailable
  }
}
