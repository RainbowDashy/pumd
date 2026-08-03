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
fn guided_dependencies(gcloud : GcloudStatus) -> GuidedSetupDependencies {
  {
    inspect_gcloud: fn() { Ok(gcloud) },
    list_accounts: fn() { Ok([{ email: "author@example.com" }]) },
    select_account: fn(_, _) { Ok("author@example.com") },
    list_projects: fn(_) {
      Ok([
        {
          project_id: "docs-project",
          display_name: "Docs project",
          availability: ProjectAvailability::Available,
        },
      ])
    },
    select_project: fn(_, _) { Ok(ProjectChoice::Existing("docs-project")) },
    inspect_docs_api: fn(_, _) { Ok(true) },
    inspect_consent: fn(_) { Ok(ConsentConfiguration::CompatibleExternal) },
    preview_mutation: fn(_) { () },
    confirm_mutation: fn(_) { true },
    preview_handoff: fn(_) { () },
    confirm_handoff: fn(_) { true },
    create_project: fn(_, _) { Err(()) },
    enable_docs_api: fn(_, _) { Err(()) },
    ensure_minimal_external_consent: fn(_) {
      Ok(ConsentConfiguration::CompatibleExternal)
    },
    begin_desktop_client_handoff: fn(_, _) { Ok(()) },
    receive_desktop_client_json: fn() {
      let document =
        #|{"installed":{"client_id":"desktop-client.apps.googleusercontent.com","client_secret":"client-secret","auth_uri":"https://accounts.google.com/o/oauth2/v2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}
      Ok(document)
    },
    complete_oauth: fn(_) { Ok(completed_guided_setup_status()) },
  }
}

///|
fn selected_project_dependencies(
  availability : ProjectAvailability,
) -> GuidedSetupDependencies {
  {
    ..guided_dependencies(GcloudStatus::Ready(Some("author@example.com"), None)),
    list_projects: fn(_) {
      Ok([
        {
          project_id: "selected-project",
          display_name: "Selected project",
          availability,
        },
      ])
    },
    select_project: fn(_, _) { Ok(ProjectChoice::Existing("selected-project")) },
  }
}

///|
async test "guided Project Authorization uses the active accessible project and previews only required changes" {
  let previews : Array[GuidedSetupMutation] = []
  let consent_handoffs : Array[GuidedSetupHandoff] = []
  let enabled_apis : Array[String] = []
  let docs_accounts : Array[String] = []
  let mut consent_creations = 0
  let client_handoffs : Array[String] = []
  let mut account_preselected : String? = None
  let mut project_preselected : String? = None
  let mut handoff_url = ""
  let mut oauth_document = ""
  let dependencies : GuidedSetupDependencies = {
    inspect_gcloud: fn() {
      Ok(GcloudStatus::Ready(Some("author@example.com"), Some("docs-project")))
    },
    list_accounts: fn() {
      Ok([{ email: "author@example.com" }, { email: "other@example.com" }])
    },
    select_account: fn(_accounts, preselected) {
      account_preselected = preselected
      Ok("author@example.com")
    },
    list_projects: fn(_) {
      Ok([
        {
          project_id: "docs-project",
          display_name: "Docs project",
          availability: ProjectAvailability::Available,
        },
      ])
    },
    select_project: fn(_projects, preselected) {
      project_preselected = preselected
      Ok(ProjectChoice::Existing("docs-project"))
    },
    inspect_docs_api: fn(account, _) {
      docs_accounts.push(account)
      Ok(false)
    },
    inspect_consent: fn(_) { Ok(ConsentConfiguration::Absent) },
    preview_mutation: fn(mutation) { previews.push(mutation) },
    confirm_mutation: fn(_) { true },
    create_project: fn(_, _) { Err(()) },
    enable_docs_api: fn(account, project_id) {
      docs_accounts.push(account)
      enabled_apis.push(project_id)
      Ok(())
    },
    preview_handoff: fn(handoff) { consent_handoffs.push(handoff) },
    confirm_handoff: fn(_) { true },
    ensure_minimal_external_consent: fn(_) {
      consent_creations = consent_creations + 1
      Ok(ConsentConfiguration::CompatibleExternal)
    },
    begin_desktop_client_handoff: fn(project_id, url) {
      handoff_url = url
      client_handoffs.push(project_id)
      Ok(())
    },
    receive_desktop_client_json: fn() {
      Ok(
        (
          #|{"installed":{"client_id":"desktop-client.apps.googleusercontent.com","client_secret":"client-secret","auth_uri":"https://accounts.google.com/o/oauth2/v2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}
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
        project_id: None,
      })
    },
  }

  match guide_project_authorization(dependencies) {
    Ok(status) => {
      assert_true(status.configured)
      assert_eq(status.scope, drive_file_scope)
    }
    Err(error) => fail(error.user_message())
  }
  assert_eq(enabled_apis, ["docs-project"])
  assert_eq(docs_accounts, ["author@example.com", "author@example.com"])
  assert_eq(account_preselected, Some("author@example.com"))
  assert_eq(project_preselected, Some("docs-project"))
  assert_eq(consent_creations, 1)
  assert_eq(client_handoffs, ["docs-project"])
  assert_eq(
    handoff_url, "https://console.cloud.google.com/auth/clients?project=docs-project",
  )
  assert_true(
    oauth_document.contains("desktop-client.apps.googleusercontent.com"),
  )
  assert_eq(previews.length(), 1)
  match previews[0] {
    GuidedSetupMutation::EnableDocsApi(project_id) =>
      assert_eq(project_id, "docs-project")
    _ => fail("Docs API enablement must be previewed first")
  }
  assert_eq(consent_handoffs.length(), 1)
  match consent_handoffs[0] {
    ConfigureMinimalExternalConsent(links) => {
      assert_eq(
        links.branding_url,
        "https://console.cloud.google.com/auth/branding?project=docs-project",
      )
      assert_eq(
        links.audience_url,
        "https://console.cloud.google.com/auth/audience?project=docs-project",
      )
      assert_eq(
        links.scopes_url,
        "https://console.cloud.google.com/auth/scopes?project=docs-project",
      )
    }
  }
}

