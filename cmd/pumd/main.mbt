///|
async fn report_failure(message : String) -> Unit {
  @stdio.stderr.write("pumd: " + message + "\n")
  @sys.exit(1)
}

///|
fn read_source(path : String) -> Result[String, String] {
  let source = @fs.read_file_to_string(path) catch {
    @fs.IOError(message) => return Err(message)
  }
  Ok(source)
}

///|
fn credential_store_label(store : @args.CredentialStore) -> String {
  match store {
    @args.CredentialStore::Native =>
      @authorization.native_credential_store_label()
    @args.CredentialStore::File => "file (explicit reduced-protection choice)"
  }
}

///|
fn credential_store_kind(
  store : @args.CredentialStore,
) -> Result[
  @authorization.CredentialStoreKind,
  @authorization.ProjectAuthorizationError,
] {
  match store {
    @args.CredentialStore::Native =>
      Ok(@authorization.CredentialStoreKind::Native)
    @args.CredentialStore::File =>
      match @authorization.default_project_authorization_directory() {
        Ok(directory) => Ok(@authorization.CredentialStoreKind::File(directory))
        Err(error) => Err(error)
      }
  }
}

///|
fn selected_credential_store(
  selection : @args.CredentialStore,
) -> Result[
  @authorization.CredentialStore,
  @authorization.ProjectAuthorizationError,
] {
  match credential_store_kind(selection) {
    Ok(kind) => @authorization.production_credential_store(kind)
    Err(error) => Err(error)
  }
}

///|
priv struct ResolvedCredentialStore {
  selection : @args.CredentialStore
  store : @authorization.CredentialStore
}

///|
fn credential_store_identifier(
  selection : @args.CredentialStore,
) -> @authorization.CredentialStoreIdentifier {
  match selection {
    @args.CredentialStore::Native =>
      @authorization.CredentialStoreIdentifier::Native
    @args.CredentialStore::File =>
      @authorization.CredentialStoreIdentifier::File
  }
}

///|
fn credential_store_selection(
  identifier : @authorization.CredentialStoreIdentifier,
) -> @args.CredentialStore {
  match identifier {
    @authorization.CredentialStoreIdentifier::Native =>
      @args.CredentialStore::Native
    @authorization.CredentialStoreIdentifier::File =>
      @args.CredentialStore::File
  }
}

///|
fn project_authorization_preference() -> Result[
  @authorization.CredentialStorePreference,
  @authorization.ProjectAuthorizationError,
] {
  match @authorization.default_project_authorization_directory() {
    Ok(directory) =>
      Ok(@authorization.file_credential_store_preference(directory))
    Err(_) =>
      Err(@authorization.ProjectAuthorizationError::PreferenceUnavailable)
  }
}

///|
async fn remembered_credential_store_identifier() -> Result[
  @authorization.CredentialStoreIdentifier,
  @authorization.ProjectAuthorizationError,
] {
  match remembered_credential_store_option() {
    Ok(Some(identifier)) => Ok(identifier)
    Ok(None) => Ok(@authorization.CredentialStoreIdentifier::Native)
    Err(error) => Err(error)
  }
}

///|
async fn remembered_credential_store_option() -> Result[
  @authorization.CredentialStoreIdentifier?,
  @authorization.ProjectAuthorizationError,
] {
  let preference = match project_authorization_preference() {
    Ok(preference) => preference
    Err(error) => return Err(error)
  }
  match (preference.load)() {
    Ok(identifier) => Ok(identifier)
    Err(_) =>
      Err(@authorization.ProjectAuthorizationError::PreferenceUnavailable)
  }
}

///|
async fn publish_setup_store_request(
  request : @args.CredentialStoreRequest,
) -> Result[
  @args.SetupCredentialStore,
  @authorization.ProjectAuthorizationError,
] {
  match request {
    @args.CredentialStoreRequest::Explicit(_) =>
      Ok(@args.project_onboarding_setup_store(request, None))
    @args.CredentialStoreRequest::RememberedOrNative =>
      match remembered_credential_store_option() {
        Ok(identifier) =>
          Ok(
            @args.project_onboarding_setup_store(
              request,
              identifier.map(credential_store_selection),
            ),
          )
        Err(error) => Err(error)
      }
  }
}

///|
async fn resolve_credential_store(
  request : @args.CredentialStoreRequest,
) -> Result[ResolvedCredentialStore, @authorization.ProjectAuthorizationError] {
  let selection = match request {
    @args.CredentialStoreRequest::Explicit(selection) => selection
    @args.CredentialStoreRequest::RememberedOrNative => {
      let identifier = match remembered_credential_store_identifier() {
        Ok(identifier) => identifier
        Err(error) => return Err(error)
      }
      credential_store_selection(identifier)
    }
  }
  let store = match selected_credential_store(selection) {
    Ok(store) => store
    Err(error) => return Err(error)
  }
  Ok({ selection, store })
}

