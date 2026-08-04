///|
test "publish resolves Project Authorization through remembered-or-native storage" {
  match parse_command(["pumd", "publish", "proposal.md"]) {
    Ok(Publish(path, Project(RememberedOrNative))) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected native-vault Project Authorization publish command")
    Err(message) => fail(message)
  }
}

///|
test "explicit project authorization still resolves remembered-or-native storage" {
  match parse_command(["pumd", "publish", "--auth=project", "proposal.md"]) {
    Ok(Publish(path, Project(RememberedOrNative))) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected Project Authorization publish command")
    Err(message) => fail(message)
  }
}

///|
test "publish accepts the platform-neutral native store and legacy keychain alias" {
  match
    parse_command([
      "pumd", "publish", "--auth=project", "--credential-store=native", "proposal.md",
    ]) {
    Ok(Publish(path, Project(Explicit(Native)))) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected native-vault Project Authorization publish command")
    Err(message) => fail(message)
  }
  match
    parse_command([
      "pumd", "publish", "--auth=project", "--credential-store=keychain", "proposal.md",
    ]) {
    Ok(Publish(path, Project(Explicit(Native)))) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected compatibility alias to select the native vault")
    Err(message) => fail(message)
  }
}

///|
test "publish accepts an explicit file store in either option order" {
  match
    parse_command([
      "pumd", "publish", "--credential-store=file", "--auth=project", "proposal.md",
    ]) {
    Ok(Publish(path, Project(Explicit(File)))) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected file-backed Project Authorization publish command")
    Err(message) => fail(message)
  }
  match
    parse_command([
      "pumd", "publish", "--auth=project", "--credential-store=file", "proposal.md",
    ]) {
    Ok(Publish(path, Project(Explicit(File)))) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected file-backed Project Authorization publish command")
    Err(message) => fail(message)
  }
}

///|
test "publish accepts explicit ADC authorization" {
  match parse_command(["pumd", "publish", "--auth=adc", "proposal.md"]) {
    Ok(Publish(path, Adc)) => inspect(path, content="proposal.md")
    Ok(_) => fail("expected ADC publish command")
    Err(message) => fail(message)
  }
}

///|
test "publish accepts an explicit ephemeral access token environment" {
  match parse_command(["pumd", "publish", "--auth=token-env", "proposal.md"]) {
    Ok(Publish(path, AccessTokenEnvironment)) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected ephemeral access-token environment command")
    Err(message) => fail(message)
  }
}

///|
test "auth setup without a store preserves the need for an interactive choice" {
  match parse_command(["pumd", "auth", "setup"]) {
    Ok(AuthSetup(Guided, Prompt)) => ()
    Ok(_) => fail("expected guided setup to prompt for credential storage")
    Err(message) => fail(message)
  }
}

///|
test "auth setup accepts an optional client file and file store in either order" {
  match
    parse_command([
      "pumd", "auth", "setup", "--credential-store=file", "--client-file", "client.json",
    ]) {
    Ok(AuthSetup(Provided(client_file), Selected(File))) =>
      inspect(client_file, content="client.json")
    Ok(_) => fail("expected Project Authorization setup command")
    Err(message) => fail(message)
  }
}

///|
test "auth setup with a client file still prompts when the store is omitted" {
  match
    parse_command(["pumd", "auth", "setup", "--client-file", "client.json"]) {
    Ok(AuthSetup(Provided(client_file), Prompt)) =>
      inspect(client_file, content="client.json")
    Ok(_) => fail("expected direct setup to prompt for credential storage")
    Err(message) => fail(message)
  }
}

///|
test "noninteractive setup honors explicit and remembered stores without prompting" {
  guard noninteractive_setup_credential_store(Prompt, Some(File)) is File else {
    fail("remembered file storage must be reused")
  }
  guard noninteractive_setup_credential_store(Prompt, None) is Native else {
    fail("native storage must remain the no-preference default")
  }
  guard noninteractive_setup_credential_store(Selected(Native), Some(File))
    is Native else {
    fail("an explicit store must override the remembered store")
  }
}

///|
test "first-publish onboarding preserves explicit and remembered store intent" {
  guard project_onboarding_setup_store(Explicit(File), None)
    is Selected(File) else {
    fail("explicit publish storage must remain explicit during onboarding")
  }
  guard project_onboarding_setup_store(RememberedOrNative, Some(File))
    is Selected(File) else {
    fail("remembered publish storage must be reused during onboarding")
  }
  guard project_onboarding_setup_store(RememberedOrNative, None) is Prompt else {
    fail("only a new author without a preference should see the selector")
  }
}

