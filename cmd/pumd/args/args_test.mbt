///|
test "publish defaults to ADC authorization" {
  match parse_command(["pumd", "publish", "proposal.md"]) {
    Ok(Publish(path, Adc)) => inspect(path, content="proposal.md")
    Ok(_) => fail("expected ADC publish command")
    Err(message) => fail(message)
  }
}

///|
test "publish accepts explicit Project Authorization" {
  match parse_command(["pumd", "publish", "--auth=project", "proposal.md"]) {
    Ok(Publish(path, Project)) => inspect(path, content="proposal.md")
    Ok(_) => fail("expected Project Authorization publish command")
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
test "auth setup accepts required options in either order" {
  match
    parse_command([
      "pumd", "auth", "setup", "--credential-store=file", "--client-file", "client.json",
    ]) {
    Ok(AuthSetup(client_file, File)) =>
      inspect(client_file, content="client.json")
    Ok(_) => fail("expected Project Authorization setup command")
    Err(message) => fail(message)
  }
}

///|
test "auth status needs no options" {
  match parse_command(["pumd", "auth", "status"]) {
    Ok(AuthStatus) => ()
    Ok(_) => fail("expected authorization status command")
    Err(message) => fail(message)
  }
}

///|
test "setup rejects a missing client file with Project Authorization usage" {
  match parse_command(["pumd", "auth", "setup", "--credential-store=file"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) =>
      inspect(
        message,
        content="Project Authorization usage: pumd auth setup --client-file <path> --credential-store=file",
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
        content="Project Authorization usage: pumd publish [--auth=project|adc] <markdown-path>",
      )
  }
}

///|
test "auth status rejects extra arguments with Project Authorization usage" {
  match parse_command(["pumd", "auth", "status", "extra"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) =>
      inspect(message, content="Project Authorization usage: pumd auth status")
  }
}

///|
test "publish rejects a missing Markdown path" {
  match parse_command(["pumd", "publish"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) =>
      inspect(
        message,
        content="Project Authorization usage: pumd publish [--auth=project|adc] <markdown-path>",
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
        content="Project Authorization usage: pumd publish [--auth=project|adc] <markdown-path>",
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