///|
async fn credential_store_ready(
  store : @authorization.CredentialStore,
) -> Result[Unit, @authorization.ProjectAuthorizationError] {
  match @authorization.credential_store_capability(store) {
    @authorization.CredentialStoreCapability::Usable => Ok(())
    @authorization.CredentialStoreCapability::Unavailable(reason) =>
      Err(credential_store_capability_error(reason))
  }
}

///|
fn credential_store_capability_error(
  reason : @authorization.CredentialStoreUnavailableReason,
) -> @authorization.ProjectAuthorizationError {
  match reason {
    @authorization.CredentialStoreUnavailableReason::MissingEntitlement =>
      @authorization.ProjectAuthorizationError::StorageMissingEntitlement
    @authorization.CredentialStoreUnavailableReason::Locked =>
      @authorization.ProjectAuthorizationError::StorageLocked
    @authorization.CredentialStoreUnavailableReason::PermissionDenied =>
      @authorization.ProjectAuthorizationError::StorageDenied
    @authorization.CredentialStoreUnavailableReason::UnsupportedPlatform =>
      @authorization.ProjectAuthorizationError::UnsupportedPlatform
    @authorization.CredentialStoreUnavailableReason::ServiceUnavailable
    | @authorization.CredentialStoreUnavailableReason::CleanupFailed
    | @authorization.CredentialStoreUnavailableReason::UnknownFailure =>
      @authorization.ProjectAuthorizationError::StorageUnavailable
  }
}

///|
async fn native_credential_store_capability() -> @authorization.CredentialStoreCapability {
  match selected_credential_store(@args.CredentialStore::Native) {
    Ok(store) => @authorization.credential_store_capability(store)
    Err(@authorization.ProjectAuthorizationError::StorageMissingEntitlement) =>
      @authorization.CredentialStoreCapability::Unavailable(
        @authorization.CredentialStoreUnavailableReason::MissingEntitlement,
      )
    Err(@authorization.ProjectAuthorizationError::StorageLocked) =>
      @authorization.CredentialStoreCapability::Unavailable(
        @authorization.CredentialStoreUnavailableReason::Locked,
      )
    Err(@authorization.ProjectAuthorizationError::StorageDenied) =>
      @authorization.CredentialStoreCapability::Unavailable(
        @authorization.CredentialStoreUnavailableReason::PermissionDenied,
      )
    Err(@authorization.ProjectAuthorizationError::UnsupportedPlatform) =>
      @authorization.CredentialStoreCapability::Unavailable(
        @authorization.CredentialStoreUnavailableReason::UnsupportedPlatform,
      )
    Err(_) =>
      @authorization.CredentialStoreCapability::Unavailable(
        @authorization.CredentialStoreUnavailableReason::ServiceUnavailable,
      )
  }
}

///|
async fn choose_setup_credential_store(
  request : @args.SetupCredentialStore,
) -> Result[@args.CredentialStore, @authorization.ProjectAuthorizationError] {
  if !terminal_is_interactive() {
    let remembered = match request {
      @args.SetupCredentialStore::Selected(_) => None
      @args.SetupCredentialStore::Prompt => {
        let identifier = match remembered_credential_store_identifier() {
          Ok(identifier) => identifier
          Err(error) => return Err(error)
        }
        Some(credential_store_selection(identifier))
      }
    }
    return Ok(@args.noninteractive_setup_credential_store(request, remembered))
  }
  match request {
    @args.SetupCredentialStore::Selected(store) => return Ok(store)
    @args.SetupCredentialStore::Prompt => ()
  }
  let capability = native_credential_store_capability()
  let catalog = @authorization.credential_store_capability_catalog(
    @authorization.native_credential_store_label(),
    capability,
  )
  let native_option = catalog[0]
  let file_option = catalog[1]
  println("Choose where Project Authorization credentials will be stored:")
  match native_option.capability {
    @authorization.CredentialStoreCapability::Usable =>
      println("  1) " + native_option.label + " (recommended)")
    @authorization.CredentialStoreCapability::Unavailable(reason) =>
      println(
        "  1) " +
        native_option.label +
        " (disabled: " +
        reason.user_message() +
        ")",
      )
  }
  println("  2) " + file_option.label + " (" + file_option.protection + ")")
  match native_option.capability {
    @authorization.CredentialStoreCapability::Usable =>
      println(
        "Select a credential store [1], `r` to recheck, or `q` to cancel:",
      )
    @authorization.CredentialStoreCapability::Unavailable(_) =>
      println(
        "Select an available credential store, `r` to recheck, or `q` to cancel:",
      )
  }
  match
    @authorization.credential_store_menu_choice(
      terminal_read_line(),
      native_option.capability,
    ) {
    Ok(@authorization.CredentialStoreMenuChoice::Native) =>
      Ok(@args.CredentialStore::Native)
    Ok(@authorization.CredentialStoreMenuChoice::File) =>
      Ok(@args.CredentialStore::File)
    Err(@authorization.CredentialStoreMenuError::Disabled(reason)) =>
      Err(credential_store_capability_error(reason))
    Err(@authorization.CredentialStoreMenuError::Cancelled) =>
      Err(
        @authorization.ProjectAuthorizationError::SetupFailed(
          "credential-store selection was cancelled",
        ),
      )
    Err(@authorization.CredentialStoreMenuError::Recheck) =>
      choose_setup_credential_store(@args.SetupCredentialStore::Prompt)
    Err(@authorization.CredentialStoreMenuError::Invalid) =>
      Err(
        @authorization.ProjectAuthorizationError::SetupFailed(
          "credential-store selection was invalid",
        ),
      )
  }
}

