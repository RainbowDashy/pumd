///|
pub(all) struct PublishSuccess {
  document_id : String
  url : String
} derive(Eq, @debug.Debug)

///|
pub(all) enum PublicationRemoteStage {
  DocumentCreation
  DocumentPopulation
  DocumentRead
  DocumentUpdate
} derive(Eq, @debug.Debug)

///|
pub(all) enum AuthenticationProblem {
  CredentialsNotConfigured
  CredentialVaultDenied
  UnsupportedPlatform
  CredentialsUnavailable
  CredentialsInvalid
  CredentialsRefreshFailed
  CredentialsRejected
} derive(Eq, @debug.Debug)

///|
pub(all) enum AuthorizationMode {
  Project
  Adc
  Ephemeral
} derive(Eq, @debug.Debug)

///|
/// A locally validated and fully planned first publication. Constructing this
/// value performs every source/render/planning step and no authorization or
/// remote work, so interactive onboarding can only begin after preflight.
pub(all) struct PreparedPublication {
  title : String
  document : @pumd.DesiredDocument
  plan : DocsUpdatePlan
}

///|
pub(all) enum PublishError {
  SourceAccess(path~ : String)
  Rendering(Array[@pumd.RenderingDiagnostic])
  Planning(String)
  Authentication(
    authorization_mode~ : AuthorizationMode,
    problem~ : AuthenticationProblem,
    created_document~ : PublishSuccess?
  )
  Creation(String)
  AmbiguousCreation
  AmbiguousPopulation(PublishSuccess)
  Population(created_document~ : PublishSuccess, message~ : String)
  Permission(
    authorization_mode~ : AuthorizationMode,
    stage~ : PublicationRemoteStage,
    created_document~ : PublishSuccess?
  )
  Throttled(
    stage~ : PublicationRemoteStage,
    created_document~ : PublishSuccess?
  )
  ResponseDecode(
    stage~ : PublicationRemoteStage,
    message~ : String,
    created_document~ : PublishSuccess?
  )
  Registry(String)
  BlockedPublication(source_path~ : String)
  Read(document_id~ : String, url~ : String, message~ : String)
  RemoteMissing(document_id~ : String, url~ : String)
  PublicationConflict(message~ : String)
  ReviewBarrier(unresolved~ : Int)
  Concurrency(message~ : String)
  AmbiguousUpdate(document_id~ : String, url~ : String)
  UpdateFailed(document_id~ : String, url~ : String, message~ : String)
} derive(@debug.Debug)

///|
pub fn canonical_document_url(document_id : String) -> String {
  "https://docs.google.com/document/d/" + document_id + "/edit"
}

///|
let adc_setup_hint = "Run `gcloud auth application-default login --client-id-file=oauth-client.json --scopes=https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/drive.file`."

///|
let project_setup_hint = "Run `pumd auth setup` interactively, or `pumd auth setup --client-file oauth-client.json` with a Desktop OAuth client configuration."

///|
let ephemeral_setup_hint = "Set PUMD_ACCESS_TOKEN for this invocation and use `--auth=token-env`; pumd never stores this token."

///|
fn remote_stage_name(stage : PublicationRemoteStage) -> String {
  match stage {
    DocumentCreation => "document creation"
    DocumentPopulation => "document population"
    DocumentRead => "document read"
    DocumentUpdate => "document update"
  }
}

///|
fn format_document_identity(created_document : PublishSuccess?) -> String {
  match created_document {
    Some(document) =>
      " (document ID " + document.document_id + ", " + document.url + ")"
    None => ""
  }
}

///|
fn response_decode_recovery_guidance(
  created_document : PublishSuccess?,
) -> String {
  let inspection_target = match created_document {
    Some(_) => "Google Drive and the created document"
    None => "Google Drive"
  }
  "A remote mutation may have succeeded; inspect " +
  inspection_target +
  " before retrying. pumd will not retry automatically."
}

///|
let generic_remote_recovery_guidance = "Check the reported HTTP status: for a 5xx response, wait and retry later; otherwise report the status to the pumd maintainer before retrying."

///|
fn classified_google_error(
  authorization_mode : AuthorizationMode,
  stage : PublicationRemoteStage,
  kind : GoogleErrorKind?,
  created_document : PublishSuccess?,
) -> PublishError? {
  match kind {
    Some(Unauthenticated) =>
      Some(
        Authentication(
          authorization_mode~,
          problem=CredentialsRejected,
          created_document~,
        ),
      )
    Some(PermissionDenied) =>
      Some(Permission(authorization_mode~, stage~, created_document~))
    Some(Throttled) => Some(Throttled(stage~, created_document~))
    None => None
  }
}

