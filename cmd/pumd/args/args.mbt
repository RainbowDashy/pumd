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
pub(all) struct ListOptions {
  json : Bool
  refresh : Bool
}

///|
pub enum Command {
  Publish(String, Authorization, Bool)
  List(ListOptions)
  Move(String, String)
  Forget(String)
  AuthSetup(ClientFile, SetupCredentialStore)
  AuthStatus(CredentialStoreRequest)
  AuthLogout(CredentialStoreRequest)
}

///|
fn publish_usage() -> String {
  "Project Authorization usage: pumd publish [--dry-run] [--auth=project|adc|token-env] [--credential-store=native|file] <markdown-path>"
}

///|
fn list_usage() -> String {
  "Project Authorization usage: pumd list [--json] [--refresh]"
}

///|
fn move_usage() -> String {
  "Project Authorization usage: pumd move <old-path> <new-path>"
}

///|
fn forget_usage() -> String {
  "Project Authorization usage: pumd forget <path>"
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
  "Project Authorization usage: pumd publish [--dry-run] [--auth=project|adc|token-env] [--credential-store=native|file] <markdown-path>; pumd list [--json] [--refresh]; pumd move <old-path> <new-path>; pumd forget <path>; pumd auth <setup|status|logout>"
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
fn parse_publish_options(
  args : Array[String],
  index : Int,
  authorization : Authorization?,
  credential_store : CredentialStore?,
  dry_run : Bool,
  path : String?,
) -> Result[Command, String] {
  if index == args.length() {
    match path {
      None => Err(publish_usage())
      Some(path) =>
        match (authorization, credential_store) {
          (None, None) => Ok(Publish(path, Project(RememberedOrNative), dry_run))
          (Some(Project(_)), None) =>
            Ok(Publish(path, Project(RememberedOrNative), dry_run))
          (Some(Adc), None) => Ok(Publish(path, Adc, dry_run))
          (Some(AccessTokenEnvironment), None) =>
            Ok(Publish(path, AccessTokenEnvironment, dry_run))
          (None, Some(store)) => Ok(Publish(path, Project(Explicit(store)), dry_run))
          (Some(Project(_)), Some(store)) =>
            Ok(Publish(path, Project(Explicit(store)), dry_run))
          _ => Err(publish_usage())
        }
    }
  } else {
    let argument = args[index]
    match argument {
      "--auth=project" =>
        match authorization {
          Some(_) => Err(publish_usage())
          None =>
            parse_publish_options(
              args, index + 1, Some(Project(RememberedOrNative)), credential_store,
              dry_run, path,
            )
        }
      "--auth=adc" =>
        match authorization {
          Some(_) => Err(publish_usage())
          None =>
            parse_publish_options(args, index + 1, Some(Adc), credential_store, dry_run, path)
        }
      "--auth=token-env" =>
        match authorization {
          Some(_) => Err(publish_usage())
          None =>
            parse_publish_options(
              args, index + 1, Some(AccessTokenEnvironment), credential_store, dry_run, path,
            )
        }
      "--dry-run" =>
        if dry_run {
          Err(publish_usage())
        } else {
          parse_publish_options(
            args, index + 1, authorization, credential_store, true, path,
          )
        }
      _ =>
        match parse_credential_store(argument) {
          Some(store) =>
            match credential_store {
              Some(_) => Err(publish_usage())
              None =>
                parse_publish_options(
                  args, index + 1, authorization, Some(store), dry_run, path,
                )
            }
          None =>
            if argument.has_prefix("--") {
              Err(publish_usage())
            } else {
              match path {
                Some(_) => Err(publish_usage())
                None =>
                  parse_publish_options(
                    args, index + 1, authorization, credential_store, dry_run,
                    Some(argument),
                  )
              }
            }
        }
    }
  }
}

///|
fn parse_publish(args : Array[String]) -> Result[Command, String] {
  parse_publish_options(args, 2, None, None, false, None)
}

///|
fn parse_list(args : Array[String]) -> Result[Command, String] {
  let mut json = false
  let mut refresh = false
  for index = 2; index < args.length(); index = index + 1 {
    match args[index] {
      "--json" if !json => json = true
      "--refresh" if !refresh => refresh = true
      _ => return Err(list_usage())
    }
  }
  Ok(List({ json, refresh }))
}

///|
fn parse_move(args : Array[String]) -> Result[Command, String] {
  if args.length() != 4 {
    return Err(move_usage())
  }
  let old_path = args[2]
  let new_path = args[3]
  if old_path.is_empty() || new_path.is_empty() || old_path.has_prefix("--") || new_path.has_prefix("--") {
    Err(move_usage())
  } else {
    Ok(Move(old_path, new_path))
  }
}

///|
fn parse_forget(args : Array[String]) -> Result[Command, String] {
  if args.length() != 3 {
    return Err(forget_usage())
  }
  let path = args[2]
  if path.is_empty() || path.has_prefix("--") {
    Err(forget_usage())
  } else {
    Ok(Forget(path))
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
    "list" => parse_list(args)
    "move" => parse_move(args)
    "forget" => parse_forget(args)
    "auth" => parse_auth(args)
    _ => Err(command_usage())
  }
}

///|
/// Compatibility seam for callers that explicitly select ADC.
pub fn parse_publish_path(args : Array[String]) -> Result[String, String] {
  match parse_command(args) {
    Ok(Publish(path, Adc, false)) if args.length() == 4 => Ok(path)
    Ok(Publish(_, Project(_), _)) => Err(publish_usage())
    Ok(Publish(_, Adc, _)) => Err(publish_usage())
    Ok(Publish(_, AccessTokenEnvironment, _)) => Err(publish_usage())
    Ok(_) => Err(command_usage())
    Err(message) => Err(message)
  }
}
