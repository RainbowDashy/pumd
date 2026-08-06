///|
/// The exact Google Cloud Console destinations opened by guided Project
/// Authorization setup. Google handles sign-in, project selection, Docs API
/// enablement, and Desktop OAuth client creation in the browser; pumd never
/// enumerates, creates, or mutates cloud resources itself.
pub(all) struct ProjectConsoleHandoff {
  enable_docs_api_url : String
  enable_drive_api_url : String
  oauth_clients_url : String
}

///|
/// The concrete Cloud Console destinations for a browser-first setup run.
pub let project_console_handoff : ProjectConsoleHandoff = {
  enable_docs_api_url: "https://console.cloud.google.com/flows/enableapi?apiid=docs.googleapis.com",
  enable_drive_api_url: "https://console.cloud.google.com/flows/enableapi?apiid=drive.googleapis.com",
  oauth_clients_url: "https://console.cloud.google.com/auth/clients",
}

///|
/// The typed outcome of the injected Cloud Console handoff. `Cancelled`
/// means the user declined the handoff; `Unavailable` means the environment
/// could not open it.
pub(all) enum ProjectConsoleHandoffError {
  Cancelled
  Unavailable
}

///|
/// Safe, actionable failures from the guided Project Authorization orchestration.
/// No branch incorporates adapter output, so process output and OAuth material
/// cannot appear in messages.
pub(all) enum GuidedSetupError {
  Cancelled
  ConsoleHandoffFailed
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
    Cancelled =>
      "Project Authorization setup was cancelled before OAuth was completed."
    ConsoleHandoffFailed =>
      "Project Authorization could not open Google Cloud Console. Enable the Google Docs and Google Drive APIs and create a Desktop OAuth client, then run setup again."
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
/// All external behavior is injected. The adapter owns the Cloud Console
/// handoff, Desktop client JSON receipt, and OAuth completion; this module
/// owns only ordering, validation, and safe failure mapping.
pub(all) struct GuidedSetupDependencies {
  complete_project_console_handoff : async (ProjectConsoleHandoff) -> Result[
    Unit,
    ProjectConsoleHandoffError,
  ]
  receive_desktop_client_json : async () -> Result[String, Unit]
  // This callback must preserve any prior Project Authorization if it fails.
  complete_oauth : async (String) -> Result[
    ProjectAuthorizationStatus,
    ProjectAuthorizationError,
  ]
}

///|
/// Run the pure guided Project Authorization state machine. The Cloud Console
/// handoff opens the Docs API enablement and OAuth client destinations; the
/// user's downloaded Desktop client JSON is validated locally before direct
/// OAuth. No cloud project is enumerated, created, or mutated by pumd, and the
/// Desktop client's own `project_id` is never requested here.
pub async fn guide_project_authorization(
  dependencies : GuidedSetupDependencies,
) -> Result[ProjectAuthorizationStatus, GuidedSetupError] {
  match
    (dependencies.complete_project_console_handoff)(project_console_handoff) {
    Err(ProjectConsoleHandoffError::Cancelled) => return Err(Cancelled)
    Err(ProjectConsoleHandoffError::Unavailable) =>
      return Err(ConsoleHandoffFailed)
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