///|
async fn report_project_authorization_failure(
  error : @authorization.ProjectAuthorizationError,
  store : @args.CredentialStore,
) -> Unit {
  match (error, store) {
    (
      @authorization.ProjectAuthorizationError::StorageMissingEntitlement,
      @args.CredentialStore::Native,
    ) =>
      report_failure(
        "this pumd executable lacks the entitlement required by its macOS Keychain implementation. Install a compatible build. pumd did not fall back to file storage; run `pumd auth setup --client-file oauth-client.json --credential-store=file` only to opt into reduced protection explicitly.",
      )
    (
      @authorization.ProjectAuthorizationError::StorageLocked,
      @args.CredentialStore::Native,
    ) =>
      report_failure(
        "the native OS credential vault is locked. Unlock it, then recheck availability. pumd did not fall back to file storage; run `pumd auth setup --client-file oauth-client.json --credential-store=file` only to opt into reduced protection explicitly.",
      )
    (
      @authorization.ProjectAuthorizationError::StorageDenied,
      @args.CredentialStore::Native,
    ) =>
      report_failure(
        "permission to use the native OS credential vault was denied. Allow pumd or correct the platform policy, then recheck availability. pumd did not fall back to file storage; run `pumd auth setup --client-file oauth-client.json --credential-store=file` only to opt into reduced protection explicitly.",
      )
    (
      @authorization.ProjectAuthorizationError::StorageUnavailable,
      @args.CredentialStore::Native,
    ) =>
      report_failure(
        "the native OS credential-vault service, session, or collection is unavailable. Restore it, then recheck availability. pumd did not fall back to file storage; run `pumd auth setup --client-file oauth-client.json --credential-store=file` only to opt into reduced protection explicitly.",
      )
    (
      @authorization.ProjectAuthorizationError::UnsupportedPlatform,
      @args.CredentialStore::Native,
    ) =>
      report_failure(
        "this platform has no supported native credential vault. pumd did not fall back to file storage; run `pumd auth setup --client-file oauth-client.json --credential-store=file` only to opt into reduced protection explicitly.",
      )
    _ => report_failure(error.user_message())
  }
}

///|
fn project_authentication_problem(
  error : @authorization.ProjectAuthorizationError,
) -> @publish.AuthenticationProblem {
  match error {
    @authorization.ProjectAuthorizationError::NotConfigured =>
      @publish.AuthenticationProblem::CredentialsNotConfigured
    @authorization.ProjectAuthorizationError::GcloudUnavailable =>
      @publish.AuthenticationProblem::GcloudUnavailable
    @authorization.ProjectAuthorizationError::GcloudUnauthenticated =>
      @publish.AuthenticationProblem::GcloudUnauthenticated
    @authorization.ProjectAuthorizationError::ReauthorizationRequired =>
      @publish.AuthenticationProblem::CredentialsRejected
    @authorization.ProjectAuthorizationError::RefreshTransient =>
      @publish.AuthenticationProblem::CredentialsRefreshFailed
    @authorization.ProjectAuthorizationError::StorageMissingEntitlement =>
      @publish.AuthenticationProblem::CredentialsUnavailable
    @authorization.ProjectAuthorizationError::StorageLocked =>
      @publish.AuthenticationProblem::CredentialVaultDenied
    @authorization.ProjectAuthorizationError::StorageDenied =>
      @publish.AuthenticationProblem::CredentialVaultDenied
    @authorization.ProjectAuthorizationError::StorageUnavailable =>
      @publish.AuthenticationProblem::CredentialsUnavailable
    @authorization.ProjectAuthorizationError::PreferenceUnavailable
    | @authorization.ProjectAuthorizationError::CredentialRollbackFailed
    | @authorization.ProjectAuthorizationError::StaleCredentialCleanupFailed =>
      @publish.AuthenticationProblem::CredentialsUnavailable
    @authorization.ProjectAuthorizationError::InvalidClientFile(_) =>
      @publish.AuthenticationProblem::CredentialsInvalid
    @authorization.ProjectAuthorizationError::SetupFailed(_) =>
      @publish.AuthenticationProblem::CredentialsInvalid
    @authorization.ProjectAuthorizationError::UnsupportedPlatform =>
      @publish.AuthenticationProblem::UnsupportedPlatform
  }
}