///|
/// A user-facing publish failure message. Paragraphs are separated by blank
/// lines: a short summary first, then what happened and how to recover. The
/// CLI renders each paragraph wrapped and indented; embedded messages stay
/// single-line so they compose cleanly into these paragraphs.
pub fn PublishError::user_message(self : PublishError) -> String {
  match self {
    SourceAccess(path~) =>
      "source access failed: could not read or decode Markdown file `" +
      path +
      "`"
    Rendering(diagnostics) => {
      let message = StringBuilder::new()
      message.write_string("rendering failed")
      for diagnostic in diagnostics {
        message.write_string("\n- ")
        message.write_string(diagnostic.node_kind)
        message.write_string(": ")
        message.write_string(diagnostic.message)
      }
      message.to_string()
    }
    Planning(message) => "Desired Document planning failed: " + message
    Authentication(authorization_mode~, problem~, created_document~) => {
      let (explanation, hint) = match (authorization_mode, problem) {
        (Project, CredentialsNotConfigured) =>
          ("Project Authorization is not configured.", project_setup_hint)
        (Project, CredentialVaultDenied) =>
          (
            "The native credential vault is locked or denied access. Unlock it and allow pumd, then retry; no file fallback was used.",
            "",
          )
        (Project, UnsupportedPlatform) =>
          (
            "Project Authorization has no supported native credential vault on this platform.",
            "Select `--credential-store=file` explicitly only if its reduced protection is acceptable.",
          )
        (Project, CredentialsUnavailable) =>
          (
            "Project Authorization credentials are unavailable.",
            project_setup_hint,
          )
        (Project, CredentialsInvalid) =>
          (
            "Project Authorization credentials are invalid. Recreate them before retrying.",
            project_setup_hint,
          )
        (Project, CredentialsRefreshFailed) =>
          (
            "Project Authorization credentials are expired or could not be refreshed. Recreate them before retrying.",
            project_setup_hint,
          )
        (Project, CredentialsRejected) =>
          (
            "Google rejected the Project Authorization credentials; set them up again before retrying.",
            project_setup_hint,
          )
        (Adc, CredentialsUnavailable) | (Adc, CredentialsNotConfigured) =>
          ("Application Default Credentials are unavailable.", adc_setup_hint)
        (Adc, CredentialsInvalid) =>
          (
            "Application Default Credentials are invalid. Recreate them before retrying.",
            adc_setup_hint,
          )
        (Adc, CredentialsRefreshFailed) =>
          (
            "Application Default Credentials are expired or could not be refreshed. Recreate them before retrying.",
            adc_setup_hint,
          )
        (Adc, CredentialsRejected) =>
          (
            "Google rejected the Application Default Credentials; refresh ADC before retrying.",
            adc_setup_hint,
          )
        (Adc, CredentialVaultDenied) | (Adc, UnsupportedPlatform) =>
          ("Application Default Credentials are unavailable.", adc_setup_hint)
        (Ephemeral, CredentialsNotConfigured)
        | (Ephemeral, CredentialsUnavailable) =>
          (
            "An ephemeral access token was not supplied.",
            ephemeral_setup_hint,
          )
        (Ephemeral, CredentialsInvalid)
        | (Ephemeral, CredentialsRefreshFailed)
        | (Ephemeral, CredentialsRejected) =>
          (
            "The ephemeral access token is invalid or was rejected.",
            ephemeral_setup_hint,
          )
        (Ephemeral, CredentialVaultDenied) | (Ephemeral, UnsupportedPlatform) =>
          (
            "An ephemeral access token was not supplied.",
            ephemeral_setup_hint,
          )
      }
      let suffix = if hint.is_empty() { "" } else { "\n\n" + hint }
      "authentication failed" +
      format_document_identity(created_document) +
      "\n\n" +
      explanation +
      suffix
    }
    Creation(message) =>
      "document creation failed: " +
      message +
      "\n\n" +
      generic_remote_recovery_guidance
    AmbiguousCreation =>
      "document creation had an ambiguous transport outcome.\n\npumd will not retry automatically; inspect Google Drive before retrying."
    AmbiguousPopulation(created_document) =>
      "document population had an ambiguous transport outcome after creation" +
      format_document_identity(Some(created_document)) +
      ".\n\npumd will not retry automatically; inspect Google Drive before retrying."
    Population(created_document~, message~) =>
      "document population failed after creation" +
      format_document_identity(Some(created_document)) +
      ": " +
      message +
      "\n\n" +
      generic_remote_recovery_guidance
    Permission(authorization_mode~, stage~, created_document~) => {
      let guidance = match authorization_mode {
        Project =>
          "Check that Project Authorization is configured with https://www.googleapis.com/auth/drive.file."
        Adc =>
          "Check that ADC includes https://www.googleapis.com/auth/drive.file."
        Ephemeral =>
          "Check that PUMD_ACCESS_TOKEN grants https://www.googleapis.com/auth/drive.file."
      }
      remote_stage_name(stage) +
      " permission failed" +
      format_document_identity(created_document) +
      "\n\nGoogle denied permission.\n\n" +
      guidance
    }
    Throttled(stage~, created_document~) =>
      remote_stage_name(stage) +
      " was throttled" +
      format_document_identity(created_document) +
      "\n\nGoogle Docs limited the request; wait and retry later."
    ResponseDecode(stage~, message~, created_document~) =>
      remote_stage_name(stage) +
      " response decoding failed" +
      format_document_identity(created_document) +
      ": " +
      message +
      "\n\n" +
      response_decode_recovery_guidance(created_document)
    Registry(message) => "publication registry failed: " + message
    BlockedPublication(source_path~) =>
      "publication is blocked for `" +
      source_path +
      "`.\n\nInspect Google Drive and explicitly `pumd forget <path>` before retrying."
    Read(document_id~, url~, message~) =>
      "registered document readback failed (document ID " +
      document_id +
      ", " +
      url +
      ").\n\n" +
      message
    RemoteMissing(document_id~, url~) =>
      "the registered document or its Managed Tab is no longer available " +
      "(document ID " +
      document_id +
      ", " +
      url +
      ").\n\npumd will not create a replacement; restore the document or forget the Publication explicitly."
    PublicationConflict(message~) =>
      "publish blocked.\n\n" +
      message +
      "\n\npumd applied no partial updates; resolve the overlapping edits in Google Docs or revert the local change, then publish again."
    ReviewBarrier(unresolved~) =>
      "publish blocked.\n\n" +
      unresolved.to_string() +
      " unresolved review comment(s) remain in Google Docs.\n\nResolve or delete them, then publish again; pumd never bypasses review feedback."
    Concurrency(message~) =>
      "publish was interrupted by a concurrent change.\n\n" +
      message +
      "\n\nNothing was applied to the document or the local registry. Re-read the document and publish again."
    AmbiguousUpdate(document_id~, url~) =>
      "the update request had an ambiguous transport outcome (document ID " +
      document_id +
      ", " +
      url +
      ").\n\npumd re-read the document and could not confirm whether the intended state landed; run publish again to reconcile. No local state was committed."
    UpdateFailed(document_id~, url~, message~) =>
      "document update failed (document ID " +
      document_id +
      ", " +
      url +
      "): " +
      message +
      "\n\n" +
      generic_remote_recovery_guidance
  }
}

