///|
test "publish accepts exactly one Markdown path" {
  match parse_publish_path(["pumd", "publish", "proposal.md"]) {
    Ok(path) => inspect(path, content="proposal.md")
    Err(message) => fail(message)
  }
}

///|
test "publish rejects a missing Markdown path" {
  match parse_publish_path(["pumd", "publish"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) =>
      inspect(message, content="usage: pumd publish <markdown-path>")
  }
}

///|
test "publish rejects extra arguments" {
  match parse_publish_path(["pumd", "publish", "one.md", "two.md"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) =>
      inspect(message, content="usage: pumd publish <markdown-path>")
  }
}

///|
test "publish rejects an unknown command" {
  match parse_publish_path(["pumd", "render", "proposal.md"]) {
    Ok(_) => fail("expected argument validation to fail")
    Err(message) =>
      inspect(message, content="usage: pumd publish <markdown-path>")
  }
}
