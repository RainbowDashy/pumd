///|
/// The only cloud service changed by guided Project Authorization setup.
pub let google_docs_api = "docs.googleapis.com"

///|
/// A Google account offered by the injected account-selection UI.
pub(all) struct CloudAccount {
  email : String
}

///|
/// The safe availability state supplied by the injected gcloud adapter.
pub(all) enum ProjectAvailability {
  Available
  Inaccessible
  Suspended
  QuotaBlocked
  PolicyBlocked
}

///|
/// A project offered by the injected project-selection UI.
pub(all) struct CloudProject {
  project_id : String
  display_name : String
  availability : ProjectAvailability
}

///|
/// The inspected gcloud state. Active identifiers are hints only; the
/// orchestrator preselects them only when they appear in the enumerated data.
pub(all) enum GcloudStatus {
  Missing
  Unauthenticated
  Ready(String?, String?)
}

///|
/// The explicit optional project-creation request collected by the selection UI.
pub(all) struct NewCloudProject {
  project_id : String
  display_name : String
}

///|
/// Existing Project Authorization is deliberately the default selection path.
/// A UI may offer `Create` only as an explicit user choice.
pub(all) enum ProjectChoice {
  Existing(String)
  Create(NewCloudProject)
}

///|
/// The narrow consent-screen states this flow can safely act on.
pub(all) enum ConsentConfiguration {
  Absent
  CompatibleExternal
  Unknown
  Conflicting
}

///|
/// A concrete mutation which must be previewed and confirmed before dispatch.
pub(all) enum GuidedSetupMutation {
  CreateProject(NewCloudProject)
  EnableDocsApi(String)
}

///|
/// Direct Google Auth Platform links for the manual consent handoff.
pub(all) struct ConsentConsoleLinks {
  branding_url : String
  audience_url : String
  scopes_url : String
}

///|
/// A non-automated Cloud Console handoff. These actions deliberately require a
/// human to edit Google Auth Platform; pumd never writes consent settings.
pub(all) enum GuidedSetupHandoff {
  ConfigureMinimalExternalConsent(ConsentConsoleLinks)
}

///|
/// Safe, actionable failures from the guided Project Authorization orchestration.
/// No branch incorporates adapter output, so process output and OAuth material
/// cannot appear in messages.
pub(all) enum GuidedSetupError {
  GcloudUnavailable
  GcloudUnauthenticated
  AccountEnumerationFailed
  AccountSelectionInvalid
  ProjectEnumerationFailed
  ProjectSelectionInvalid
  ProjectUnavailable
  ProjectSuspended
  ProjectQuotaBlocked
  ProjectPolicyBlocked
  Cancelled
  ProjectCreationFailed
  DocsApiInspectionFailed
  DocsApiEnablementFailed
  ConsentInspectionFailed
  ConsentConflict
  ConsentHandoffFailed
  DesktopClientHandoffFailed
  DesktopClientFileUnavailable
  DesktopClientFileInvalid
  CredentialVaultDenied
  CredentialVaultLocked
  CredentialVaultMissingEntitlement
  CredentialVaultUnavailable
  CredentialVaultUnsupported
  CredentialPreferenceCommitFailed
  CredentialRollbackIncomplete
  PreviousCredentialCleanupFailed
  OAuthSetupFailed
}

