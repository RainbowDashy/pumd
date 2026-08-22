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
  assert_true(message.contains("image-source:"))
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
  let adc_http = adc_quota_http_client(http, adc_quota_project_id())
  let client = @google_core.GoogleClient::new(
    fn() { token },
    http=Some(adc_http),
  )
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

///|
fn updated_live_smoke_markdown() -> String {
  live_smoke_markdown() +
  "\n# Pumd live smoke update heading\n\nLIVE SMOKE UPDATED CONTENT 🚀\n"
}

///|
async fn run_publish_cli_and_return_output(
  pumd : String,
  markdown : String,
  temporary_directory : String,
) -> Result[String, String] {
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
  Ok(stdout_text)
}

///|
#skip("run explicitly after configuring ADC; creates and updates a real Google Doc")
async test "live smoke creates, updates, and re-reads one real Google Doc" {
  let pumd = match native_pumd_binary() {
    Ok(path) => path
    Err(message) => abort(message)
  }
  let temporary_directory = @async_fs.tmpdir(prefix="pumd-live-update-") catch {
    error => abort("could not create live smoke directory: " + error.to_string())
  }
  let first_output = match (run_publish_cli_and_return_output(pumd, live_smoke_markdown(), temporary_directory)) {
    Ok(output) => output
    Err(message) => abort(message)
  }
  let created = match parse_cli_publish_success(first_output) {
    Some(success) => success
    None => abort("first publish must print the document ID and edit URL:\n" + first_output)
  }
  println("REAL GOOGLE DOC CREATED: " + created.url)

  // Republish the same Markdown: no local changes must produce a no-op.
  let noop_output = match (run_publish_cli_and_return_output(pumd, live_smoke_markdown(), temporary_directory)) {
    Ok(output) => output
    Err(message) => abort(message)
  }
  assert_true(noop_output.contains("no local changes"))
  let noop_identity = match parse_cli_publish_success(noop_output) {
    Some(success) => success
    None => abort("no-op publish must still print identity:\n" + noop_output)
  }
  assert_eq(noop_identity.document_id, created.document_id)

  // Republish with a local change: the same document and Managed Tab must be
  // updated in place.
  let update_output = match (run_publish_cli_and_return_output(pumd, updated_live_smoke_markdown(), temporary_directory)) {
    Ok(output) => output
    Err(message) => abort(message)
  }
  assert_true(update_output.contains("Publication updated."))
  let updated = match parse_cli_publish_success(update_output) {
    Some(success) => success
    None => abort("update publish must print identity:\n" + update_output)
  }
  assert_eq(updated.document_id, created.document_id)
  assert_eq(updated.url, created.url)

  let token = match application_default_access_token() {
    Ok(token) => token
    Err(error) => abort(error.user_message())
  }
  let http = @google_http.DefaultHttpClient::new()
  let adc_http = adc_quota_http_client(http, adc_quota_project_id())
  let client = @google_core.GoogleClient::new(
    fn() { token },
    http=Some(adc_http),
  )
  let document = match get_document(client, created.document_id) {
    Ok(document) => document
    Err(error) => abort(error.message())
  }
  assert_eq(document.document_id, created.document_id)
  assert_true(document.body.contains("Pumd live smoke update heading"))
  assert_true(document.body.contains("LIVE SMOKE UPDATED CONTENT"))
  // The reviewer-owned title and the Managed Tab must survive the update.
  let decoded = match decode_remote_document(document.body, created.document_id) {
    Ok(decoded) => decoded
    Err(error) => abort(error.user_message())
  }
  assert_true(decoded.tabs.length() >= 1)
  println("Live update smoke passed: " + created.url)
  @async_fs.rmdir(temporary_directory, recursive=true) catch {
    _ => ()
  }
}

///|
#skip("run explicitly after configuring ADC; exercises the native Pull and Pending Merge lifecycle against one real Google Doc")
async test "live Publication Pull smoke covers abort and Pending Merge resolution" {
  run_live_publication_pull_lifecycle()
}

///|
priv struct LiveCliResult {
  exit_code : Int
  stdout : String
  stderr : String
}

///|
async fn run_live_cli(
  pumd : String,
  arguments : Array[String],
  configuration_root : String,
) -> LiveCliResult {
  let (exit_code, stdout, stderr) = @process.collect_output(pumd, arguments, extra_env={
    "XDG_CONFIG_HOME": configuration_root,
  })
  {
    exit_code,
    stdout: stdout.text() catch {
      _ => abort("could not decode pumd stdout")
    },
    stderr: stderr.text() catch {
      _ => abort("could not decode pumd stderr")
    },
  }
}

