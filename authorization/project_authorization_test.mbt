///|
test "Project Authorization accepts a Google Desktop installed-client document" {
  let document =
    #|{"installed":{"client_id":"desktop-client.apps.googleusercontent.com","project_id":"review-project","client_secret":"client-secret","auth_uri":"https://accounts.google.com/o/oauth2/v2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}
  match parse_installed_client(document) {
    Ok(client) => {
      assert_eq(client.client_id, "desktop-client.apps.googleusercontent.com")
      assert_eq(client.auth_uri, "https://accounts.google.com/o/oauth2/v2/auth")
      assert_eq(client.token_uri, "https://oauth2.googleapis.com/token")
      assert_eq(client.project_id, Some("review-project"))
    }
    Err(error) => fail(error.user_message())
  }
}

///|
async test "Project Authorization setup constructs a PKCE desktop request with exactly drive.file" {
  let document =
    #|{"installed":{"client_id":"desktop-client.apps.googleusercontent.com","project_id":"review-project","client_secret":"client-secret","auth_uri":"https://accounts.google.com/o/oauth2/v2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}
  let random = b"abcdabcdabcdabcdabcdabcdabcdabcd"
  let callback_state = "YWJjZGFiY2RhYmNkYWJjZGFiY2RhYmNkYWJjZGFiY2Q"
  let mut exchanged : TokenExchangeRequest? = None
  let mut saved : StoredAuthorization? = None
  let dependencies : SetupDependencies = {
    random_bytes: fn(_) { Ok(random) },
    start_listener: fn() {
      Ok({
        redirect_uri: "http://127.0.0.1:47123/oauth2/callback",
        await_callback: fn() {
          Ok("code=authorization-code&state=" + callback_state)
        },
      })
    },
    launch_browser: fn(url) {
      if !url.contains("scope=") ||
        !url.contains("drive.file") ||
        !url.contains("access_type=offline") ||
        !url.contains("prompt=consent") ||
        !url.contains("code_challenge_method=S256") ||
        url.contains("openid") ||
        url.contains("userinfo") {
        return Err("unexpected authorization request")
      }
      Ok(())
    },
    report_authorization_url: fn(_) { () },
    exchange_code: fn(request) {
      exchanged = Some(request)
      Ok({ access_token: "transient", refresh_token: Some("refresh-token") })
    },
    store: {
      probe: fn() { Ok(()) },
      load: fn() { Err(CredentialStoreError::NotConfigured) },
      replace: fn(authorization) {
        saved = Some(authorization)
        Ok(())
      },
      delete: fn() { Ok(()) },
    },
  }
  let result = setup_project_authorization(document, dependencies)
  match result {
    Ok(status) => {
      assert_true(status.configured)
      assert_eq(status.scope, drive_file_scope)
      assert_eq(status.project_id, Some("review-project"))
    }
    Err(error) => fail(error.user_message())
  }
  let request = exchanged.unwrap()
  assert_eq(request.code, "authorization-code")
  assert_eq(request.redirect_uri, "http://127.0.0.1:47123/oauth2/callback")
  assert_eq(request.scope, drive_file_scope)
  assert_true(request.code_verifier.length() >= 43)
  let stored = saved.unwrap()
  assert_eq(stored.refresh_token, "refresh-token")
  assert_eq(stored.scope, drive_file_scope)
  assert_eq(stored.project_id, Some("review-project"))
}

///|
async fn setup_with_store_replacement_error(
  store_error : CredentialStoreError,
) -> Result[ProjectAuthorizationStatus, ProjectAuthorizationError] {
  let document =
    #|{"installed":{"client_id":"desktop-client.apps.googleusercontent.com","client_secret":"client-secret","auth_uri":"https://accounts.google.com/o/oauth2/v2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}
  setup_project_authorization(document, {
    random_bytes: fn(_) { Ok(b"abcdabcdabcdabcdabcdabcdabcdabcd") },
    start_listener: fn() {
      Ok({
        redirect_uri: "http://127.0.0.1:1/oauth2/callback",
        await_callback: fn() {
          Ok("code=ok&state=YWJjZGFiY2RhYmNkYWJjZGFiY2RhYmNkYWJjZGFiY2Q")
        },
      })
    },
    launch_browser: fn(_) { Ok(()) },
    report_authorization_url: fn(_) { () },
    exchange_code: fn(_) {
      Ok({ access_token: "access", refresh_token: Some("refresh") })
    },
    store: {
      probe: fn() { Ok(()) },
      load: fn() { Err(CredentialStoreError::NotConfigured) },
      replace: fn(_) { Err(store_error) },
      delete: fn() { Ok(()) },
    },
  })
}

