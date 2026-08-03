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
fn macos_smoke_inputs() -> Result[PackagedSmokeInputs, String] {
  packaged_smoke_inputs({
    opt_in_environment: "PUMD_MACOS_PROJECT_AUTH_SMOKE",
    opt_in_error: "set PUMD_MACOS_PROJECT_AUTH_SMOKE=1 to acknowledge that this replaces the active Project Authorization in the default Keychain; use a dedicated test account and project",
    binary_environment: "PUMD_MACOS_SMOKE_BINARY",
    binary_path_error: "PUMD_MACOS_SMOKE_BINARY must name a prebuilt packaged pumd binary",
    client_file_environment: "PUMD_MACOS_SMOKE_CLIENT_FILE",
    client_file_path_error: "PUMD_MACOS_SMOKE_CLIENT_FILE must name a Desktop OAuth client JSON file",
  })
}

///|
#skip("opt-in only: replaces the active Project Authorization in the default Keychain; use a dedicated macOS account and Google Cloud project")
async test "macOS Apple Silicon packaged artifact smoke publishes with Project Authorization" {
  match macos_arm64_gate() {
    Ok(_) => ()
    Err(message) => abort(message)
  }
  let inputs = match macos_smoke_inputs() {
    Ok(inputs) => inputs
    Err(message) => abort(message)
  }
  let success = run_packaged_project_authorization_smoke(
    "macOS",
    "macOS Keychain",
    inputs.pumd,
    inputs.client_file,
  )
  println("macOS Project Authorization smoke evidence created: " + success.url)
}
