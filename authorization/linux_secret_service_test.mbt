///|
async test "Linux Secret Service adapter creates, reads, safely replaces, and idempotently deletes" {
  let first : StoredAuthorization = {
    version: 1,
    client_id: "first-client",
    client_secret: "first-secret",
    refresh_token: "first-refresh",
    token_uri: "https://oauth2.googleapis.com/token",
    scope: drive_file_scope,
    project_id: None,
  }
  let second : StoredAuthorization = {
    ..first,
    client_id: "second-client",
    refresh_token: "second-refresh",
  }
  let mut saved : String? = None
  let mut fail_replace = false
  let store = linux_secret_service_credential_store_with_backend({
    probe: fn() { Ok(()) },
    load: fn() {
      match saved {
        Some(document) => Ok(document)
        None => Err(CredentialStoreError::NotConfigured)
      }
    },
    replace: fn(document) {
      if fail_replace {
        Err(CredentialStoreError::Unavailable)
      } else {
        saved = Some(document)
        Ok(())
      }
    },
    delete: fn() {
      saved = None
      Ok(())
    },
  })
  guard (store.load)() is Err(CredentialStoreError::NotConfigured) else {
    fail("an empty Secret Service store must be absent")
  }
  guard (store.replace)(first) is Ok(_) else {
    fail("Secret Service must create the active authorization")
  }
  guard (store.load)() is Ok(created) else {
    fail("created Secret Service authorization must load")
  }
  assert_eq(created.refresh_token, "first-refresh")
  fail_replace = true
  guard (store.replace)(second) is Err(CredentialStoreError::Unavailable) else {
    fail("failed Secret Service replacement must be classified")
  }
  guard (store.load)() is Ok(preserved) else {
    fail("failed replacement must preserve the prior authorization")
  }
  assert_eq(preserved.refresh_token, "first-refresh")
  fail_replace = false
  guard (store.replace)(second) is Ok(_) else {
    fail("Secret Service must update the active authorization")
  }
  guard (store.load)() is Ok(updated) else {
    fail("updated Secret Service authorization must load")
  }
  assert_eq(updated.refresh_token, "second-refresh")
  guard (store.delete)() is Ok(_) else {
    fail("Secret Service delete must succeed")
  }
  guard (store.load)() is Err(CredentialStoreError::NotConfigured) else {
    fail("deleted Secret Service authorization must be absent")
  }
  guard (store.delete)() is Ok(_) else {
    fail("Secret Service delete must be idempotent")
  }
}

///|
async test "Linux Secret Service adapter classifies malformed, locked, unavailable, and unsupported without diagnostics" {
  let malformed = linux_secret_service_credential_store_with_backend({
    probe: fn() { Ok(()) },
    load: fn() { Ok("not-an-authorization-document") },
    replace: fn(_) { Ok(()) },
    delete: fn() { Ok(()) },
  })
  guard (malformed.load)() is Err(CredentialStoreError::Malformed) else {
    fail("corrupted Secret Service entries must be malformed")
  }
  let secret = "never-display-secret-service-value"
  let denied = linux_secret_service_credential_store_with_backend({
    probe: fn() { Err(CredentialStoreError::Denied) },
    load: fn() { Err(CredentialStoreError::Denied) },
    replace: fn(_) { Err(CredentialStoreError::Denied) },
    delete: fn() { Err(CredentialStoreError::Denied) },
  })
  guard (denied.replace)({
      version: 1,
      client_id: "client",
      client_secret: secret,
      refresh_token: secret,
      token_uri: "https://oauth2.googleapis.com/token",
      scope: drive_file_scope,
      project_id: None,
    })
    is Err(denied_error) else {
    fail("locked or denied Secret Service replacement must fail")
  }
  guard denied_error is CredentialStoreError::Denied else {
    fail("denied Secret Service errors must contain no native diagnostic")
  }
  let unavailable = linux_secret_service_credential_store_with_backend({
    probe: fn() { Err(CredentialStoreError::Unavailable) },
    load: fn() { Err(CredentialStoreError::Unavailable) },
    replace: fn(_) { Err(CredentialStoreError::Unavailable) },
    delete: fn() { Err(CredentialStoreError::Unavailable) },
  })
  guard (unavailable.load)() is Err(CredentialStoreError::Unavailable) else {
    fail("missing service, session bus, or collection must be unavailable")
  }
  let unsupported = linux_secret_service_credential_store_with_backend({
    probe: fn() { Err(CredentialStoreError::Unsupported) },
    load: fn() { Err(CredentialStoreError::Unsupported) },
    replace: fn(_) { Err(CredentialStoreError::Unsupported) },
    delete: fn() { Err(CredentialStoreError::Unsupported) },
  })
  guard (unsupported.delete)() is Err(CredentialStoreError::Unsupported) else {
    fail("unsupported targets must remain distinct")
  }
}

///|
async test "Linux Secret Service selection has no file fallback when unavailable" {
  let backend : CredentialDocumentBackend = {
    probe: fn() { Ok(()) },
    load: fn() { Err(CredentialStoreError::NotConfigured) },
    replace: fn(_) { Ok(()) },
    delete: fn() { Ok(()) },
  }
  guard linux_secret_service_credential_store_with_availability(
      false,
      linux_secret_service_credential_store_with_backend(backend),
    )
    is Err(StorageUnavailable) else {
    fail("unavailable Secret Service must not silently select a file store")
  }
}
