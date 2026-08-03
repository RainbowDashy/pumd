///|
/// The opt-in test in this file creates a real Google Doc and leaves it in the
/// authenticated account's Drive so the result remains available for review.

///|
fn live_smoke_markdown() -> String {
  let before_hard_break =
    #|# Pumd live smoke heading 1 🚀
    #|
    #|## Pumd live smoke heading 2
    #|
    #|### Pumd live smoke heading 3
    #|
    #|#### Pumd live smoke heading 4
    #|
    #|##### Pumd live smoke heading 5
    #|
    #|###### Pumd live smoke heading 6
    #|
    #|A **strong** and *emphasized* [direct link](https://example.com/direct) plus a [reference link][reference-target] with `inline code`.
    #|Soft break stays in this paragraph.
  let after_hard_break =
    #|第二行 with é.
    #|
    #|```text
    #|fenced code
    #|```
    #|
    #|1. ordered item
    #|   - nested item
    #|
    #|- bullet item
    #|
    #|| Header | Right |
    #|| --- | ---: |
    #|| Cell | [linked](https://example.com/table) |
    #|
    #|[reference-target]: https://example.com/reference "Reference link"
  before_hard_break + "\nHard break follows here.  \n" + after_hard_break
}

///|
fn cli_output_value(output : String, prefix : String) -> String? {
  for part in output.split("\n") {
    let line = part.to_owned()
    if line.has_prefix(prefix) {
      let value = line.unsafe_substring(
        start=prefix.length(),
        end=line.length(),
      )
      if value.has_suffix("\r") {
        return Some(value.unsafe_substring(start=0, end=value.length() - 1))
      }
      return Some(value)
    }
  }
  None
}

///|
fn parse_cli_publish_success(output : String) -> PublishSuccess? {
  let document_id = cli_output_value(output, "document ID: ")
  let url = cli_output_value(output, "edit URL: ")
  match (document_id, url) {
    (Some(document_id), Some(url)) => Some({ document_id, url })
    _ => None
  }
}

///|
fn native_pumd_binary() -> Result[String, String] {
  let candidates = [
    "_build/native/debug/build/rainbowdashy/pumd/cmd/pumd/pumd.exe", "_build/native/debug/build/rainbowdashy/pumd/cmd/pumd/pumd",
  ]
  for candidate in candidates {
    if @fs.path_exists(candidate) {
      return Ok(candidate)
    }
  }
  Err(
    "native pumd executable is missing; run `moon build --target native cmd/pumd`",
  )
}

///|
async fn run_publish_cli_in_directory(
  pumd : String,
  markdown : String,
  temporary_directory : String,
) -> Result[PublishSuccess, String] {
  let markdown_path = temporary_directory + "/pumd-live-smoke.md"
  @fs.write_string_to_file(markdown_path, markdown) catch {
    @fs.IOError(message) =>
      return Err("could not write live smoke Markdown: " + message)
  }
  let (exit_code, stdout, stderr) = @process.collect_output(pumd, [
    "publish", "--auth=adc", markdown_path,
  ])
  let stdout_text = stdout.text() catch {
    _ => return Err("could not decode pumd stdout")
  }
  let stderr_text = stderr.text() catch {
    _ => return Err("could not decode pumd stderr")
  }
  if exit_code != 0 {
    return Err(
      "pumd publish failed (exit " +
      exit_code.to_string() +
      "):\n" +
      stderr_text +
      stdout_text,
    )
  }
  match parse_cli_publish_success(stdout_text) {
    Some(success) => Ok(success)
    None =>
      Err("pumd did not print its document ID and edit URL:\n" + stdout_text)
  }
}

///|
async fn run_publish_cli(markdown : String) -> Result[PublishSuccess, String] {
  let pumd = match native_pumd_binary() {
    Ok(path) => path
    Err(message) => return Err(message)
  }
  let temporary_directory = @async_fs.tmpdir(prefix="pumd-live-smoke-") catch {
    error =>
      return Err("could not create live smoke directory: " + error.to_string())
  }
  let result = run_publish_cli_in_directory(pumd, markdown, temporary_directory)
  @async_fs.rmdir(temporary_directory, recursive=true) catch {
    _ => ()
  }
  result
}