///|
test "auth status resolves remembered storage and accepts an explicit override" {
  match parse_command(["pumd", "auth", "status"]) {
    Ok(AuthStatus(RememberedOrNative)) => ()
    Ok(_) => fail("expected native-vault authorization status command")
    Err(message) => fail(message)
  }
  match parse_command(["pumd", "auth", "status", "--credential-store=file"]) {
    Ok(AuthStatus(Explicit(File))) => ()
    Ok(_) => fail("expected authorization status command")
    Err(message) => fail(message)
  }
}

///|
test "auth logout resolves remembered storage and accepts an explicit override" {
  match parse_command(["pumd", "auth", "logout"]) {
    Ok(AuthLogout(RememberedOrNative)) => ()
    Ok(_) => fail("expected native-vault authorization logout command")
    Err(message) => fail(message)
  }
  match parse_command(["pumd", "auth", "logout", "--credential-store=file"]) {
    Ok(AuthLogout(Explicit(File))) => ()
    Ok(_) => fail("expected file authorization logout command")
    Err(message) => fail(message)
  }
}

///|
test "auth logout rejects an invalid credential store" {
  match parse_command(["pumd", "auth", "logout", "--credential-store=memory"]) {
    Ok(_) => fail("expected logout credential store validation to fail")
    Err(message) =>
      inspect(
        message,
        content="Project Authorization usage: pumd auth logout [--credential-store=native|file]",
      )
  }
}

///|
test "setup rejects a missing client file argument with Project Authorization usage" {
  match parse_command(["pumd", "auth", "setup", "--client-file"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) =>
      inspect(
        message,
        content="Project Authorization usage: pumd auth setup [--client-file <path>] [--credential-store=native|file]\nInteractive setup prompts when the store is omitted; noninteractive setup uses the remembered store or the native default without prompting.",
      )
  }
}

///|
test "publish rejects an unknown authorization mode with Project Authorization usage" {
  match parse_command(["pumd", "publish", "--auth=managed", "proposal.md"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) =>
      inspect(
        message,
        content="Project Authorization usage: pumd publish [--auth=project|adc|token-env] [--credential-store=native|file] <markdown-path>",
      )
  }
}

///|
test "auth status rejects extra arguments with Project Authorization usage" {
  match parse_command(["pumd", "auth", "status", "extra"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) =>
      inspect(
        message,
        content="Project Authorization usage: pumd auth status [--credential-store=native|file]",
      )
  }
}

///|
test "publish rejects a missing Markdown path" {
  match parse_command(["pumd", "publish"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) =>
      inspect(
        message,
        content="Project Authorization usage: pumd publish [--auth=project|adc|token-env] [--credential-store=native|file] <markdown-path>",
      )
  }
}

///|
test "publish rejects an option where its Markdown path belongs" {
  match parse_command(["pumd", "publish", "--auth=managed"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) =>
      inspect(
        message,
        content="Project Authorization usage: pumd publish [--auth=project|adc|token-env] [--credential-store=native|file] <markdown-path>",
      )
  }
}

///|
test "auth rejects a missing subcommand without indexing past the arguments" {
  match parse_command(["pumd", "auth"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) => assert_true(message.contains("Project Authorization usage"))
  }
}

///|
test "setup rejects another option where the client path belongs" {
  match
    parse_command([
      "pumd", "auth", "setup", "--client-file", "--credential-store=file", "--credential-store=file",
    ]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) => assert_true(message.contains("Project Authorization usage"))
  }
}

///|
test "explicit authorization rejects another option as the Markdown path" {
  match parse_command(["pumd", "publish", "--auth=project", "--unknown"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) => assert_true(message.contains("Project Authorization usage"))
  }
}

///|
test "ADC rejects a credential store option" {
  match
    parse_command([
      "pumd", "publish", "--auth=adc", "--credential-store=file", "proposal.md",
    ]) {
    Ok(_) => fail("expected ADC credential store validation to fail")
    Err(message) => assert_true(message.contains("Project Authorization usage"))
  }
}

///|
test "parse_publish_path remains available only for explicit ADC" {
  match parse_publish_path(["pumd", "publish", "proposal.md"]) {
    Ok(_) => fail("expected bare publish to use Project Authorization")
    Err(message) => assert_true(message.contains("Project Authorization usage"))
  }
  match parse_publish_path(["pumd", "publish", "--auth=adc", "proposal.md"]) {
    Ok(path) => inspect(path, content="proposal.md")
    Err(message) => fail(message)
  }
}
