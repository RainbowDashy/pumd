///|
pub enum Authorization {
  Project
  Adc
}

///|
pub enum CredentialStore {
  File
}

///|
pub enum Command {
  Publish(String, Authorization)
  AuthSetup(String, CredentialStore)
  AuthStatus
}

///|
fn publish_usage() -> String {
  "Project Authorization usage: pumd publish [--auth=project|adc] <markdown-path>"
}

///|
fn setup_usage() -> String {
  "Project Authorization usage: pumd auth setup --client-file <path> --credential-store=file"
}

///|
fn status_usage() -> String {
  "Project Authorization usage: pumd auth status"
}

///|
fn command_usage() -> String {
  "Project Authorization usage: pumd auth <setup|status> or pumd publish [--auth=project|adc] <markdown-path>"
}

///|
fn parse_publish(args : Array[String]) -> Result[Command, String] {
  match args.length() {
    3 => {
      let path = args[2]
      if path.has_prefix("--") {
        Err(publish_usage())
      } else {
        Ok(Publish(path, Adc))
      }
    }
    4 =>
      match (args[2], args[3]) {
        ("--auth=project", path) if !path.has_prefix("--") =>
          Ok(Publish(path, Project))
        ("--auth=adc", path) if !path.has_prefix("--") => Ok(Publish(path, Adc))
        _ => Err(publish_usage())
      }
    _ => Err(publish_usage())
  }
}

///|
fn parse_setup(args : Array[String]) -> Result[Command, String] {
  if args.length() != 6 {
    return Err(setup_usage())
  }
  match (args[3], args[4], args[5]) {
    ("--client-file", client_file, "--credential-store=file") if !client_file.is_empty() &&
      !client_file.has_prefix("--") => Ok(AuthSetup(client_file, File))
    ("--credential-store=file", "--client-file", client_file) if !client_file.is_empty() &&
      !client_file.has_prefix("--") => Ok(AuthSetup(client_file, File))
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
        "status" => Ok(AuthStatus)
        "setup" => Err(setup_usage())
        _ => Err(command_usage())
      }
    _ =>
      if args[2] == "setup" {
        parse_setup(args)
      } else if args[2] == "status" {
        Err(status_usage())
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
    Ok(Publish(path, Adc)) => Ok(path)
    Ok(Publish(_, Project)) => Err(publish_usage())
    Ok(_) => Err(command_usage())
    Err(message) => Err(message)
  }
}
