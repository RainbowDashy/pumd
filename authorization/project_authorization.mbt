///|
/// A validated Google Desktop OAuth client used for Project Authorization.
pub(all) struct InstalledClient {
  client_id : String
  client_secret : String
  auth_uri : String
  token_uri : String
}

///|
/// A safe, actionable Project Authorization failure.
pub(all) enum ProjectAuthorizationError {
  InvalidClientFile(String)
  SetupFailed(String)
  ReauthorizationRequired
  StorageUnavailable
}

///|
pub fn ProjectAuthorizationError::user_message(
  self : ProjectAuthorizationError,
) -> String {
  match self {
    InvalidClientFile(message) =>
      "Project Authorization client file is invalid: " + message
    SetupFailed(message) => "Project Authorization setup failed: " + message
    ReauthorizationRequired =>
      "Project Authorization needs reauthorization. Run `pumd auth setup --client-file <path> --credential-store=file`."
    StorageUnavailable =>
      "Project Authorization credential store is unavailable."
  }
}

///|
/// The only Google scope used by Project Authorization.
pub let drive_file_scope = "https://www.googleapis.com/auth/drive.file"

///|
/// A durable Project Authorization grant. It deliberately has no access token.
pub(all) struct StoredAuthorization {
  version : Int
  client_id : String
  client_secret : String
  refresh_token : String
  token_uri : String
  scope : String
}

///|
/// The safe data reported by `project_authorization_status`.
pub(all) struct ProjectAuthorizationStatus {
  configured : Bool
  client_id : String?
  token_uri : String?
  scope : String
}

///|
/// The token material returned by an OAuth token endpoint.
pub(all) struct OAuthToken {
  access_token : String
  refresh_token : String?
}

///|
/// The authorization-code exchange supplied to the OAuth HTTP seam.
pub(all) struct TokenExchangeRequest {
  client_id : String
  client_secret : String
  token_uri : String
  code : String
  code_verifier : String
  redirect_uri : String
  scope : String
}

///|
/// The refresh request supplied to the OAuth HTTP seam.
pub(all) struct TokenRefreshRequest {
  client_id : String
  client_secret : String
  token_uri : String
  refresh_token : String
  scope : String
}

///|
/// An injectable store. `replace` must atomically preserve the old grant on failure.
pub(all) struct CredentialStore {
  load : async () -> Result[StoredAuthorization, String]
  replace : async (StoredAuthorization) -> Result[Unit, String]
}

///|
/// A loopback listener already bound to the local callback port.
pub(all) struct LoopbackCallback {
  redirect_uri : String
  await_callback : async () -> Result[String, String]
}

///|
/// All effectful collaborators at the Project Authorization setup seam.
pub(all) struct SetupDependencies {
  random_bytes : (Int) -> Result[Bytes, String]
  start_listener : async () -> Result[LoopbackCallback, String]
  launch_browser : async (String) -> Result[Unit, String]
  report_authorization_url : (String) -> Unit
  exchange_code : async (TokenExchangeRequest) -> Result[OAuthToken, String]
  store : CredentialStore
}

///|
/// Create random bytes from the platform CSPRNG; there is intentionally no fallback.
pub fn secure_random_bytes(
  size : Int,
) -> Result[Bytes, ProjectAuthorizationError] {
  match @env.rand(size) {
    Some(bytes) => Ok(bytes)
    None => Err(SetupFailed("secure random bytes are unavailable"))
  }
}

///|
fn base64url(bytes : BytesView) -> String {
  let padded = @base64.encode(bytes, url_safe=true)
  let output = StringBuilder::new()
  for c in padded {
    if c != '=' {
      output.write_char(c)
    }
  }
  output.to_string()
}

///|
fn pkce_challenge(verifier : String) -> String {
  let digest = @crypto.sha256(@utf8.encode(verifier))
  base64url(Bytes::from_array(digest)[:])
}

