///|
pub enum Authorization {
  Project(CredentialStore)
  Adc
  AccessTokenEnvironment
}

///|
pub enum CredentialStore {
  Native
  File
}

///|
pub enum ClientFile {
  Guided
  Provided(String)
}

///|
pub enum Command {
  Publish(String, Authorization)
  AuthSetup(ClientFile, CredentialStore)
  AuthStatus(CredentialStore)
  AuthLogout(CredentialStore)
}

///|
fn publish_usage() -> String {
  "Project Authorization usage: pumd publish [--auth=project|adc|token-env] [--credential-store=native|file] <markdown-path>"
}

///|
fn setup_usage() -> String {
  "Project Authorization usage: pumd auth setup [--client-file <path>] [--credential-store=native|file]"
}

///|
fn status_usage() -> String {
  "Project Authorization usage: pumd auth status [--credential-store=native|file]"
}

///|
fn logout_usage() -> String {
  "Project Authorization usage: pumd auth logout [--credential-store=native|file]"
}

///|
fn command_usage() -> String {
  "Project Authorization usage: pumd auth <setup|status|logout> or pumd publish [--auth=project|adc|token-env] [--credential-store=native|file] <markdown-path>"
}

///|
fn parse_credential_store(value : String) -> CredentialStore? {
  match value {
    "--credential-store=native" => Some(Native)
    // Compatibility for the Milestone 2 macOS-only spelling. It now selects
    // the platform's native vault; help and new documentation use `native`.
    "--credential-store=keychain" => Some(Native)
    "--credential-store=file" => Some(File)
    _ => None
  }
}

///|
fn parse_publish(args : Array[String]) -> Result[Command, String] {
  match args.length() {
    3 => {
      let path = args[2]
      if path.has_prefix("--") {
        Err(publish_usage())
      } else {
        Ok(Publish(path, Project(Native)))
      }
    }
    4 =>
      match (args[2], args[3]) {
        ("--auth=project", path) if !path.has_prefix("--") =>
          Ok(Publish(path, Project(Native)))
        ("--auth=adc", path) if !path.has_prefix("--") => Ok(Publish(path, Adc))
        ("--auth=token-env", path) if !path.has_prefix("--") =>
          Ok(Publish(path, AccessTokenEnvironment))
        _ => Err(publish_usage())
      }
    5 =>
      match (args[2], args[3], args[4]) {
        ("--auth=project", store, path) if !path.has_prefix("--") =>
          match parse_credential_store(store) {
            Some(store) => Ok(Publish(path, Project(store)))
            None => Err(publish_usage())
          }
        (store, "--auth=project", path) if !path.has_prefix("--") =>
          match parse_credential_store(store) {
            Some(store) => Ok(Publish(path, Project(store)))
            None => Err(publish_usage())
          }
        _ => Err(publish_usage())
      }
    _ => Err(publish_usage())
  }
}

///|
fn parse_setup(args : Array[String]) -> Result[Command, String] {
  match args.length() {
    3 => Ok(AuthSetup(Guided, Native))
    4 =>
      match parse_credential_store(args[3]) {
        Some(store) => Ok(AuthSetup(Guided, store))
        None => Err(setup_usage())
      }
    5 =>
      match (args[3], args[4]) {
        ("--client-file", client_file) if !client_file.is_empty() &&
          !client_file.has_prefix("--") =>
          Ok(AuthSetup(Provided(client_file), Native))
        _ => Err(setup_usage())
      }
    6 =>
      match (args[3], args[4], args[5]) {
        ("--client-file", client_file, store) if !client_file.is_empty() &&
          !client_file.has_prefix("--") =>
          match parse_credential_store(store) {
            Some(store) => Ok(AuthSetup(Provided(client_file), store))
            None => Err(setup_usage())
          }
        (store, "--client-file", client_file) if !client_file.is_empty() &&
          !client_file.has_prefix("--") =>
          match parse_credential_store(store) {
            Some(store) => Ok(AuthSetup(Provided(client_file), store))
            None => Err(setup_usage())
          }
        _ => Err(setup_usage())
      }
    _ => Err(setup_usage())
  }
}

///|
fn parse_auth(args : Array[String]) -> Result[Command, String] {
  if args.length() < 3 {
    return Err(command_usage())
  }
  match args.length() {
    3 =>
      match args[2] {
        "status" => Ok(AuthStatus(Native))
        "setup" => parse_setup(args)
        "logout" => Ok(AuthLogout(Native))
        _ => Err(command_usage())
      }
    _ =>
      if args[2] == "setup" {
        parse_setup(args)
      } else if args[2] == "status" {
        match args.length() {
          4 =>
            match parse_credential_store(args[3]) {
              Some(store) => Ok(AuthStatus(store))
              None => Err(status_usage())
            }
          _ => Err(status_usage())
        }
      } else if args[2] == "logout" {
        match args.length() {
          4 =>
            match parse_credential_store(args[3]) {
              Some(store) => Ok(AuthLogout(store))
              None => Err(logout_usage())
            }
          _ => Err(logout_usage())
        }
      } else {
        Err(command_usage())
      }
  }
}

///|
/// Parse a complete `pumd` command line without performing I/O.
pub fn parse_command(args : Array[String]) -> Result[Command, String] {
  if args.length() < 2 {
    return Err(command_usage())
  }
  match args[1] {
    "publish" => parse_publish(args)
    "auth" => parse_auth(args)
    _ => Err(command_usage())
  }
}

///|
/// Compatibility seam for callers that explicitly select ADC.
pub fn parse_publish_path(args : Array[String]) -> Result[String, String] {
  match parse_command(args) {
    Ok(Publish(path, Adc)) if args.length() == 4 => Ok(path)
    Ok(Publish(_, Project(_))) => Err(publish_usage())
    Ok(Publish(_, Adc)) => Err(publish_usage())
    Ok(Publish(_, AccessTokenEnvironment)) => Err(publish_usage())
    Ok(_) => Err(command_usage())
    Err(message) => Err(message)
  }
}