///|
pub fn GuidedSetupError::user_message(self : GuidedSetupError) -> String {
  match self {
    GcloudUnavailable =>
      "Project Authorization setup requires the Google Cloud CLI (`gcloud`). Install it from https://cloud.google.com/sdk/docs/install, then run setup again."
    GcloudUnauthenticated =>
      "Project Authorization setup requires a signed-in gcloud account. Run `gcloud auth login`, then run setup again."
    AccountEnumerationFailed =>
      "Project Authorization could not list Google accounts from gcloud. Verify gcloud access, then run setup again."
    AccountSelectionInvalid =>
      "Select one of the Google accounts reported by gcloud."
    ProjectEnumerationFailed =>
      "Project Authorization could not list Google Cloud projects for the selected account."
    ProjectSelectionInvalid =>
      "Select an existing Google Cloud project or provide a valid new project ID."
    ProjectUnavailable =>
      "The selected Google Cloud project is not accessible to the selected account."
    ProjectSuspended =>
      "The selected Google Cloud project is suspended. Restore it in Google Cloud Console before setup."
    ProjectQuotaBlocked =>
      "The selected Google Cloud project is blocked by quota or billing. Resolve it in Google Cloud Console before setup."
    ProjectPolicyBlocked =>
      "Organization policy prevents Project Authorization changes in the selected project. Contact the project administrator."
    Cancelled =>
      "Project Authorization setup was cancelled before the requested cloud change."
    ProjectCreationFailed =>
      "Google Cloud could not create the requested project. Check project ID, quota, billing, and organization policy."
    DocsApiInspectionFailed =>
      "Project Authorization could not inspect the Google Docs API state."
    DocsApiEnablementFailed =>
      "Google Cloud could not enable the Google Docs API. Check project permissions, quota, and organization policy."
    ConsentInspectionFailed =>
      "Project Authorization could not inspect the OAuth consent configuration."
    ConsentConflict =>
      "The existing or unknown OAuth consent configuration was left unchanged. Review Branding, Audience, and Data Access in Google Cloud Console."
    ConsentHandoffFailed =>
      "Complete the minimal external OAuth consent configuration in Google Cloud Console, then resume setup."
    DesktopClientHandoffFailed =>
      "Open the OAuth client page in Google Cloud Console and create a Desktop app client, then run setup again."
    DesktopClientFileUnavailable =>
      "Project Authorization needs the downloaded Desktop OAuth client JSON to continue."
    DesktopClientFileInvalid =>
      "The downloaded file is not a valid Google Desktop OAuth client JSON."
    CredentialVaultDenied =>
      "Permission to use the native credential vault was denied. Allow pumd or correct the platform policy, then recheck availability."
    CredentialVaultLocked =>
      "The native credential vault is locked. Unlock it, then recheck availability."
    CredentialVaultMissingEntitlement =>
      "This pumd executable lacks the entitlement required by the macOS Keychain implementation. Install a correctly signed build or explicitly choose file storage only if reduced protection is acceptable."
    CredentialVaultUnavailable =>
      "The selected credential store is unavailable. No existing authorization was replaced."
    CredentialVaultUnsupported =>
      "This platform has no supported native credential vault. No file fallback was used."
    CredentialPreferenceCommitFailed =>
      "The new credential-store preference could not be saved safely. The prior authorization and preference were preserved."
    CredentialRollbackIncomplete =>
      "Project Authorization setup could not restore the prior local credential after a commit failure. Inspect both credential stores before retrying."
    PreviousCredentialCleanupFailed =>
      "The new Project Authorization is active, but the previous local credential could not be removed. Resolve the stale credential before treating migration as complete."
    OAuthSetupFailed =>
      "Project Authorization could not complete direct OAuth. No existing credential was replaced."
  }
}

///|
pub fn GuidedSetupError::project_authorization_error(
  self : GuidedSetupError,
) -> ProjectAuthorizationError {
  match self {
    GcloudUnavailable => ProjectAuthorizationError::GcloudUnavailable
    GcloudUnauthenticated => ProjectAuthorizationError::GcloudUnauthenticated
    CredentialVaultDenied => ProjectAuthorizationError::StorageDenied
    CredentialVaultLocked => ProjectAuthorizationError::StorageLocked
    CredentialVaultMissingEntitlement =>
      ProjectAuthorizationError::StorageMissingEntitlement
    CredentialVaultUnavailable => ProjectAuthorizationError::StorageUnavailable
    CredentialVaultUnsupported => ProjectAuthorizationError::UnsupportedPlatform
    CredentialPreferenceCommitFailed =>
      ProjectAuthorizationError::PreferenceUnavailable
    CredentialRollbackIncomplete =>
      ProjectAuthorizationError::CredentialRollbackFailed
    PreviousCredentialCleanupFailed =>
      ProjectAuthorizationError::StaleCredentialCleanupFailed
    _ => ProjectAuthorizationError::SetupFailed(self.user_message())
  }
}