///|
async fn prepare_source_path(
  path : String,
  read_source : async (String) -> Result[String, String],
) -> Result[(String, String), PublishError] {
  let source = match read_source(path) {
    Ok(source) => source
    Err(_) => return Err(SourceAccess(path~))
  }
  Ok((source, publication_title_from_path(path)))
}

///|
/// Read, render, validate, and plan a path without touching authorization or
/// remote services.
pub async fn prepare_publication_path(
  path : String,
  read_source : async (String) -> Result[String, String],
) -> Result[PreparedPublication, PublishError] {
  let (source, title) = match prepare_source_path(path, read_source) {
    Ok(prepared) => prepared
    Err(error) => return Err(error)
  }
  prepare_publication_markdown(source, title)
}

///|
/// Render, validate, and plan Markdown without authorization or remote work.
pub fn prepare_publication_markdown(
  source : String,
  title : String,
) -> Result[PreparedPublication, PublishError] {
  let document = match @pumd.render_markdown(source) {
    Ok(document) => document
    Err(diagnostics) => return Err(Rendering(diagnostics))
  }
  let plan = match prepare_docs_update_plan(document) {
    Ok(plan) => plan
    Err(error) => return Err(Planning(error.message()))
  }
  Ok({ title, document, plan })
}

///|
async fn publish_prepared_with_authorization_providers(
  prepared : PreparedPublication,
  authorization_mode : AuthorizationMode,
  get_project_token : async () -> Result[String, AuthenticationProblem],
  get_adc_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  let get_token = match authorization_mode {
    Project => get_project_token
    Adc => get_adc_token
    Ephemeral => get_project_token
  }
  publish_prepared(prepared, authorization_mode, get_token, http)
}