///|
async fn project_access_token(
  http : &@google_http.HttpClient,
  request : @args.CredentialStoreRequest,
) -> Result[String, @publish.AuthenticationProblem] {
  let resolved = match resolve_credential_store(request) {
    Ok(resolved) => resolved
    Err(error) => return Err(project_authentication_problem(error))
  }
  match
    @authorization.project_access_token_classified(resolved.store, async fn(
      request,
    ) {
      @authorization.refresh_with_http_classified(http, request)
    }) {
    Ok(token) => Ok(token)
    Err(error) => Err(project_authentication_problem(error))
  }
}

///|
async fn adc_access_token() -> Result[String, @publish.AuthenticationProblem] {
  match @publish.application_default_access_token() {
    Ok(token) => Ok(token)
    Err(@publish.PublishError::Authentication(problem~, ..)) => Err(problem)
    Err(_) => Err(@publish.AuthenticationProblem::CredentialsInvalid)
  }
}

///|
async fn publish_file(
  path : String,
  authorization : @args.Authorization,
) -> Unit {
  let prepared = match
    @publish.prepare_publication_path(path, fn(source_path) {
      read_source(source_path)
    }) {
    Ok(prepared) => prepared
    Err(error) => return report_failure(error.user_message())
  }
  let http = @google_http.DefaultHttpClient::new()
  let result = match authorization {
    @args.Authorization::Project(store_request) =>
      @publish.publish_prepared_with_project_onboarding(
        prepared,
        terminal_is_interactive(),
        async fn() { project_access_token(http, store_request) },
        fn() {
          confirm_yes(
            "Project Authorization is not configured. Run guided setup now?",
          )
        },
        async fn() {
          let setup_request = match publish_setup_store_request(store_request) {
            Ok(request) => request
            Err(error) => return Err(project_authentication_problem(error))
          }
          let selection = match choose_setup_credential_store(setup_request) {
            Ok(selection) => selection
            Err(error) => return Err(project_authentication_problem(error))
          }
          let probe = setup_request is @args.SetupCredentialStore::Prompt
          match run_guided_setup(selection, probe) {
            Ok(status) => {
              report_setup_success(status, selection)
              Ok(())
            }
            Err(error) => {
              @stdio.stderr.write("pumd: " + error.user_message() + "\n")
              Err(project_authentication_problem(error))
            }
          }
        },
        http,
      )
    @args.Authorization::Adc =>
      @publish.publish_prepared(
        prepared,
        @publish.AuthorizationMode::Adc,
        adc_access_token,
        http,
      )
    @args.Authorization::AccessTokenEnvironment =>
      @publish.publish_prepared(
        prepared,
        @publish.AuthorizationMode::Ephemeral,
        fn() {
          match @env.get_env_var("PUMD_ACCESS_TOKEN") {
            Some(token) if !token.is_empty() => Ok(token)
            _ => Err(@publish.AuthenticationProblem::CredentialsNotConfigured)
          }
        },
        http,
      )
  }
  match result {
    Ok(success) => {
      @stdio.stdout.write("document ID: " + success.document_id + "\n")
      @stdio.stdout.write("edit URL: " + success.url + "\n")
    }
    Err(error) => report_failure(error.user_message())
  }
}

///|
fn choice_index(value : String, default_index : Int, count : Int) -> Int? {
  if value.is_empty() {
    return if default_index >= 0 { Some(default_index) } else { None }
  }
  let one_based = @string.parse_int(value, base=10) catch { _ => return None }
  let index = one_based - 1
  if index >= 0 && index < count {
    Some(index)
  } else {
    None
  }
}

