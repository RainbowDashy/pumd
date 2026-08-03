///|
fn windows_test_authorization(refresh_token : String) -> StoredAuthorization {
  {
    version: 1,
    client_id: "windows-client",
    client_secret: "windows-secret",
    refresh_token,
    token_uri: "https://oauth2.googleapis.com/token",
    scope: drive_file_scope,
    project_id: None,
  }
}

///|
async test "Windows Credential Manager adapter safely replaces and deletes idempotently" {
  let first_document =
    #|{"version":1,"client_id":"windows-client","client_secret":"windows-secret","refresh_token":"first-refresh","token_uri":"https://oauth2.googleapis.com/token","scope":"https://www.googleapis.com/auth/drive.file"}
  let mut saved : String? = Some(first_document)
  let mut replacement_denied = false
  let store = windows_credential_manager_credential_store_with_backend({
    load: fn() {
      match saved {
        Some(document) => Ok(document)
        None => Err(CredentialStoreError::NotConfigured)
      }
    },
    replace: fn(document) {
      if replacement_denied {
        Err(CredentialStoreError::Denied)
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
  guard (store.load)() is Ok(first) else {
    fail("existing Windows credential must load")
  }
  assert_eq(first.refresh_token, "first-refresh")
  replacement_denied = true
  guard (store.replace)(windows_test_authorization("second-refresh"))
    is Err(CredentialStoreError::Denied) else {
    fail("failed Windows replacement must be classified")
  }
  guard (store.load)() is Ok(preserved) else {
    fail("failed Windows replacement must preserve the prior credential")
  }
  assert_eq(preserved.refresh_token, "first-refresh")
  replacement_denied = false
  guard (store.replace)(windows_test_authorization("second-refresh")) is Ok(_) else {
    fail("Windows credential replacement must succeed")
  }
  guard (store.load)() is Ok(replaced) else {
    fail("replaced Windows credential must load")
  }
  assert_eq(replaced.refresh_token, "second-refresh")
  guard (store.delete)() is Ok(_) else {
    fail("Windows credential delete must succeed")
  }
  guard (store.load)() is Err(CredentialStoreError::NotConfigured) else {
    fail("deleted Windows credential must be absent")
  }
  guard (store.delete)() is Ok(_) else {
    fail("Windows credential delete must be idempotent")
  }
}

///|
async test "Windows Credential Manager adapter classifies malformed and vault failures without diagnostics" {
  let malformed = windows_credential_manager_credential_store_with_backend({
    load: fn() { Ok("credential=never-display-windows-secret") },
    replace: fn(_) { Err(CredentialStoreError::Unsupported) },
    delete: fn() { Err(CredentialStoreError::Unavailable) },
  })
  guard (malformed.load)() is Err(CredentialStoreError::Malformed) else {
    fail("malformed Windows credential must be classified without its contents")
  }
  guard (malformed.replace)(windows_test_authorization("never-display-refresh"))
    is Err(CredentialStoreError::Unsupported) else {
    fail(
      "unsupported Windows vault must be classified without native diagnostics",
    )
  }
  guard (malformed.delete)() is Err(CredentialStoreError::Unavailable) else {
    fail(
      "unavailable Windows vault must be classified without native diagnostics",
    )
  }
  let absent_or_denied = windows_credential_manager_credential_store_with_backend({
      load: fn() { Err(CredentialStoreError::NotConfigured) },
      replace: fn(_) { Err(CredentialStoreError::Denied) },
      delete: fn() { Err(CredentialStoreError::Denied) },
    },
  )
  guard (absent_or_denied.load)() is Err(CredentialStoreError::NotConfigured) else {
    fail("absent Windows credential must be classified")
  }
  guard (absent_or_denied.replace)(windows_test_authorization("secret"))
    is Err(CredentialStoreError::Denied) else {
    fail("denied Windows replacement must be classified")
  }
}

///|
test "Windows Credential Manager selection never falls back when unavailable" {
  let backend : CredentialDocumentBackend = {
    load: fn() { Err(CredentialStoreError::NotConfigured) },
    replace: fn(_) { Ok(()) },
    delete: fn() { Ok(()) },
  }
  guard windows_credential_manager_credential_store_with_availability(
      false, backend,
    )
    is Err(StorageUnavailable) else {
    fail("unavailable Windows Credential Manager must not select file storage")
  }
}

///|
test "native Windows x64 exposes Credential Manager only on its supported platform" {
  let selected = windows_credential_manager_credential_store()
  match (@env.get_env_var("OS"), @env.get_env_var("PROCESSOR_ARCHITECTURE")) {
    (Some("Windows_NT"), Some("AMD64")) => {
      guard selected is Ok(_) else {
        fail("Windows x64 must expose the native Credential Manager store")
      }
    }
    _ => {
      guard selected is Err(StorageUnavailable) else {
        fail("other platforms must not expose the Windows credential store")
      }
    }
  }
}