///|
pub async fn publish_path(
  path : String,
  read_source : async (String) -> Result[String, String],
  get_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  publish_path_with_authorization(
    path,
    read_source,
    Adc,
    get_token,
    get_token,
    http,
  )
}

///|
/// Publish a path using exactly the provider selected by `authorization_mode`.
/// Both providers are injected so callers can compose Project Authorization and
/// ADC without giving this boundary permission to fall back between them.
pub async fn publish_path_with_authorization(
  path : String,
  read_source : async (String) -> Result[String, String],
  authorization_mode : AuthorizationMode,
  get_project_token : async () -> Result[String, AuthenticationProblem],
  get_adc_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  let prepared = match prepare_publication_path(path, read_source) {
    Ok(prepared) => prepared
    Err(error) => return Err(error)
  }
  publish_prepared_with_authorization_providers(
    prepared, authorization_mode, get_project_token, get_adc_token, http,
  )
}

///|
pub async fn publish_markdown(
  source : String,
  title : String,
  get_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  publish_markdown_with_authorization(
    source,
    title,
    Adc,
    get_token,
    get_token,
    http,
  )
}

///|
/// Render and publish Markdown with the explicitly selected authorization mode.
pub async fn publish_markdown_with_authorization(
  source : String,
  title : String,
  authorization_mode : AuthorizationMode,
  get_project_token : async () -> Result[String, AuthenticationProblem],
  get_adc_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  let prepared = match prepare_publication_markdown(source, title) {
    Ok(prepared) => prepared
    Err(error) => return Err(error)
  }
  publish_prepared_with_authorization_providers(
    prepared, authorization_mode, get_project_token, get_adc_token, http,
  )
}

///|
pub async fn publish_desired_document(
  document : @pumd.DesiredDocument,
  title : String,
  get_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  publish_desired_document_with_authorization(
    document,
    title,
    Adc,
    get_token,
    get_token,
    http,
  )
}

///|
/// Publish a prepared Desired Document using exactly one selected provider.
/// Planning completes before either provider is invoked.
pub async fn publish_desired_document_with_authorization(
  document : @pumd.DesiredDocument,
  title : String,
  authorization_mode : AuthorizationMode,
  get_project_token : async () -> Result[String, AuthenticationProblem],
  get_adc_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  let plan = match prepare_docs_update_plan(document) {
    Ok(plan) => plan
    Err(error) => return Err(Planning(error.message()))
  }
  let prepared : PreparedPublication = { title, document, plan }
  publish_prepared_with_authorization_providers(
    prepared, authorization_mode, get_project_token, get_adc_token, http,
  )
}

///|
/// Publish an already validated plan with exactly the selected token provider.
pub async fn publish_prepared(
  prepared : PreparedPublication,
  authorization_mode : AuthorizationMode,
  get_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  let token = match get_token() {
    Ok(token) => token
    Err(problem) =>
      return Err(
        Authentication(authorization_mode~, problem~, created_document=None),
      )
  }
  publish_prepared_with_token(prepared, authorization_mode, token, http)
}

