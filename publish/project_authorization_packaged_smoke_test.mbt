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
fn parse_packaged_smoke_publish_success(output : String) -> PublishSuccess? {
  let document_id = smoke_cli_output_value(output, "document ID: ")
  let url = smoke_cli_output_value(output, "edit URL: ")
  match (document_id, url) {
    (Some(document_id), Some(url)) if !document_id.is_empty() &&
      url == canonical_document_url(document_id) => Some({ document_id, url })
    _ => None
  }
}

///|
test "packaged Project Authorization smoke parses only a canonical publish identity" {
  let output =
    #|document ID: smoke-doc-123
    #|edit URL: https://docs.google.com/document/d/smoke-doc-123/edit
  guard parse_packaged_smoke_publish_success(output) is Some(success) else {
    fail("expected canonical publish identity")
  }
  assert_eq(success.document_id, "smoke-doc-123")
  assert_eq(
    success.url,
    "https://docs.google.com/document/d/smoke-doc-123/edit",
  )
}

///|
test "packaged Project Authorization smoke rejects a noncanonical publish URL" {
  let output =
    #|document ID: smoke-doc-123
    #|edit URL: https://example.test/document/d/smoke-doc-123/edit
  assert_eq(parse_packaged_smoke_publish_success(output), None)
}

///|
fn smoke_env(name : String) -> Result[String, String] {
  match @env.get_env_var(name) {
    Some(value) if !value.is_empty() => Ok(value)
    _ => Err("set " + name + " before running this opt-in smoke test")
  }
}

///|
priv struct PackagedSmokeConfiguration {
  opt_in_environment : String
  opt_in_error : String
  binary_environment : String
  binary_path_error : String
  client_file_environment : String
  client_file_path_error : String
}

///|
priv struct PackagedSmokeInputs {
  pumd : String
  client_file : String
}

///|
fn packaged_smoke_inputs(
  configuration : PackagedSmokeConfiguration,
) -> Result[PackagedSmokeInputs, String] {
  match @env.get_env_var(configuration.opt_in_environment) {
    Some("1") => ()
    _ => return Err(configuration.opt_in_error)
  }
  let pumd = match smoke_env(configuration.binary_environment) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let client_file = match smoke_env(configuration.client_file_environment) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if !@fs.path_exists(pumd) {
    return Err(configuration.binary_path_error)
  }
  if !@fs.path_exists(client_file) {
    return Err(configuration.client_file_path_error)
  }
  Ok({ pumd, client_file })
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
async fn run_packaged_project_authorization_smoke(
  platform_name : String,
  expected_store_label : String,
  pumd : String,
  client_file : String,
) -> PublishSuccess {
  match
    smoke_command_stdout(
      pumd,
      [
        "auth", "setup", "--client-file", client_file, "--credential-store=native",
      ],
      "auth setup",
    ) {
    Ok(_) => ()
    Err(message) => abort(message)
  }
  match
    smoke_command_stdout(
      pumd,
      [
        "auth", "setup", "--client-file", client_file, "--credential-store=native",
      ],
      "auth replacement",
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
    !status.contains("credential store: " + expected_store_label) ||
    !status_output_is_secret_free(status) {
    abort(
      platform_name +
      " auth status was not usable, native-vault-backed, and secret-free",
    )
  }
  let directory = @async_fs.tmpdir(prefix="pumd-project-auth-packaged-smoke-") catch {
    error => abort("could not create smoke directory: " + error.to_string())
  }
  let markdown_path = directory + "/smoke.md"
  @fs.write_string_to_file(
    markdown_path,
    "# " + platform_name + " Project Authorization smoke\n",
  ) catch {
    @fs.IOError(_) => abort("could not write smoke Markdown")
  }
  let published = smoke_command_stdout(
    pumd,
    ["publish", markdown_path],
    "publish",
  )
  guard published is Ok(output) else { abort("packaged publish failed") }
  guard parse_packaged_smoke_publish_success(output) is Some(success) else {
    abort("publish did not print a canonical document identity")
  }
  // Create-then-update identity: republishing the same source must update the
  // same document and Managed Tab in place.
  @fs.write_string_to_file(
    markdown_path,
    "# " + platform_name + " Project Authorization smoke updated\n",
  ) catch {
    @fs.IOError(_) => abort("could not write updated smoke Markdown")
  }
  let updated_output = smoke_command_stdout(
    pumd,
    ["publish", markdown_path],
    "update publish",
  )
  guard updated_output is Ok(update_text) else {
    abort("packaged update publish failed")
  }
  if !update_text.contains("Publication updated.") {
    abort("update publish did not report an in-place update:\n" + update_text)
  }
  guard parse_packaged_smoke_publish_success(update_text) is Some(updated) else {
    abort("update publish did not print a canonical document identity")
  }
  if updated.document_id != success.document_id {
    abort("update must reuse the created document identity")
  }
  // Dry-run runs the full inspection pipeline without writing.
  let dry_run = smoke_command_stdout(
    pumd,
    ["publish", "--dry-run", markdown_path],
    "dry-run",
  )
  guard dry_run is Ok(dry_text) else { abort("packaged dry-run failed") }
  if !dry_text.contains("planned structural units: 0") ||
    !dry_text.contains("No remote write or registry change was performed.") {
    abort("dry-run did not report a zero-write inspection:\n" + dry_text)
  }
  // Offline listing must enumerate the local Publication Registry.
  let listed = smoke_command_stdout(pumd, ["list", "--json"], "list")
  guard listed is Ok(list_text) else { abort("packaged list failed") }
  if !list_text.contains(success.document_id) {
    abort("list must include the created Publication")
  }
  // Reassociation and forgetting must update only the local relationship.
  let moved_path = directory + "/smoke-moved.md"
  @fs.write_string_to_file(
    moved_path,
    "# " + platform_name + " Project Authorization smoke moved\n",
  ) catch {
    @fs.IOError(_) => abort("could not write moved smoke Markdown")
  }
  let moved = smoke_command_stdout(
    pumd,
    ["move", markdown_path, moved_path],
    "move",
  )
  guard moved is Ok(_) else { abort("packaged move failed") }
  let forgotten = smoke_command_stdout(
    pumd,
    ["forget", moved_path],
    "forget",
  )
  guard forgotten is Ok(_) else { abort("packaged forget failed") }
  @async_fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
  match smoke_command_stdout(pumd, ["auth", "logout"], "auth logout") {
    Ok(_) => ()
    Err(message) => abort(message)
  }
  let logged_out = match
    smoke_command_stdout(pumd, ["auth", "status"], "logged-out auth status") {
    Ok(output) => output
    Err(message) => abort(message)
  }
  if !logged_out.contains("Project Authorization: not configured") ||
    !logged_out.contains("credential store: " + expected_store_label) ||
    !status_output_is_secret_free(logged_out) {
    abort(
      platform_name +
      " packaged logout did not delete the remembered native-vault credential",
    )
  }
  success
}

///|
test "packaged Project Authorization smoke recognizes secret-bearing status labels" {
  assert_true(
    !status_output_is_secret_free("refresh_token: should-never-print"),
  )
  assert_true(status_output_is_secret_free("Project Authorization: usable\n"))
}
