///|
pub(all) struct PublishSuccess {
  document_id : String
  url : String
} derive(Eq, @debug.Debug)

///|
pub(all) enum PublicationRemoteStage {
  DocumentCreation
  DocumentPopulation
} derive(Eq, @debug.Debug)

///|
pub(all) enum AuthenticationProblem {
  CredentialsUnavailable
  CredentialsInvalid
  CredentialsRefreshFailed
  CredentialsRejected
} derive(Eq, @debug.Debug)

///|
pub(all) enum PublishError {
  SourceAccess(path~ : String)
  Rendering(Array[@pumd.RenderingDiagnostic])
  Planning(String)
  Authentication(
    problem~ : AuthenticationProblem,
    created_document~ : PublishSuccess?
  )
  Creation(String)
  AmbiguousCreation
  AmbiguousPopulation(PublishSuccess)
  Population(created_document~ : PublishSuccess, message~ : String)
  Permission(
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
} derive(@debug.Debug)

///|
pub fn canonical_document_url(document_id : String) -> String {
  "https://docs.google.com/document/d/" + document_id + "/edit"
}

///|
let adc_setup_hint = "Run `gcloud auth application-default login --client-id-file=oauth-client.json --scopes=https://www.googleapis.com/auth/drive.file`."

///|
fn remote_stage_name(stage : PublicationRemoteStage) -> String {
  match stage {
    DocumentCreation => "document creation"
    DocumentPopulation => "document population"
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
  " A remote mutation may have succeeded; inspect " +
  inspection_target +
  " before retrying. pumd will not retry automatically."
}

///|
let generic_remote_recovery_guidance = " Check the reported HTTP status: for a 5xx response, wait and retry later; otherwise report the status to the pumd maintainer before retrying."

///|
fn classified_google_error(
  stage : PublicationRemoteStage,
  kind : GoogleErrorKind?,
  created_document : PublishSuccess?,
) -> PublishError? {
  match kind {
    Some(Unauthenticated) =>
      Some(Authentication(problem=CredentialsRejected, created_document~))
    Some(PermissionDenied) => Some(Permission(stage~, created_document~))
    Some(Throttled) => Some(Throttled(stage~, created_document~))
    None => None
  }
}

///|
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
    Authentication(problem~, created_document~) => {
      let guidance = match problem {
        CredentialsUnavailable =>
          "Application Default Credentials are unavailable. " + adc_setup_hint
        CredentialsInvalid =>
          "Application Default Credentials are invalid. Recreate them before retrying. " +
          adc_setup_hint
        CredentialsRefreshFailed =>
          "Application Default Credentials are expired or could not be refreshed. Recreate them before retrying. " +
          adc_setup_hint
        CredentialsRejected =>
          "Google rejected the Application Default Credentials; refresh ADC before retrying. " +
          adc_setup_hint
      }
      "authentication failed" +
      format_document_identity(created_document) +
      ": " +
      guidance
    }
    Creation(message) =>
      "document creation failed: " + message + generic_remote_recovery_guidance
    AmbiguousCreation =>
      "document creation had an ambiguous transport outcome. pumd will not retry automatically; inspect Google Drive before retrying."
    AmbiguousPopulation(created_document) =>
      "document population had an ambiguous transport outcome after creation" +
      format_document_identity(Some(created_document)) +
      ". pumd will not retry automatically; inspect Google Drive before retrying."
    Population(created_document~, message~) =>
      "document population failed after creation" +
      format_document_identity(Some(created_document)) +
      ": " +
      message +
      generic_remote_recovery_guidance
    Permission(stage~, created_document~) =>
      remote_stage_name(stage) +
      " permission failed" +
      format_document_identity(created_document) +
      ": Google denied permission. Check that ADC includes https://www.googleapis.com/auth/drive.file."
    Throttled(stage~, created_document~) =>
      remote_stage_name(stage) +
      " was throttled" +
      format_document_identity(created_document) +
      ": Google Docs limited the request; wait and retry later."
    ResponseDecode(stage~, message~, created_document~) =>
      remote_stage_name(stage) +
      " response decoding failed" +
      format_document_identity(created_document) +
      ": " +
      message +
      response_decode_recovery_guidance(created_document)
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
pub async fn publish_path(
  path : String,
  read_source : async (String) -> Result[String, String],
  get_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  let (source, title) = match prepare_source_path(path, read_source) {
    Ok(prepared) => prepared
    Err(error) => return Err(error)
  }
  publish_markdown(source, title, get_token, http)
}

///|
pub async fn publish_markdown(
  source : String,
  title : String,
  get_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  let document = match @pumd.render_markdown(source) {
    Ok(document) => document
    Err(diagnostics) => return Err(Rendering(diagnostics))
  }
  publish_desired_document(document, title, get_token, http)
}

///|
pub async fn publish_desired_document(
  document : @pumd.DesiredDocument,
  title : String,
  get_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  let plan = match prepare_docs_update_plan(document) {
    Ok(plan) => plan
    Err(error) => return Err(Planning(error.message()))
  }
  let token = match get_token() {
    Ok(token) => token
    Err(problem) => return Err(Authentication(problem~, created_document=None))
  }
  let client = @google_core.GoogleClient::new(fn() { token }, http=Some(http))
  let document_id = match create_document(client, title) {
    Ok(document_id) => document_id
    Err(AdapterTransport(_)) => return Err(AmbiguousCreation)
    Err(AdapterHttpStatus(status~, kind~)) => {
      match classified_google_error(DocumentCreation, kind, None) {
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
  match batch_update_document(client, document_id, plan) {
    Ok(_) => Ok(created_document)
    Err(AdapterTransport(_)) => Err(AmbiguousPopulation(created_document))
    Err(AdapterHttpStatus(status~, kind~)) =>
      match
        classified_google_error(
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
pub async fn application_default_access_token() -> Result[String, PublishError] {
  let auth_client = match @googleauth.auto_detect_and_authenticate() {
    Ok(client) => client
    Err(error) =>
      return Err(
        Authentication(
          problem=google_auth_problem(error),
          created_document=None,
        ),
      )
  }
  match @googleauth.get_access_token(auth_client) {
    Ok(token) => Ok(token)
    Err(error) =>
      Err(
        Authentication(
          problem=match error {
            @googleauth.AuthenticationError::NoValidCredentials =>
              CredentialsUnavailable
            _ => CredentialsRefreshFailed
          },
          created_document=None,
        ),
      )
  }
}