///|
async test "setup preserves vault replacement failure classifications" {
  guard setup_with_store_replacement_error(
      CredentialStoreError::MissingEntitlement,
    )
    is Err(StorageMissingEntitlement) else {
    fail("missing Keychain entitlement must remain distinct")
  }
  guard setup_with_store_replacement_error(CredentialStoreError::Denied)
    is Err(StorageDenied) else {
    fail("denied replacement must remain distinct")
  }
  guard setup_with_store_replacement_error(CredentialStoreError::Unsupported)
    is Err(UnsupportedPlatform) else {
    fail("unsupported replacement must remain distinct")
  }
  guard setup_with_store_replacement_error(CredentialStoreError::Unavailable)
    is Err(StorageUnavailable) else {
    fail("unavailable replacement must remain distinct")
  }
}

///|
test "Project Authorization rejects malformed, read-level, and web client documents without secrets" {
  let invalid_documents = [
    "not JSON", "{}", "{\"web\":{\"client_id\":\"secret-client\",\"client_secret\":\"secret-value\"}}",
    "{\"installed\":{\"client_id\":\"id\",\"client_secret\":\"secret-value\",\"auth_uri\":\"http://accounts.google.com/auth\",\"token_uri\":\"https://oauth2.googleapis.com/token\"}}",
    "{\"installed\":{\"client_id\":\"id\",\"client_secret\":\"secret-value\",\"auth_uri\":\"https://accounts.google.com/o/oauth2/v2/auth.evil\",\"token_uri\":\"https://oauth2.googleapis.com/token\",\"redirect_uris\":[\"http://localhost\"]}}",
    "{\"installed\":{\"client_id\":\"id\",\"client_secret\":\"secret-value\",\"auth_uri\":\"https://accounts.google.com/o/oauth2/v2/auth\",\"token_uri\":\"https://oauth2.googleapis.com/token?target=evil\",\"redirect_uris\":[\"http://localhost\"]}}",
    "{\"installed\":{\"client_id\":\"id\",\"client_secret\":\"secret-value\",\"auth_uri\":\"https://accounts.google.com/o/oauth2/v2/auth\",\"token_uri\":\"https://oauth2.googleapis.com/token\",\"redirect_uris\":[\"http://localhost:not-a-port\"]}}",
    "{\"installed\":{\"client_id\":\"id\",\"client_secret\":\"secret-value\",\"auth_uri\":\"https://accounts.google.com/o/oauth2/v2/auth\",\"token_uri\":\"https://oauth2.googleapis.com/token\",\"redirect_uris\":[\"http://127.0.0.1:65536\"]}}",
  ]
  for document in invalid_documents {
    match parse_installed_client(document) {
      Err(error) => {
        let message = error.user_message()
        assert_false(message.contains("secret-value"))
        assert_false(message.contains("secret-client"))
      }
      Ok(_) =>
        fail("invalid Project Authorization client document was accepted")
    }
  }
}

///|
test "Project Authorization callback rejects OAuth errors, mismatched state, and duplicate fields" {
  guard parse_callback_query("error=access_denied&state=expected", "expected")
    is Err(_) else {
    fail("OAuth callback error must be rejected")
  }
  guard parse_callback_query("code=one&state=other", "expected") is Err(_) else {
    fail("state mismatch must be rejected")
  }
  guard parse_callback_query("code=one&code=two&state=expected", "expected")
    is Err(_) else {
    fail("duplicate callback field must be rejected")
  }
  match parse_callback_query("code=a%2Bb&state=expected", "expected") {
    Ok(code) => assert_eq(code, "a+b")
    Err(error) => fail(error.user_message())
  }
}