///|
fn url_encode(value : String) -> String {
  let output = StringBuilder::new()
  for byte in @utf8.encode(value) {
    let n = byte.to_int()
    if (n >= 65 && n <= 90) ||
      (n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      n == 45 ||
      n == 46 ||
      n == 95 ||
      n == 126 {
      output.write_char(n.unsafe_to_char())
    } else {
      output.write_char('%')
      output.write_string(byte.to_hex())
    }
  }
  output.to_string()
}

///|
fn authorization_url(
  client : InstalledClient,
  callback : LoopbackCallback,
  state : String,
  verifier : String,
) -> String {
  client.auth_uri +
  "?response_type=code&client_id=" +
  url_encode(client.client_id) +
  "&redirect_uri=" +
  url_encode(callback.redirect_uri) +
  "&scope=" +
  url_encode(drive_file_scope) +
  "&state=" +
  url_encode(state) +
  "&code_challenge=" +
  url_encode(pkce_challenge(verifier)) +
  "&code_challenge_method=S256&access_type=offline&prompt=consent"
}

///|
fn required_callback_value(
  values : Map[String, String],
  name : String,
) -> Result[String, ProjectAuthorizationError] {
  match values.get(name) {
    Some(value) if !value.is_empty() => Ok(value)
    _ => Err(SetupFailed("callback is missing `" + name + "`"))
  }
}

///|
fn hex_value(character : Char) -> Int? {
  match character {
    '0'..='9' => Some(character.to_int() - '0')
    'a'..='f' => Some(character.to_int() - 'a' + 10)
    'A'..='F' => Some(character.to_int() - 'A' + 10)
    _ => None
  }
}

///|
/// Decode the ASCII OAuth query encoding and reject malformed escapes.
fn decode_callback_component(
  value : String,
) -> Result[String, ProjectAuthorizationError] {
  let chars = value.to_array()
  let output = StringBuilder::new()
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '%' {
      if index + 2 >= chars.length() {
        return Err(SetupFailed("callback has malformed percent encoding"))
      }
      let hi = match hex_value(chars[index + 1]) {
        Some(n) => n
        _ => return Err(SetupFailed("callback has malformed percent encoding"))
      }
      let lo = match hex_value(chars[index + 2]) {
        Some(n) => n
        _ => return Err(SetupFailed("callback has malformed percent encoding"))
      }
      output.write_char((hi * 16 + lo).unsafe_to_char())
      index = index + 3
    } else {
      output.write_char(if chars[index] == '+' { ' ' } else { chars[index] })
      index = index + 1
    }
  }
  Ok(output.to_string())
}

///|
/// Parse the narrow OAuth callback query; duplicate fields are rejected.
pub fn parse_callback_query(
  query : String,
  expected_state : String,
) -> Result[String, ProjectAuthorizationError] {
  let values : Map[String, String] = Map([])
  for part in query.split("&") {
    match part.to_owned().split_once("=") {
      Some((key, value)) => {
        let key = match decode_callback_component(key.to_owned()) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        if values.get(key) is Some(_) {
          return Err(SetupFailed("callback contains duplicate `" + key + "`"))
        }
        let value = match decode_callback_component(value.to_owned()) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        values.set(key, value)
      }
      None => return Err(SetupFailed("callback query is malformed"))
    }
  }
  if values.get("error") is Some(_) {
    return Err(SetupFailed("Google denied or cancelled Project Authorization"))
  }
  let state = match required_callback_value(values, "state") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if state != expected_state {
    return Err(
      SetupFailed("callback state did not match the authorization request"),
    )
  }
  required_callback_value(values, "code")
}

