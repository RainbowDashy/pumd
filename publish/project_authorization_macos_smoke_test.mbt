///|
fn smoke_cli_output_value(output : String, prefix : String) -> String? {
  for part in output.split("\n") {
    let line = part.to_owned()
    if line.has_prefix(prefix) {
      let value = line.unsafe_substring(
        start=prefix.length(),
        end=line.length(),
      )
      if value.has_suffix("\r") {
        return Some(value.unsafe_substring(start=0, end=value.length() - 1))
      }
      return Some(value)
    }
  }
  None
}

///|
fn parse_macos_smoke_publish_success(output : String) -> PublishSuccess? {
  let document_id = smoke_cli_output_value(output, "document ID: ")
  let url = smoke_cli_output_value(output, "edit URL: ")
  match (document_id, url) {
    (Some(document_id), Some(url)) if !document_id.is_empty() &&
      url == canonical_document_url(document_id) => Some({ document_id, url })
    _ => None
  }
}

///|
test "macOS Project Authorization smoke parses only a canonical publish identity" {
  let output =
    #|document ID: smoke-doc-123
    #|edit URL: https://docs.google.com/document/d/smoke-doc-123/edit
  guard parse_macos_smoke_publish_success(output) is Some(success) else {
    fail("expected canonical publish identity")
  }
  assert_eq(success.document_id, "smoke-doc-123")
  assert_eq(
    success.url,
    "https://docs.google.com/document/d/smoke-doc-123/edit",
  )
}

///|
test "macOS Project Authorization smoke rejects a noncanonical publish URL" {
  let output =
    #|document ID: smoke-doc-123
    #|edit URL: https://example.test/document/d/smoke-doc-123/edit
  assert_eq(parse_macos_smoke_publish_success(output), None)
}

///|
fn smoke_env(name : String) -> Result[String, String] {
  match @env.get_env_var(name) {
    Some(value) if !value.is_empty() => Ok(value)
    _ => Err("set " + name + " before running this opt-in smoke test")
  }
}

///|
async fn macos_arm64_gate() -> Result[Unit, String] {
  let (system_exit, system_stdout, _) = @process.collect_output(
    "/usr/bin/uname",
    ["-s"],
  )
  let (machine_exit, machine_stdout, _) = @process.collect_output(
    "/usr/bin/uname",
    ["-m"],
  )
  let system = system_stdout.text() catch {
    _ => return Err("could not determine operating system")
  }
  let machine = machine_stdout.text() catch {
    _ => return Err("could not determine machine architecture")
  }
  if system_exit != 0 || system.trim() != "Darwin" {
    return Err("this smoke test requires Darwin (macOS)")
  }
  if machine_exit != 0 || machine.trim() != "arm64" {
    return Err("this smoke test requires Apple Silicon (arm64)")
  }
  Ok(())
}

///|
fn smoke_configuration() -> Result[(String, String), String] {
  match @env.get_env_var("PUMD_MACOS_PROJECT_AUTH_SMOKE") {
    Some("1") => ()
    _ =>
      return Err(
        "set PUMD_MACOS_PROJECT_AUTH_SMOKE=1 to acknowledge that this replaces the active Project Authorization in the default Keychain; use a dedicated test account and project",
      )
  }
  let pumd = match smoke_env("PUMD_MACOS_SMOKE_BINARY") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let client_file = match smoke_env("PUMD_MACOS_SMOKE_CLIENT_FILE") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if !@fs.path_exists(pumd) {
    return Err(
      "PUMD_MACOS_SMOKE_BINARY must name a prebuilt packaged pumd binary",
    )
  }
  if !@fs.path_exists(client_file) {
    return Err(
      "PUMD_MACOS_SMOKE_CLIENT_FILE must name a Desktop OAuth client JSON file",
    )
  }
  Ok((pumd, client_file))
}

///|
async fn smoke_command_stdout(
  pumd : String,
  arguments : Array[String],
  action : String,
) -> Result[String, String] {
  let (exit_code, stdout, _) = @process.collect_output(pumd, arguments)
  if exit_code != 0 {
    return Err(
      "" +
      action +
      " failed (exit " +
      exit_code.to_string() +
      "); inspect the dedicated smoke environment without printing credentials",
    )
  }
  Ok(stdout.text())
}

///|
fn status_output_is_secret_free(output : String) -> Bool {
  !output.contains("token") &&
  !output.contains("secret") &&
  !output.contains("Bearer ")
}

///|
test "macOS Project Authorization smoke recognizes secret-bearing status labels" {
  assert_true(
    !status_output_is_secret_free("refresh_token: should-never-print"),
  )
  assert_true(status_output_is_secret_free("Project Authorization: usable\n"))
}

///|
#skip("opt-in only: replaces the active Project Authorization in the default Keychain; use a dedicated macOS account and Google Cloud project")
async test "macOS Apple Silicon packaged artifact smoke publishes with Project Authorization" {
  match macos_arm64_gate() {
    Ok(_) => ()
    Err(message) => abort(message)
  }
  let (pumd, client_file) = match smoke_configuration() {
    Ok(configuration) => configuration
    Err(message) => abort(message)
  }
  match
    smoke_command_stdout(
      pumd,
      ["auth", "setup", "--client-file", client_file],
      "auth setup",
    ) {
    Ok(_) => ()
    Err(message) => abort(message)
  }
  let status = match
    smoke_command_stdout(pumd, ["auth", "status"], "auth status") {
    Ok(output) => output
    Err(message) => abort(message)
  }
  if !status.contains("Project Authorization: usable") ||
    !status.contains("credential store: macOS Keychain") ||
    !status_output_is_secret_free(status) {
    abort(
      "auth status did not report a usable, secret-free default-Keychain Project Authorization",
    )
  }
  let temporary_directory = @async_fs.tmpdir(
    prefix="pumd-project-auth-macos-smoke-",
  ) catch {
    error =>
      abort("could not create smoke Markdown directory: " + error.to_string())
  }
  let markdown_path = temporary_directory + "/pumd-project-auth-macos-smoke.md"
  @fs.write_string_to_file(
    markdown_path, "# Pumd macOS Project Authorization smoke\n\nThis document is intentional smoke-test evidence.\n",
  ) catch {
    @fs.IOError(_) => abort("could not write smoke Markdown")
  }
  let published = smoke_command_stdout(
    pumd,
    ["publish", "--auth=project", markdown_path],
    "publish --auth=project",
  )
  @async_fs.rmdir(temporary_directory, recursive=true) catch {
    _ => ()
  }
  let success = match published {
    Ok(output) =>
      match parse_macos_smoke_publish_success(output) {
        Some(result) => result
        None =>
          abort(
            "publish did not print a valid document ID and canonical edit URL",
          )
      }
    Err(message) => abort(message)
  }
  println("macOS Project Authorization smoke evidence created: " + success.url)
}