///|
async test "Project Authorization status redacts secrets and refresh failures require reauthorization" {
  let stored : StoredAuthorization = {
    version: 1,
    client_id: "visible-client",
    client_secret: "never-display-client-secret",
    refresh_token: "never-display-refresh-token",
    token_uri: "https://oauth2.googleapis.com/token",
    scope: drive_file_scope,
    project_id: None,
  }
  let store : CredentialStore = {
    probe: fn() { Ok(()) },
    load: fn() { Ok(stored) },
    replace: fn(_) { Ok(()) },
    delete: fn() { Ok(()) },
  }
  match project_authorization_status(store) {
    Ok(status) => {
      assert_true(status.configured)
      assert_eq(status.client_id, Some("visible-client"))
      assert_eq(status.scope, drive_file_scope)
    }
    Err(error) => fail(error.user_message())
  }
  let result = project_authorization_usable_status(store, fn(_) {
    Err("revoked refresh token")
  })
  match result {
    Err(error) => {
      let message = error.user_message()
      assert_true(message.contains("reauthorization"))
      assert_false(message.contains("never-display"))
      assert_false(message.contains("revoked"))
    }
    Ok(_) => fail("revoked credentials must not return an access token")
  }
}

///|
async test "Project Authorization keeps missing, denied, unavailable, and unsupported stores distinct" {
  fn store_with(error : CredentialStoreError) -> CredentialStore {
    {
      probe: fn() { Err(error) },
      load: fn() { Err(error) },
      replace: fn(_) { Err(error) },
      delete: fn() { Err(error) },
    }
  }
  guard project_access_token(store_with(CredentialStoreError::NotConfigured), fn(
      _,
    ) {
      Err("must not refresh")
    })
    is Err(NotConfigured) else {
    fail("missing setup must remain distinct")
  }
  guard project_authorization_status(store_with(CredentialStoreError::Denied))
    is Err(StorageDenied) else {
    fail("vault denial must remain distinct")
  }
  guard project_authorization_status(
      store_with(CredentialStoreError::Unavailable),
    )
    is Err(StorageUnavailable) else {
    fail("vault unavailability must remain distinct")
  }
  guard project_authorization_status(
      store_with(CredentialStoreError::Unsupported),
    )
    is Err(UnsupportedPlatform) else {
    fail("unsupported platforms must remain distinct")
  }
}

///|
async test "Project Authorization listener and token failures never replace the prior grant" {
  let document =
    #|{"installed":{"client_id":"desktop-client.apps.googleusercontent.com","client_secret":"client-secret","auth_uri":"https://accounts.google.com/o/oauth2/v2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}
  let mut browser_calls = 0
  let mut exchange_calls = 0
  let mut replacement_calls = 0
  let listener_failure : SetupDependencies = {
    random_bytes: fn(_) { Ok(b"abcdabcdabcdabcdabcdabcdabcdabcd") },
    start_listener: fn() { Err("port unavailable") },
    launch_browser: fn(_) {
      browser_calls = browser_calls + 1
      Ok(())
    },
    report_authorization_url: fn(_) { () },
    exchange_code: fn(_) {
      exchange_calls = exchange_calls + 1
      Ok({ access_token: "", refresh_token: None })
    },
    store: {
      probe: fn() { Ok(()) },
      load: fn() { Err(CredentialStoreError::NotConfigured) },
      replace: fn(_) {
        replacement_calls = replacement_calls + 1
        Ok(())
      },
      delete: fn() { Ok(()) },
    },
  }
  guard setup_project_authorization(document, listener_failure) is Err(_) else {
    fail("listener failure must stop setup")
  }
  assert_eq(browser_calls, 0)
  assert_eq(exchange_calls, 0)
  assert_eq(replacement_calls, 0)
  let missing_refresh : SetupDependencies = {
    random_bytes: fn(_) { Ok(b"abcdabcdabcdabcdabcdabcdabcdabcd") },
    start_listener: fn() {
      Ok({
        redirect_uri: "http://127.0.0.1:1/oauth2/callback",
        await_callback: fn() {
          Ok("code=ok&state=YWJjZGFiY2RhYmNkYWJjZGFiY2RhYmNkYWJjZGFiY2Q")
        },
      })
    },
    launch_browser: fn(_) { Ok(()) },
    report_authorization_url: fn(_) { () },
    exchange_code: fn(_) { Ok({ access_token: "access", refresh_token: None }) },
    store: {
      probe: fn() { Ok(()) },
      load: fn() { Err(CredentialStoreError::NotConfigured) },
      replace: fn(_) {
        replacement_calls = replacement_calls + 1
        Ok(())
      },
      delete: fn() { Ok(()) },
    },
  }
  guard setup_project_authorization(document, missing_refresh) is Err(_) else {
    fail("missing refresh token must stop setup")
  }
  assert_eq(replacement_calls, 0)
  let missing_access : SetupDependencies = {
    ..missing_refresh,
    exchange_code: fn(_) {
      Ok({ access_token: "", refresh_token: Some("refresh") })
    },
  }
  guard setup_project_authorization(document, missing_access) is Err(_) else {
    fail("missing access token must stop setup")
  }
  assert_eq(replacement_calls, 0)
}