///|
async test "guided Project Authorization cancellation previews an API change but performs no mutation" {
  let mutations : Array[GuidedSetupMutation] = []
  let mut enabled = 0
  let mut consent_inspections = 0
  let mut client_handoffs = 0
  let dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(
      GcloudStatus::Ready(Some("author@example.com"), Some("docs-project")),
    ),
    inspect_docs_api: fn(_, _) { Ok(false) },
    inspect_consent: fn(_) {
      consent_inspections = consent_inspections + 1
      Ok(ConsentConfiguration::CompatibleExternal)
    },
    preview_mutation: fn(mutation) { mutations.push(mutation) },
    confirm_mutation: fn(_) { false },
    enable_docs_api: fn(_, _) {
      enabled = enabled + 1
      Ok(())
    },
    begin_desktop_client_handoff: fn(_, _) {
      client_handoffs = client_handoffs + 1
      Ok(())
    },
  }
  guard guide_project_authorization(dependencies) is Err(Cancelled) else {
    fail("declining a preview must cancel setup")
  }
  assert_eq(mutations.length(), 1)
  assert_eq(enabled, 0)
  assert_eq(consent_inspections, 0)
  assert_eq(client_handoffs, 0)
}

///|
async test "guided Project Authorization reruns leave existing Docs API and compatible consent unchanged" {
  let mutations : Array[GuidedSetupMutation] = []
  let handoffs : Array[GuidedSetupHandoff] = []
  let dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(
      GcloudStatus::Ready(Some("author@example.com"), Some("docs-project")),
    ),
    preview_mutation: fn(mutation) { mutations.push(mutation) },
    preview_handoff: fn(handoff) { handoffs.push(handoff) },
  }
  guard guide_project_authorization(dependencies) is Ok(_) else {
    fail("an already configured project must remain usable on rerun")
  }
  assert_eq(mutations.length(), 0)
  assert_eq(handoffs.length(), 0)
}

///|
async test "guided Project Authorization cancels the manual consent handoff before OAuth" {
  let handoffs : Array[GuidedSetupHandoff] = []
  let mut oauth_calls = 0
  let dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(GcloudStatus::Ready(Some("author@example.com"), None)),
    inspect_consent: fn(_) { Ok(ConsentConfiguration::Absent) },
    preview_handoff: fn(handoff) { handoffs.push(handoff) },
    confirm_handoff: fn(_) { false },
    complete_oauth: fn(_) {
      oauth_calls = oauth_calls + 1
      Ok(completed_guided_setup_status())
    },
  }
  guard guide_project_authorization(dependencies) is Err(Cancelled) else {
    fail("declining the manual consent handoff must cancel setup")
  }
  assert_eq(handoffs.length(), 1)
  assert_eq(oauth_calls, 0)
}

