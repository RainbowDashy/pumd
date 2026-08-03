///|
/// Captured process state for the narrow, injectable gcloud boundary. Process
/// text is intentionally used only for structured parsing and is never copied
/// into an adapter error.
pub(all) struct GcloudProcessResult {
  launched : Bool
  exit_code : Int
  stdout : String
  stderr : String
}

///|
/// A gcloud adapter whose process boundary can be replaced with fixture data.
pub(all) struct GcloudAdapter {
  run : async (Array[String]) -> GcloudProcessResult
}

///|
/// Build a gcloud adapter around an injected command runner.
pub fn gcloud_adapter_with_runner(
  run : async (Array[String]) -> GcloudProcessResult,
) -> GcloudAdapter {
  { run, }
}

///|
/// Build the production gcloud adapter. The runner discards subprocess output
/// on process/decode failure so it cannot reach a user-facing error.
pub fn production_gcloud_adapter() -> GcloudAdapter {
  gcloud_adapter_with_runner(async fn(arguments) {
    let (exit_code, stdout, stderr) = @process.collect_output(
      "gcloud", arguments,
    ) catch {
      _ => return { launched: false, exit_code: -1, stdout: "", stderr: "" }
    }
    let stdout = stdout.text() catch { _ => "" }
    let stderr = stderr.text() catch { _ => "" }
    { launched: true, exit_code, stdout, stderr }
  })
}

///|
fn successful(result : GcloudProcessResult) -> Bool {
  result.launched && result.exit_code == 0
}

///|
fn parse_accounts(output : String) -> Result[Array[CloudAccount], Unit] {
  let json = @json.parse(output) catch { _ => return Err(()) }
  let values = match json {
    Array(values) => values
    _ => return Err(())
  }
  let accounts : Array[CloudAccount] = []
  for value in values {
    let fields = match value {
      Object(fields) => fields
      _ => return Err(())
    }
    let email = match fields.get("account") {
      Some(String(email)) if !email.is_empty() => email
      _ => return Err(())
    }
    accounts.push({ email, })
  }
  Ok(accounts)
}

///|
fn active_account(output : String) -> Result[String?, Unit] {
  let json = @json.parse(output) catch { _ => return Err(()) }
  let values = match json {
    Array(values) => values
    _ => return Err(())
  }
  for value in values {
    let fields = match value {
      Object(fields) => fields
      _ => return Err(())
    }
    let email = match fields.get("account") {
      Some(String(email)) if !email.is_empty() => email
      _ => return Err(())
    }
    match fields.get("status") {
      Some(String("ACTIVE")) => return Ok(Some(email))
      Some(String(_)) => ()
      Some(_) => return Err(())
      None => ()
    }
  }
  Ok(None)
}

///|
fn active_project(output : String) -> String? {
  let project_id = output.trim(chars=" \t\n\r").to_owned()
  if project_id.is_empty() || project_id == "(unset)" {
    None
  } else {
    Some(project_id)
  }
}

///|
/// Detect whether gcloud is runnable and has a usable signed-in account. The
/// access-token command validates credentials; its standard output is ignored.
pub async fn GcloudAdapter::inspect(
  self : GcloudAdapter,
) -> Result[GcloudStatus, GuidedSetupError] {
  let accounts = (self.run)(["auth", "list", "--format=json", "--quiet"])
  if !accounts.launched {
    return Ok(GcloudStatus::Missing)
  }
  if accounts.exit_code != 0 {
    return Err(GuidedSetupError::AccountEnumerationFailed)
  }
  let active_account = match active_account(accounts.stdout) {
    Ok(active_account) => active_account
    Err(_) => return Err(GuidedSetupError::AccountEnumerationFailed)
  }
  if active_account is None {
    return Ok(GcloudStatus::Unauthenticated)
  }
  let token = (self.run)(["auth", "print-access-token", "--quiet"])
  if !token.launched {
    return Ok(GcloudStatus::Missing)
  }
  if token.exit_code != 0 {
    return Ok(GcloudStatus::Unauthenticated)
  }
  let configured_project = (self.run)([
    "config", "get", "core/project", "--quiet",
  ])
  let active_project = if successful(configured_project) {
    active_project(configured_project.stdout)
  } else {
    None
  }
  Ok(GcloudStatus::Ready(active_account, active_project))
}

///|
pub async fn GcloudAdapter::list_accounts(
  self : GcloudAdapter,
) -> Result[Array[CloudAccount], GuidedSetupError] {
  let result = (self.run)(["auth", "list", "--format=json", "--quiet"])
  if !successful(result) {
    return Err(GuidedSetupError::AccountEnumerationFailed)
  }
  match parse_accounts(result.stdout) {
    Ok(accounts) => Ok(accounts)
    Err(_) => Err(GuidedSetupError::AccountEnumerationFailed)
  }
}

///|
fn availability(lifecycle_state : String) -> ProjectAvailability {
  match lifecycle_state {
    "ACTIVE" => ProjectAvailability::Available
    "SUSPENDED" => ProjectAvailability::Suspended
    _ => ProjectAvailability::Inaccessible
  }
}

