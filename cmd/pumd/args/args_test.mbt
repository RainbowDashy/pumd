///|
test "publish resolves Project Authorization through remembered-or-native storage" {
  match parse_command(["pumd", "publish", "proposal.md"]) {
    Ok(Publish(path, Project(RememberedOrNative), false)) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected native-vault Project Authorization publish command")
    Err(message) => fail(message)
  }
}

///|
test "explicit project authorization still resolves remembered-or-native storage" {
  match parse_command(["pumd", "publish", "--auth=project", "proposal.md"]) {
    Ok(Publish(path, Project(RememberedOrNative), false)) =>
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
    Ok(Publish(path, Project(Explicit(Native)), false)) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected native-vault Project Authorization publish command")
    Err(message) => fail(message)
  }
  match
    parse_command([
      "pumd", "publish", "--auth=project", "--credential-store=keychain", "proposal.md",
    ]) {
    Ok(Publish(path, Project(Explicit(Native)), false)) =>
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
    Ok(Publish(path, Project(Explicit(File)), false)) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected file-backed Project Authorization publish command")
    Err(message) => fail(message)
  }
  match
    parse_command([
      "pumd", "publish", "--auth=project", "--credential-store=file", "proposal.md",
    ]) {
    Ok(Publish(path, Project(Explicit(File)), false)) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected file-backed Project Authorization publish command")
    Err(message) => fail(message)
  }
}

///|
test "publish accepts explicit ADC authorization" {
  match parse_command(["pumd", "publish", "--auth=adc", "proposal.md"]) {
    Ok(Publish(path, Adc, false)) => inspect(path, content="proposal.md")
    Ok(_) => fail("expected ADC publish command")
    Err(message) => fail(message)
  }
}