///|
fn confirm_yes(message : String) -> Bool {
  println(message + " [y/N]")
  match terminal_read_line() {
    Some(value) => value.to_lower() == "y" || value.to_lower() == "yes"
    None => false
  }
}

///|
fn choose_account(
  accounts : Array[@authorization.CloudAccount],
  preselected : String?,
) -> Result[String, Unit] {
  if accounts.is_empty() {
    return Err(())
  }
  println("Google accounts available to gcloud:")
  let mut default_index = 0
  for index in 0..<accounts.length() {
    let marker = if preselected == Some(accounts[index].email) {
      default_index = index
      " (active)"
    } else {
      ""
    }
    println(
      "  " + (index + 1).to_string() + ") " + accounts[index].email + marker,
    )
  }
  println("Select an account [" + (default_index + 1).to_string() + "]:")
  let value = match terminal_read_line() {
    Some(value) => value
    None => return Err(())
  }
  match choice_index(value, default_index, accounts.length()) {
    Some(index) => Ok(accounts[index].email)
    None => Err(())
  }
}

///|
fn project_availability_label(
  availability : @authorization.ProjectAvailability,
) -> String {
  match availability {
    @authorization.ProjectAvailability::Available => "available"
    @authorization.ProjectAvailability::Inaccessible => "inaccessible"
    @authorization.ProjectAvailability::Suspended => "suspended"
    @authorization.ProjectAvailability::QuotaBlocked => "quota blocked"
    @authorization.ProjectAvailability::PolicyBlocked => "policy blocked"
  }
}

///|
fn choose_project(
  projects : Array[@authorization.CloudProject],
  preselected : String?,
) -> Result[@authorization.ProjectChoice, Unit] {
  println("Google Cloud projects (existing project is the default path):")
  let mut default_index = -1
  for index in 0..<projects.length() {
    if default_index < 0 &&
      projects[index].availability
      is @authorization.ProjectAvailability::Available {
      default_index = index
    }
    let marker = if preselected == Some(projects[index].project_id) {
      default_index = index
      " (active)"
    } else {
      ""
    }
    println(
      "  " +
      (index + 1).to_string() +
      ") " +
      projects[index].display_name +
      " [" +
      projects[index].project_id +
      "; " +
      project_availability_label(projects[index].availability) +
      "]" +
      marker,
    )
  }
  println("  c) Create a new project (optional)")
  let default_text = if default_index >= 0 {
    " [" + (default_index + 1).to_string() + "]"
  } else {
    ""
  }
  println("Select a project or `c`" + default_text + ":")
  let value = match terminal_read_line() {
    Some(value) => value
    None => return Err(())
  }
  if value.to_lower() == "c" {
    println("New globally unique project ID:")
    let project_id = match terminal_read_line() {
      Some(value) if !value.is_empty() => value
      _ => return Err(())
    }
    println("New project display name:")
    let display_name = match terminal_read_line() {
      Some(value) if !value.is_empty() => value
      _ => return Err(())
    }
    return Ok(
      @authorization.ProjectChoice::Create({ project_id, display_name }),
    )
  }
  match choice_index(value, default_index, projects.length()) {
    Some(index) =>
      Ok(@authorization.ProjectChoice::Existing(projects[index].project_id))
    None => Err(())
  }
}

///|
fn preview_mutation(mutation : @authorization.GuidedSetupMutation) -> Unit {
  match mutation {
    @authorization.GuidedSetupMutation::CreateProject(request) => {
      println("External mutation preview:")
      println("  create Google Cloud project: " + request.project_id)
      println("  display name: " + request.display_name)
      println("  automatically enabled APIs: none")
    }
    @authorization.GuidedSetupMutation::EnableDocsApi(project_id) => {
      println("External mutation preview:")
      println("  project: " + project_id)
      println("  enable API: docs.googleapis.com (Google Docs API only)")
    }
  }
}

///|
fn confirm_mutation(mutation : @authorization.GuidedSetupMutation) -> Bool {
  match mutation {
    @authorization.GuidedSetupMutation::CreateProject(_) =>
      confirm_yes("Create this Google Cloud project?")
    @authorization.GuidedSetupMutation::EnableDocsApi(_) =>
      confirm_yes("Enable the Google Docs API?")
  }
}

///|
fn choose_consent_configuration() -> @authorization.ConsentConfiguration {
  println(
    "Google does not expose normal Google Auth Platform consent settings through a supported API.",
  )
  println(
    "Choose the current state; pumd will never overwrite existing settings:",
  )
  println("  1) Compatible External/testing configuration already exists")
  println("  2) No consent configuration exists yet")
  println(
    "  3) Existing configuration is different, conflicting, or unknown [default]",
  )
  match terminal_read_line() {
    Some("1") => @authorization.ConsentConfiguration::CompatibleExternal
    Some("2") => @authorization.ConsentConfiguration::Absent
    _ => @authorization.ConsentConfiguration::Conflicting
  }
}