///|
fn parse_project(value : Json) -> Result[CloudProject, Unit] {
  let fields = match value {
    Object(fields) => fields
    _ => return Err(())
  }
  let project_id = match fields.get("projectId") {
    Some(String(project_id)) if !project_id.is_empty() => project_id
    _ => return Err(())
  }
  let display_name = match fields.get("name") {
    Some(String(name)) if !name.is_empty() => name
    _ => return Err(())
  }
  let lifecycle_state = match fields.get("lifecycleState") {
    Some(String(lifecycle_state)) if !lifecycle_state.is_empty() =>
      lifecycle_state
    _ => return Err(())
  }
  Ok({ project_id, display_name, availability: availability(lifecycle_state) })
}

///|
fn parse_projects(output : String) -> Result[Array[CloudProject], Unit] {
  let json = @json.parse(output) catch { _ => return Err(()) }
  let values = match json {
    Array(values) => values
    _ => return Err(())
  }
  let projects : Array[CloudProject] = []
  for value in values {
    match parse_project(value) {
      Ok(project) => projects.push(project)
      Err(_) => return Err(())
    }
  }
  Ok(projects)
}

///|
/// List projects for the selected account without changing gcloud's active
/// account or configuration.
pub async fn GcloudAdapter::list_projects(
  self : GcloudAdapter,
  account : String,
) -> Result[Array[CloudProject], GuidedSetupError] {
  let result = (self.run)([
    "projects",
    "list",
    "--format=json",
    "--quiet",
    "--account=" + account,
  ])
  if !successful(result) {
    return Err(GuidedSetupError::ProjectEnumerationFailed)
  }
  match parse_projects(result.stdout) {
    Ok(projects) => Ok(projects)
    Err(_) => Err(GuidedSetupError::ProjectEnumerationFailed)
  }
}

///|
pub async fn GcloudAdapter::create_project(
  self : GcloudAdapter,
  account : String,
  request : NewCloudProject,
) -> Result[CloudProject, GuidedSetupError] {
  let result = (self.run)([
    "projects",
    "create",
    request.project_id,
    "--name=" + request.display_name,
    "--no-enable-cloud-apis",
    "--format=json",
    "--quiet",
    "--account=" + account,
  ])
  if !successful(result) {
    return Err(GuidedSetupError::ProjectCreationFailed)
  }
  match
    parse_project(
      @json.parse(result.stdout) catch {
        _ => return Err(GuidedSetupError::ProjectCreationFailed)
      },
    ) {
    Ok(project) if project.availability is ProjectAvailability::Available =>
      Ok(project)
    _ => Err(GuidedSetupError::ProjectCreationFailed)
  }
}

///|
fn docs_api_enabled(output : String) -> Result[Bool, Unit] {
  let json = @json.parse(output) catch { _ => return Err(()) }
  let values = match json {
    Array(values) => values
    _ => return Err(())
  }
  for value in values {
    let service = match value {
      Object(service) => service
      _ => return Err(())
    }
    let config = match service.get("config") {
      Some(Object(config)) => config
      _ => return Err(())
    }
    let name = match config.get("name") {
      Some(String(name)) => name
      _ => return Err(())
    }
    if name == google_docs_api {
      return Ok(true)
    }
  }
  Ok(false)
}

///|
fn docs_api_list_command(
  project_id : String,
  account : String,
) -> Array[String] {
  [
    "services",
    "list",
    "--enabled",
    "--project=" + project_id,
    "--filter=config.name=docs.googleapis.com",
    "--format=json",
    "--quiet",
    "--account=" + account,
  ]
}

///|
pub async fn GcloudAdapter::inspect_docs_api(
  self : GcloudAdapter,
  account : String,
  project_id : String,
) -> Result[Bool, GuidedSetupError] {
  let result = (self.run)(docs_api_list_command(project_id, account))
  if !successful(result) {
    return Err(GuidedSetupError::DocsApiInspectionFailed)
  }
  match docs_api_enabled(result.stdout) {
    Ok(enabled) => Ok(enabled)
    Err(_) => Err(GuidedSetupError::DocsApiInspectionFailed)
  }
}

///|
/// Enable exactly the Docs API when it is absent, then re-inspect it before
/// reporting success. A rerun against an enabled service performs no mutation.
pub async fn GcloudAdapter::enable_docs_api(
  self : GcloudAdapter,
  account : String,
  project_id : String,
) -> Result[Unit, GuidedSetupError] {
  match self.inspect_docs_api(account, project_id) {
    Ok(true) => return Ok(())
    Ok(false) => ()
    Err(_) => return Err(GuidedSetupError::DocsApiInspectionFailed)
  }
  let result = (self.run)([
    "services",
    "enable",
    google_docs_api,
    "--project=" + project_id,
    "--quiet",
    "--account=" + account,
  ])
  if !successful(result) {
    return Err(GuidedSetupError::DocsApiEnablementFailed)
  }
  match self.inspect_docs_api(account, project_id) {
    Ok(true) => Ok(())
    Ok(false) => Err(GuidedSetupError::DocsApiEnablementFailed)
    Err(_) => Err(GuidedSetupError::DocsApiInspectionFailed)
  }
}