///|
priv struct OAuthHttpFake {
  requests : Array[@google_http.HttpRequest]
  responses : Array[@google_http.HttpResponse]
}

///|
impl @google_http.HttpClient for OAuthHttpFake with fn request(self, request) {
  let index = self.requests.length()
  self.requests.push(request)
  self.responses[index]
}

///|
async test "OAuth HTTP exchange and refresh send exact form grants without exposing tokens" {
  let fake = OAuthHttpFake::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"access_token\":\"setup-access\",\"refresh_token\":\"stored-refresh\",\"token_type\":\"Bearer\"}",
      ),
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"access_token\":\"refreshed-access\",\"token_type\":\"Bearer\"}",
      ),
    ],
  }
  let exchanged = exchange_code_with_http(fake, {
    client_id: "desktop-client",
    client_secret: "client-secret",
    token_uri: "https://oauth2.googleapis.com/token",
    code: "code with +",
    code_verifier: "verifier/value",
    redirect_uri: "http://127.0.0.1:12345/oauth2/callback",
    scope: drive_file_scope,
  })
  guard exchanged is Ok(setup_token) else { fail("code exchange must succeed") }
  assert_eq(setup_token.access_token, "setup-access")
  assert_eq(setup_token.refresh_token, Some("stored-refresh"))
  let exchange_body = fake.requests[0].body.unwrap()
  let normalized_exchange_body = exchange_body.to_lower()
  assert_true(exchange_body.contains("grant_type=authorization_code"))
  assert_true(normalized_exchange_body.contains("code=code%20with%20%2b"))
  assert_true(
    normalized_exchange_body.contains("code_verifier=verifier%2fvalue"),
  )
  assert_false(exchange_body.contains("scope=openid"))

  let refreshed = refresh_with_http(fake, {
    client_id: "desktop-client",
    client_secret: "client-secret",
    token_uri: "https://oauth2.googleapis.com/token",
    refresh_token: "stored-refresh",
    scope: drive_file_scope,
  })
  guard refreshed is Ok(refresh_token) else { fail("refresh must succeed") }
  assert_eq(refresh_token.access_token, "refreshed-access")
  let refresh_body = fake.requests[1].body.unwrap()
  assert_true(refresh_body.contains("grant_type=refresh_token"))
  assert_true(refresh_body.contains("refresh_token=stored-refresh"))
  assert_false(refresh_body.contains("authorization_code"))
}

///|
async test "classified refresh distinguishes revoked grants from transient endpoint failures" {
  let fake = OAuthHttpFake::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        400,
        {},
        "{\"error\":\"invalid_grant\",\"error_description\":\"private-revoked\"}",
      ),
      @google_http.HttpResponse::new(
        400,
        {},
        "{\"error\":\"temporarily_unavailable\",\"error_description\":\"private-transient\"}",
      ),
      @google_http.HttpResponse::new(503, {}, "Bearer private-transient"),
    ],
  }
  let request : TokenRefreshRequest = {
    client_id: "desktop-client",
    client_secret: "private-client-secret",
    token_uri: "https://oauth2.googleapis.com/token",
    refresh_token: "private-refresh-token",
    scope: drive_file_scope,
  }
  guard refresh_with_http_classified(fake, request) is Err(Rejected) else {
    fail("invalid_grant-style response must require reauthorization")
  }
  guard refresh_with_http_classified(fake, request) is Err(Transient) else {
    fail("temporary OAuth failure must remain retryable")
  }
  guard refresh_with_http_classified(fake, request) is Err(Transient) else {
    fail("server failure must remain retryable")
  }
}

