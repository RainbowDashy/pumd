///|
priv struct VaultContractHttp {
  requests : Array[@google_http.HttpRequest]
  responses : Array[@google_http.HttpResponse]
}

///|
impl @google_http.HttpClient for VaultContractHttp with fn request(
  self,
  request,
) {
  let index = self.requests.length()
  self.requests.push(request)
  self.responses[index]
}

///|
async fn verify_credential_store_lifecycle(
  name : String,
  store : CredentialStore,
  verify_failed_replacement : async (StoredAuthorization) -> Unit,
) -> Unit {
  guard (store.load)() is Err(CredentialStoreError::NotConfigured) else {
    fail(name + " must report an absent authorization")
  }
  let client_document =
    #|{"installed":{"client_id":"contract-client.apps.googleusercontent.com","project_id":"contract-project","client_secret":"contract-client-secret","auth_uri":"https://accounts.google.com/o/oauth2/v2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}
  let callback_state = "YWJjZGFiY2RhYmNkYWJjZGFiY2RhYmNkYWJjZGFiY2Q"
  let setup = setup_project_authorization(client_document, {
    random_bytes: fn(_) { Ok(b"abcdabcdabcdabcdabcdabcdabcdabcd") },
    start_listener: fn() {
      Ok({
        redirect_uri: "http://127.0.0.1:47123/oauth2/callback",
        await_callback: fn() {
          Ok("code=authorization-code&state=" + callback_state)
        },
      })
    },
    launch_browser: fn(_) { Ok(()) },
    report_authorization_url: fn(_) { () },
    exchange_code: fn(_) {
      Ok({ access_token: "setup-access", refresh_token: Some("first-refresh") })
    },
    store,
  })
  guard setup is Ok(setup_status) else { fail(name + " must complete setup") }
  assert_eq(setup_status.project_id, Some("contract-project"))
  guard project_authorization_status(store) is Ok(status) else {
    fail(name + " must report configured status")
  }
  assert_true(status.configured)
  guard project_access_token_classified(store, fn(_) {
      Ok({ access_token: "fresh-access", refresh_token: None })
    })
    is Ok("fresh-access") else {
    fail(name + " must refresh the stored authorization")
  }
  guard (store.load)() is Ok(created) else {
    fail(name + " must load a created authorization")
  }
  assert_eq(created.project_id, Some("contract-project"))
  let http = VaultContractHttp::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"documentId\":\"contract-doc\"}",
      ),
      @google_http.HttpResponse::new(200, {}, "{}"),
    ],
  }
  guard @publish.publish_markdown_with_authorization(
      "Hello",
      "contract",
      @publish.AuthorizationMode::Project,
      fn() { Ok("fresh-access") },
      fn() { Err(@publish.AuthenticationProblem::CredentialsInvalid) },
      http,
    )
    is Ok(published) else {
    fail(name + " must publish with its refreshed authorization")
  }
  assert_eq(published.document_id, "contract-doc")
  let second : StoredAuthorization = {
    ..created,
    refresh_token: "second-refresh",
  }
  verify_failed_replacement(second)
  guard (store.load)() is Ok(preserved) else {
    fail(name + " must preserve the authorization before replacement")
  }
  assert_eq(preserved.refresh_token, "first-refresh")
  guard (store.replace)(second) is Ok(_) else {
    fail(name + " must replace an authorization")
  }
  guard (store.load)() is Ok(updated) else {
    fail(name + " must load the updated authorization")
  }
  assert_eq(updated.refresh_token, "second-refresh")
  guard (store.delete)() is Ok(_) else {
    fail(name + " must delete an authorization")
  }
  guard (store.load)() is Err(CredentialStoreError::NotConfigured) else {
    fail(name + " must report a deleted authorization as absent")
  }
  guard (store.delete)() is Ok(_) else {
    fail(name + " delete must be idempotent")
  }
}

///|
async fn verify_injected_native_vault_contract(
  name : String,
  adapt : (
    async () -> Result[String, CredentialStoreError],
    async (String) -> Result[Unit, CredentialStoreError],
    async () -> Result[Unit, CredentialStoreError],
  ) -> CredentialStore,
) -> Unit {
  let mut saved : String? = None
  let mut fail_replace = false
  let store = adapt(
    fn() {
      match saved {
        Some(document) => Ok(document)
        None => Err(CredentialStoreError::NotConfigured)
      }
    },
    fn(document) {
      if fail_replace {
        Err(CredentialStoreError::Unavailable)
      } else {
        saved = Some(document)
        Ok(())
      }
    },
    fn() {
      saved = None
      Ok(())
    },
  )
  verify_credential_store_lifecycle(name, store, async fn(second) {
    fail_replace = true
    guard (store.replace)(second) is Err(CredentialStoreError::Unavailable) else {
      fail(name + " must classify replacement failure")
    }
    fail_replace = false
  })
}

///|
async test "native vault adapters satisfy the shared CredentialStore contract" {
  verify_injected_native_vault_contract("macOS Keychain", fn(
    load,
    replace,
    delete,
  ) {
    macos_keychain_credential_store_with_backend({ load, replace, delete })
  })
  verify_injected_native_vault_contract("Linux Secret Service", fn(
    load,
    replace,
    delete,
  ) {
    linux_secret_service_credential_store_with_backend({ load, replace, delete })
  })
  verify_injected_native_vault_contract("Windows Credential Manager", fn(
    load,
    replace,
    delete,
  ) {
    windows_credential_manager_credential_store_with_backend({
      load,
      replace,
      delete,
    })
  })
}

///|
async test "explicit file adapter satisfies the shared CredentialStore contract" {
  let directory = "_build/credential-store-contract-file"
  @fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
  verify_credential_store_lifecycle(
    "Explicit file store",
    file_credential_store(directory),
    fn(_) { () },
  )
  @fs.rmdir(directory, recursive=true)
}