///|
/// Complete direct installed-app OAuth and replace a stored Project Authorization only on success.
pub async fn setup_project_authorization(
  client_document : String,
  dependencies : SetupDependencies,
) -> Result[ProjectAuthorizationStatus, ProjectAuthorizationError] {
  let client = match parse_installed_client(client_document) {
    Ok(client) => client
    Err(error) => return Err(error)
  }
  let state = match (dependencies.random_bytes)(32) {
    Ok(bytes) => base64url(bytes[:])
    Err(_) => return Err(SetupFailed("secure random state generation failed"))
  }
  let verifier = match (dependencies.random_bytes)(48) {
    Ok(bytes) => base64url(bytes[:])
    Err(_) => return Err(SetupFailed("secure random PKCE generation failed"))
  }
  let callback = match (dependencies.start_listener)() {
    Ok(callback) => callback
    Err(_) =>
      return Err(SetupFailed("could not start the local loopback listener"))
  }
  let url = authorization_url(client, callback, state, verifier)
  match (dependencies.launch_browser)(url) {
    Ok(_) => ()
    Err(_) => (dependencies.report_authorization_url)(url)
  }
  let callback_query = match (callback.await_callback)() {
    Ok(query) => query
    Err(_) => return Err(SetupFailed("did not receive a local OAuth callback"))
  }
  let code = match parse_callback_query(callback_query, state) {
    Ok(code) => code
    Err(error) => return Err(error)
  }
  let token = match
    (dependencies.exchange_code)({
      client_id: client.client_id,
      client_secret: client.client_secret,
      token_uri: client.token_uri,
      code,
      code_verifier: verifier,
      redirect_uri: callback.redirect_uri,
      scope: drive_file_scope,
    }) {
    Ok(token) => token
    Err(_) => return Err(SetupFailed("OAuth code exchange failed"))
  }
  if token.access_token.is_empty() {
    return Err(SetupFailed("OAuth response did not include an access token"))
  }
  let refresh_token = match token.refresh_token {
    Some(token) if !token.is_empty() => token
    _ =>
      return Err(SetupFailed("OAuth response did not include a refresh token"))
  }
  let authorization : StoredAuthorization = {
    version: 1,
    client_id: client.client_id,
    client_secret: client.client_secret,
    refresh_token,
    token_uri: client.token_uri,
    scope: drive_file_scope,
  }
  match (dependencies.store.replace)(authorization) {
    Ok(_) =>
      Ok({
        configured: true,
        client_id: Some(client.client_id),
        token_uri: Some(client.token_uri),
        scope: drive_file_scope,
      })
    Err(_) => Err(StorageUnavailable)
  }
}

///|
/// Report whether Project Authorization is configured without exposing secret material.
pub async fn project_authorization_status(
  store : CredentialStore,
) -> Result[ProjectAuthorizationStatus, ProjectAuthorizationError] {
  match (store.load)() {
    Ok(authorization) =>
      if authorization.version != 1 ||
        authorization.scope != drive_file_scope ||
        authorization.client_id.is_empty() ||
        authorization.client_secret.is_empty() ||
        authorization.token_uri.is_empty() ||
        authorization.refresh_token.is_empty() {
        Err(ReauthorizationRequired)
      } else {
        Ok({
          configured: true,
          client_id: Some(authorization.client_id),
          token_uri: Some(authorization.token_uri),
          scope: drive_file_scope,
        })
      }
    Err("not configured") =>
      Ok({
        configured: false,
        client_id: None,
        token_uri: None,
        scope: drive_file_scope,
      })
    Err(_) => Err(ReauthorizationRequired)
  }
}

///|
/// Report a usable Project Authorization only after its refresh material works.
pub async fn project_authorization_usable_status(
  store : CredentialStore,
  refresh : async (TokenRefreshRequest) -> Result[OAuthToken, String],
) -> Result[ProjectAuthorizationStatus, ProjectAuthorizationError] {
  let status = match project_authorization_status(store) {
    Ok(status) => status
    Err(error) => return Err(error)
  }
  if !status.configured {
    return Ok(status)
  }
  match project_access_token(store, refresh) {
    Ok(_) => Ok(status)
    Err(error) => Err(error)
  }
}

