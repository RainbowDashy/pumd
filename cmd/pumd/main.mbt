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
) -> Result[String, @publish.AuthenticationProblem] {
  match @authorization.project_access_token_production(http) {
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
    @args.Authorization::Project => @publish.AuthorizationMode::Project
    @args.Authorization::Adc => @publish.AuthorizationMode::Adc
  }
  match
    @publish.publish_path_with_authorization(
      path,
      fn(source_path) { read_source(source_path) },
      mode,
      async fn() { project_access_token(http) },
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
async fn setup_project_authorization(client_file : String) -> Unit {
  let client_document = @fs.read_file_to_string(client_file) catch {
    @fs.IOError(_) =>
      return report_failure(
        "Project Authorization client file could not be read: `" +
        client_file +
        "`",
      )
  }
  let http = @google_http.DefaultHttpClient::new()
  match
    @authorization.setup_project_authorization_production(client_document, http) {
    Ok(status) => {
      @stdio.stdout.write("Project Authorization setup complete.\n")
      @stdio.stdout.write("credential store: file\n")
      @stdio.stdout.write("scope: " + status.scope + "\n")
    }
    Err(error) => report_failure(error.user_message())
  }
}

///|
async fn report_project_authorization_status() -> Unit {
  let http = @google_http.DefaultHttpClient::new()
  match @authorization.project_authorization_status_production(http) {
    Ok(status) => {
      let usability = if status.configured {
        "usable"
      } else {
        "not configured"
      }
      @stdio.stdout.write("Project Authorization: " + usability + "\n")
      @stdio.stdout.write("credential store: file\n")
      @stdio.stdout.write("scope: " + status.scope + "\n")
    }
    Err(error) => report_failure(error.user_message())
  }
}

///|
async fn main {
  match @args.parse_command(@sys.get_cli_args()) {
    Ok(@args.Command::Publish(path, authorization)) =>
      publish_file(path, authorization)
    Ok(@args.Command::AuthSetup(client_file, @args.CredentialStore::File)) =>
      setup_project_authorization(client_file)
    Ok(@args.Command::AuthStatus) => report_project_authorization_status()
    Err(message) => report_failure(message)
  }
}