///|
fn preview_handoff(handoff : @authorization.GuidedSetupHandoff) -> Unit {
  match handoff {
    @authorization.GuidedSetupHandoff::ConfigureMinimalExternalConsent(links) => {
      println(
        "Manual Google Auth Platform change preview (pumd will not apply it):",
      )
      println("  audience: External/testing")
      println("  data access: " + @authorization.drive_file_scope + " only")
      println(
        "  preserve all existing branding, audience, publishing, and test-user settings",
      )
      println("  Branding: " + links.branding_url)
      println("  Audience: " + links.audience_url)
      println("  Data Access: " + links.scopes_url)
    }
  }
}

///|
async fn complete_consent_handoff(
  project_id : String,
) -> Result[@authorization.ConsentConfiguration, Unit] {
  let links = @authorization.consent_console_links(project_id)
  match @authorization.launch_default_browser(links.branding_url) {
    Ok(_) => ()
    Err(_) => println("Open this page in a browser: " + links.branding_url)
  }
  println(
    "Create the minimum External/testing configuration, add the publishing account as a test user when needed, and configure only drive.file.",
  )
  if confirm_yes("Have you completed and reviewed the consent configuration?") {
    Ok(@authorization.ConsentConfiguration::CompatibleExternal)
  } else {
    Err(())
  }
}

///|
async fn begin_desktop_client_handoff(
  project_id : String,
  url : String,
) -> Result[Unit, Unit] {
  println(
    "Project Authorization requires a Desktop OAuth client owned by project `" +
    project_id +
    "`. Google requires this client to be created manually in Cloud Console.",
  )
  println("Create a Desktop app client and download its JSON: " + url)
  match @authorization.launch_default_browser(url) {
    Ok(_) => Ok(())
    Err(_) => Ok(())
  }
}

///|
fn receive_desktop_client_json() -> Result[String, Unit] {
  println("Path to the downloaded Desktop OAuth client JSON:")
  let path = match terminal_read_line() {
    Some(path) if !path.is_empty() => path
    _ => return Err(())
  }
  match read_source(path) {
    Ok(document) => Ok(document)
    Err(_) => Err(())
  }
}

///|
async fn finish_setup(
  client_document : String,
  store : @authorization.CredentialStore,
  http : &@google_http.HttpClient,
) -> Result[
  @authorization.ProjectAuthorizationStatus,
  @authorization.ProjectAuthorizationError,
] {
  @authorization.setup_project_authorization(
    client_document,
    @authorization.production_setup_dependencies(store, http),
  )
}

///|
priv struct SetupStoreCommit {
  selected_identifier : @authorization.CredentialStoreIdentifier
  selected_store : @authorization.CredentialStore
  previous_identifier : @authorization.CredentialStoreIdentifier
  previous_store : @authorization.CredentialStore
  preference : @authorization.CredentialStorePreference
}

///|
async fn prepare_setup_store_commit(
  selection : @args.CredentialStore,
  selected_store : @authorization.CredentialStore,
) -> Result[SetupStoreCommit, @authorization.ProjectAuthorizationError] {
  let preference = match project_authorization_preference() {
    Ok(preference) => preference
    Err(error) => return Err(error)
  }
  let remembered_identifier = match (preference.load)() {
    Ok(identifier) => identifier
    Err(_) =>
      return Err(
        @authorization.ProjectAuthorizationError::PreferenceUnavailable,
      )
  }
  let mut previous_identifier = match remembered_identifier {
    Some(identifier) => identifier
    None => @authorization.CredentialStoreIdentifier::Native
  }
  let previous_selection = credential_store_selection(previous_identifier)
  let previous_store = match selected_credential_store(previous_selection) {
    Ok(store) => store
    Err(_) if remembered_identifier is None => {
      previous_identifier = credential_store_identifier(selection)
      selected_store
    }
    Err(error) => return Err(error)
  }
  Ok({
    selected_identifier: credential_store_identifier(selection),
    selected_store,
    previous_identifier,
    previous_store,
    preference,
  })
}

///|
async fn finish_setup_and_commit_store(
  client_document : String,
  commit : SetupStoreCommit,
  http : &@google_http.HttpClient,
) -> Result[
  @authorization.ProjectAuthorizationStatus,
  @authorization.ProjectAuthorizationError,
] {
  @authorization.commit_credential_store_selection(
    commit.selected_identifier,
    commit.selected_store,
    commit.previous_identifier,
    commit.previous_store,
    commit.preference,
    async fn(store) { finish_setup(client_document, store, http) },
  )
}