///|
/// Refresh silently from Project Authorization; this never opens a browser or consults ADC.
pub async fn project_access_token(
  store : CredentialStore,
  refresh : async (TokenRefreshRequest) -> Result[OAuthToken, String],
) -> Result[String, ProjectAuthorizationError] {
  let authorization = match (store.load)() {
    Ok(authorization) => authorization
    Err(_) => return Err(ReauthorizationRequired)
  }
  if authorization.version != 1 ||
    authorization.scope != drive_file_scope ||
    authorization.client_id.is_empty() ||
    authorization.client_secret.is_empty() ||
    authorization.refresh_token.is_empty() ||
    authorization.token_uri.is_empty() {
    return Err(ReauthorizationRequired)
  }
  match
    refresh({
      client_id: authorization.client_id,
      client_secret: authorization.client_secret,
      token_uri: authorization.token_uri,
      refresh_token: authorization.refresh_token,
      scope: drive_file_scope,
    }) {
    Ok(token) if !token.access_token.is_empty() => Ok(token.access_token)
    _ => Err(ReauthorizationRequired)
  }
}

///|
fn form_encode(values : Array[(String, String)]) -> String {
  let output = StringBuilder::new()
  for i in 0..<values.length() {
    if i > 0 {
      output.write_char('&')
    }
    let (key, value) = values[i]
    output.write_string(url_encode(key))
    output.write_char('=')
    output.write_string(url_encode(value))
  }
  output.to_string()
}

///|
fn token_response(body : String) -> Result[OAuthToken, String] {
  let json = @json.parse(body) catch {
    _ => return Err("invalid token response")
  }
  let fields = match json {
    Object(fields) => fields
    _ => return Err("invalid token response")
  }
  let access_token = match fields.get("access_token") {
    Some(String(value)) if !value.is_empty() => value
    _ => return Err("invalid token response")
  }
  let refresh_token = match fields.get("refresh_token") {
    Some(String(value)) if !value.is_empty() => Some(value)
    _ => None
  }
  Ok({ access_token, refresh_token })
}

///|
async fn post_token_request(
  http : &@google_http.HttpClient,
  token_uri : String,
  body : String,
) -> Result[OAuthToken, String] {
  let response = http.request(
    @google_http.HttpRequest::new(
      token_uri,
      @google_http.HttpMethod::POST,
      {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
      },
      body=Some(body),
    ),
  ) catch {
    _ => return Err("OAuth transport failed")
  }
  if response.status_code < 200 || response.status_code >= 300 {
    return Err("OAuth token endpoint rejected the request")
  }
  token_response(response.body)
}

///|
/// Real OAuth authorization-code exchange over the injected Google HTTP client.
pub async fn exchange_code_with_http(
  http : &@google_http.HttpClient,
  request : TokenExchangeRequest,
) -> Result[OAuthToken, String] {
  let body = form_encode([
    ("grant_type", "authorization_code"),
    ("code", request.code),
    ("client_id", request.client_id),
    ("client_secret", request.client_secret),
    ("redirect_uri", request.redirect_uri),
    ("code_verifier", request.code_verifier),
  ])
  post_token_request(http, request.token_uri, body)
}

///|
/// Real OAuth refresh over the injected Google HTTP client.
pub async fn refresh_with_http(
  http : &@google_http.HttpClient,
  request : TokenRefreshRequest,
) -> Result[OAuthToken, String] {
  let body = form_encode([
    ("grant_type", "refresh_token"),
    ("refresh_token", request.refresh_token),
    ("client_id", request.client_id),
    ("client_secret", request.client_secret),
  ])
  post_token_request(http, request.token_uri, body)
}

///|
/// A deterministic location below the user's configuration directory.
pub fn default_project_authorization_directory() -> Result[
  String,
  ProjectAuthorizationError,
] {
  match @env.get_env_var("XDG_CONFIG_HOME") {
    Some(path) if !path.is_empty() => Ok(path + "/pumd")
    _ =>
      match @env.get_env_var("APPDATA") {
        Some(path) if !path.is_empty() => Ok(path + "/pumd")
        _ =>
          match @env.get_env_var("HOME") {
            Some(home) if !home.is_empty() => Ok(home + "/.config/pumd")
            _ => Err(StorageUnavailable)
          }
      }
  }
}

