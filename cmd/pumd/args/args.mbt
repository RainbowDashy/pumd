///|
pub enum Authorization {
  Project(CredentialStore)
  Adc
}

///|
pub enum CredentialStore {
  Keychain
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
  "Project Authorization usage: pumd publish [--auth=project|adc] [--credential-store=keychain|file] <markdown-path>"
}

///|
fn setup_usage() -> String {
  "Project Authorization usage: pumd auth setup [--client-file <path>] [--credential-store=keychain|file]"
}

///|
fn status_usage() -> String {
  "Project Authorization usage: pumd auth status [--credential-store=keychain|file]"
}

///|
fn logout_usage() -> String {
  "Project Authorization usage: pumd auth logout [--credential-store=keychain|file]"
}

///|
fn command_usage() -> String {
  "Project Authorization usage: pumd auth <setup|status|logout> or pumd publish [--auth=project|adc] [--credential-store=keychain|file] <markdown-path>"
}

///|
fn parse_publish(args : Array[String]) -> Result[Command, String] {
  match args.length() {
    3 => {
      let path = args[2]
      if path.has_prefix("--") {
        Err(publish_usage())
      } else {
        // ADR-0005 keeps the cross-platform publish default on ADC until
        // every release platform has an equivalent secure credential vault.
        Ok(Publish(path, Adc))
      }
    }
    4 =>
      match (args[2], args[3]) {
        ("--auth=project", path) if !path.has_prefix("--") =>
          Ok(Publish(path, Project(Keychain)))
        ("--auth=adc", path) if !path.has_prefix("--") => Ok(Publish(path, Adc))
        _ => Err(publish_usage())
      }
    5 =>
      match (args[2], args[3], args[4]) {
        ("--auth=project", "--credential-store=keychain", path) if !path.has_prefix(
            "--",
          ) => Ok(Publish(path, Project(Keychain)))
        ("--credential-store=keychain", "--auth=project", path) if !path.has_prefix(
            "--",
          ) => Ok(Publish(path, Project(Keychain)))
        ("--auth=project", "--credential-store=file", path) if !path.has_prefix(
            "--",
          ) => Ok(Publish(path, Project(File)))
        ("--credential-store=file", "--auth=project", path) if !path.has_prefix(
            "--",
          ) => Ok(Publish(path, Project(File)))
        _ => Err(publish_usage())
      }
    _ => Err(publish_usage())
  }
}

///|
fn parse_setup(args : Array[String]) -> Result[Command, String] {
  match args.length() {
    3 => Ok(AuthSetup(Guided, Keychain))
    4 =>
      match args[3] {
        "--credential-store=keychain" => Ok(AuthSetup(Guided, Keychain))
        "--credential-store=file" => Ok(AuthSetup(Guided, File))
        _ => Err(setup_usage())
      }
    5 =>
      match (args[3], args[4]) {
        ("--client-file", client_file) if !client_file.is_empty() &&
          !client_file.has_prefix("--") =>
          Ok(AuthSetup(Provided(client_file), Keychain))
        _ => Err(setup_usage())
      }
    6 =>
      match (args[3], args[4], args[5]) {
        ("--client-file", client_file, "--credential-store=keychain") if !client_file.is_empty() &&
          !client_file.has_prefix("--") =>
          Ok(AuthSetup(Provided(client_file), Keychain))
        ("--credential-store=keychain", "--client-file", client_file) if !client_file.is_empty() &&
          !client_file.has_prefix("--") =>
          Ok(AuthSetup(Provided(client_file), Keychain))
        ("--client-file", client_file, "--credential-store=file") if !client_file.is_empty() &&
          !client_file.has_prefix("--") =>
          Ok(AuthSetup(Provided(client_file), File))
        ("--credential-store=file", "--client-file", client_file) if !client_file.is_empty() &&
          !client_file.has_prefix("--") =>
          Ok(AuthSetup(Provided(client_file), File))
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
        "status" => Ok(AuthStatus(Keychain))
        "setup" => parse_setup(args)
        "logout" => Ok(AuthLogout(Keychain))
        _ => Err(command_usage())
      }
    _ =>
      if args[2] == "setup" {
        parse_setup(args)
      } else if args[2] == "status" {
        match args.length() {
          4 =>
            match args[3] {
              "--credential-store=keychain" => Ok(AuthStatus(Keychain))
              "--credential-store=file" => Ok(AuthStatus(File))
              _ => Err(status_usage())
            }
          _ => Err(status_usage())
        }
      } else if args[2] == "logout" {
        match args.length() {
          4 =>
            match args[3] {
              "--credential-store=keychain" => Ok(AuthLogout(Keychain))
              "--credential-store=file" => Ok(AuthLogout(File))
              _ => Err(logout_usage())
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
/// Compatibility seam for the existing ADC-only entry point.
pub fn parse_publish_path(args : Array[String]) -> Result[String, String] {
  match parse_command(args) {
    Ok(Publish(path, Adc)) if args.length() == 3 => Ok(path)
    Ok(Publish(_, Project(_))) => Err(publish_usage())
    Ok(Publish(_, Adc)) => Err(publish_usage())
    Ok(_) => Err(command_usage())
    Err(message) => Err(message)
  }
}
