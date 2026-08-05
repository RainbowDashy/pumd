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
  let message = match store {
    @args.CredentialStore::Native =>
      @authorization.native_credential_store_failure_message(error)
    @args.CredentialStore::File => error.user_message()
  }
  report_failure(message)
}

///|
fn project_authentication_problem(
  error : @authorization.ProjectAuthorizationError,
) -> @publish.AuthenticationProblem {
  match error {
    @authorization.ProjectAuthorizationError::NotConfigured =>
      @publish.AuthenticationProblem::CredentialsNotConfigured
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
  dry_run : Bool,
) -> Unit {
  let prepared = match
    @publish.prepare_publication_path(path, fn(source_path) {
      read_source(source_path)
    }) {
    Ok(prepared) => prepared
    Err(error) => return report_failure(error.user_message())
  }
  let registry_directory = match @registry.default_registry_directory() {
    Ok(directory) => directory
    Err(error) =>
      return report_failure(
        @publish.PublishError::Registry(error.user_message()).user_message(),
      )
  }
  let http = @google_http.DefaultHttpClient::new()
  let result = match authorization {
    @args.Authorization::Project(store_request) =>
      @publish.publish_prepared_with_registry(
        prepared,
        path,
        registry_directory,
        @publish.AuthorizationMode::Project,
        if dry_run {
          async fn() { project_access_token(http, store_request) }
        } else {
          async fn() {
            project_access_token_with_onboarding(http, store_request)
          }
        },
        adc_access_token,
        http,
        dry_run,
      )
    @args.Authorization::Adc =>
      @publish.publish_prepared_with_registry(
        prepared,
        path,
        registry_directory,
        @publish.AuthorizationMode::Adc,
        adc_access_token,
        adc_access_token,
        http,
        dry_run,
      )
    @args.Authorization::AccessTokenEnvironment =>
      @publish.publish_prepared_with_registry(
        prepared,
        path,
        registry_directory,
        @publish.AuthorizationMode::Ephemeral,
        fn() {
          match @env.get_env_var("PUMD_ACCESS_TOKEN") {
            Some(token) if !token.is_empty() => Ok(token)
            _ => Err(@publish.AuthenticationProblem::CredentialsNotConfigured)
          }
        },
        fn() {
          match @env.get_env_var("PUMD_ACCESS_TOKEN") {
            Some(token) if !token.is_empty() => Ok(token)
            _ => Err(@publish.AuthenticationProblem::CredentialsNotConfigured)
          }
        },
        http,
        dry_run,
      )
  }
  match result {
    Ok(outcome) => report_publish_outcome(outcome)
    Err(error) => report_failure(error.user_message())
  }
}

///|
/// Offer first-publish setup only when Project Authorization is genuinely
/// absent, only in an interactive session, and only after callers have
/// successfully prepared the publication. Mirrors the previous
/// publish_prepared_with_project_onboarding contract for the registry flow.
async fn project_access_token_with_onboarding(
  http : &@google_http.HttpClient,
  request : @args.CredentialStoreRequest,
) -> Result[String, @publish.AuthenticationProblem] {
  match project_access_token(http, request) {
    Ok(token) => Ok(token)
    Err(@publish.AuthenticationProblem::CredentialsNotConfigured) if terminal_is_interactive() => {
      if !confirm_yes(
          "Project Authorization is not configured. Run guided setup now?",
        ) {
        Err(@publish.AuthenticationProblem::CredentialsNotConfigured)
      } else {
        let setup_request = match publish_setup_store_request(request) {
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
            project_access_token(http, request)
          }
          Err(error) => {
            @stdio.stderr.write("pumd: " + error.user_message() + "\n")
            Err(project_authentication_problem(error))
          }
        }
      }
    }
    Err(problem) => Err(problem)
  }
}