///|
fn required_stored_string(
  fields : Map[String, Json],
  name : String,
) -> Result[String, String] {
  match fields.get(name) {
    Some(String(value)) if !value.is_empty() => Ok(value)
    _ => Err("invalid stored authorization")
  }
}

///|
fn authorization_json(authorization : StoredAuthorization) -> String {
  let values : Map[String, Json] = {
    "version": Json::number(1.0),
    "client_id": Json::string(authorization.client_id),
    "client_secret": Json::string(authorization.client_secret),
    "refresh_token": Json::string(authorization.refresh_token),
    "token_uri": Json::string(authorization.token_uri),
    "scope": Json::string(drive_file_scope),
  }
  Json::object(values).stringify()
}

///|
async fn load_authorization_file(
  path : String,
) -> Result[StoredAuthorization, String] {
  if !@fs.exists(path) {
    return Err("not configured")
  }
  let data = @fs.read_file(path) catch {
    _ => return Err("invalid stored authorization")
  }
  let text = data.text() catch {
    _ => return Err("invalid stored authorization")
  }
  let json = @json.parse(text) catch {
    _ => return Err("invalid stored authorization")
  }
  let fields = match json {
    Object(fields) => fields
    _ => return Err("invalid stored authorization")
  }
  let version = match fields.get("version") {
    Some(Number(number, ..)) if number == 1.0 => 1
    _ => return Err("invalid stored authorization")
  }
  let client_id = match required_stored_string(fields, "client_id") {
    Ok(x) => x
    Err(e) => return Err(e)
  }
  let client_secret = match required_stored_string(fields, "client_secret") {
    Ok(x) => x
    Err(e) => return Err(e)
  }
  let refresh_token = match required_stored_string(fields, "refresh_token") {
    Ok(x) => x
    Err(e) => return Err(e)
  }
  let token_uri = match required_stored_string(fields, "token_uri") {
    Ok(x) => x
    Err(e) => return Err(e)
  }
  let scope = match required_stored_string(fields, "scope") {
    Ok(x) => x
    Err(e) => return Err(e)
  }
  if scope != drive_file_scope {
    return Err("invalid stored authorization")
  }
  Ok({ version, client_id, client_secret, refresh_token, token_uri, scope })
}

///|
async fn replace_authorization_file(
  parent : String,
  path : String,
  authorization : StoredAuthorization,
) -> Result[Unit, String] {
  if !@fs.exists(parent) {
    @fs.mkdir(parent, permission=0o700, recursive=true) catch {
      _ => return Err("credential store unavailable")
    }
  }
  let is_windows = match @env.get_env_var("OS") {
    Some(value) => value == "Windows_NT"
    _ => false
  }
  if !is_windows {
    @fs.chmod(parent, 0o700) catch {
      _ => return Err("credential store unavailable")
    }
  }
  let suffix = match secure_random_bytes(16) {
    Ok(bytes) => base64url(bytes[:])
    Err(_) => return Err("credential store unavailable")
  }
  let temp = path + ".tmp-" + suffix
  let file = @fs.open(
    temp,
    mode=@fs.Mode::WriteOnly,
    create_mode=@fs.CreateMode::CreateNew,
    permission=0o600,
  ) catch {
    _ => return Err("credential store unavailable")
  }
  let write_outcome : Result[Unit, String] = try {
    file.write(authorization_json(authorization))
    file.sync()
    Ok(())
  } catch {
    _ => Err("credential store write failed")
  }
  let outcome : Result[Unit, String] = match write_outcome {
    Ok(_) => {
      file.close()
      try {
        @fs.rename(temp, path, replace=true)
        Ok(())
      } catch {
        _ => Err("credential store replacement failed")
      }
    }
    Err(error) => {
      file.close()
      Err(error)
    }
  }
  match outcome {
    Ok(_) => Ok(())
    Err(error) => {
      @fs.remove(temp) catch {
        _ => ()
      }
      Err(error)
    }
  }
}