///|
async fn report_setup_success(
  status : @authorization.ProjectAuthorizationStatus,
  selection : @args.CredentialStore,
) -> Unit {
  @stdio.stdout.write("Project Authorization setup complete.\n")
  @stdio.stdout.write(
    "credential store: " + credential_store_label(selection) + "\n",
  )
  @stdio.stdout.write("scope: " + status.scope + "\n")
  match status.project_id {
    Some(project_id) => @stdio.stdout.write("project: " + project_id + "\n")
    None => ()
  }
}

///|
async fn prepared_setup_store(
  selection : @args.CredentialStore,
  probe : Bool,
) -> Result[
  @authorization.CredentialStore,
  @authorization.ProjectAuthorizationError,
] {
  let store = match selected_credential_store(selection) {
    Ok(store) => store
    Err(error) => return Err(error)
  }
  if probe {
    match credential_store_ready(store) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  if selection is @args.CredentialStore::File {
    @stdio.stderr.write(
      "pumd: warning: file credential storage is an explicit reduced-protection choice; no OS vault fallback is active.\n",
    )
  }
  Ok(store)
}

///|
async fn setup_from_client_file(
  client_file : String,
  selection : @args.CredentialStore,
  probe : Bool,
) -> Unit {
  let client_document = match read_source(client_file) {
    Ok(document) => document
    Err(_) =>
      return report_failure(
        "Project Authorization client file could not be read: `" +
        client_file +
        "`",
      )
  }
  let store = match prepared_setup_store(selection, probe) {
    Ok(store) => store
    Err(error) => return report_project_authorization_failure(error, selection)
  }
  let commit = match prepare_setup_store_commit(selection, store) {
    Ok(commit) => commit
    Err(error) => return report_project_authorization_failure(error, selection)
  }
  let http = @google_http.DefaultHttpClient::new()
  match finish_setup_and_commit_store(client_document, commit, http) {
    Ok(status) => report_setup_success(status, selection)
    Err(error) => report_project_authorization_failure(error, selection)
  }
}

///|
async fn run_guided_setup(
  selection : @args.CredentialStore,
  probe : Bool,
) -> Result[
  @authorization.ProjectAuthorizationStatus,
  @authorization.ProjectAuthorizationError,
] {
  let store = match prepared_setup_store(selection, probe) {
    Ok(store) => store
    Err(error) => return Err(error)
  }
  let commit = match prepare_setup_store_commit(selection, store) {
    Ok(commit) => commit
    Err(error) => return Err(error)
  }
  let adapter = @authorization.production_gcloud_adapter()
  let http = @google_http.DefaultHttpClient::new()
  let result = @authorization.guide_project_authorization({
    inspect_gcloud: async fn() {
      match adapter.inspect() {
        Ok(status) => Ok(status)
        Err(_) => Err(())
      }
    },
    list_accounts: async fn() {
      match adapter.list_accounts() {
        Ok(accounts) => Ok(accounts)
        Err(_) => Err(())
      }
    },
    select_account: choose_account,
    list_projects: async fn(account) {
      match adapter.list_projects(account) {
        Ok(projects) => Ok(projects)
        Err(_) => Err(())
      }
    },
    select_project: choose_project,
    inspect_docs_api: async fn(account, project_id) {
      match adapter.inspect_docs_api(account, project_id) {
        Ok(enabled) => Ok(enabled)
        Err(_) => Err(())
      }
    },
    inspect_consent: fn(_) { Ok(choose_consent_configuration()) },
    preview_mutation,
    confirm_mutation,
    preview_handoff,
    confirm_handoff: fn(_) {
      confirm_yes("Open Google Cloud Console and make these manual changes?")
    },
    create_project: async fn(account, request) {
      match adapter.create_project(account, request) {
        Ok(project) => Ok(project)
        Err(_) => Err(())
      }
    },
    enable_docs_api: async fn(account, project_id) {
      match adapter.enable_docs_api(account, project_id) {
        Ok(_) => Ok(())
        Err(_) => Err(())
      }
    },
    ensure_minimal_external_consent: complete_consent_handoff,
    begin_desktop_client_handoff,
    receive_desktop_client_json: fn() { receive_desktop_client_json() },
    complete_oauth: async fn(document) {
      finish_setup_and_commit_store(document, commit, http)
    },
  })
  match result {
    Ok(status) => Ok(status)
    Err(error) => Err(error.project_authorization_error())
  }
}

///|
async fn guided_setup(selection : @args.CredentialStore, probe : Bool) -> Unit {
  if !terminal_is_interactive() {
    return report_failure(
      "guided Project Authorization requires an interactive terminal. Supply a preconfigured Desktop client with `pumd auth setup --client-file <path>` or use explicit automation credentials.",
    )
  }
  match run_guided_setup(selection, probe) {
    Ok(status) => report_setup_success(status, selection)
    Err(error) => report_project_authorization_failure(error, selection)
  }
}

///|
async fn auth_setup(
  client_file : @args.ClientFile,
  store_request : @args.SetupCredentialStore,
) -> Unit {
  let selection = match choose_setup_credential_store(store_request) {
    Ok(selection) => selection
    Err(error) =>
      return report_project_authorization_failure(
        error,
        @args.CredentialStore::Native,
      )
  }
  let probe = store_request is @args.SetupCredentialStore::Prompt
  match client_file {
    @args.ClientFile::Guided => guided_setup(selection, probe)
    @args.ClientFile::Provided(path) =>
      setup_from_client_file(path, selection, probe)
  }
}

///|
async fn report_project_authorization_status(
  request : @args.CredentialStoreRequest,
) -> Unit {
  let resolved = match resolve_credential_store(request) {
    Ok(resolved) => resolved
    Err(error) =>
      return report_project_authorization_failure(
        error,
        @args.CredentialStore::Native,
      )
  }
  let http = @google_http.DefaultHttpClient::new()
  match
    @authorization.inspect_project_authorization_status(resolved.store, async fn(
      request,
    ) {
      @authorization.refresh_with_http_classified(http, request)
    }) {
    Ok(inspection) => {
      let status = inspection.status
      let usability = match (status.configured, inspection.usability_error) {
        (false, _) => "not configured"
        (true, None) => "usable"
        (
          true,
          Some(
            @authorization.ProjectAuthorizationError::ReauthorizationRequired
          ),
        ) => "needs reauthorization"
        (true, Some(@authorization.ProjectAuthorizationError::RefreshTransient)) =>
          "refresh temporarily unavailable"
        (true, Some(_)) => "unavailable"
      }
      @stdio.stdout.write("Project Authorization: " + usability + "\n")
      @stdio.stdout.write(
        "credential store: " + credential_store_label(resolved.selection) + "\n",
      )
      @stdio.stdout.write("scope: " + status.scope + "\n")
      match status.project_id {
        Some(project_id) => @stdio.stdout.write("project: " + project_id + "\n")
        None => ()
      }
      match inspection.usability_error {
        Some(error) =>
          report_project_authorization_failure(error, resolved.selection)
        None => ()
      }
    }
    Err(error) =>
      report_project_authorization_failure(error, resolved.selection)
  }
}

///|
async fn logout_project_authorization(
  request : @args.CredentialStoreRequest,
) -> Unit {
  let resolved = match resolve_credential_store(request) {
    Ok(resolved) => resolved
    Err(error) =>
      return report_project_authorization_failure(
        error,
        @args.CredentialStore::Native,
      )
  }
  match (resolved.store.delete)() {
    Ok(_) | Err(@authorization.CredentialStoreError::NotConfigured) => {
      @stdio.stdout.write(
        "Project Authorization credentials removed locally.\n",
      )
      @stdio.stdout.write(
        "credential store: " + credential_store_label(resolved.selection) + "\n",
      )
      @stdio.stdout.write(
        "Google's remote authorization may still be active; revoke it separately in your Google Account if required.\n",
      )
    }
    Err(@authorization.CredentialStoreError::Denied) =>
      report_project_authorization_failure(
        @authorization.ProjectAuthorizationError::StorageDenied,
        resolved.selection,
      )
    Err(@authorization.CredentialStoreError::Unsupported) =>
      report_project_authorization_failure(
        @authorization.ProjectAuthorizationError::UnsupportedPlatform,
        resolved.selection,
      )
    Err(_) =>
      report_project_authorization_failure(
        @authorization.ProjectAuthorizationError::StorageUnavailable,
        resolved.selection,
      )
  }
}

///|
async fn main {
  match @args.parse_command(@env.args()) {
    Ok(@args.Command::Publish(path, authorization)) =>
      publish_file(path, authorization)
    Ok(@args.Command::AuthSetup(client_file, store)) =>
      auth_setup(client_file, store)
    Ok(@args.Command::AuthStatus(store)) =>
      report_project_authorization_status(store)
    Ok(@args.Command::AuthLogout(store)) => logout_project_authorization(store)
    Err(message) => report_failure(message)
  }
}
