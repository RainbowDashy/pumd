///|
pub enum Authorization {
  Project(CredentialStoreRequest)
  Adc
  AccessTokenEnvironment
}

///|
pub(all) enum CredentialStore {
  Native
  File
}

///|
/// Omitted lifecycle flags resolve the remembered store, then native when no
/// preference exists. Explicit flags override that resolution for one command.
pub(all) enum CredentialStoreRequest {
  RememberedOrNative
  Explicit(CredentialStore)
}

///|
/// Setup distinguishes an omitted store from an explicit native selection so
/// interactive sessions can ask and noninteractive sessions can stay deterministic.
pub(all) enum SetupCredentialStore {
  Prompt
  Selected(CredentialStore)
}

///|
/// Resolve setup only when prompting is forbidden. An explicit choice wins;
/// otherwise the remembered choice or native default is deterministic.
pub fn noninteractive_setup_credential_store(
  request : SetupCredentialStore,
  remembered : CredentialStore?,
) -> CredentialStore {
  match request {
    Selected(store) => store
    Prompt =>
      match remembered {
        Some(store) => store
        None => Native
      }
  }
}

///|
/// Preserve publish's store intent when missing authorization starts setup.
pub fn project_onboarding_setup_store(
  request : CredentialStoreRequest,
  remembered : CredentialStore?,
) -> SetupCredentialStore {
  match request {
    Explicit(store) => Selected(store)
    RememberedOrNative =>
      match remembered {
        Some(store) => Selected(store)
        None => Prompt
      }
  }
}

///|
pub enum ClientFile {
  Guided
  Provided(String)
}

///|
pub enum Command {
  Publish(String, Authorization)
  AuthSetup(ClientFile, SetupCredentialStore)
  AuthStatus(CredentialStoreRequest)
  AuthLogout(CredentialStoreRequest)
}

///|
fn publish_usage() -> String {
  "Project Authorization usage: pumd publish [--auth=project|adc|token-env] [--credential-store=native|file] <markdown-path>"
}

///|
fn setup_usage() -> String {
  "Project Authorization usage: pumd auth setup [--client-file <path>] [--credential-store=native|file]\nInteractive setup prompts when the store is omitted; noninteractive setup uses the remembered store or the native default without prompting."
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
        Ok(Publish(path, Project(RememberedOrNative)))
      }
    }
    4 =>
      match (args[2], args[3]) {
        ("--auth=project", path) if !path.has_prefix("--") =>
          Ok(Publish(path, Project(RememberedOrNative)))
        ("--auth=adc", path) if !path.has_prefix("--") => Ok(Publish(path, Adc))
        ("--auth=token-env", path) if !path.has_prefix("--") =>
          Ok(Publish(path, AccessTokenEnvironment))
        _ => Err(publish_usage())
      }
    5 =>
      match (args[2], args[3], args[4]) {
        ("--auth=project", store, path) if !path.has_prefix("--") =>
          match parse_credential_store(store) {
            Some(store) => Ok(Publish(path, Project(Explicit(store))))
            None => Err(publish_usage())
          }
        (store, "--auth=project", path) if !path.has_prefix("--") =>
          match parse_credential_store(store) {
            Some(store) => Ok(Publish(path, Project(Explicit(store))))
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
    3 => Ok(AuthSetup(Guided, Prompt))
    4 =>
      match parse_credential_store(args[3]) {
        Some(store) => Ok(AuthSetup(Guided, Selected(store)))
        None => Err(setup_usage())
      }
    5 =>
      match (args[3], args[4]) {
        ("--client-file", client_file) if !client_file.is_empty() &&
          !client_file.has_prefix("--") =>
          Ok(AuthSetup(Provided(client_file), Prompt))
        _ => Err(setup_usage())
      }
    6 =>
      match (args[3], args[4], args[5]) {
        ("--client-file", client_file, store) if !client_file.is_empty() &&
          !client_file.has_prefix("--") =>
          match parse_credential_store(store) {
            Some(store) => Ok(AuthSetup(Provided(client_file), Selected(store)))
            None => Err(setup_usage())
          }
        (store, "--client-file", client_file) if !client_file.is_empty() &&
          !client_file.has_prefix("--") =>
          match parse_credential_store(store) {
            Some(store) => Ok(AuthSetup(Provided(client_file), Selected(store)))
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
        "status" => Ok(AuthStatus(RememberedOrNative))
        "setup" => parse_setup(args)
        "logout" => Ok(AuthLogout(RememberedOrNative))
        _ => Err(command_usage())
      }
    _ =>
      if args[2] == "setup" {
        parse_setup(args)
      } else if args[2] == "status" {
        match args.length() {
          4 =>
            match parse_credential_store(args[3]) {
              Some(store) => Ok(AuthStatus(Explicit(store)))
              None => Err(status_usage())
            }
          _ => Err(status_usage())
        }
      } else if args[2] == "logout" {
        match args.length() {
          4 =>
            match parse_credential_store(args[3]) {
              Some(store) => Ok(AuthLogout(Explicit(store)))
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