///|
/// All external behavior is injected. Adapters own gcloud commands, UI,
/// Cloud Console launching, and credential-vault/OAuth details; this module
/// owns only ordering, validation, idempotency, and safe failure mapping.
pub(all) struct GuidedSetupDependencies {
  inspect_gcloud : async () -> Result[GcloudStatus, Unit]
  list_accounts : async () -> Result[Array[CloudAccount], Unit]
  select_account : (Array[CloudAccount], String?) -> Result[String, Unit]
  list_projects : async (String) -> Result[Array[CloudProject], Unit]
  select_project : (Array[CloudProject], String?) -> Result[ProjectChoice, Unit]
  inspect_docs_api : async (String, String) -> Result[Bool, Unit]
  inspect_consent : async (String) -> Result[ConsentConfiguration, Unit]
  preview_mutation : (GuidedSetupMutation) -> Unit
  confirm_mutation : (GuidedSetupMutation) -> Bool
  preview_handoff : (GuidedSetupHandoff) -> Unit
  confirm_handoff : (GuidedSetupHandoff) -> Bool
  create_project : async (String, NewCloudProject) -> Result[CloudProject, Unit]
  enable_docs_api : async (String, String) -> Result[Unit, Unit]
  ensure_minimal_external_consent : async (String) -> Result[
    ConsentConfiguration,
    Unit,
  ]
  begin_desktop_client_handoff : async (String, String) -> Result[Unit, Unit]
  receive_desktop_client_json : async () -> Result[String, Unit]
  // This callback must preserve any prior Project Authorization if it fails.
  complete_oauth : async (String) -> Result[
    ProjectAuthorizationStatus,
    ProjectAuthorizationError,
  ]
}

