///|
async test "ADC dependency boundary returns the acquired token" {
  let client = @googleauth.new_auth_client(None)
  let detect : async () -> Result[
    @googleauth.GoogleAuthClient,
    AuthenticationProblem,
  ] = fn() { Ok(client) }
  let acquire : async (@googleauth.GoogleAuthClient) -> Result[
    String,
    AuthenticationProblem,
  ] = fn(_) { Ok("adc-token") }
  let result = application_default_access_token_with(detect, acquire)
  match result {
    Ok(token) => inspect(token, content="adc-token")
    Err(error) => fail(error.user_message())
  }
}

///|
async test "ADC dependency detection errors retain actionable categories" {
  let acquire_calls : Array[Unit] = []
  let unavailable = application_default_access_token_with(
    fn() { Err(CredentialsUnavailable) },
    fn(_) {
      acquire_calls.push(())
      Ok("unused")
    },
  )
  guard unavailable is Err(Authentication(problem=CredentialsUnavailable, ..)) else {
    fail("missing ADC must remain distinguishable")
  }
  assert_eq(acquire_calls.length(), 0)
  let invalid = application_default_access_token_with(
    fn() { Err(CredentialsInvalid) },
    fn(_) { Ok("unused") },
  )
  guard invalid is Err(Authentication(problem=CredentialsInvalid, ..)) else {
    fail("invalid ADC must remain distinguishable")
  }
}

///|
async test "ADC token acquisition errors retain refresh categories" {
  let client = @googleauth.new_auth_client(None)
  let detect : async () -> Result[
    @googleauth.GoogleAuthClient,
    AuthenticationProblem,
  ] = fn() { Ok(client) }
  let unavailable = application_default_access_token_with(detect, fn(_) {
    Err(CredentialsUnavailable)
  })
  guard unavailable is Err(Authentication(problem=CredentialsUnavailable, ..)) else {
    fail("missing ADC during acquisition must remain distinguishable")
  }
  let refresh_failed = application_default_access_token_with(
    fn() { Ok(client) },
    fn(_) { Err(CredentialsRefreshFailed) },
  )
  guard refresh_failed
    is Err(Authentication(problem=CredentialsRefreshFailed, ..)) else {
    fail("refresh failure must remain distinguishable")
  }
  assert_true(refresh_failed.unwrap_err().user_message().contains("refresh"))
}

///|
async test "googleauth read-only errors map through the production boundary" {
  let metadata_client = @googleauth.new_auth_client(None)
  match @googleauth.get_access_token(metadata_client) {
    Err(error) => assert_eq(google_auth_problem(error), CredentialsUnavailable)
    Ok(_) => fail("metadata fixture must expose the pinned dependency error")
  }
  match acquire_googleauth_token(metadata_client) {
    Err(CredentialsRefreshFailed) => ()
    _ => fail("metadata token failure must map to refresh failure")
  }
  let service_account_json =
    #|{"type":"service_account","project_id":"fixture","private_key_id":"fixture","private_key":"fixture","client_email":"fixture@example.test","client_id":"fixture","auth_uri":"https://accounts.example.test/auth","token_uri":"https://accounts.example.test/token"}
  let credentials = match
    @googleauth.parse_service_account_key(service_account_json) {
    Ok(credentials) => credentials
    Err(_) => fail("service-account dependency fixture must parse")
  }
  let service_account_client = @googleauth.new_auth_client(Some(credentials))
  match @googleauth.get_access_token(service_account_client) {
    Err(error) => assert_eq(google_auth_problem(error), CredentialsInvalid)
    Ok(_) => fail("service-account fixture must expose the pinned error")
  }
  match acquire_googleauth_token(service_account_client) {
    Err(CredentialsRefreshFailed) => ()
    _ => fail("invalid token acquisition must map to refresh failure")
  }
}
