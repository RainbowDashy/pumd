///|
/// Render a user-facing error message for the terminal. The first paragraph
/// becomes the `pumd: ` summary line, later paragraphs are indented, and
/// every paragraph is wrapped at word boundaries so long messages stay
/// readable without becoming one-line walls of text.
fn format_error_message(message : String) -> String {
  let prefix = "pumd: "
  let body_indent = "  "
  let bullet_indent = "    "
  let continuation_indent = "      "
  let wrap_width = 78
  let output = StringBuilder::new()
  let lines = message.split("\n").map(fn(line) { line.to_owned() }).collect()
  for i, line in lines {
    if i > 0 {
      output.write_char('\n')
    }
    if line.is_empty() {
      continue
    }
    let first_paragraph = i == 0
    let is_bullet = !first_paragraph && line.find("- ") == Some(0)
    let continuation = if first_paragraph {
      continuation_indent
    } else if is_bullet {
      bullet_indent
    } else {
      body_indent
    }
    let first_indent = if first_paragraph { prefix } else { body_indent }
    let width = wrap_width - continuation.length()
    let pieces = wrap_line(line, width)
    for j, piece in pieces {
      if j > 0 {
        output.write_char('\n')
        output.write_string(continuation)
      } else {
        output.write_string(first_indent)
      }
      output.write_string(piece)
    }
  }
  output.to_string()
}

///|
/// Wrap a single line at word boundaries, keeping words and URLs intact.
fn wrap_line(line : String, width : Int) -> Array[String] {
  if line.length() <= width {
    return [line]
  }
  let words = line.split(" ").map(fn(word) { word.to_owned() }).collect()
  let wrapped : Array[String] = []
  let mut current = ""
  for word in words {
    if word.is_empty() {
      continue
    }
    if current.is_empty() {
      current = word
    } else if current.length() + 1 + word.length() <= width {
      current = current + " " + word
    } else {
      wrapped.push(current)
      current = word
    }
  }
  if !current.is_empty() {
    wrapped.push(current)
  }
  wrapped
}