///|
fn live_paragraph_text(paragraph : RemoteParagraph) -> String {
  let text = StringBuilder::new()
  for run in paragraph.runs {
    text.write_string(run.text)
  }
  text.to_string()
}

///|
fn live_json_string(value : String) -> String {
  let output = StringBuilder::new()
  output.write_char('"')
  for char in value {
    match char {
      '"' => output.write_string("\\\"")
      '\\' => output.write_string("\\\\")
      '\n' => output.write_string("\\n")
      '\r' => output.write_string("\\r")
      '\t' => output.write_string("\\t")
      _ => output.write_char(char)
    }
  }
  output.write_char('"')
  output.to_string()
}

///|
async fn replace_live_remote_paragraph(
  client : @google_core.GoogleClient,
  document_id : String,
  tab_id : String,
  expected : String,
  replacement : String,
) -> Unit {
  let retrieved = match get_document(client, document_id) {
    Ok(document) => document
    Err(error) => abort(error.message())
  }
  let remote = match decode_remote_document(retrieved.body, document_id) {
    Ok(document) => document
    Err(error) => abort(error.user_message())
  }
  let content = match remote_tab_content(remote, tab_id) {
    Some(content) => content
    None => abort("live Publication Managed Tab disappeared")
  }
  let mut target : RemoteParagraph? = None
  for unit in content.units {
    match unit {
      Paragraph(paragraph) if live_paragraph_text(paragraph) == expected =>
        target = Some(paragraph)
      _ => ()
    }
  }
  guard target is Some(paragraph) else {
    abort("could not find the live paragraph to replace: " + expected)
  }
  let body = "{\"requests\":[{\"deleteContentRange\":{\"range\":{\"startIndex\":" +
    paragraph.start_index.to_string() +
    ",\"endIndex\":" +
    (paragraph.end_index - 1).to_string() +
    ",\"tabId\":" +
    live_json_string(tab_id) +
    "}}},{\"insertText\":{\"location\":{\"index\":" +
    paragraph.start_index.to_string() +
    ",\"tabId\":" +
    live_json_string(tab_id) +
    "},\"text\":" +
    live_json_string(replacement) +
    "}}]}"
  let request = @google_http.HttpRequest::new(
    "https://docs.googleapis.com/v1/documents/" + document_id + ":batchUpdate",
    @google_http.HttpMethod::POST,
    { "Content-Type": "application/json" },
    body=Some(body),
  )
  let response = client.request(request) catch {
    @google_http.HttpError::NetworkError(message) => abort(message)
    @google_http.HttpError::TimeoutError(message) => abort(message)
    @google_http.HttpError::InvalidUrl(message) => abort(message)
  }
  if response.status_code < 200 || response.status_code >= 300 {
    abort(
      "live reviewer edit failed with HTTP " +
      response.status_code.to_string() +
      ": " +
      response.body,
    )
  }
}

