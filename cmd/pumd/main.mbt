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
    @args.CredentialStore::Keychain => "macOS Keychain"
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
    @args.CredentialStore::Keychain =>
      Ok(@authorization.CredentialStoreKind::Keychain)
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
async fn credential_store_ready(
  store : @authorization.CredentialStore,
) -> Result[Unit, @authorization.ProjectAuthorizationError] {
  match (store.load)() {
    Ok(_)
    | Err(@authorization.CredentialStoreError::NotConfigured)
    | Err(@authorization.CredentialStoreError::Malformed) => Ok(())
    Err(_) => Err(@authorization.ProjectAuthorizationError::StorageUnavailable)
  }
}

///|
async fn report_project_authorization_failure(
  error : @authorization.ProjectAuthorizationError,
  store : @args.CredentialStore,
) -> Unit {
  match (error, store) {
    (
      @authorization.ProjectAuthorizationError::StorageUnavailable,
      @args.CredentialStore::Keychain,
    ) =>
      report_failure(
        "macOS Keychain is unavailable or access was denied. Unlock the login Keychain and allow access, then retry. pumd did not fall back to file storage.",
      )
    _ => report_failure(error.user_message())
  }
}

///|
fn project_authentication_problem(
  error : @authorization.ProjectAuthorizationError,
) -> @publish.AuthenticationProblem {
  match error {
    @authorization.ProjectAuthorizationError::ReauthorizationRequired =>
      @publish.AuthenticationProblem::CredentialsRefreshFailed
    @authorization.ProjectAuthorizationError::StorageUnavailable =>
      @publish.AuthenticationProblem::CredentialsUnavailable
    @authorization.ProjectAuthorizationError::InvalidClientFile(_) =>
      @publish.AuthenticationProblem::CredentialsInvalid
    @authorization.ProjectAuthorizationError::SetupFailed(_) =>
      @publish.AuthenticationProblem::CredentialsInvalid
  }
}

///|
async fn project_access_token(
  http : &@google_http.HttpClient,
  selection : @args.CredentialStore,
) -> Result[String, @publish.AuthenticationProblem] {
  let store = match selected_credential_store(selection) {
    Ok(store) => store
    Err(error) => return Err(project_authentication_problem(error))
  }
  match
    @authorization.project_access_token(store, async fn(request) {
      @authorization.refresh_with_http(http, request)
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
  let http = @google_http.DefaultHttpClient::new()
  let mode = match authorization {
    @args.Authorization::Project(_) => @publish.AuthorizationMode::Project
    @args.Authorization::Adc => @publish.AuthorizationMode::Adc
  }
  match
    @publish.publish_path_with_authorization(
      path,
      fn(source_path) { read_source(source_path) },
      mode,
      async fn() {
        match authorization {
          @args.Authorization::Project(store) =>
            project_access_token(http, store)
          @args.Authorization::Adc =>
            Err(@publish.AuthenticationProblem::CredentialsInvalid)
        }
      },
      adc_access_token,
      http,
    ) {
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
async fn prepared_setup_store(
  selection : @args.CredentialStore,
) -> Result[
  @authorization.CredentialStore,
  @authorization.ProjectAuthorizationError,
] {
  let store = match selected_credential_store(selection) {
    Ok(store) => store
    Err(error) => return Err(error)
  }
  match credential_store_ready(store) {
    Ok(_) => ()
    Err(error) => return Err(error)
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
  let store = match prepared_setup_store(selection) {
    Ok(store) => store
    Err(error) => return report_project_authorization_failure(error, selection)
  }
  let http = @google_http.DefaultHttpClient::new()
  match finish_setup(client_document, store, http) {
    Ok(status) => {
      @stdio.stdout.write("Project Authorization setup complete.\n")
      @stdio.stdout.write(
        "credential store: " + credential_store_label(selection) + "\n",
      )
      @stdio.stdout.write("scope: " + status.scope + "\n")
    }
    Err(error) => report_project_authorization_failure(error, selection)
  }
}

///|
async fn guided_setup(selection : @args.CredentialStore) -> Unit {
  if !terminal_is_interactive() {
    return report_failure(
      "guided Project Authorization requires an interactive terminal. Supply a preconfigured Desktop client with `pumd auth setup --client-file <path>` or use explicit automation credentials.",
    )
  }
  let store = match prepared_setup_store(selection) {
    Ok(store) => store
    Err(error) => return report_project_authorization_failure(error, selection)
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
    complete_oauth: async fn(document) { finish_setup(document, store, http) },
  })
  match result {
    Ok(status) => {
      @stdio.stdout.write("Project Authorization setup complete.\n")
      @stdio.stdout.write(
        "credential store: " + credential_store_label(selection) + "\n",
      )
      @stdio.stdout.write("scope: " + status.scope + "\n")
    }
    Err(error) => report_failure(error.user_message())
  }
}

///|
async fn report_project_authorization_status(
  selection : @args.CredentialStore,
) -> Unit {
  let store = match selected_credential_store(selection) {
    Ok(store) => store
    Err(error) => return report_project_authorization_failure(error, selection)
  }
  let http = @google_http.DefaultHttpClient::new()
  match
    @authorization.project_authorization_usable_status(store, async fn(
      request,
    ) {
      @authorization.refresh_with_http(http, request)
    }) {
    Ok(status) => {
      let usability = if status.configured {
        "usable"
      } else {
        "not configured"
      }
      @stdio.stdout.write("Project Authorization: " + usability + "\n")
      @stdio.stdout.write(
        "credential store: " + credential_store_label(selection) + "\n",
      )
      @stdio.stdout.write("scope: " + status.scope + "\n")
    }
    Err(error) => report_project_authorization_failure(error, selection)
  }
}

///|
async fn logout_project_authorization(
  selection : @args.CredentialStore,
) -> Unit {
  let store = match selected_credential_store(selection) {
    Ok(store) => store
    Err(error) => return report_project_authorization_failure(error, selection)
  }
  match (store.delete)() {
    Ok(_) | Err(@authorization.CredentialStoreError::NotConfigured) => {
      @stdio.stdout.write("Project Authorization removed.\n")
      @stdio.stdout.write(
        "credential store: " + credential_store_label(selection) + "\n",
      )
    }
    Err(_) =>
      report_project_authorization_failure(
        @authorization.ProjectAuthorizationError::StorageUnavailable,
        selection,
      )
  }
}

///|
async fn main {
  match @args.parse_command(@sys.get_cli_args()) {
    Ok(@args.Command::Publish(path, authorization)) =>
      publish_file(path, authorization)
    Ok(@args.Command::AuthSetup(@args.ClientFile::Guided, store)) =>
      guided_setup(store)
    Ok(@args.Command::AuthSetup(@args.ClientFile::Provided(path), store)) =>
      setup_from_client_file(path, store)
    Ok(@args.Command::AuthStatus(store)) =>
      report_project_authorization_status(store)
    Ok(@args.Command::AuthLogout(store)) => logout_project_authorization(store)
    Err(message) => report_failure(message)
  }
}
