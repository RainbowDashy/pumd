///|
fn completed_guided_setup_status() -> ProjectAuthorizationStatus {
  {
    configured: true,
    client_id: Some("desktop-client.apps.googleusercontent.com"),
    token_uri: Some("https://oauth2.googleapis.com/token"),
    scope: drive_file_scope,
    project_id: None,
  }
}

///|
fn guided_dependencies() -> GuidedSetupDependencies {
  {
    complete_project_console_handoff: fn(_) { Ok(()) },
    receive_desktop_client_json: fn() {
      let document =
        #|{"installed":{"client_id":"desktop-client.apps.googleusercontent.com","client_secret":"client-secret","auth_uri":"https://accounts.google.com/o/oauth2/v2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}
      Ok(document)
    },
    complete_oauth: fn(_) { Ok(completed_guided_setup_status()) },
  }
}

///|
test "project console handoff exposes the exact setup destinations" {
  let handoff = project_console_handoff
  assert_eq(
    handoff.enable_docs_api_url,
    "https://console.cloud.google.com/flows/enableapi?apiid=docs.googleapis.com",
  )
  assert_eq(
    handoff.enable_drive_api_url,
    "https://console.cloud.google.com/flows/enableapi?apiid=drive.googleapis.com",
  )
  assert_eq(
    handoff.oauth_clients_url,
    "https://console.cloud.google.com/auth/clients",
  )
}

///|
async test "guided Project Authorization hands off to Cloud Console, validates the Desktop client, then completes OAuth" {
  let mut received_handoff : ProjectConsoleHandoff? = None
  let mut oauth_document = ""
  let dependencies : GuidedSetupDependencies = {
    complete_project_console_handoff: fn(handoff) {
      received_handoff = Some(handoff)
      Ok(())
    },
    receive_desktop_client_json: fn() {
      Ok(
        (
          #|{"installed":{"client_id":"desktop-client.apps.googleusercontent.com","client_secret":"client-secret","auth_uri":"https://accounts.google.com/o/oauth2/v2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"],"project_id":"docs-project"}}
        ),
      )
    },
    complete_oauth: fn(document) {
      oauth_document = document
      Ok({
        configured: true,
        client_id: Some("desktop-client.apps.googleusercontent.com"),
        token_uri: Some("https://oauth2.googleapis.com/token"),
        scope: drive_file_scope,
        project_id: Some("docs-project"),
      })
    },
  }

  match guide_project_authorization(dependencies) {
    Ok(status) => {
      assert_true(status.configured)
      assert_eq(status.scope, drive_file_scope)
      assert_eq(status.project_id, Some("docs-project"))
    }
    Err(error) => fail(error.user_message())
  }
  let handoff = received_handoff.unwrap()
  assert_eq(
    handoff.enable_docs_api_url,
    "https://console.cloud.google.com/flows/enableapi?apiid=docs.googleapis.com",
  )
  assert_eq(
    handoff.enable_drive_api_url,
    "https://console.cloud.google.com/flows/enableapi?apiid=drive.googleapis.com",
  )
  assert_eq(
    handoff.oauth_clients_url,
    "https://console.cloud.google.com/auth/clients",
  )
  assert_true(
    oauth_document.contains("desktop-client.apps.googleusercontent.com"),
  )
}

///|
async test "guided Project Authorization cancels when the user declines the Cloud Console handoff" {
  let mut receives = 0
  let dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(),
    complete_project_console_handoff: fn(_) {
      Err(ProjectConsoleHandoffError::Cancelled)
    },
    receive_desktop_client_json: fn() {
      receives = receives + 1
      Ok("{}")
    },
  }
  guard guide_project_authorization(dependencies) is Err(Cancelled) else {
    fail("declining the Cloud Console handoff must cancel setup")
  }
  assert_eq(receives, 0)
}

///|
async test "guided Project Authorization stops when the Cloud Console handoff cannot start" {
  let mut receives = 0
  let dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(),
    complete_project_console_handoff: fn(_) {
      Err(ProjectConsoleHandoffError::Unavailable)
    },
    receive_desktop_client_json: fn() {
      receives = receives + 1
      Ok("{}")
    },
  }
  guard guide_project_authorization(dependencies) is Err(ConsoleHandoffFailed) else {
    fail("an unopenable Cloud Console handoff must stop setup")
  }
  assert_eq(receives, 0)
}