///|
async fn report_publish_outcome(outcome : @publish.PublishOutcome) -> Unit {
  match outcome {
    @publish.PublishOutcome::Completed(success) => {
      @stdio.stdout.write("document ID: " + success.document_id + "\n")
      @stdio.stdout.write("edit URL: " + success.url + "\n")
      @stdio.stdout.write("Publication registered locally.\n")
    }
    @publish.PublishOutcome::AlreadyPublished(success, last_publish) => {
      @stdio.stdout.write("already published\n")
      @stdio.stdout.write("document ID: " + success.document_id + "\n")
      @stdio.stdout.write("edit URL: " + success.url + "\n")
      @stdio.stdout.write(
        "last successful publish: " + last_publish + "\n",
      )
      @stdio.stdout.write(
        "this release cannot update an existing Publication yet.\n",
      )
    }
    @publish.PublishOutcome::DryRunCreation(title~) => {
      @stdio.stdout.write(
        "dry run: this source has no Publication; publishing would create\n",
      )
      @stdio.stdout.write("  a new document titled \"" + title + "\"\n")
      @stdio.stdout.write(
        "  and register it locally as a Publication.\n",
      )
      @stdio.stdout.write(
        "No authorization, document creation, or registry change was performed.\n",
      )
    }
    @publish.PublishOutcome::DryRunInspection(inspection~) => {
      @stdio.stdout.write(
        "dry run: existing Publication readback succeeded\n",
      )
      @stdio.stdout.write(
        "document ID: " + inspection.document_id + "\n",
      )
      @stdio.stdout.write("edit URL: " + inspection.url + "\n")
      match inspection.title {
        Some(title) =>
          @stdio.stdout.write("current title: " + title + "\n")
        None => @stdio.stdout.write("current title: unavailable\n")
      }
      @stdio.stdout.write("managed tab: present\n")
      @stdio.stdout.write(
        "No remote write or registry change was performed.\n",
      )
    }
    @publish.PublishOutcome::DryRunProvisional(success) => {
      @stdio.stdout.write(
        "dry run: this source has a Publication whose population is not\n",
      )
      @stdio.stdout.write("  yet confirmed.\n")
      @stdio.stdout.write(
        "document ID: " + success.document_id + "\n",
      )
      @stdio.stdout.write("edit URL: " + success.url + "\n")
      @stdio.stdout.write(
        "Run publish again to resume population; no state changed.\n",
      )
    }
    @publish.PublishOutcome::DryRunBlocked(source_path~) => {
      @stdio.stdout.write(
        "dry run: this source has a blocked Publication from an earlier\n",
      )
      @stdio.stdout.write("  ambiguous document creation.\n")
      @stdio.stdout.write(
        "Inspect Google Drive; then `pumd forget " +
        source_path +
        "` to retry. No state changed.\n",
      )
    }
  }
}

///|
fn publication_status_label(
  lifecycle : @registry.PublicationLifecycle,
) -> String {
  match lifecycle {
    @registry.PublicationLifecycle::Ready => "ready"
    @registry.PublicationLifecycle::Provisional =>
      "provisional (population not confirmed)"
    @registry.PublicationLifecycle::Blocked =>
      "blocked (inspect Google Drive, then forget)"
  }
}

///|
fn remote_status_label(
  status : @publish.RemotePublicationStatus,
) -> String {
  match status {
    @publish.RemotePublicationStatus::Ready => "ready"
    @publish.RemotePublicationStatus::Trashed => "trashed"
    @publish.RemotePublicationStatus::ReadOnly => "read-only"
    @publish.RemotePublicationStatus::RemoteMissing => "remote-missing"
    @publish.RemotePublicationStatus::Inaccessible => "inaccessible"
    @publish.RemotePublicationStatus::Unavailable => "unavailable"
  }
}