///|
async test "guided Project Authorization previews optional project creation and enables only Docs API" {
  let mutations : Array[GuidedSetupMutation] = []
  let mut created_project : NewCloudProject? = None
  let mut created_by : String? = None
  let docs_accounts : Array[String] = []
  let mut enabled_project : String? = None
  let dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(GcloudStatus::Ready(Some("author@example.com"), None)),
    select_project: fn(_, _) {
      Ok(
        ProjectChoice::Create({
          project_id: "new-docs-project",
          display_name: "New Docs project",
        }),
      )
    },
    preview_mutation: fn(mutation) { mutations.push(mutation) },
    create_project: fn(account, request) {
      created_by = Some(account)
      created_project = Some(request)
      Ok({
        project_id: request.project_id,
        display_name: request.display_name,
        availability: ProjectAvailability::Available,
      })
    },
    inspect_docs_api: fn(account, _) {
      docs_accounts.push(account)
      Ok(false)
    },
    enable_docs_api: fn(account, project_id) {
      docs_accounts.push(account)
      enabled_project = Some(project_id)
      Ok(())
    },
  }
  guard guide_project_authorization(dependencies) is Ok(_) else {
    fail("optional project creation should reach direct OAuth")
  }
  assert_eq(created_project.unwrap().project_id, "new-docs-project")
  assert_eq(created_by, Some("author@example.com"))
  assert_eq(docs_accounts, ["author@example.com", "author@example.com"])
  assert_eq(enabled_project, Some("new-docs-project"))
  assert_eq(mutations.length(), 2)
  match mutations[0] {
    CreateProject(request) => assert_eq(request.project_id, "new-docs-project")
    _ => fail("project creation must be previewed before it is created")
  }
  match mutations[1] {
    EnableDocsApi(project_id) => {
      assert_eq(project_id, "new-docs-project")
      assert_eq(google_docs_api, "docs.googleapis.com")
    }
    _ => fail("only the Google Docs API may be enabled")
  }
}

///|
async test "guided Project Authorization preserves conflicting consent and validates the manual Desktop client handoff" {
  let mut desktop_handoffs = 0
  let conflict_dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(GcloudStatus::Ready(Some("author@example.com"), None)),
    inspect_consent: fn(_) { Ok(ConsentConfiguration::Conflicting) },
    begin_desktop_client_handoff: fn(_, _) {
      desktop_handoffs = desktop_handoffs + 1
      Ok(())
    },
  }
  guard guide_project_authorization(conflict_dependencies)
    is Err(ConsentConflict) else {
    fail("conflicting consent must not be overwritten")
  }
  assert_eq(desktop_handoffs, 0)

  let mut oauth_calls = 0
  let invalid_client_dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(GcloudStatus::Ready(Some("author@example.com"), None)),
    receive_desktop_client_json: fn() { Ok("not a Desktop client document") },
    complete_oauth: fn(_) {
      oauth_calls = oauth_calls + 1
      Ok(completed_guided_setup_status())
    },
  }
  guard guide_project_authorization(invalid_client_dependencies)
    is Err(DesktopClientFileInvalid) else {
    fail("manual Desktop client JSON must be validated before OAuth")
  }
  assert_eq(oauth_calls, 0)
}

///|
async test "guided Project Authorization maps unavailable gcloud and blocked project states to secret-free guidance" {
  guard guide_project_authorization(guided_dependencies(GcloudStatus::Missing))
    is Err(GcloudUnavailable) else {
    fail("missing gcloud must stop setup")
  }
  guard guide_project_authorization(
      guided_dependencies(GcloudStatus::Unauthenticated),
    )
    is Err(GcloudUnauthenticated) else {
    fail("unauthenticated gcloud must stop setup")
  }
  guard guide_project_authorization(
      selected_project_dependencies(ProjectAvailability::Inaccessible),
    )
    is Err(ProjectUnavailable) else {
    fail("inaccessible projects must stop before cloud mutation")
  }
  guard guide_project_authorization(
      selected_project_dependencies(ProjectAvailability::Suspended),
    )
    is Err(ProjectSuspended) else {
    fail("suspended projects must stop before cloud mutation")
  }
  guard guide_project_authorization(
      selected_project_dependencies(ProjectAvailability::QuotaBlocked),
    )
    is Err(ProjectQuotaBlocked) else {
    fail("quota-blocked projects must stop before cloud mutation")
  }
  guard guide_project_authorization(
      selected_project_dependencies(ProjectAvailability::PolicyBlocked),
    )
    is Err(ProjectPolicyBlocked) else {
    fail("policy-blocked projects must stop before cloud mutation")
  }
  let message = GuidedSetupError::OAuthSetupFailed.user_message()
  assert_false(message.contains("client-secret"))
  assert_false(message.contains("refresh-token"))
}

///|
test "guided setup preserves credential-vault failure classes" {
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
}

///|
test "guided setup preserves gcloud prerequisite failure classes" {
  guard GuidedSetupError::GcloudUnavailable.project_authorization_error()
    is ProjectAuthorizationError::GcloudUnavailable else {
    fail("missing gcloud must remain structured")
  }
  guard GuidedSetupError::GcloudUnauthenticated.project_authorization_error()
    is ProjectAuthorizationError::GcloudUnauthenticated else {
    fail("unauthenticated gcloud must remain structured")
  }
}

///|
async test "guided setup keeps a denied replacement actionable" {
  let dependencies : GuidedSetupDependencies = {
    ..guided_dependencies(GcloudStatus::Ready(Some("author@example.com"), None)),
    complete_oauth: fn(_) { Err(ProjectAuthorizationError::StorageDenied) },
  }
  guard guide_project_authorization(dependencies) is Err(CredentialVaultDenied) else {
    fail(
      "guided setup must not collapse vault denial into generic OAuth failure",
    )
  }
}
