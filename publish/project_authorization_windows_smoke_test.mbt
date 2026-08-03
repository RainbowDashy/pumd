///|
fn windows_x64_gate() -> Result[Unit, String] {
  match (@env.get_env_var("OS"), @env.get_env_var("PROCESSOR_ARCHITECTURE")) {
    (Some("Windows_NT"), Some("AMD64")) => Ok(())
    _ => Err("this smoke test requires Windows x64")
  }
}

///|
fn windows_smoke_inputs() -> Result[PackagedSmokeInputs, String] {
  packaged_smoke_inputs({
    opt_in_environment: "PUMD_WINDOWS_PROJECT_AUTH_SMOKE",
    opt_in_error: "set PUMD_WINDOWS_PROJECT_AUTH_SMOKE=1 to acknowledge replacement of the active native-vault authorization",
    binary_environment: "PUMD_WINDOWS_SMOKE_BINARY",
    binary_path_error: "Windows smoke binary and Desktop OAuth client file must exist",
    client_file_environment: "PUMD_WINDOWS_SMOKE_CLIENT_FILE",
    client_file_path_error: "Windows smoke binary and Desktop OAuth client file must exist",
  })
}

///|
#skip("opt-in only: replaces native-vault Project Authorization and creates a real Google Doc")
async test "Windows x64 packaged artifact smoke publishes with Project Authorization" {
  match windows_x64_gate() {
    Ok(_) => ()
    Err(message) => abort(message)
  }
  let inputs = match windows_smoke_inputs() {
    Ok(inputs) => inputs
    Err(message) => abort(message)
  }
  let success = run_packaged_project_authorization_smoke(
    "Windows",
    "Windows Credential Manager",
    inputs.pumd,
    inputs.client_file,
  )
  println(
    "Windows Project Authorization smoke evidence created: " + success.url,
  )
}