///|
async fn print_publication_listing(
  entry : @registry.PublicationEntry,
  inspection : @publish.RemotePublicationInspection?,
  missing_source : Bool,
) -> Unit {
  @stdio.stdout.write(entry.source_path + "\n")
  match entry.document_id {
    Some(document_id) => {
      @stdio.stdout.write("  document ID: " + document_id + "\n")
      match entry.url {
        Some(url) => @stdio.stdout.write("  edit URL: " + url + "\n")
        None => ()
      }
    }
    None => ()
  }
  match entry.last_successful_publish {
    Some(timestamp) =>
      @stdio.stdout.write(
        "  last successful publish: " + timestamp + "\n",
      )
    None => ()
  }
  @stdio.stdout.write(
    "  status: " + publication_status_label(entry.lifecycle),
  )
  if missing_source {
    @stdio.stdout.write(" (source missing)")
  }
  @stdio.stdout.write("\n")
  match inspection {
    Some(inspection) => {
      @stdio.stdout.write(
        "  remote: " + remote_status_label(inspection.status),
      )
      match inspection.title {
        Some(title) => @stdio.stdout.write(" (title \"" + title + "\"")
        None => @stdio.stdout.write(" (title unavailable")
      }
      match inspection.editable {
        Some(editable) =>
          if editable {
            @stdio.stdout.write(", editable")
          } else {
            @stdio.stdout.write(", read-only")
          }
        None => ()
      }
      @stdio.stdout.write(")\n")
    }
    None => ()
  }
}

///|
async fn list_publications(options : @args.ListOptions) -> Unit {
  let directory = match @registry.default_registry_directory() {
    Ok(directory) => directory
    Err(error) =>
      return report_failure(
        @publish.PublishError::Registry(error.user_message()).user_message(),
      )
  }
  let document = match @registry.registry_snapshot(directory) {
    Ok(document) => document
    Err(error) =>
      return report_failure(
        @publish.PublishError::Registry(error.user_message()).user_message(),
      )
  }
  let missing_source = fn(path : String) { !@fs.path_exists(path) }
  if options.json && !options.refresh {
    @stdio.stdout.write(
      @publish.publication_list_json(document, missing_source) + "\n",
    )
    return
  }
  if options.refresh {
    let http = @google_http.DefaultHttpClient::new()
    let token = match
      project_access_token(
        http,
        @args.CredentialStoreRequest::RememberedOrNative,
      ) {
      Ok(token) => token
      Err(problem) =>
        return report_failure(
          @publish.PublishError::Authentication(
            authorization_mode=@publish.AuthorizationMode::Project,
            problem~,
            created_document=None,
          ).user_message(),
        )
    }
    let inspections : Array[@publish.RemotePublicationInspection] = []
    let entries = document.entries.copy()
    entries.sort_by(fn(a, b) {
      if a.source_path < b.source_path {
        -1
      } else if a.source_path > b.source_path {
        1
      } else {
        0
      }
    })
    for entry in entries {
      inspections.push(
        @publish.inspect_registered_publication(token, http, entry),
      )
    }
    if options.json {
      @stdio.stdout.write(
        @publish.publication_refresh_json(
          document,
          missing_source,
          inspections,
        ) + "\n",
      )
      return
    }
    for index = 0; index < entries.length(); index = index + 1 {
      let entry = entries[index]
      let inspection = match entry.document_id {
        Some(_) => Some(inspections[index])
        None => None
      }
      print_publication_listing(
        entry,
        inspection,
        !@fs.path_exists(entry.source_path),
      )
    }
    return
  }
  if options.json {
    @stdio.stdout.write(
      @publish.publication_list_json(document, missing_source) + "\n",
    )
    return
  }
  let entries = document.entries.copy()
  entries.sort_by(fn(a, b) {
    if a.source_path < b.source_path {
      -1
    } else if a.source_path > b.source_path {
      1
    } else {
      0
    }
  })
  for entry in entries {
    print_publication_listing(
      entry,
      None,
      !@fs.path_exists(entry.source_path),
    )
  }
}