///|
fn safe_project_id(project_id : String) -> Bool {
  if project_id.is_empty() {
    return false
  }
  for character in project_id {
    if !((character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '-') {
      return false
    }
  }
  true
}

///|
fn selected_account_is_listed(
  accounts : Array[CloudAccount],
  email : String,
) -> Bool {
  for account in accounts {
    if account.email == email {
      return true
    }
  }
  false
}

///|
fn selected_project(
  projects : Array[CloudProject],
  project_id : String,
) -> CloudProject? {
  for project in projects {
    if project.project_id == project_id {
      return Some(project)
    }
  }
  None
}

///|
fn valid_preselected_account(
  accounts : Array[CloudAccount],
  active_account : String?,
) -> String? {
  match active_account {
    Some(account) if selected_account_is_listed(accounts, account) =>
      Some(account)
    _ => None
  }
}

///|
fn valid_preselected_project(
  projects : Array[CloudProject],
  active_project : String?,
) -> String? {
  match active_project {
    Some(project_id) =>
      match selected_project(projects, project_id) {
        Some(project) if project.availability is Available => Some(project_id)
        _ => None
      }
    None => None
  }
}

///|
fn project_availability_error(
  availability : ProjectAvailability,
) -> GuidedSetupError? {
  match availability {
    Available => None
    Inaccessible => Some(ProjectUnavailable)
    Suspended => Some(ProjectSuspended)
    QuotaBlocked => Some(ProjectQuotaBlocked)
    PolicyBlocked => Some(ProjectPolicyBlocked)
  }
}

///|
fn preview_and_confirm(
  dependencies : GuidedSetupDependencies,
  mutation : GuidedSetupMutation,
) -> Result[Unit, GuidedSetupError] {
  (dependencies.preview_mutation)(mutation)
  if (dependencies.confirm_mutation)(mutation) {
    Ok(())
  } else {
    Err(Cancelled)
  }
}

///|
fn preview_and_confirm_handoff(
  dependencies : GuidedSetupDependencies,
  handoff : GuidedSetupHandoff,
) -> Result[Unit, GuidedSetupError] {
  (dependencies.preview_handoff)(handoff)
  if (dependencies.confirm_handoff)(handoff) {
    Ok(())
  } else {
    Err(Cancelled)
  }
}

///|
/// The direct Cloud Console handoff URL for manual Desktop OAuth client creation.
/// Callers can present or open this exact link through the injected handoff.
pub fn desktop_client_console_url(project_id : String) -> String {
  "https://console.cloud.google.com/auth/clients?project=" + project_id
}

///|
/// The concrete manual Google Auth Platform destinations for a project. The
/// adapter should explain the minimal external/testing configuration at these
/// links and then re-inspect it through `ensure_minimal_external_consent`.
pub fn consent_console_links(project_id : String) -> ConsentConsoleLinks {
  let prefix = "https://console.cloud.google.com/auth/"
  {
    branding_url: prefix + "branding?project=" + project_id,
    audience_url: prefix + "audience?project=" + project_id,
    scopes_url: prefix + "scopes?project=" + project_id,
  }
}

///|
async fn resolve_project(
  dependencies : GuidedSetupDependencies,
  account : String,
  projects : Array[CloudProject],
  active_project : String?,
) -> Result[String, GuidedSetupError] {
  let choice = match
    (dependencies.select_project)(
      projects,
      valid_preselected_project(projects, active_project),
    ) {
    Ok(choice) => choice
    Err(_) => return Err(ProjectSelectionInvalid)
  }
  match choice {
    Existing(project_id) => {
      if !safe_project_id(project_id) {
        return Err(ProjectSelectionInvalid)
      }
      match selected_project(projects, project_id) {
        None => Err(ProjectSelectionInvalid)
        Some(project) =>
          match project_availability_error(project.availability) {
            Some(error) => Err(error)
            None => Ok(project.project_id)
          }
      }
    }
    Create(request) => {
      if !safe_project_id(request.project_id) || request.display_name.is_empty() {
        return Err(ProjectSelectionInvalid)
      }
      let mutation = GuidedSetupMutation::CreateProject(request)
      match preview_and_confirm(dependencies, mutation) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      let created = match (dependencies.create_project)(account, request) {
        Ok(project) => project
        Err(_) => return Err(ProjectCreationFailed)
      }
      if created.project_id != request.project_id {
        return Err(ProjectCreationFailed)
      }
      match project_availability_error(created.availability) {
        Some(error) => Err(error)
        None => Ok(created.project_id)
      }
    }
  }
}

///|
async fn ensure_docs_api(
  dependencies : GuidedSetupDependencies,
  account : String,
  project_id : String,
) -> Result[Unit, GuidedSetupError] {
  let enabled = match (dependencies.inspect_docs_api)(account, project_id) {
    Ok(enabled) => enabled
    Err(_) => return Err(DocsApiInspectionFailed)
  }
  if enabled {
    return Ok(())
  }
  let mutation = GuidedSetupMutation::EnableDocsApi(project_id)
  match preview_and_confirm(dependencies, mutation) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match (dependencies.enable_docs_api)(account, project_id) {
    Ok(_) => Ok(())
    Err(_) => Err(DocsApiEnablementFailed)
  }
}

///|
async fn ensure_consent(
  dependencies : GuidedSetupDependencies,
  project_id : String,
) -> Result[Unit, GuidedSetupError] {
  let consent = match (dependencies.inspect_consent)(project_id) {
    Ok(consent) => consent
    Err(_) => return Err(ConsentInspectionFailed)
  }
  match consent {
    CompatibleExternal => Ok(())
    Unknown | Conflicting => Err(ConsentConflict)
    Absent => {
      let handoff = GuidedSetupHandoff::ConfigureMinimalExternalConsent(
        consent_console_links(project_id),
      )
      match preview_and_confirm_handoff(dependencies, handoff) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      match (dependencies.ensure_minimal_external_consent)(project_id) {
        Ok(CompatibleExternal) => Ok(())
        Ok(_) => Err(ConsentConflict)
        Err(_) => Err(ConsentHandoffFailed)
      }
    }
  }
}

///|
/// Run the pure guided Project Authorization state machine. Each mutation is
/// concrete, previewed, and confirmed immediately before its injected effect.
/// Consent is never mutated by pumd: an absent configuration gets a separately
/// previewed manual Console handoff. Existing Docs API and compatible consent
/// state are left untouched on rerun.
pub async fn guide_project_authorization(
  dependencies : GuidedSetupDependencies,
) -> Result[ProjectAuthorizationStatus, GuidedSetupError] {
  let (active_account, active_project) = match (dependencies.inspect_gcloud)() {
    Ok(GcloudStatus::Missing) => return Err(GcloudUnavailable)
    Ok(GcloudStatus::Unauthenticated) => return Err(GcloudUnauthenticated)
    Ok(GcloudStatus::Ready(active_account, active_project)) =>
      (active_account, active_project)
    Err(_) => return Err(GcloudUnavailable)
  }
  let accounts = match (dependencies.list_accounts)() {
    Ok(accounts) => accounts
    Err(_) => return Err(AccountEnumerationFailed)
  }
  let account = match
    (dependencies.select_account)(
      accounts,
      valid_preselected_account(accounts, active_account),
    ) {
    Ok(account) if selected_account_is_listed(accounts, account) => account
    _ => return Err(AccountSelectionInvalid)
  }
  let projects = match (dependencies.list_projects)(account) {
    Ok(projects) => projects
    Err(_) => return Err(ProjectEnumerationFailed)
  }
  let project_id = match
    resolve_project(dependencies, account, projects, active_project) {
    Ok(project_id) => project_id
    Err(error) => return Err(error)
  }
  match ensure_docs_api(dependencies, account, project_id) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match ensure_consent(dependencies, project_id) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match
    (dependencies.begin_desktop_client_handoff)(
      project_id,
      desktop_client_console_url(project_id),
    ) {
    Err(_) => return Err(DesktopClientHandoffFailed)
    Ok(_) => ()
  }
  let client_document = match (dependencies.receive_desktop_client_json)() {
    Ok(document) => document
    Err(_) => return Err(DesktopClientFileUnavailable)
  }
  match parse_installed_client(client_document) {
    Err(_) => return Err(DesktopClientFileInvalid)
    Ok(_) => ()
  }
  match (dependencies.complete_oauth)(client_document) {
    Ok(status) if status.configured && status.scope == drive_file_scope =>
      Ok(status)
    Ok(_) => Err(OAuthSetupFailed)
    Err(ProjectAuthorizationError::StorageDenied) => Err(CredentialVaultDenied)
    Err(ProjectAuthorizationError::StorageLocked) => Err(CredentialVaultLocked)
    Err(ProjectAuthorizationError::StorageMissingEntitlement) =>
      Err(CredentialVaultMissingEntitlement)
    Err(ProjectAuthorizationError::StorageUnavailable) =>
      Err(CredentialVaultUnavailable)
    Err(ProjectAuthorizationError::UnsupportedPlatform) =>
      Err(CredentialVaultUnsupported)
    Err(ProjectAuthorizationError::PreferenceUnavailable) =>
      Err(CredentialPreferenceCommitFailed)
    Err(ProjectAuthorizationError::CredentialRollbackFailed) =>
      Err(CredentialRollbackIncomplete)
    Err(ProjectAuthorizationError::StaleCredentialCleanupFailed) =>
      Err(PreviousCredentialCleanupFailed)
    Err(_) => Err(OAuthSetupFailed)
  }
}