///|
async test "classified Project Authorization refresh preserves revoked and transient states" {
  let stored : StoredAuthorization = {
    version: 1,
    client_id: "desktop-client",
    client_secret: "private-client-secret",
    refresh_token: "private-refresh-token",
    token_uri: "https://oauth2.googleapis.com/token",
    scope: drive_file_scope,
    project_id: None,
  }
  let store : CredentialStore = {
    probe: fn() { Ok(()) },
    load: fn() { Ok(stored) },
    replace: fn(_) { Ok(()) },
    delete: fn() { Ok(()) },
  }
  guard project_access_token_classified(store, fn(_) { Err(Rejected) })
    is Err(ReauthorizationRequired) else {
    fail("revoked authorization must require setup")
  }
  guard project_access_token_classified(store, fn(_) { Err(Transient) })
    is Err(RefreshTransient) else {
    fail("transient refresh must preserve the stored grant for retry")
  }
}

///|
async test "status inspection preserves project context when reauthorization is required" {
  let stored : StoredAuthorization = {
    version: 1,
    client_id: "desktop-client",
    client_secret: "client-secret",
    refresh_token: "stored-refresh",
    token_uri: "https://oauth2.googleapis.com/token",
    scope: drive_file_scope,
    project_id: Some("status-project"),
  }
  let store : CredentialStore = {
    probe: fn() { Ok(()) },
    load: fn() { Ok(stored) },
    replace: fn(_) { Ok(()) },
    delete: fn() { Ok(()) },
  }
  guard inspect_project_authorization_status(store, fn(_) { Err(Rejected) })
    is Ok(inspection) else {
    fail("revoked authorization must still produce a status inspection")
  }
  assert_true(inspection.status.configured)
  assert_eq(inspection.status.project_id, Some("status-project"))
  guard inspection.usability_error is Some(ReauthorizationRequired) else {
    fail("status inspection must retain the reauthorization state")
  }
}

///|
async test "stored Project Authorization refreshes silently without replacement" {
  let stored : StoredAuthorization = {
    version: 1,
    client_id: "desktop-client",
    client_secret: "client-secret",
    refresh_token: "stored-refresh",
    token_uri: "https://oauth2.googleapis.com/token",
    scope: drive_file_scope,
    project_id: None,
  }
  let mut load_calls = 0
  let mut replace_calls = 0
  let mut refresh_request : TokenRefreshRequest? = None
  let store : CredentialStore = {
    probe: fn() { Ok(()) },
    load: fn() {
      load_calls = load_calls + 1
      Ok(stored)
    },
    replace: fn(_) {
      replace_calls = replace_calls + 1
      Ok(())
    },
    delete: fn() { Ok(()) },
  }
  let token = project_access_token(store, fn(request) {
    refresh_request = Some(request)
    Ok({ access_token: "fresh-access", refresh_token: None })
  })
  guard token is Ok(access_token) else { fail("stored grant must refresh") }
  assert_eq(access_token, "fresh-access")
  let request = refresh_request.unwrap()
  assert_eq(request.refresh_token, "stored-refresh")
  assert_eq(request.scope, drive_file_scope)
  let usable = project_authorization_usable_status(store, fn(_) {
    Ok({ access_token: "another-fresh-access", refresh_token: None })
  })
  guard usable is Ok(status) else { fail("refreshable grant must be usable") }
  assert_true(status.configured)
  assert_eq(load_calls, 3)
  assert_eq(replace_calls, 0)
}