///|
async fn move_publication(old_path : String, new_path : String) -> Unit {
  let directory = match @registry.default_registry_directory() {
    Ok(directory) => directory
    Err(error) =>
      return report_failure(
        @publish.PublishError::Registry(error.user_message()).user_message(),
      )
  }
  // Publications are keyed by canonical absolute source paths, so resolve the
  // typed paths before touching the registry. The old file may be absent
  // (the reassociation case); canonical_source_path keeps typed paths then.
  let canonical_old = @registry.canonical_source_path(old_path)
  let canonical_new = @registry.canonical_source_path(new_path)
  match @registry.reassociate_publication(
    directory,
    canonical_old,
    canonical_new,
  ) {
    Ok(_) =>
      @stdio.stdout.write(
        "moved Publication: " + canonical_old + " -> " + canonical_new + "\n",
      )
    Err(error) =>
      report_failure(
        @publish.PublishError::Registry(error.user_message()).user_message(),
      )
  }
}

///|
async fn forget_publication(path : String) -> Unit {
  let directory = match @registry.default_registry_directory() {
    Ok(directory) => directory
    Err(error) =>
      return report_failure(
        @publish.PublishError::Registry(error.user_message()).user_message(),
      )
  }
  let canonical = @registry.canonical_source_path(path)
  match @registry.forget_publication(directory, canonical) {
    Ok(true) =>
      @stdio.stdout.write("forgotten Publication: " + canonical + "\n")
    Ok(false) =>
      @stdio.stdout.write("no Publication found for " + canonical + "\n")
    Err(error) =>
      report_failure(
        @publish.PublishError::Registry(error.user_message()).user_message(),
      )
  }
}

///|
async fn main {
  match @args.parse_command(@env.args()) {
    Ok(@args.Command::Publish(path, authorization, dry_run)) =>
      publish_file(path, authorization, dry_run)
    Ok(@args.Command::List(options)) => list_publications(options)
    Ok(@args.Command::Move(old_path, new_path)) =>
      move_publication(old_path, new_path)
    Ok(@args.Command::Forget(path)) => forget_publication(path)
    Ok(@args.Command::AuthSetup(client_file, store)) =>
      auth_setup(client_file, store)
    Ok(@args.Command::AuthStatus(store)) =>
      report_project_authorization_status(store)
    Ok(@args.Command::AuthLogout(store)) => logout_project_authorization(store)
    Err(message) => report_failure(message)
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
async fn open_project_console_url(url : String) -> Unit {
  match @authorization.launch_default_browser(url) {
    Ok(_) => ()
    Err(_) => {
      println(
        "Could not open a browser automatically. Open this page yourself:",
      )
      println(url)
    }
  }
}

///|
async fn complete_project_console_handoff(
  handoff : @authorization.ProjectConsoleHandoff,
) -> Result[Unit, @authorization.ProjectConsoleHandoffError] {
  println(
    "Guided Project Authorization hands off two browser-owned steps to Google Cloud Console:",
  )
  println("  1) Enable the Google Docs API: " + handoff.enable_docs_api_url)
  println(
    "  2) Create a Desktop OAuth client and download its JSON: " +
    handoff.oauth_clients_url,
  )
  println(
    "Google handles account selection and project selection or creation in your browser.",
  )
  println("Authorization guidance:")
  println(
    "  - Workspace organization users should prefer an Internal audience where available.",
  )
  println(
    "  - External Testing authorization expires after seven days; External users wanting durable authorization should choose In production.",
  )
  println(
    "  - Request only " +
    @authorization.drive_file_scope +
    "; no identity scopes.",
  )
  println(
    "  - Create a Desktop app client and download its JSON when prompted.",
  )
  if !confirm_yes("Open the first step (enable the Google Docs API) now?") {
    return Err(@authorization.ProjectConsoleHandoffError::Cancelled)
  }
  open_project_console_url(handoff.enable_docs_api_url)
  if !confirm_yes(
      "Have you enabled the Google Docs API for the project you will use?",
    ) {
    return Err(@authorization.ProjectConsoleHandoffError::Cancelled)
  }
  open_project_console_url(handoff.oauth_clients_url)
  if !confirm_yes(
      "Have you created a Desktop app OAuth client and downloaded its JSON?",
    ) {
    return Err(@authorization.ProjectConsoleHandoffError::Cancelled)
  }
  Ok(())
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
  let http = @google_http.DefaultHttpClient::new()
  let result = @authorization.guide_project_authorization({
    complete_project_console_handoff,
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