///|
fn compact_json(value : String) -> String {
  let result = StringBuilder::new()
  let mut inside_string = false
  let mut escaped = false
  for char in value {
    if inside_string {
      result.write_char(char)
      if escaped {
        escaped = false
      } else if char == '\\' {
        escaped = true
      } else if char == '"' {
        inside_string = false
      }
    } else {
      match char {
        ' ' | '\n' | '\r' | '\t' => ()
        '"' => {
          result.write_char(char)
          inside_string = true
        }
        _ => result.write_char(char)
      }
    }
  }
  result.to_string()
}

///|
test "live readback compacts JSON without changing string values" {
  let response =
    #|{
    #|  "weightedFontFamily": {
    #|    "fontFamily": "Roboto Mono"
    #|  }
    #|}
  assert_eq(
    compact_json(response),
    "{\"weightedFontFamily\":{\"fontFamily\":\"Roboto Mono\"}}",
  )
}

///|
test "live smoke parses the native CLI publish result" {
  let output =
    #|document ID: doc-123
    #|edit URL: https://docs.google.com/document/d/doc-123/edit
  guard parse_cli_publish_success(output) is Some(success) else {
    fail("expected CLI result to parse")
  }
  assert_eq(success.document_id, "doc-123")
  assert_eq(success.url, "https://docs.google.com/document/d/doc-123/edit")
}

///|
test "live smoke fixture renders and plans locally" {
  let markdown = live_smoke_markdown()
  assert_true(markdown.contains("Pumd live smoke heading 1 🚀"))
  assert_true(markdown.contains("第二行 with é."))
  assert_true(markdown.contains("Hard break follows here.  \n"))
  let document = match @pumd.render_markdown(markdown) {
    Ok(document) => document
    Err(_) => abort("live smoke fixture must render")
  }
  match prepare_docs_update_plan(document) {
    Ok(_) => ()
    Err(error) => abort(error.message())
  }
}

///|
#skip("run explicitly after building the native CLI; performs no network access")
async test "MoonBit smoke runner drives the native CLI before network access" {
  let result = run_publish_cli("![unsupported](image.png)")
  guard result is Err(message) else {
    fail("unsupported Markdown must fail in the native CLI")
  }
  assert_true(message.contains("rendering failed"))
  assert_true(message.contains("image:"))
}

///|
#skip("run explicitly after configuring ADC; creates a real Google Doc")
async test "live smoke publishes and reads a real Google Doc" {
  let title = "pumd-live-smoke"
  let published = match run_publish_cli(live_smoke_markdown()) {
    Ok(success) => success
    Err(message) => abort(message)
  }
  let document_id = published.document_id
  let url = published.url
  assert_eq(url, canonical_document_url(document_id))
  println("REAL GOOGLE DOC CREATED: " + url)
  let token = match application_default_access_token() {
    Ok(token) => token
    Err(error) => abort(error.user_message())
  }
  let http = @google_http.DefaultHttpClient::new()
  let client = @google_core.GoogleClient::new(fn() { token }, http=Some(http))
  let document = match get_document(client, document_id) {
    Ok(document) => document
    Err(error) => abort(error.message())
  }
  assert_eq(document.document_id, document_id)
  let required_content = [
    title, "Pumd live smoke heading 1", "Pumd live smoke heading 2", "Pumd live smoke heading 3",
    "Pumd live smoke heading 4", "Pumd live smoke heading 5", "Pumd live smoke heading 6",
    "strong", "emphasized", "https://example.com/direct", "reference link", "https://example.com/reference",
    "inline code", "fenced code", "第二行", "ordered item", "nested item", "bullet item",
    "Header", "linked",
  ]
  for fragment in required_content {
    assert_true(document.body.contains(fragment))
  }
  let compact_response = compact_json(document.body)
  let required_structure = [
    "\"namedStyleType\":\"HEADING_1\"", "\"namedStyleType\":\"HEADING_2\"", "\"namedStyleType\":\"HEADING_3\"",
    "\"namedStyleType\":\"HEADING_4\"", "\"namedStyleType\":\"HEADING_5\"", "\"namedStyleType\":\"HEADING_6\"",
    "\"bold\":true", "\"italic\":true", "Roboto Mono", "\"bullet\"", "\"table\"",
    "\"backgroundColor\"", "\"alignment\":\"END\"",
  ]
  for fragment in required_structure {
    assert_true(compact_response.contains(fragment))
  }
  println("Live smoke passed: " + url)
}