///|
async test "stored Project Authorization never sends refresh material to a non-Google endpoint" {
  let stored : StoredAuthorization = {
    version: 1,
    client_id: "desktop-client",
    client_secret: "client-secret",
    refresh_token: "stored-refresh",
    token_uri: "https://attacker.example/token",
    scope: drive_file_scope,
    project_id: None,
  }
  let mut refresh_calls = 0
  let result = project_access_token(
    {
      probe: fn() { Ok(()) },
      load: fn() { Ok(stored) },
      replace: fn(_) { Ok(()) },
      delete: fn() { Ok(()) },
    },
    fn(_) {
      refresh_calls = refresh_calls + 1
      Ok({ access_token: "must-not-be-returned", refresh_token: None })
    },
  )
  guard result is Err(ReauthorizationRequired) else {
    fail("a non-Google stored token endpoint must require reauthorization")
  }
  assert_eq(refresh_calls, 0)
}

///|
async test "explicit file store round-trips one active authorization without access tokens" {
  let directory = "_build/project-authorization-file-store-test"
  @fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
  let store = file_credential_store(directory)
  let first : StoredAuthorization = {
    version: 1,
    client_id: "first-client",
    client_secret: "first-secret",
    refresh_token: "first-refresh",
    token_uri: "https://oauth2.googleapis.com/token",
    scope: drive_file_scope,
    project_id: Some("file-store-project"),
  }
  guard (store.replace)(first) is Ok(_) else {
    fail("first store write must succeed")
  }
  guard (store.load)() is Ok(first_loaded) else {
    fail("stored grant must load")
  }
  assert_eq(first_loaded.client_id, "first-client")
  assert_eq(first_loaded.refresh_token, "first-refresh")
  assert_eq(first_loaded.project_id, Some("file-store-project"))
  let second : StoredAuthorization = {
    ..first,
    client_id: "second-client",
    refresh_token: "second-refresh",
  }
  let replacement = (store.replace)(second)
  guard replacement is Ok(_) else {
    guard replacement is Err(_) else { fail("replacement failed") }
    fail("replacement must succeed")
  }
  guard (store.load)() is Ok(second_loaded) else {
    fail("replacement must load")
  }
  assert_eq(second_loaded.client_id, "second-client")
  assert_eq(second_loaded.refresh_token, "second-refresh")
  let raw = @fs.read_file(directory + "/project-authorization.json").text()
  assert_false(raw.contains("access_token"))
  guard (store.delete)() is Ok(_) else {
    fail("file store delete must succeed")
  }
  guard (store.load)() is Err(CredentialStoreError::NotConfigured) else {
    fail("deleted authorization must be reported as not configured")
  }
  guard (store.delete)() is Ok(_) else {
    fail("file store delete must be idempotent")
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "macOS Keychain adapter preserves prior values and redacts backend failures" {
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
  let first_document =
    #|{"version":1,"client_id":"first-client","client_secret":"first-secret","refresh_token":"first-refresh","token_uri":"https://oauth2.googleapis.com/token","scope":"https://www.googleapis.com/auth/drive.file"}
  let mut saved : String? = Some(first_document)
  let mut fail_replace = false
  let store = macos_keychain_credential_store_with_backend({
    probe: fn() { Ok(()) },
    load: fn() {
      match saved {
        Some(value) => Ok(value)
        None => Err(CredentialStoreError::NotConfigured)
      }
    },
    replace: fn(value) {
      if fail_replace {
        Err(CredentialStoreError::Unavailable)
      } else {
        saved = Some(value)
        Ok(())
      }
    },
    delete: fn() {
      saved = None
      Ok(())
    },
  })
  guard (store.load)() is Ok(before) else { fail("fake keychain must load") }
  assert_eq(before.refresh_token, "first-refresh")
  fail_replace = true
  guard (store.replace)(second) is Err(CredentialStoreError::Unavailable) else {
    fail("keychain replacement failure must be classified")
  }
  guard (store.load)() is Ok(after) else {
    fail("failed replacement must preserve prior value")
  }
  assert_eq(after.refresh_token, "first-refresh")
  fail_replace = false
  guard (store.replace)(second) is Ok(_) else {
    fail("keychain update must replace the existing value")
  }
  guard (store.load)() is Ok(updated) else {
    fail("updated keychain authorization must load")
  }
  assert_eq(updated.refresh_token, "second-refresh")
  guard (store.delete)() is Ok(_) else { fail("keychain delete must succeed") }
  guard (store.load)() is Err(CredentialStoreError::NotConfigured) else {
    fail("deleted keychain authorization must be absent")
  }
}

///|
async test "macOS Keychain adapter maps denied and unavailable without secret errors" {
  let secret = "never-display-keychain-secret"
  let denied = macos_keychain_credential_store_with_backend({
    probe: fn() { Err(CredentialStoreError::Denied) },
    load: fn() { Err(CredentialStoreError::Denied) },
    replace: fn(_) { Err(CredentialStoreError::Denied) },
    delete: fn() { Err(CredentialStoreError::Denied) },
  })
  guard (denied.load)() is Err(CredentialStoreError::Denied) else {
    fail("denied keychain access must be classified")
  }
  guard (denied.replace)({
      version: 1,
      client_id: "client",
      client_secret: secret,
      refresh_token: secret,
      token_uri: "https://oauth2.googleapis.com/token",
      scope: drive_file_scope,
      project_id: None,
    })
    is Err(error) else {
    fail("denied replacement must fail")
  }
  guard error is CredentialStoreError::Denied else {
    fail("denied error must contain no secret diagnostic")
  }
  let unavailable = macos_keychain_credential_store_with_backend({
    probe: fn() { Err(CredentialStoreError::Unavailable) },
    load: fn() { Err(CredentialStoreError::Unavailable) },
    replace: fn(_) { Err(CredentialStoreError::Unavailable) },
    delete: fn() { Err(CredentialStoreError::Unavailable) },
  })
  guard (unavailable.delete)() is Err(CredentialStoreError::Unavailable) else {
    fail("unavailable keychain access must be classified")
  }
}

///|
async test "production keychain selection has no file fallback on unsupported platforms" {
  let keychain = macos_keychain_credential_store_with_backend({
    probe: fn() { Ok(()) },
    load: fn() { Err(CredentialStoreError::NotConfigured) },
    replace: fn(_) { Ok(()) },
    delete: fn() { Ok(()) },
  })
  guard production_credential_store_with_keychain(
      CredentialStoreKind::Native,
      false,
      keychain,
    )
    is Err(StorageUnavailable) else {
    fail("unsupported Keychain must not silently select a file store")
  }
}

///|
async test "browser fallback continues setup and store failure preserves the prior grant" {
  let document =
    #|{"installed":{"client_id":"desktop-client.apps.googleusercontent.com","client_secret":"client-secret","auth_uri":"https://accounts.google.com/o/oauth2/v2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}
  let previous : StoredAuthorization = {
    version: 1,
    client_id: "previous-client",
    client_secret: "previous-secret",
    refresh_token: "previous-refresh",
    token_uri: "https://oauth2.googleapis.com/token",
    scope: drive_file_scope,
    project_id: None,
  }
  let mut reported_urls = 0
  let store : CredentialStore = {
    probe: fn() { Ok(()) },
    load: fn() { Ok(previous) },
    replace: fn(_) { Err(CredentialStoreError::Unavailable) },
    delete: fn() { Ok(()) },
  }
  let result = setup_project_authorization(document, {
    random_bytes: fn(_) { Ok(b"abcdabcdabcdabcdabcdabcdabcdabcd") },
    start_listener: fn() {
      Ok({
        redirect_uri: "http://127.0.0.1:1/oauth2/callback",
        await_callback: fn() {
          Ok("code=ok&state=YWJjZGFiY2RhYmNkYWJjZGFiY2RhYmNkYWJjZGFiY2Q")
        },
      })
    },
    launch_browser: fn(_) { Err("browser unavailable") },
    report_authorization_url: fn(_) { reported_urls = reported_urls + 1 },
    exchange_code: fn(_) {
      Ok({ access_token: "access", refresh_token: Some("new-refresh") })
    },
    store,
  })
  guard result is Err(StorageUnavailable) else {
    fail("store failure must surface")
  }
  assert_eq(reported_urls, 1)
  guard (store.load)() is Ok(still_previous) else {
    fail("prior grant must remain")
  }
  assert_eq(still_previous.refresh_token, "previous-refresh")
}
