///|
async fn linux_x64_gate() -> Result[Unit, String] {
  let (system_exit, system_stdout, _) = @process.collect_output("uname", ["-s"])
  let (machine_exit, machine_stdout, _) = @process.collect_output("uname", [
    "-m",
  ])
  let system = system_stdout.text() catch {
    _ => return Err("could not determine operating system")
  }
  let machine = machine_stdout.text() catch {
    _ => return Err("could not determine machine architecture")
  }
  if system_exit != 0 || system.trim() != "Linux" {
    return Err("this smoke test requires Linux")
  }
  if machine_exit != 0 ||
    (machine.trim() != "x86_64" && machine.trim() != "amd64") {
    return Err("this smoke test requires Linux x64")
  }
  Ok(())
}

///|
fn linux_smoke_inputs() -> Result[PackagedSmokeInputs, String] {
  packaged_smoke_inputs({
    opt_in_environment: "PUMD_LINUX_PROJECT_AUTH_SMOKE",
    opt_in_error: "set PUMD_LINUX_PROJECT_AUTH_SMOKE=1 to acknowledge replacement of the active native-vault authorization",
    binary_environment: "PUMD_LINUX_SMOKE_BINARY",
    binary_path_error: "Linux smoke binary and Desktop OAuth client file must exist",
    client_file_environment: "PUMD_LINUX_SMOKE_CLIENT_FILE",
    client_file_path_error: "Linux smoke binary and Desktop OAuth client file must exist",
  })
}

///|
#skip("opt-in only: replaces native-vault Project Authorization and creates a real Google Doc")
async test "Linux x64 packaged artifact smoke publishes with Project Authorization" {
  match linux_x64_gate() {
    Ok(_) => ()
    Err(message) => abort(message)
  }
  let inputs = match linux_smoke_inputs() {
    Ok(inputs) => inputs
    Err(message) => abort(message)
  }
  let success = run_packaged_project_authorization_smoke(
    "Linux",
    "Linux Secret Service",
    inputs.pumd,
    inputs.client_file,
  )
  println("Linux Project Authorization smoke evidence created: " + success.url)
}
