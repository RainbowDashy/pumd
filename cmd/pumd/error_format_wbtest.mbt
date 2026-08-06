///|
test "format_error_message keeps short messages on one line" {
  assert_eq(format_error_message("short failure"), "pumd: short failure")
}

///|
test "format_error_message preserves paragraphs and indents the body" {
  let message = "authentication failed\n\nGoogle rejected the credentials.\n\nRun `pumd auth setup`."
  assert_eq(
    format_error_message(message),
    "pumd: authentication failed\n\n  Google rejected the credentials.\n\n  Run `pumd auth setup`.",
  )
}

///|
test "format_error_message wraps long lines with a hanging indent" {
  let message = "this first paragraph is long enough that it must wrap onto a second line for readability"
  let formatted = format_error_message(message)
  assert_true(formatted.contains("pumd: this first paragraph"))
  assert_true(formatted.contains("\n      for readability"))
  for line in formatted.split("\n") {
    assert_true(line.length() <= 78)
  }
}

///|
test "format_error_message aligns wrapped bullet continuations" {
  let message = "rendering failed\n- frontmatter: Remove the YAML frontmatter; document metadata is not supported."
  let formatted = format_error_message(message)
  assert_true(formatted.contains("\n  - frontmatter: Remove the YAML"))
  assert_true(formatted.contains("\n    supported."))
}

///|
test "wrap_line breaks at word boundaries" {
  assert_eq(wrap_line("aa bb cc dd ee", 7), ["aa bb", "cc dd", "ee"])
}

///|
test "wrap_line keeps short lines and long words intact" {
  assert_eq(wrap_line("short", 10), ["short"])
  assert_eq(
    wrap_line("https://example.com/very/long/url", 10),
    ["https://example.com/very/long/url"],
  )
}
