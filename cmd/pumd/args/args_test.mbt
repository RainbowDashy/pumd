///|
test "publish defaults to ADC authorization" {
  match parse_command(["pumd", "publish", "proposal.md"]) {
    Ok(Publish(path, Adc)) => inspect(path, content="proposal.md")
    Ok(_) => fail("expected ADC publish command")
    Err(message) => fail(message)
  }
}

///|
test "publish defaults Project Authorization to the Keychain store" {
  match parse_command(["pumd", "publish", "--auth=project", "proposal.md"]) {
    Ok(Publish(path, Project(Keychain))) => inspect(path, content="proposal.md")
    Ok(_) => fail("expected Project Authorization publish command")
    Err(message) => fail(message)
  }
}

///|
test "publish accepts an explicit file store in either option order" {
  match
    parse_command([
      "pumd", "publish", "--credential-store=file", "--auth=project", "proposal.md",
    ]) {
    Ok(Publish(path, Project(File))) => inspect(path, content="proposal.md")
    Ok(_) => fail("expected file-backed Project Authorization publish command")
    Err(message) => fail(message)
  }
  match
    parse_command([
      "pumd", "publish", "--auth=project", "--credential-store=file", "proposal.md",
    ]) {
    Ok(Publish(path, Project(File))) => inspect(path, content="proposal.md")
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
test "auth setup guides a Keychain setup without a client file" {
  match parse_command(["pumd", "auth", "setup"]) {
    Ok(AuthSetup(Guided, Keychain)) => ()
    Ok(_) => fail("expected guided Keychain setup command")
    Err(message) => fail(message)
  }
}

///|
test "auth setup accepts an optional client file and file store in either order" {
  match
    parse_command([
      "pumd", "auth", "setup", "--credential-store=file", "--client-file", "client.json",
    ]) {
    Ok(AuthSetup(Provided(client_file), File)) =>
      inspect(client_file, content="client.json")
    Ok(_) => fail("expected Project Authorization setup command")
    Err(message) => fail(message)
  }
}

///|
test "auth setup accepts a direct client file with the default Keychain store" {
  match
    parse_command(["pumd", "auth", "setup", "--client-file", "client.json"]) {
    Ok(AuthSetup(Provided(client_file), Keychain)) =>
      inspect(client_file, content="client.json")
    Ok(_) => fail("expected direct Keychain setup command")
    Err(message) => fail(message)
  }
}

///|
test "auth status defaults to Keychain and accepts an explicit store" {
  match parse_command(["pumd", "auth", "status"]) {
    Ok(AuthStatus(Keychain)) => ()
    Ok(_) => fail("expected Keychain authorization status command")
    Err(message) => fail(message)
  }
  match parse_command(["pumd", "auth", "status", "--credential-store=file"]) {
    Ok(AuthStatus(File)) => ()
    Ok(_) => fail("expected authorization status command")
    Err(message) => fail(message)
  }
}

///|
test "auth logout defaults to Keychain and accepts an explicit store" {
  match parse_command(["pumd", "auth", "logout"]) {
    Ok(AuthLogout(Keychain)) => ()
    Ok(_) => fail("expected Keychain authorization logout command")
    Err(message) => fail(message)
  }
  match parse_command(["pumd", "auth", "logout", "--credential-store=file"]) {
    Ok(AuthLogout(File)) => ()
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
        content="Project Authorization usage: pumd auth logout [--credential-store=keychain|file]",
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
        content="Project Authorization usage: pumd auth setup [--client-file <path>] [--credential-store=keychain|file]",
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
        content="Project Authorization usage: pumd publish [--auth=project|adc] [--credential-store=keychain|file] <markdown-path>",
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
        content="Project Authorization usage: pumd auth status [--credential-store=keychain|file]",
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
        content="Project Authorization usage: pumd publish [--auth=project|adc] [--credential-store=keychain|file] <markdown-path>",
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
        content="Project Authorization usage: pumd publish [--auth=project|adc] [--credential-store=keychain|file] <markdown-path>",
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
test "parse_publish_path remains available only for the bare ADC command" {
  match parse_publish_path(["pumd", "publish", "proposal.md"]) {
    Ok(path) => inspect(path, content="proposal.md")
    Err(message) => fail(message)
  }
  match parse_publish_path(["pumd", "publish", "--auth=adc", "proposal.md"]) {
    Ok(_) => fail("expected explicit ADC command to use parse_command")
    Err(message) => assert_true(message.contains("Project Authorization usage"))
  }
}
