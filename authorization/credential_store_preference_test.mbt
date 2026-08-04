///|
async test "credential-store preference persists only the non-secret selected identifier" {
  let directory = "_build/credential-store-preference"
  @fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
  let preference = file_credential_store_preference(directory)
  guard (preference.load)() is Ok(None) else {
    fail("an absent preference must preserve the native default")
  }
  guard (preference.replace)(CredentialStoreIdentifier::File) is Ok(_) else {
    fail("the explicit file choice must be persisted")
  }
  guard (preference.load)() is Ok(Some(CredentialStoreIdentifier::File)) else {
    fail("the explicit file choice must round-trip")
  }
  let document = @fs.read_file(directory + "/credential-store.json") catch {
    _ => fail("the preference document must exist")
  }
  let text = document.text()
  assert_true(text.contains("\"credential_store\":\"file\""))
  assert_false(text.contains("token"))
  assert_false(text.contains("secret"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "remembered store resolves bare lifecycle commands while explicit selection overrides" {
  let preference : CredentialStorePreference = {
    load: fn() { Ok(Some(CredentialStoreIdentifier::File)) },
    replace: fn(_) { Ok(()) },
  }
  guard resolve_credential_store_identifier(None, preference)
    is Ok(CredentialStoreIdentifier::File) else {
    fail("bare lifecycle commands must use the remembered file store")
  }
  guard resolve_credential_store_identifier(
      Some(CredentialStoreIdentifier::Native),
      preference,
    )
    is Ok(CredentialStoreIdentifier::Native) else {
    fail("an explicit store flag must override the remembered preference")
  }
  let absent : CredentialStorePreference = {
    load: fn() { Ok(None) },
    replace: fn(_) { Ok(()) },
  }
  guard resolve_credential_store_identifier(None, absent)
    is Ok(CredentialStoreIdentifier::Native) else {
    fail("native storage must remain the no-preference default")
  }
}

///|
async test "successful cross-store setup remembers the new store and removes the stale credential" {
  let authorization = preference_test_authorization("new-refresh")
  let mut selected_value : StoredAuthorization? = None
  let mut previous_deleted = false
  let mut preference_value = Some(CredentialStoreIdentifier::Native)
  let selected = credential_store_for_preference_test(
    fn() {
      match selected_value {
        Some(value) => Ok(value)
        None => Err(CredentialStoreError::NotConfigured)
      }
    },
    fn(value) {
      selected_value = Some(value)
      Ok(())
    },
    fn() {
      selected_value = None
      Ok(())
    },
  )
  let previous = credential_store_for_preference_test(
    fn() { Err(CredentialStoreError::NotConfigured) },
    fn(_) { Ok(()) },
    fn() {
      previous_deleted = true
      Ok(())
    },
  )
  let preference : CredentialStorePreference = {
    load: fn() { Ok(preference_value) },
    replace: fn(value) {
      preference_value = Some(value)
      Ok(())
    },
  }
  guard commit_credential_store_selection(
      CredentialStoreIdentifier::File,
      selected,
      CredentialStoreIdentifier::Native,
      previous,
      preference,
      async fn(store) {
        guard (store.replace)(authorization) is Ok(_) else {
          return Err(ProjectAuthorizationError::StorageUnavailable)
        }
        Ok({
          configured: true,
          client_id: Some(authorization.client_id),
          token_uri: Some(authorization.token_uri),
          scope: authorization.scope,
          project_id: authorization.project_id,
        })
      },
    )
    is Ok(_) else {
    fail("a validated new authorization must commit its store preference")
  }
  assert_eq(preference_value, Some(CredentialStoreIdentifier::File))
  assert_true(previous_deleted)
  guard selected_value is Some(saved) else {
    fail("the selected store must retain the new authorization")
  }
  assert_eq(saved.refresh_token, "new-refresh")
}

///|
async test "failed setup and preference writes preserve the prior authorization and preference" {
  let prior = preference_test_authorization("prior-refresh")
  let replacement = preference_test_authorization("replacement-refresh")
  let mut saved : StoredAuthorization? = Some(prior)
  let preference_value = Some(CredentialStoreIdentifier::Native)
  let store = credential_store_for_preference_test(
    fn() {
      match saved {
        Some(value) => Ok(value)
        None => Err(CredentialStoreError::NotConfigured)
      }
    },
    fn(value) {
      saved = Some(value)
      Ok(())
    },
    fn() {
      saved = None
      Ok(())
    },
  )
  let preference : CredentialStorePreference = {
    load: fn() { Ok(preference_value) },
    replace: fn(_) { Err(CredentialStorePreferenceError::Unavailable) },
  }
  guard commit_credential_store_selection(
      CredentialStoreIdentifier::Native,
      store,
      CredentialStoreIdentifier::Native,
      store,
      preference,
      fn(_) { Err(ProjectAuthorizationError::SetupFailed("OAuth failed")) },
    )
    is Err(ProjectAuthorizationError::SetupFailed(_)) else {
    fail("OAuth failure must remain the reported setup failure")
  }
  guard saved is Some(after_setup_failure) else {
    fail("failed OAuth must preserve the prior authorization")
  }
  assert_eq(after_setup_failure.refresh_token, "prior-refresh")
  guard commit_credential_store_selection(
      CredentialStoreIdentifier::Native,
      store,
      CredentialStoreIdentifier::Native,
      store,
      preference,
      async fn(selected) {
        guard (selected.replace)(replacement) is Ok(_) else {
          return Err(ProjectAuthorizationError::StorageUnavailable)
        }
        Ok(preference_test_status(replacement))
      },
    )
    is Err(ProjectAuthorizationError::PreferenceUnavailable) else {
    fail("preference failure must make setup fail")
  }
  guard saved is Some(after_preference_failure) else {
    fail("preference failure must restore the prior authorization")
  }
  assert_eq(after_preference_failure.refresh_token, "prior-refresh")
  assert_eq(preference_value, Some(CredentialStoreIdentifier::Native))
}

///|
async test "stale credential cleanup failure is explicit after the new preference commits" {
  let replacement = preference_test_authorization("replacement-refresh")
  let mut selected_value : StoredAuthorization? = None
  let mut preference_value = Some(CredentialStoreIdentifier::Native)
  let selected = credential_store_for_preference_test(
    fn() {
      match selected_value {
        Some(value) => Ok(value)
        None => Err(CredentialStoreError::NotConfigured)
      }
    },
    fn(value) {
      selected_value = Some(value)
      Ok(())
    },
    fn() { Ok(()) },
  )
  let previous = credential_store_for_preference_test(
    fn() { Ok(preference_test_authorization("prior-refresh")) },
    fn(_) { Ok(()) },
    fn() { Err(CredentialStoreError::Denied) },
  )
  let preference : CredentialStorePreference = {
    load: fn() { Ok(preference_value) },
    replace: fn(value) {
      preference_value = Some(value)
      Ok(())
    },
  }
  guard commit_credential_store_selection(
      CredentialStoreIdentifier::File,
      selected,
      CredentialStoreIdentifier::Native,
      previous,
      preference,
      async fn(store) {
        guard (store.replace)(replacement) is Ok(_) else {
          return Err(ProjectAuthorizationError::StorageUnavailable)
        }
        Ok(preference_test_status(replacement))
      },
    )
    is Err(ProjectAuthorizationError::StaleCredentialCleanupFailed) else {
    fail("stale credential cleanup must not be reported as full success")
  }
  assert_eq(preference_value, Some(CredentialStoreIdentifier::File))
  guard selected_value is Some(active) else {
    fail("the new active authorization must remain committed")
  }
  assert_eq(active.refresh_token, "replacement-refresh")
}

///|
async test "failed preference rollback is reported instead of hidden" {
  let prior = preference_test_authorization("prior-refresh")
  let replacement = preference_test_authorization("replacement-refresh")
  let mut saved = prior
  let mut replace_calls = 0
  let store = credential_store_for_preference_test(
    fn() { Ok(saved) },
    fn(value) {
      replace_calls = replace_calls + 1
      if replace_calls == 1 {
        saved = value
        Ok(())
      } else {
        Err(CredentialStoreError::Unavailable)
      }
    },
    fn() { Ok(()) },
  )
  let preference : CredentialStorePreference = {
    load: fn() { Ok(Some(CredentialStoreIdentifier::Native)) },
    replace: fn(_) { Err(CredentialStorePreferenceError::Unavailable) },
  }
  guard commit_credential_store_selection(
      CredentialStoreIdentifier::Native,
      store,
      CredentialStoreIdentifier::Native,
      store,
      preference,
      async fn(selected) {
        guard (selected.replace)(replacement) is Ok(_) else {
          return Err(ProjectAuthorizationError::StorageUnavailable)
        }
        Ok(preference_test_status(replacement))
      },
    )
    is Err(ProjectAuthorizationError::CredentialRollbackFailed) else {
    fail("rollback failure must be explicit")
  }
  assert_eq(saved.refresh_token, "replacement-refresh")
}

///|
fn credential_store_for_preference_test(
  load : async () -> Result[StoredAuthorization, CredentialStoreError],
  replace : async (StoredAuthorization) -> Result[Unit, CredentialStoreError],
  delete : async () -> Result[Unit, CredentialStoreError],
) -> CredentialStore {
  { probe: fn() { Ok(()) }, load, replace, delete }
}

///|
fn preference_test_authorization(refresh_token : String) -> StoredAuthorization {
  {
    version: 1,
    client_id: "new-client",
    client_secret: "new-secret",
    refresh_token,
    token_uri: "https://oauth2.googleapis.com/token",
    scope: drive_file_scope,
    project_id: Some("new-project"),
  }
}

///|
fn preference_test_status(
  authorization : StoredAuthorization,
) -> ProjectAuthorizationStatus {
  {
    configured: true,
    client_id: Some(authorization.client_id),
    token_uri: Some(authorization.token_uri),
    scope: authorization.scope,
    project_id: authorization.project_id,
  }
}