///|
async test "guided Project Authorization stops when the Desktop client JSON is unavailable" {
  let mut oauth_calls = 0
  let dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(),
    receive_desktop_client_json: fn() { Err(()) },
    complete_oauth: fn(_) {
      oauth_calls = oauth_calls + 1
      Ok(completed_guided_setup_status())
    },
  }
  guard guide_project_authorization(dependencies)
    is Err(DesktopClientFileUnavailable) else {
    fail("a missing Desktop client JSON must stop setup")
  }
  assert_eq(oauth_calls, 0)
}

///|
async test "guided Project Authorization validates the Desktop client JSON before OAuth" {
  let mut oauth_calls = 0
  let dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(),
    receive_desktop_client_json: fn() { Ok("not a Desktop client document") },
    complete_oauth: fn(_) {
      oauth_calls = oauth_calls + 1
      Ok(completed_guided_setup_status())
    },
  }
  guard guide_project_authorization(dependencies)
    is Err(DesktopClientFileInvalid) else {
    fail("Desktop client JSON must be validated before OAuth")
  }
  assert_eq(oauth_calls, 0)
}

///|
async test "guided Project Authorization rejects an incomplete OAuth result" {
  let dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(),
    complete_oauth: fn(_) {
      Ok({
        configured: false,
        client_id: None,
        token_uri: None,
        scope: drive_file_scope,
        project_id: None,
      })
    },
  }
  guard guide_project_authorization(dependencies) is Err(OAuthSetupFailed) else {
    fail("an unconfigured OAuth result must not be reported as success")
  }
}

///|
async test "guided Project Authorization requires exactly the drive.file scope" {
  let dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(),
    complete_oauth: fn(_) {
      Ok({
        configured: true,
        client_id: Some("desktop-client.apps.googleusercontent.com"),
        token_uri: Some("https://oauth2.googleapis.com/token"),
        scope: "https://www.googleapis.com/auth/drive",
        project_id: None,
      })
    },
  }
  guard guide_project_authorization(dependencies) is Err(OAuthSetupFailed) else {
    fail("a non-drive.file grant must not be reported as success")
  }
}

///|
test "guided setup preserves credential-vault failure classes" {
  guard GuidedSetupError::CredentialVaultLocked.project_authorization_error()
    is ProjectAuthorizationError::StorageLocked else {
    fail("a locked vault must remain distinct from permission denial")
  }
  guard GuidedSetupError::CredentialVaultDenied.project_authorization_error()
    is ProjectAuthorizationError::StorageDenied else {
    fail("vault denial must remain structured")
  }
  guard GuidedSetupError::CredentialVaultUnavailable.project_authorization_error()
    is ProjectAuthorizationError::StorageUnavailable else {
    fail("vault unavailability must remain structured")
  }
  guard GuidedSetupError::CredentialVaultUnsupported.project_authorization_error()
    is ProjectAuthorizationError::UnsupportedPlatform else {
    fail("unsupported vault must remain structured")
  }
  guard GuidedSetupError::CredentialPreferenceCommitFailed.project_authorization_error()
    is ProjectAuthorizationError::PreferenceUnavailable else {
    fail("preference commit failure must remain structured")
  }
  guard GuidedSetupError::CredentialRollbackIncomplete.project_authorization_error()
    is ProjectAuthorizationError::CredentialRollbackFailed else {
    fail("credential rollback failure must remain structured")
  }
  guard GuidedSetupError::PreviousCredentialCleanupFailed.project_authorization_error()
    is ProjectAuthorizationError::StaleCredentialCleanupFailed else {
    fail("stale credential cleanup failure must remain structured")
  }
}

///|
async test "guided setup keeps a denied replacement actionable" {
  let dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(),
    complete_oauth: fn(_) { Err(ProjectAuthorizationError::StorageDenied) },
  }
  guard guide_project_authorization(dependencies) is Err(CredentialVaultDenied) else {
    fail(
      "guided setup must not collapse vault denial into generic OAuth failure",
    )
  }
}

///|
test "guided setup guidance stays secret-free" {
  let message = GuidedSetupError::OAuthSetupFailed.user_message()
  assert_false(message.contains("client-secret"))
  assert_false(message.contains("refresh-token"))
  assert_true(
    GuidedSetupError::ConsoleHandoffFailed
    .user_message()
    .contains("Google Cloud Console"),
  )
}