///|
/// Offer first-publish setup only for a genuinely absent Project
/// Authorization, only in an interactive session, and only after callers have
/// successfully constructed `prepared`.
pub async fn publish_prepared_with_project_onboarding(
  prepared : PreparedPublication,
  interactive : Bool,
  get_project_token : async () -> Result[String, AuthenticationProblem],
  offer_setup : () -> Bool,
  setup : async () -> Result[Unit, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  match get_project_token() {
    Ok(token) => publish_prepared_with_token(prepared, Project, token, http)
    Err(CredentialsNotConfigured) if interactive =>
      if !offer_setup() {
        Err(
          Authentication(
            authorization_mode=Project,
            problem=CredentialsNotConfigured,
            created_document=None,
          ),
        )
      } else {
        match setup() {
          Ok(_) => publish_prepared(prepared, Project, get_project_token, http)
          Err(problem) =>
            Err(
              Authentication(
                authorization_mode=Project,
                problem~,
                created_document=None,
              ),
            )
        }
      }
    Err(problem) =>
      Err(
        Authentication(
          authorization_mode=Project,
          problem~,
          created_document=None,
        ),
      )
  }
}

///|
async fn publish_prepared_with_token(
  prepared : PreparedPublication,
  authorization_mode : AuthorizationMode,
  token : String,
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  let client = @google_core.GoogleClient::new(fn() { token }, http=Some(http))
  let document_id = match create_document(client, prepared.title) {
    Ok(document_id) => document_id
    Err(AdapterTransport(_)) => return Err(AmbiguousCreation)
    Err(AdapterHttpStatus(status~, kind~)) => {
      match
        classified_google_error(
          authorization_mode,
          DocumentCreation,
          kind,
          None,
        ) {
        Some(error) => return Err(error)
        None => ()
      }
      let error = AdapterHttpStatus(status~, kind~)
      return Err(Creation(error.message()))
    }
    Err(AdapterDecode(message)) =>
      return Err(
        ResponseDecode(stage=DocumentCreation, message~, created_document=None),
      )
  }
  let created_document : PublishSuccess = {
    document_id,
    url: canonical_document_url(document_id),
  }
  match batch_update_document(client, document_id, prepared.plan) {
    Ok(_) => Ok(created_document)
    Err(AdapterTransport(_)) => Err(AmbiguousPopulation(created_document))
    Err(AdapterHttpStatus(status~, kind~)) =>
      match
        classified_google_error(
          authorization_mode,
          DocumentPopulation,
          kind,
          Some(created_document),
        ) {
        Some(error) => Err(error)
        None => {
          let error = AdapterHttpStatus(status~, kind~)
          Err(Population(created_document~, message=error.message()))
        }
      }
    Err(AdapterDecode(message)) =>
      Err(
        ResponseDecode(
          stage=DocumentPopulation,
          message~,
          created_document=Some(created_document),
        ),
      )
  }
}

///|
pub async fn publish_markdown_with_adc(
  source : String,
  title : String,
) -> Result[PublishSuccess, PublishError] {
  let default_http = @google_http.DefaultHttpClient::new()
  publish_markdown(
    source,
    title,
    async fn() {
      match application_default_access_token() {
        Ok(token) => Ok(token)
        Err(Authentication(problem~, ..)) => Err(problem)
        Err(_) => Err(CredentialsInvalid)
      }
    },
    default_http,
  )
}

///|
pub async fn publish_path_with_adc(
  path : String,
  read_source : async (String) -> Result[String, String],
) -> Result[PublishSuccess, PublishError] {
  let (source, title) = match prepare_source_path(path, read_source) {
    Ok(prepared) => prepared
    Err(error) => return Err(error)
  }
  publish_markdown_with_adc(source, title)
}

///|
fn google_auth_problem(
  error : @googleauth.AuthenticationError,
) -> AuthenticationProblem {
  match error {
    @googleauth.AuthenticationError::NoValidCredentials =>
      CredentialsUnavailable
    @googleauth.AuthenticationError::MetadataServerError(_) =>
      CredentialsUnavailable
    @googleauth.AuthenticationError::InvalidCredentials(_) => CredentialsInvalid
  }
}

///|
async fn detect_googleauth_client() -> Result[
  @googleauth.GoogleAuthClient,
  AuthenticationProblem,
] {
  match @googleauth.auto_detect_and_authenticate() {
    Ok(client) => Ok(client)
    Err(error) => Err(google_auth_problem(error))
  }
}

///|
async fn acquire_googleauth_token(
  client : @googleauth.GoogleAuthClient,
) -> Result[String, AuthenticationProblem] {
  match @googleauth.get_access_token(client) {
    Ok(token) => Ok(token)
    Err(@googleauth.AuthenticationError::NoValidCredentials) =>
      Err(CredentialsUnavailable)
    Err(_) => Err(CredentialsRefreshFailed)
  }
}

///|
/// Testable composition seam around googleauth's two-step ADC contract. The
/// production wrapper below owns dependency-error mapping; this function owns
/// sequencing and converts the mapped result into pumd's public error model.
async fn application_default_access_token_with(
  detect_credentials : async () -> Result[
    @googleauth.GoogleAuthClient,
    AuthenticationProblem,
  ],
  acquire_token : async (@googleauth.GoogleAuthClient) -> Result[
    String,
    AuthenticationProblem,
  ],
) -> Result[String, PublishError] {
  let auth_client = match detect_credentials() {
    Ok(client) => client
    Err(problem) =>
      return Err(
        Authentication(authorization_mode=Adc, problem~, created_document=None),
      )
  }
  match acquire_token(auth_client) {
    Ok(token) => Ok(token)
    Err(problem) =>
      Err(
        Authentication(authorization_mode=Adc, problem~, created_document=None),
      )
  }
}

///|
pub async fn application_default_access_token() -> Result[String, PublishError] {
  application_default_access_token_with(
    detect_googleauth_client, acquire_googleauth_token,
  )
}
