///|
pub(all) struct PublishSuccess {
  document_id : String
  url : String
} derive(Eq, @debug.Debug)

///|
pub(all) enum PublishError {
  Rendering(Array[@pumd.RenderingDiagnostic])
  Authentication(String)
  Creation(String)
  AmbiguousCreation(String)
  Population(document_id~ : String, url~ : String, message~ : String)
  ResponseDecode(
    stage~ : String,
    message~ : String,
    document_id~ : String?,
    url~ : String?
  )
} derive(@debug.Debug)

///|
pub fn canonical_document_url(document_id : String) -> String {
  "https://docs.google.com/document/d/" + document_id + "/edit"
}

///|
let adc_setup_hint = "Run `gcloud auth application-default login --client-id-file=oauth-client.json --scopes=https://www.googleapis.com/auth/drive.file`."

///|
pub fn PublishError::user_message(self : PublishError) -> String {
  match self {
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
    Authentication(message) => "authentication failed: " + message
    Creation(message) => "document creation failed: " + message
    AmbiguousCreation(message) =>
      "document creation had an ambiguous transport outcome; pumd will not retry automatically: " +
      message
    Population(document_id~, url~, message~) =>
      "document population failed after creation (document ID " +
      document_id +
      ", " +
      url +
      "): " +
      message
    ResponseDecode(stage~, message~, document_id~, url~) => {
      let identity = match (document_id, url) {
        (Some(id), Some(edit_url)) =>
          " (document ID " + id + ", " + edit_url + ")"
        _ => ""
      }
      stage + " response decoding failed" + identity + ": " + message
    }
  }
}

///|
pub async fn publish_markdown(
  source : String,
  title : String,
  get_token : async () -> Result[String, String],
  http : &@google_http.HttpClient,
) -> Result[PublishSuccess, PublishError] {
  let document = match @pumd.render_markdown(source) {
    Ok(document) => document
    Err(diagnostics) => return Err(Rendering(diagnostics))
  }
  let plan = compile_docs_update_plan(document)
  let token = match get_token() {
    Ok(token) => token
    Err(message) => return Err(Authentication(message))
  }
  let client = @google_core.GoogleClient::new(fn() { token }, http=Some(http))
  let document_id = match create_document(client, title) {
    Ok(document_id) => document_id
    Err(AdapterTransport(message)) => return Err(AmbiguousCreation(message))
    Err(AdapterHttpStatus(status~, body~)) =>
      return Err(Creation("HTTP " + status.to_string() + ": " + body))
    Err(AdapterDecode(message)) =>
      return Err(
        ResponseDecode(stage="creation", message~, document_id=None, url=None),
      )
  }
  let url = canonical_document_url(document_id)
  match batch_update_document(client, document_id, plan) {
    Ok(_) => Ok({ document_id, url })
    Err(AdapterDecode(message)) =>
      Err(
        ResponseDecode(
          stage="population",
          message~,
          document_id=Some(document_id),
          url=Some(url),
        ),
      )
    Err(error) => Err(Population(document_id~, url~, message=error.message()))
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
        Err(Authentication(message)) => Err(message)
        Err(error) => Err(error.user_message())
      }
    },
    default_http,
  )
}

///|
fn google_auth_error_message(error : @googleauth.AuthenticationError) -> String {
  match error {
    @googleauth.AuthenticationError::NoValidCredentials =>
      "no valid credentials were found"
    @googleauth.AuthenticationError::MetadataServerError(message) => message
    @googleauth.AuthenticationError::InvalidCredentials(message) => message
  }
}

///|
pub async fn application_default_access_token() -> Result[String, PublishError] {
  let auth_client = match @googleauth.auto_detect_and_authenticate() {
    Ok(client) => client
    Err(error) =>
      return Err(
        Authentication(
          "Application Default Credentials are unavailable. " +
          adc_setup_hint +
          " Detail: " +
          google_auth_error_message(error),
        ),
      )
  }
  match @googleauth.get_access_token(auth_client) {
    Ok(token) => Ok(token)
    Err(error) =>
      Err(
        Authentication(
          "Application Default Credentials could not be refreshed. " +
          adc_setup_hint +
          " Detail: " +
          google_auth_error_message(error),
        ),
      )
  }
}