///|
test "publish accepts an explicit ephemeral access token environment" {
  match parse_command(["pumd", "publish", "--auth=token-env", "proposal.md"]) {
    Ok(Publish(path, AccessTokenEnvironment, false)) =>
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
  guard project_onboarding_setup_store(Explicit(File), None) is Selected(File) else {
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
        content="Project Authorization usage: pumd publish [--dry-run] [--auth=project|adc|token-env] [--credential-store=native|file] <markdown-path>",
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
        content="Project Authorization usage: pumd publish [--dry-run] [--auth=project|adc|token-env] [--credential-store=native|file] <markdown-path>",
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
        content="Project Authorization usage: pumd publish [--dry-run] [--auth=project|adc|token-env] [--credential-store=native|file] <markdown-path>",
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

///|
test "list accepts its optional flags in either order" {
  match parse_command(["pumd", "list"]) {
    Ok(List({ json: false, refresh: false })) => ()
    Ok(_) => fail("expected bare list command")
    Err(message) => fail(message)
  }
  match parse_command(["pumd", "list", "--json"]) {
    Ok(List({ json: true, refresh: false })) => ()
    Ok(_) => fail("expected JSON list command")
    Err(message) => fail(message)
  }
  match parse_command(["pumd", "list", "--refresh"]) {
    Ok(List({ json: false, refresh: true })) => ()
    Ok(_) => fail("expected refreshed list command")
    Err(message) => fail(message)
  }
  match parse_command(["pumd", "list", "--refresh", "--json"]) {
    Ok(List({ json: true, refresh: true })) => ()
    Ok(_) => fail("expected JSON refreshed list command")
    Err(message) => fail(message)
  }
  match parse_command(["pumd", "list", "--json", "--refresh"]) {
    Ok(List({ json: true, refresh: true })) => ()
    Ok(_) => fail("expected JSON refreshed list command")
    Err(message) => fail(message)
  }
}

///|
test "list rejects unknown, repeated, and positional arguments" {
  for
    arguments in [
      ["pumd", "list", "--unknown"],
      ["pumd", "list", "--json", "--json"],
      ["pumd", "list", "notes.md"],
    ] {
    match parse_command(arguments) {
      Ok(_) => fail("expected list argument validation to fail")
      Err(message) =>
        inspect(
          message,
          content="Project Authorization usage: pumd list [--json] [--refresh]",
        )
    }
  }
}

///|
test "move and forget validate positional paths" {
  match parse_command(["pumd", "move", "old.md", "new.md"]) {
    Ok(Move(old_path, new_path)) => {
      inspect(old_path, content="old.md")
      inspect(new_path, content="new.md")
    }
    Ok(_) => fail("expected move command")
    Err(message) => fail(message)
  }
  match parse_command(["pumd", "forget", "old.md"]) {
    Ok(Forget(path)) => inspect(path, content="old.md")
    Ok(_) => fail("expected forget command")
    Err(message) => fail(message)
  }
  for
    arguments in [
      ["pumd", "move", "old.md"],
      ["pumd", "move", "--old", "new.md"],
      ["pumd", "move", "", "new.md"],
      ["pumd", "forget"],
      ["pumd", "forget", "--path"],
      ["pumd", "forget", ""],
    ] {
    match parse_command(arguments) {
      Ok(_) => fail("expected path validation to fail")
      Err(_) => ()
    }
  }
}

///|
test "publish accepts dry-run in any position with supported options" {
  match parse_command(["pumd", "publish", "--dry-run", "proposal.md"]) {
    Ok(Publish(path, Project(RememberedOrNative), true)) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected dry-run Project Authorization publish command")
    Err(message) => fail(message)
  }
  match
    parse_command(["pumd", "publish", "--auth=adc", "--dry-run", "proposal.md"]) {
    Ok(Publish(path, Adc, true)) => inspect(path, content="proposal.md")
    Ok(_) => fail("expected dry-run ADC publish command")
    Err(message) => fail(message)
  }
  match
    parse_command([
      "pumd", "publish", "--dry-run", "--auth=project", "--credential-store=file",
      "proposal.md",
    ]) {
    Ok(Publish(path, Project(Explicit(File)), true)) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected dry-run file-backed publish command")
    Err(message) => fail(message)
  }
  match
    parse_command([
      "pumd", "publish", "proposal.md", "--credential-store=file", "--dry-run",
    ]) {
    Ok(Publish(path, Project(Explicit(File)), true)) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected trailing dry-run file-backed publish command")
    Err(message) => fail(message)
  }
}

///|
test "publish rejects duplicate or pathless dry-run" {
  for
    arguments in [
      ["pumd", "publish", "--dry-run", "--dry-run", "proposal.md"],
      ["pumd", "publish", "--dry-run"],
    ] {
    match parse_command(arguments) {
      Ok(_) => fail("expected dry-run validation to fail")
      Err(message) =>
        assert_true(message.contains("Project Authorization usage"))
    }
  }
}

///|
test "pull accepts remote-read authorization and reporting options in any position" {
  match parse_command(["pumd", "pull", "proposal.md"]) {
    Ok(Pull(path, Project(RememberedOrNative), false, false)) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected Project Authorization pull command")
    Err(message) => fail(message)
  }
  match
    parse_command([
      "pumd", "pull", "--dry-run", "--json", "--auth=adc", "proposal.md",
    ]) {
    Ok(Pull(path, Adc, true, true)) => inspect(path, content="proposal.md")
    Ok(_) => fail("expected JSON dry-run ADC pull command")
    Err(message) => fail(message)
  }
  match
    parse_command([
      "pumd", "pull", "proposal.md", "--credential-store=file", "--json", "--dry-run",
    ]) {
    Ok(Pull(path, Project(Explicit(File)), true, true)) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected trailing pull options")
    Err(message) => fail(message)
  }
  match parse_command(["pumd", "pull", "--auth=token-env", "proposal.md"]) {
    Ok(Pull(path, AccessTokenEnvironment, false, false)) =>
      inspect(path, content="proposal.md")
    Ok(_) => fail("expected ephemeral-token pull command")
    Err(message) => fail(message)
  }
}

///|
test "pull rejects duplicate flags, unknown options, and missing or duplicate paths" {
  for
    arguments in [
      ["pumd", "pull"],
      ["pumd", "pull", "--dry-run"],
      ["pumd", "pull", "--dry-run", "--dry-run", "proposal.md"],
      ["pumd", "pull", "--json", "--json", "proposal.md"],
      ["pumd", "pull", "--unknown", "proposal.md"],
      ["pumd", "pull", "one.md", "two.md"],
      ["pumd", "pull", "--auth=adc", "--credential-store=file", "proposal.md"],
    ] {
    match parse_command(arguments) {
      Ok(_) => fail("expected pull validation to fail")
      Err(message) => assert_true(message.contains("pumd pull"))
    }
  }
}

///|
test "pull abort is a distinct unauthenticated command and rejects remote options" {
  match parse_command(["pumd", "pull", "--abort", "proposal.md"]) {
    Ok(PullAbort(path)) => inspect(path, content="proposal.md")
    _ => fail("expected pull abort command")
  }
  match parse_command(["pumd", "pull", "proposal.md", "--abort"]) {
    Ok(PullAbort(path)) => inspect(path, content="proposal.md")
    _ => fail("expected trailing pull abort command")
  }
  for
    args in [
      ["pumd", "pull", "--abort"],
      ["pumd", "pull", "--abort", "--auth=adc", "proposal.md"],
      ["pumd", "pull", "--abort", "--dry-run", "proposal.md"],
      ["pumd", "pull", "--abort", "--json", "proposal.md"],
    ] {
    guard parse_command(args) is Err(_) else {
      fail("pull abort must reject missing paths and remote options")
    }
  }
}

///|
test "resolve accepts publish authorization options without dry-run" {
  match parse_command(["pumd", "resolve", "proposal.md"]) {
    Ok(Resolve(path, Project(RememberedOrNative))) =>
      inspect(path, content="proposal.md")
    _ => fail("expected default Project Authorization resolve")
  }
  match
    parse_command([
      "pumd", "resolve", "--auth=project", "--credential-store=file", "proposal.md",
    ]) {
    Ok(Resolve(path, Project(Explicit(File)))) =>
      inspect(path, content="proposal.md")
    _ => fail("expected file-backed Project Authorization resolve")
  }
  match parse_command(["pumd", "resolve", "proposal.md", "--auth=adc"]) {
    Ok(Resolve(path, Adc)) => inspect(path, content="proposal.md")
    _ => fail("expected ADC resolve")
  }
  for
    args in [
      ["pumd", "resolve"],
      ["pumd", "resolve", "--dry-run", "proposal.md"],
      ["pumd", "resolve", "one.md", "two.md"],
    ] {
    guard parse_command(args) is Err(_) else {
      fail("resolve must reject invalid arguments")
    }
  }
}

///|
test "unknown commands return command usage" {
  match parse_command(["pumd", "frobnicate"]) {
    Ok(_) => fail("expected unknown command validation to fail")
    Err(message) =>
      assert_true(message.contains("pumd list [--json] [--refresh]"))
  }
}

///|
test "parse_publish_path rejects dry-run forms" {
  match
    parse_publish_path([
      "pumd", "publish", "--auth=adc", "--dry-run", "proposal.md",
    ]) {
    Ok(_) =>
      fail(
        "expected dry-run ADC publish to stay outside the compatibility seam",
      )
    Err(message) => assert_true(message.contains("Project Authorization usage"))
  }
}