///|
/// Production explicit file credential store. Replacement is write/sync/close then atomic rename.
pub fn file_credential_store(config_directory : String) -> CredentialStore {
  let path = config_directory + "/project-authorization.json"
  {
    load: async fn() { load_authorization_file(path) },
    replace: async fn(authorization) {
      replace_authorization_file(config_directory, path, authorization)
    },
  }
}

///|
/// Bind a one-use IPv4 loopback callback listener on an OS-chosen port.
pub async fn start_loopback_callback() -> Result[LoopbackCallback, String] {
  let server = @async_http.Server::Server(@socket.Addr::new(0x7f000001U, 0)) catch {
    _ => return Err("loopback listener unavailable")
  }
  let redirect_uri = "http://127.0.0.1:" +
    server.addr.port().to_string() +
    "/oauth2/callback"
  Ok({
    redirect_uri,
    await_callback: async fn() {
      defer server.close()
      let received = @async.with_timeout_opt(300000, async fn() {
        let (connection, _) = server.accept()
        defer connection.close()
        let request = connection.read_request()
        if request.meth != @async_http.RequestMethod::Get ||
          !request.path.has_prefix("/oauth2/callback?") {
          connection.send_response(400, "Bad Request")
          connection.write_string("Invalid Project Authorization callback.")
          connection.end_response()
          return Err("unexpected callback request")
        }
        connection.send_response(200, "OK")
        connection.write_string(
          "<!doctype html><title>Project Authorization complete</title><p>Project Authorization is complete. You may return to the terminal.</p>",
        )
        connection.end_response()
        match request.path.split_once("?") {
          Some((_, query)) => Ok(query.to_owned())
          None => Err("callback query missing")
        }
      })
      match received {
        Some(result) => result
        None => Err("loopback callback timed out")
      }
    },
  })
}

///|
/// Best-effort cross-platform browser launcher. A caller can print the URL and continue on failure.
pub async fn launch_default_browser(url : String) -> Result[Unit, String] {
  let is_windows = match @env.get_env_var("OS") {
    Some(value) => value == "Windows_NT"
    _ => false
  }
  if is_windows {
    let status = @process.run(
      "rundll32",
      ["url.dll,FileProtocolHandler", url],
      no_console_window=true,
    ) catch {
      _ => return Err("browser launcher unavailable")
    }
    return if status == 0 {
      Ok(())
    } else {
      Err("browser launcher unavailable")
    }
  }
  let mac_status = @process.run("open", [url]) catch { _ => -1 }
  if mac_status == 0 {
    return Ok(())
  }
  let linux_status = @process.run("xdg-open", [url]) catch { _ => -1 }
  if linux_status == 0 {
    Ok(())
  } else {
    Err("browser launcher unavailable")
  }
}

///|
/// Print a recoverable manual-authorization URL without displaying secrets.
pub fn print_authorization_url(url : String) -> Unit {
  println("Open this Project Authorization URL in a browser:")
  println(url)
}

///|
/// Production setup collaborators backed by CSPRNG, loopback HTTP, process launch, and Google HTTP.
pub fn production_setup_dependencies(
  store : CredentialStore,
  http : &@google_http.HttpClient,
) -> SetupDependencies {
  {
    random_bytes: fn(size) {
      match secure_random_bytes(size) {
        Ok(bytes) => Ok(bytes)
        Err(_) => Err("secure random bytes unavailable")
      }
    },
    start_listener: async fn() { start_loopback_callback() },
    launch_browser: async fn(url) { launch_default_browser(url) },
    report_authorization_url: print_authorization_url,
    exchange_code: async fn(request) { exchange_code_with_http(http, request) },
    store,
  }
}

///|
/// Production high-level setup using the default explicit file credential store.
pub async fn setup_project_authorization_production(
  client_document : String,
  http : &@google_http.HttpClient,
) -> Result[ProjectAuthorizationStatus, ProjectAuthorizationError] {
  let directory = match default_project_authorization_directory() {
    Ok(directory) => directory
    Err(error) => return Err(error)
  }
  let store = file_credential_store(directory)
  setup_project_authorization(
    client_document,
    production_setup_dependencies(store, http),
  )
}