///|
async fn run_live_publication_pull_lifecycle() -> Unit {
  let pumd = match native_pumd_binary() {
    Ok(path) => path
    Err(message) => abort(message)
  }
  let directory = @async_fs.tmpdir(prefix="pumd-live-sync-") catch {
    error =>
      abort(
        "could not create live Publication Pull directory: " + error.to_string(),
      )
  }
  let configuration_root = directory + "/config"
  let markdown_path = directory + "/publication.md"
  let initial = "# Pumd Publication Pull smoke\n\nPublished Baseline paragraph.\n"
  @fs.write_string_to_file(markdown_path, initial) catch {
    @fs.IOError(message) =>
      abort("could not write live Publication Markdown: " + message)
  }

  let published = run_live_cli(
    pumd,
    ["publish", "--auth=adc", markdown_path],
    configuration_root,
  )
  if published.exit_code != 0 {
    abort("live publish failed:\n" + published.stderr + published.stdout)
  }
  let success = match parse_cli_publish_success(published.stdout) {
    Some(success) => success
    None => abort("live publish did not report its Publication identity")
  }
  println("REAL GOOGLE DOC CREATED: " + success.url)

  let token = match application_default_access_token() {
    Ok(token) => token
    Err(error) => abort(error.user_message())
  }
  let http = @google_http.DefaultHttpClient::new()
  let adc_http = adc_quota_http_client(http, adc_quota_project_id())
  let client = @google_core.GoogleClient::new(
    fn() { token },
    http=Some(adc_http),
  )
  let view = match get_document_view(client, success.document_id) {
    Ok(view) => view
    Err(error) => abort(error.message())
  }
  guard view.tab_ids is [tab_id, ..] else {
    abort("live Publication document has no Managed Tab")
  }

  replace_live_remote_paragraph(
    client,
    success.document_id,
    tab_id,
    "Published Baseline paragraph.\n",
    "Reviewer clean edit.",
  )
  let dry_run = run_live_cli(
    pumd,
    ["pull", "--auth=adc", "--dry-run", "--json", markdown_path],
    configuration_root,
  )
  assert_eq(dry_run.exit_code, 0)
  assert_true(dry_run.stdout.contains("\"dry_run\":true"))
  assert_true(dry_run.stdout.contains("\"incoming\":1"))
  assert_eq(@fs.read_file_to_string(markdown_path), initial)

  let pulled = run_live_cli(
    pumd,
    ["pull", "--auth=adc", markdown_path],
    configuration_root,
  )
  assert_eq(pulled.exit_code, 0)
  let clean_source = "# Pumd Publication Pull smoke\n\nReviewer clean edit.\n"
  assert_eq(@fs.read_file_to_string(markdown_path), clean_source)

  let pre_pull = "# Pumd Publication Pull smoke\n\nAuthor local edit.\n"
  @fs.write_string_to_file(markdown_path, pre_pull)
  replace_live_remote_paragraph(
    client,
    success.document_id,
    tab_id,
    "Reviewer clean edit.\n",
    "Reviewer conflicting edit.",
  )
  let conflicted = run_live_cli(
    pumd,
    ["pull", "--auth=adc", markdown_path],
    configuration_root,
  )
  assert_eq(conflicted.exit_code, 1)
  let marked = @fs.read_file_to_string(markdown_path)
  assert_true(marked.contains("<<<<<<< local"))
  assert_true(marked.contains("||||||| baseline"))
  assert_true(marked.contains("Author local edit."))
  assert_true(marked.contains("Reviewer clean edit."))
  assert_true(marked.contains("Reviewer conflicting edit."))

  let conflicted_listing = run_live_cli(
    pumd,
    ["list", "--json"],
    configuration_root,
  )
  assert_eq(conflicted_listing.exit_code, 0)
  assert_true(conflicted_listing.stdout.contains("merge-conflicted"))

  let aborted = run_live_cli(
    pumd,
    ["pull", "--abort", markdown_path],
    configuration_root,
  )
  assert_eq(aborted.exit_code, 0)
  assert_eq(@fs.read_file_to_string(markdown_path), pre_pull)

  let conflicted_again = run_live_cli(
    pumd,
    ["pull", "--auth=adc", markdown_path],
    configuration_root,
  )
  if conflicted_again.exit_code != 1 ||
    !conflicted_again.stdout.contains("pull blocked by Merge Conflicts") {
    abort(
      "second live pull did not recreate a Pending Merge:\n" +
      conflicted_again.stderr +
      conflicted_again.stdout,
    )
  }
  let resolved_source = "# Pumd Publication Pull smoke\n\nResolved author and reviewer edit.\n"
  @fs.write_string_to_file(markdown_path, resolved_source)
  let resolved = run_live_cli(
    pumd,
    ["resolve", "--auth=adc", markdown_path],
    configuration_root,
  )
  if resolved.exit_code != 0 {
    abort("live resolve failed:\n" + resolved.stderr + resolved.stdout)
  }
  assert_true(resolved.stdout.contains("Publication updated."))
  assert_eq(@fs.read_file_to_string(markdown_path), resolved_source)

  let final_document = match get_document(client, success.document_id) {
    Ok(document) => document
    Err(error) => abort(error.message())
  }
  assert_true(
    final_document.body.contains("Resolved author and reviewer edit."),
  )
  let final_listing = run_live_cli(pumd, ["list", "--json"], configuration_root)
  assert_eq(final_listing.exit_code, 0)
  assert_true(final_listing.stdout.contains("\"lifecycle\":\"ready\""))
  assert_true(!final_listing.stdout.contains("merge-conflicted"))
  println("Live Publication Pull smoke passed: " + success.url)
  @async_fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
}