///|
/// Production high-level secret-free Project Authorization status.
pub async fn project_authorization_status_production(
  http : &@google_http.HttpClient,
) -> Result[ProjectAuthorizationStatus, ProjectAuthorizationError] {
  let directory = match default_project_authorization_directory() {
    Ok(directory) => directory
    Err(error) => return Err(error)
  }
  project_authorization_usable_status(file_credential_store(directory), async fn(
    request,
  ) {
    refresh_with_http(http, request)
  })
}

///|
/// Production high-level silent Project Authorization access-token acquisition.
pub async fn project_access_token_production(
  http : &@google_http.HttpClient,
) -> Result[String, ProjectAuthorizationError] {
  let directory = match default_project_authorization_directory() {
    Ok(directory) => directory
    Err(error) => return Err(error)
  }
  project_access_token(file_credential_store(directory), async fn(request) {
    refresh_with_http(http, request)
  })
}

///|
fn required_string(
  fields : Map[String, Json],
  name : String,
) -> Result[String, ProjectAuthorizationError] {
  match fields.get(name) {
    Some(String(value)) if !value.is_empty() => Ok(value)
    _ =>
      Err(InvalidClientFile("missing required `installed." + name + "` field"))
  }
}

///|
fn valid_loopback_redirect(uri : String) -> Bool {
  let bases = ["http://localhost", "http://127.0.0.1"]
  for base in bases {
    if uri == base || uri == base + "/" {
      return true
    }
    let prefix = base + ":"
    if uri.has_prefix(prefix) {
      let port_text = uri[prefix.length():]
      let port = @string.parse_int(port_text, base=10) catch {
        _ => return false
      }
      return port > 0 && port <= 65535
    }
  }
  false
}

///|
fn has_loopback_redirect(fields : Map[String, Json]) -> Bool {
  match fields.get("redirect_uris") {
    Some(Array(redirects)) => {
      for redirect in redirects {
        match redirect {
          String(uri) if valid_loopback_redirect(uri) => return true
          _ => ()
        }
      }
      false
    }
    _ => false
  }
}

///|
/// Validate a Google Cloud Desktop application's downloaded client JSON locally.
pub fn parse_installed_client(
  document : String,
) -> Result[InstalledClient, ProjectAuthorizationError] {
  let root = @json.parse(document) catch {
    _ => return Err(InvalidClientFile("malformed JSON"))
  }
  let fields = match root {
    Object(root_fields) =>
      match root_fields.get("installed") {
        Some(Object(installed)) => installed
        Some(_) =>
          return Err(InvalidClientFile("`installed` must be an object"))
        None =>
          if root_fields.get("web") is Some(_) {
            return Err(
              InvalidClientFile(
                "expected a Desktop installed client, not a web client",
              ),
            )
          } else {
            return Err(InvalidClientFile("missing `installed` object"))
          }
      }
    _ => return Err(InvalidClientFile("JSON root must be an object"))
  }
  let client_id = match required_string(fields, "client_id") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let client_secret = match required_string(fields, "client_secret") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let auth_uri = match required_string(fields, "auth_uri") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let token_uri = match required_string(fields, "token_uri") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if auth_uri != "https://accounts.google.com/o/oauth2/auth" &&
    auth_uri != "https://accounts.google.com/o/oauth2/v2/auth" {
    return Err(
      InvalidClientFile(
        "`installed.auth_uri` must be a Google HTTPS authorization endpoint",
      ),
    )
  }
  if token_uri != "https://oauth2.googleapis.com/token" {
    return Err(
      InvalidClientFile(
        "`installed.token_uri` must be the Google HTTPS token endpoint",
      ),
    )
  }
  if !has_loopback_redirect(fields) {
    return Err(
      InvalidClientFile(
        "`installed.redirect_uris` must include a loopback redirect",
      ),
    )
  }
  Ok({ client_id, client_secret, auth_uri, token_uri })
}
