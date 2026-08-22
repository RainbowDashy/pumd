///|
/// A deterministic injected transport for registry workflow tests.
priv struct WorkflowFakeHttpClient {
  requests : Array[@google_http.HttpRequest]
  responses : Array[@google_http.HttpResponse]
}

///|
impl @google_http.HttpClient for WorkflowFakeHttpClient with fn request(
  self,
  request,
) {
  let index = self.requests.length()
  self.requests.push(request)
  self.responses[index]
}

///|
priv struct WorkflowNetworkFailureClient {
  requests : Array[@google_http.HttpRequest]
}

///|
impl @google_http.HttpClient for WorkflowNetworkFailureClient with fn request(
  self,
  request,
) {
  self.requests.push(request)
  raise @google_http.HttpError::NetworkError("deterministic network failure")
}

///|
fn workflow_directory(name : String) -> String {
  "_build/publication-workflow-" + name
}

///|
async fn clean_workflow_directory(directory : String) -> Unit {
  @async_fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
}

///|
fn create_response(id : String, tab : String) -> @google_http.HttpResponse {
  @google_http.HttpResponse::new(
    200,
    {},
    "{\"documentId\":\"" +
    id +
    "\",\"tabs\":[{\"tabProperties\":{\"tabId\":\"" +
    tab +
    "\"}}]}",
  )
}

///|
fn success_response() -> @google_http.HttpResponse {
  @google_http.HttpResponse::new(200, {}, "{}")
}

///|
fn ready_entry(
  path : String,
  id : String,
  tab : String,
) -> @registry.PublicationEntry {
  {
    source_path: path,
    document_id: Some(id),
    url: Some(canonical_document_url(id)),
    managed_tab_id: Some(tab),
    lifecycle: Provisional,
    last_successful_publish: None,
    published_baseline: None,
    pending_merge: None,
  }
}

///|
fn hello_document() -> @pumd.DesiredDocument {
  match @pumd.render_markdown("Hello") {
    Ok(document) => document
    Err(_) => abort("Hello must render")
  }
}

///|
fn workflow_json_string(value : String, output : StringBuilder) -> Unit {
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
}

///|
fn workflow_named_style(style : @pumd.NamedStyle) -> String {
  match style {
    NormalText => "NORMAL_TEXT"
    Heading1 => "HEADING_1"
    Heading2 => "HEADING_2"
    Heading3 => "HEADING_3"
    Heading4 => "HEADING_4"
    Heading5 => "HEADING_5"
    Heading6 => "HEADING_6"
  }
}

///|
fn write_workflow_paragraph(
  paragraph : @pumd.Paragraph,
  start : Int,
  output : StringBuilder,
  include_background : Bool,
) -> Int {
  let mut end = start
  for run in paragraph.runs {
    end = advance_google_docs_index(index=end, text=run.content)
  }
  let paragraph_end = advance_google_docs_index(index=end, text="\n")
  output.write_string("{\"startIndex\":")
  output.write_string(start.to_string())
  output.write_string(",\"endIndex\":")
  output.write_string(paragraph_end.to_string())
  output.write_string(",\"paragraph\":{\"paragraphStyle\":{\"namedStyleType\":")
  workflow_json_string(
    workflow_named_style(paragraph.style.named_style),
    output,
  )
  output.write_string(",\"lineSpacing\":")
  output.write_string(paragraph.style.line_spacing_percent.to_string())
  output.write_string(",\"spaceAbove\":{\"magnitude\":")
  output.write_string(paragraph.style.space_above_points.to_string())
  output.write_string(",\"unit\":\"PT\"},\"spaceBelow\":{\"magnitude\":")
  output.write_string(paragraph.style.space_below_points.to_string())
  output.write_string(",\"unit\":\"PT\"}")
  if include_background {
    match paragraph.style.background_color {
      Some("#F1F3F4") =>
        output.write_string(
          ",\"shading\":{\"backgroundColor\":{\"color\":{\"rgbColor\":{\"red\":0.9450980392156862,\"green\":0.9529411764705882,\"blue\":0.9568627450980393}}}}",
        )
      Some(_) =>
        abort(
          "workflow fixture needs an RGB encoding for this paragraph background",
        )
      None => ()
    }
  }
  output.write_string("},\"elements\":[")
  let mut cursor = start
  for index, run in paragraph.runs {
    if index > 0 {
      output.write_char(',')
    }
    let run_end = advance_google_docs_index(index=cursor, text=run.content)
    output.write_string("{\"startIndex\":")
    output.write_string(cursor.to_string())
    output.write_string(",\"endIndex\":")
    output.write_string(run_end.to_string())
    output.write_string(",\"textRun\":{\"content\":")
    workflow_json_string(run.content, output)
    output.write_string(",\"textStyle\":{\"bold\":")
    output.write_string(run.style.bold.to_string())
    output.write_string(",\"italic\":")
    output.write_string(run.style.italic.to_string())
    output.write_string(",\"underline\":")
    output.write_string(run.style.underline.to_string())
    output.write_string(",\"weightedFontFamily\":{\"fontFamily\":")
    workflow_json_string(run.style.font_family, output)
    output.write_string("},\"fontSize\":{\"magnitude\":")
    output.write_string(run.style.font_size_points.to_string())
    output.write_string(",\"unit\":\"PT\"}")
    // The workflow fixture is a public Docs response: code backgrounds must
    // round-trip, otherwise a v2 code baseline falsely appears remotely
    // edited before reconciliation considers its foreground-only migration.
    match run.style.background_color {
      Some("#F1F3F4") =>
        output.write_string(
          ",\"backgroundColor\":{\"color\":{\"rgbColor\":{\"red\":0.9450980392156862,\"green\":0.9529411764705882,\"blue\":0.9568627450980393}}}",
        )
      Some(_) =>
        abort("workflow fixture needs an RGB encoding for this background")
      None => ()
    }
    match run.link {
      Some(link) => {
        output.write_string(",\"link\":{\"url\":")
        workflow_json_string(link.url, output)
        output.write_char('}')
      }
      None => ()
    }
    output.write_string("}}}")
    cursor = run_end
  }
  output.write_string("]}}")
  paragraph_end
}

///|
fn docs_response_json_with_implicit_final_newline(
  document : @pumd.DesiredDocument,
  document_id : String,
  revision : String,
  tab_id : String,
  include_implicit_final_newline : Bool,
) -> String {
  let output = StringBuilder::new()
  output.write_string("{\"documentId\":")
  workflow_json_string(document_id, output)
  output.write_string(",\"revisionId\":")
  workflow_json_string(revision, output)
  output.write_string(
    ",\"title\":\"Reviewer title\",\"tabs\":[{\"tabProperties\":{\"tabId\":",
  )
  workflow_json_string(tab_id, output)
  output.write_string("},\"documentTab\":{\"body\":{\"content\":[")
  let mut cursor = 1
  for index, element in document.content {
    if index > 0 {
      output.write_char(',')
    }
    match element {
      @pumd.StructuralElement::Paragraph(paragraph) =>
        cursor = write_workflow_paragraph(
          paragraph, cursor, output, include_implicit_final_newline,
        )
      @pumd.StructuralElement::Table(_) =>
        abort("workflow Docs fixture currently supports paragraph documents")
    }
  }
  if include_implicit_final_newline {
    if !document.content.is_empty() {
      output.write_char(',')
    }
    let final_newline : @pumd.Paragraph = {
      runs: [],
      inline_images: [],
      style: @pumd.builtin_style_profile().body,
      bullet: None,
      provenance: None,
    }
    let _ = write_workflow_paragraph(final_newline, cursor, output, true)
  }
  output.write_string("]}}}]}")
  output.to_string()
}

///|
fn docs_response_json(
  document : @pumd.DesiredDocument,
  document_id : String,
  revision : String,
  tab_id : String,
) -> String {
  docs_response_json_with_implicit_final_newline(
    document, document_id, revision, tab_id, false,
  )
}

///|
fn docs_response(
  document : @pumd.DesiredDocument,
  document_id : String,
  revision : String,
  tab_id : String,
) -> @google_http.HttpResponse {
  @google_http.HttpResponse::new(
    200,
    {},
    docs_response_json(document, document_id, revision, tab_id),
  )
}

///|
fn docs_response_with_implicit_final_newline(
  document : @pumd.DesiredDocument,
  document_id : String,
  revision : String,
  tab_id : String,
) -> @google_http.HttpResponse {
  @google_http.HttpResponse::new(
    200,
    {},
    docs_response_json_with_implicit_final_newline(
      document, document_id, revision, tab_id, true,
    ),
  )
}

///|
fn drive_comments_response(unresolved : Int) -> @google_http.HttpResponse {
  let comments = StringBuilder::new()
  comments.write_string("{\"comments\":[")
  for index = 0; index < unresolved; index = index + 1 {
    if index > 0 {
      comments.write_char(',')
    }
    comments.write_string("{\"id\":\"c")
    comments.write_string(index.to_string())
    comments.write_string("\",\"resolved\":false}")
  }
  comments.write_string("]}")
  @google_http.HttpResponse::new(200, {}, comments.to_string())
}

///|
async fn seed_ready(
  directory : String,
  path : String,
  id : String,
  tab : String,
) -> Unit {
  let canonical = @registry.canonical_source_path(path)
  assert_eq(
    @registry.register_provisional_publication(
      directory,
      ready_entry(canonical, id, tab),
    ),
    Ok(()),
  )
  assert_eq(
    @registry.commit_ready_publication(
      directory,
      canonical,
      hello_document(),
      "2026-08-05T12:00:00Z",
    ),
    Ok(()),
  )
}

///|
async fn seed_ready_with_baseline(
  directory : String,
  path : String,
  id : String,
  tab : String,
  baseline : @pumd.DesiredDocument,
) -> Unit {
  let canonical = @registry.canonical_source_path(path)
  assert_eq(
    @registry.register_provisional_publication(
      directory,
      ready_entry(canonical, id, tab),
    ),
    Ok(()),
  )
  assert_eq(
    @registry.commit_ready_publication(
      directory, canonical, baseline, "2026-08-05T12:00:00Z",
    ),
    Ok(()),
  )
}

///|
fn workflow_document(markdown : String) -> @pumd.DesiredDocument {
  match @pumd.render_markdown(markdown) {
    Ok(document) => document
    Err(_) => abort("workflow fixture must render")
  }
}

///|
/// The first publish records provisional ownership before filling its Managed Tab.
async test "registry first publish records baseline after population" {
  let directory = workflow_directory("first")
  clean_workflow_directory(directory)
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [create_response("first-doc", "tab-1"), success_response()],
  }
  let result = publish_path_with_registry(
    "proposal.md",
    fn(_) { Ok("Hello") },
    directory,
    Adc,
    fn() { Ok("project") },
    fn() { Ok("adc") },
    fake,
    false,
  )
  guard result is Ok(Completed(success)) else {
    fail("first publication must complete")
  }
  inspect(success.document_id, content="first-doc")
  assert_eq(fake.requests.length(), 2)
  inspect(
    fake.requests[0].url,
    content="https://docs.googleapis.com/v1/documents",
  )
  inspect(
    fake.requests[1].url,
    content="https://docs.googleapis.com/v1/documents/first-doc:batchUpdate",
  )
  guard fake.requests[1].body is Some(population_body) else {
    fail("first population must send a JSON batch")
  }
  assert_true(population_body.contains("\"tabId\":\"tab-1\""))
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  let entry = document.entries[0]
  assert_eq(entry.lifecycle, Ready)
  assert_eq(entry.managed_tab_id, Some("tab-1"))
  guard entry.last_successful_publish is Some(timestamp) else {
    fail("ready entry needs timestamp")
  }
  assert_eq(timestamp.length(), 20)
  assert_true(timestamp.has_suffix("Z"))
  assert_eq(timestamp[4], '-')
  assert_eq(timestamp[7], '-')
  assert_eq(timestamp[10], 'T')
  assert_eq(timestamp[13], ':')
  assert_eq(timestamp[16], ':')
  guard entry.published_baseline is Some(baseline) else {
    fail("ready entry needs baseline")
  }
  assert_eq(@debug.to_string(baseline), @debug.to_string(hello_document()))
  clean_workflow_directory(directory)
}

///|
/// A failed population resumes the recorded provisional document without creating another.
async test "registry resumes provisional population" {
  let directory = workflow_directory("resume")
  clean_workflow_directory(directory)
  let first = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      create_response("resume-doc", "tab-r"),
      @google_http.HttpResponse::new(500, {}, "{}"),
    ],
  }
  guard publish_path_with_registry(
      "resume.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      first,
      false,
    )
    is Err(Population(..)) else {
    fail("population failure must surface")
  }
  guard @registry.load_registry_document(directory) is Ok(before) else {
    fail("registry must load")
  }
  assert_eq(before.entries[0].lifecycle, Provisional)
  let resumed = WorkflowFakeHttpClient::{
    requests: [],
    responses: [success_response()],
  }
  guard publish_path_with_registry(
      "resume.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      resumed,
      false,
    )
    is Ok(Completed(_)) else {
    fail("provisional must resume")
  }
  assert_eq(resumed.requests.length(), 1)
  assert_true(resumed.requests[0].url.contains("resume-doc:batchUpdate"))
  guard resumed.requests[0].body is Some(resume_body) else {
    fail("resumed population must send a JSON batch")
  }
  assert_true(resume_body.contains("\"tabId\":\"tab-r\""))
  guard @registry.load_registry_document(directory) is Ok(after) else {
    fail("registry must load")
  }
  assert_eq(after.entries[0].lifecycle, Ready)
  clean_workflow_directory(directory)
}

///|
/// An ambiguous creation blocks a source until the user explicitly forgets it.
async test "ambiguous creation records blocked publication" {
  let directory = workflow_directory("blocked")
  clean_workflow_directory(directory)
  let broken = WorkflowNetworkFailureClient::{ requests: [] }
  guard publish_path_with_registry(
      "blocked.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      broken,
      false,
    )
    is Err(AmbiguousCreation) else {
    fail("network creation must be ambiguous")
  }
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  assert_eq(document.entries[0].lifecycle, Blocked)
  let blocked_canonical = @registry.canonical_source_path("blocked.md")
  let healthy = WorkflowFakeHttpClient::{
    requests: [],
    responses: [create_response("new-doc", "tab-n"), success_response()],
  }
  guard publish_path_with_registry(
      "blocked.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      healthy,
      false,
    )
    is Err(BlockedPublication(_)) else {
    fail("blocked publication must fail closed")
  }
  assert_eq(healthy.requests.length(), 0)
  assert_eq(
    @registry.forget_publication(directory, blocked_canonical),
    Ok(true),
  )
  guard publish_path_with_registry(
      "blocked.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      healthy,
      false,
    )
    is Ok(Completed(success)) else {
    fail("forgotten publication must publish")
  }
  inspect(success.document_id, content="new-doc")
  clean_workflow_directory(directory)
}

///|
async test "ready publication with no local changes is a no-op" {
  let directory = workflow_directory("already")
  clean_workflow_directory(directory)
  seed_ready(directory, "already.md", "old-doc", "old-tab")
  let calls : Array[Unit] = []
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [docs_response(hello_document(), "old-doc", "rev-1", "old-tab")],
  }
  guard publish_path_with_registry(
      "already.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() {
        calls.push(())
        Ok("p")
      },
      fn() {
        calls.push(())
        Ok("a")
      },
      fake,
      false,
    )
    is Ok(NoOp(success, "2026-08-05T12:00:00Z")) else {
    fail("unchanged ready entry must be a no-op")
  }
  inspect(success.document_id, content="old-doc")
  assert_eq(calls.length(), 1)
  assert_eq(fake.requests.length(), 1)
  assert_true(
    fake.requests[0].url.contains("suggestionsViewMode=SUGGESTIONS_INLINE"),
  )
  clean_workflow_directory(directory)
}

///|
async test "ready publication updates the baseline with a revision-checked batch" {
  let directory = workflow_directory("update")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Hello")
  let desired = workflow_document("Updated")
  seed_ready_with_baseline(
    directory, "update.md", "update-doc", "update-tab", baseline,
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(baseline, "update-doc", "rev-update", "update-tab"),
      drive_comments_response(0),
      success_response(),
    ],
  }
  guard publish_path_with_registry(
      "update.md",
      fn(_) { Ok("Updated") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      false,
    )
    is Ok(Updated(success, timestamp)) else {
    fail("local-only edit must update")
  }
  inspect(success.document_id, content="update-doc")
  assert_true(timestamp != "2026-08-05T12:00:00Z")
  assert_eq(fake.requests.length(), 3)
  let batch = fake.requests[2].body.unwrap()
  assert_true(
    batch.contains("\"writeControl\":{\"requiredRevisionId\":\"rev-update\"}"),
  )
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  guard document.entries[0].published_baseline is Some(saved) else {
    fail("updated entry needs baseline")
  }
  assert_eq(@debug.to_string(saved), @debug.to_string(desired))
  clean_workflow_directory(directory)
}

///|
async test "style migration updates a v2 plain-code baseline to v3 highlighted runs" {
  let directory = workflow_directory("style-migration-update")
  clean_workflow_directory(directory)
  let desired = workflow_document("```javascript\nconst answer = \"yes\"\n```")
  let baseline = version_two_code_baseline(desired)
  seed_ready_with_baseline(
    directory, "migration.md", "migration-doc", "migration-tab", baseline,
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response_with_implicit_final_newline(
        baseline, "migration-doc", "rev-migration", "migration-tab",
      ),
      drive_comments_response(0),
      success_response(),
    ],
  }
  guard publish_path_with_registry(
      "migration.md",
      fn(_) { Ok("```javascript\nconst answer = \"yes\"\n```") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      false,
    )
    is Ok(Updated(_, _)) else {
    fail("style migration must update")
  }
  assert_eq(fake.requests.length(), 3)
  let batch = fake.requests[2].body.unwrap()
  assert_true(batch.contains("\"updateTextStyle\""))
  assert_true(batch.contains("foregroundColor"))
  assert_true(batch.contains("\"fields\":\"foregroundColor\""))
  assert_true(!batch.contains("weightedFontFamily"))
  assert_true(!batch.contains("\"insertText\""))
  assert_true(!batch.contains("\"deleteContentRange\""))
  assert_true(
    batch.contains(
      "\"writeControl\":{\"requiredRevisionId\":\"rev-migration\"}",
    ),
  )
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  assert_eq(
    @debug.to_string(document.entries[0].published_baseline.unwrap()),
    @debug.to_string(desired),
  )
  clean_workflow_directory(directory)
}

///|
async test "style migration preserves remote-only work outside migrated code" {
  let directory = workflow_directory("style-migration-remote-only")
  clean_workflow_directory(directory)
  let markdown = "Original note\n\n```javascript\nconst answer = \"yes\"\n```"
  let desired = workflow_document(markdown)
  let baseline = version_two_code_baseline(desired)
  let remote = version_two_code_baseline(
    workflow_document(
      "Reviewer note\n\n```javascript\nconst answer = \"yes\"\n```",
    ),
  )
  seed_ready_with_baseline(
    directory, "migration-remote.md", "migration-remote-doc", "migration-remote-tab",
    baseline,
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response_with_implicit_final_newline(
        remote, "migration-remote-doc", "rev-migration-remote", "migration-remote-tab",
      ),
      drive_comments_response(0),
      success_response(),
    ],
  }
  guard publish_path_with_registry(
      "migration-remote.md",
      fn(_) { Ok(markdown) },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      false,
    )
    is Ok(Updated(_, _)) else {
    fail("remote-only prose must coexist with the code style migration")
  }
  assert_eq(fake.requests.length(), 3)
  let batch = fake.requests[2].body.unwrap()
  assert_true(batch.contains("\"updateTextStyle\""))
  assert_true(batch.contains("foregroundColor"))
  assert_true(!batch.contains("\"insertText\""))
  assert_true(!batch.contains("\"deleteContentRange\""))
  assert_true(batch.contains("\"startIndex\":15,"))
  for index = 1; index < 15; index = index + 1 {
    assert_true(!batch.contains("\"startIndex\":" + index.to_string() + ","))
  }
  clean_workflow_directory(directory)
}

///|
async test "remote code edit conflicts with a v2-to-v3 style migration" {
  let directory = workflow_directory("style-migration-conflict")
  clean_workflow_directory(directory)
  let desired = workflow_document("```javascript\nconst answer = \"yes\"\n```")
  let baseline = version_two_code_baseline(desired)
  seed_ready_with_baseline(
    directory, "migration-conflict.md", "migration-conflict-doc", "migration-conflict-tab",
    baseline,
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response_with_implicit_final_newline(
        version_two_code_baseline(
          workflow_document("```javascript\nconst answer = \"reviewed\"\n```"),
        ),
        "migration-conflict-doc",
        "rev-migration-conflict",
        "migration-conflict-tab",
      ),
    ],
  }
  guard publish_path_with_registry(
      "migration-conflict.md",
      fn(_) { Ok("```javascript\nconst answer = \"yes\"\n```") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      false,
    )
    is Err(MergeConflict(_)) else {
    fail("remote code edit must not be overwritten by style migration")
  }
  assert_eq(fake.requests.length(), 1)
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  assert_eq(
    @debug.to_string(document.entries[0].published_baseline.unwrap()),
    @debug.to_string(baseline),
  )
  clean_workflow_directory(directory)
}

///|
async test "dry-run plans style migration without mutating the document or registry" {
  let directory = workflow_directory("style-migration-dry-run")
  clean_workflow_directory(directory)
  let desired = workflow_document("```javascript\nconst answer = \"yes\"\n```")
  let baseline = version_two_code_baseline(desired)
  seed_ready_with_baseline(
    directory, "migration-dry.md", "migration-dry-doc", "migration-dry-tab", baseline,
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response_with_implicit_final_newline(
        baseline, "migration-dry-doc", "rev-migration-dry", "migration-dry-tab",
      ),
      drive_comments_response(0),
    ],
  }
  guard publish_path_with_registry(
      "migration-dry.md",
      fn(_) { Ok("```javascript\nconst answer = \"yes\"\n```") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      true,
    )
    is Ok(DryRunUpdate(report~)) else {
    fail("dry run must expose the style migration plan")
  }
  assert_eq(report.planned_units, 1)
  assert_eq(report.planned, ["paragraph 1"])
  assert_true(report.concurrency_sensitive)
  assert_eq(fake.requests.length(), 2)
  for request in fake.requests {
    assert_true(!request.url.contains(":batchUpdate"))
  }
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  assert_eq(
    @debug.to_string(document.entries[0].published_baseline.unwrap()),
    @debug.to_string(baseline),
  )
  clean_workflow_directory(directory)
}

///|
async test "unresolved comments remain a review barrier during style migration" {
  let directory = workflow_directory("style-migration-review")
  clean_workflow_directory(directory)
  let desired = workflow_document("```javascript\nconst answer = \"yes\"\n```")
  let baseline = version_two_code_baseline(desired)
  seed_ready_with_baseline(
    directory, "migration-review.md", "migration-review-doc", "migration-review-tab",
    baseline,
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response_with_implicit_final_newline(
        baseline, "migration-review-doc", "rev-migration-review", "migration-review-tab",
      ),
      drive_comments_response(1),
    ],
  }
  guard publish_path_with_registry(
      "migration-review.md",
      fn(_) { Ok("```javascript\nconst answer = \"yes\"\n```") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      false,
    )
    is Err(ReviewBarrier(unresolved=1)) else {
    fail("comments must remain a review barrier during migration")
  }
  assert_eq(fake.requests.length(), 2)
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  assert_eq(
    @debug.to_string(document.entries[0].published_baseline.unwrap()),
    @debug.to_string(baseline),
  )
  clean_workflow_directory(directory)
}

///|
async test "style migration revision failure leaves the v2 baseline unchanged" {
  let directory = workflow_directory("style-migration-concurrency")
  clean_workflow_directory(directory)
  let markdown = "```javascript\nconst answer = \"yes\"\n```"
  let desired = workflow_document(markdown)
  let baseline = version_two_code_baseline(desired)
  seed_ready_with_baseline(
    directory, "migration-concurrency.md", "migration-concurrency-doc", "migration-concurrency-tab",
    baseline,
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response_with_implicit_final_newline(
        baseline, "migration-concurrency-doc", "rev-migration-old", "migration-concurrency-tab",
      ),
      drive_comments_response(0),
      @google_http.HttpResponse::new(400, {}, "{}"),
    ],
  }
  guard publish_path_with_registry(
      "migration-concurrency.md",
      fn(_) { Ok(markdown) },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      false,
    )
    is Err(Concurrency(_)) else {
    fail("migration must surface a revision conflict")
  }
  assert_eq(fake.requests.length(), 3)
  let batch = fake.requests[2].body.unwrap()
  assert_true(batch.contains("foregroundColor"))
  assert_true(
    batch.contains(
      "\"writeControl\":{\"requiredRevisionId\":\"rev-migration-old\"}",
    ),
  )
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  assert_eq(
    @debug.to_string(document.entries[0].published_baseline.unwrap()),
    @debug.to_string(baseline),
  )
  clean_workflow_directory(directory)
}

///|
async test "failed style migration update leaves the v2 baseline unchanged" {
  let directory = workflow_directory("style-migration-failed-update")
  clean_workflow_directory(directory)
  let markdown = "```javascript\nconst answer = \"yes\"\n```"
  let desired = workflow_document(markdown)
  let baseline = version_two_code_baseline(desired)
  seed_ready_with_baseline(
    directory, "migration-failed.md", "migration-failed-doc", "migration-failed-tab",
    baseline,
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response_with_implicit_final_newline(
        baseline, "migration-failed-doc", "rev-migration-failed", "migration-failed-tab",
      ),
      drive_comments_response(0),
      @google_http.HttpResponse::new(500, {}, "{}"),
    ],
  }
  guard publish_path_with_registry(
      "migration-failed.md",
      fn(_) { Ok(markdown) },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      false,
    )
    is Err(UpdateFailed(document_id~, ..)) else {
    fail("migration update rejection must be explicit")
  }
  assert_eq(document_id, "migration-failed-doc")
  assert_eq(fake.requests.length(), 3)
  assert_true(fake.requests[2].body.unwrap().contains("foregroundColor"))
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  assert_eq(
    @debug.to_string(document.entries[0].published_baseline.unwrap()),
    @debug.to_string(baseline),
  )
  clean_workflow_directory(directory)
}

///|
async test "conflicting ready changes do not write the document or registry" {
  let directory = workflow_directory("conflict")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Hello")
  seed_ready_with_baseline(
    directory, "conflict.md", "conflict-doc", "conflict-tab", baseline,
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(
        workflow_document("Reviewer edit"),
        "conflict-doc",
        "rev-conflict",
        "conflict-tab",
      ),
    ],
  }
  guard publish_path_with_registry(
      "conflict.md",
      fn(_) { Ok("Local edit") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      false,
    )
    is Err(MergeConflict(message~)) else {
    fail("same paragraph edits must conflict")
  }
  assert_true(message.contains("paragraph 1"))
  assert_eq(fake.requests.length(), 1)
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  assert_eq(
    @debug.to_string(document.entries[0].published_baseline.unwrap()),
    @debug.to_string(baseline),
  )
  clean_workflow_directory(directory)
}

///|
async test "unresolved comments block a planned ready update" {
  let directory = workflow_directory("review")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Hello")
  seed_ready_with_baseline(
    directory, "review.md", "review-doc", "review-tab", baseline,
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(baseline, "review-doc", "rev-review", "review-tab"),
      drive_comments_response(1),
    ],
  }
  guard publish_path_with_registry(
      "review.md",
      fn(_) { Ok("Local edit") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      false,
    )
    is Err(ReviewBarrier(unresolved=1)) else {
    fail("unresolved comment must block")
  }
  assert_eq(fake.requests.length(), 2)
  clean_workflow_directory(directory)
}

///|
async test "revision conflicts leave the ready baseline unchanged" {
  let directory = workflow_directory("concurrency")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Hello")
  seed_ready_with_baseline(
    directory, "concurrency.md", "concurrency-doc", "concurrency-tab", baseline,
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(baseline, "concurrency-doc", "rev-old", "concurrency-tab"),
      drive_comments_response(0),
      @google_http.HttpResponse::new(400, {}, "{}"),
    ],
  }
  guard publish_path_with_registry(
      "concurrency.md",
      fn(_) { Ok("Local edit") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      false,
    )
    is Err(Concurrency(message~)) else {
    fail("revision conflict must surface concurrency")
  }
  assert_true(message.contains("nothing was applied"))
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  assert_eq(
    @debug.to_string(document.entries[0].published_baseline.unwrap()),
    @debug.to_string(baseline),
  )
  clean_workflow_directory(directory)
}

///|
priv struct WorkflowAmbiguousHttpClient {
  requests : Array[@google_http.HttpRequest]
  responses : Array[@google_http.HttpResponse]
}

///|
impl @google_http.HttpClient for WorkflowAmbiguousHttpClient with fn request(
  self,
  request,
) {
  let index = self.requests.length()
  self.requests.push(request)
  if request.url.contains(":batchUpdate") {
    raise @google_http.HttpError::NetworkError("ambiguous transport")
  }
  self.responses[index]
}

///|
async test "ambiguous transport recovery commits when the re-read confirms the update landed" {
  let directory = workflow_directory("ambiguous-landed")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Hello")
  let desired = workflow_document("Local edit")
  seed_ready_with_baseline(
    directory, "ambiguous.md", "ambiguous-doc", "ambiguous-tab", baseline,
  )
  let fake = WorkflowAmbiguousHttpClient::{
    requests: [],
    responses: [
      docs_response(baseline, "ambiguous-doc", "rev-1", "ambiguous-tab"),
      drive_comments_response(0),
      success_response(),
      docs_response(desired, "ambiguous-doc", "rev-2", "ambiguous-tab"),
    ],
  }
  guard publish_path_with_registry(
      "ambiguous.md",
      fn(_) { Ok("Local edit") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      false,
    )
    is Ok(Updated(_, _)) else {
    fail("a confirmed ambiguous update must commit")
  }
  assert_eq(fake.requests.length(), 4)
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  guard document.entries[0].published_baseline is Some(saved) else {
    fail("updated entry needs baseline")
  }
  assert_eq(@debug.to_string(saved), @debug.to_string(desired))
  clean_workflow_directory(directory)
}

///|
async test "ambiguous transport recovery reports ambiguity when the intended state did not land" {
  let directory = workflow_directory("ambiguous-lost")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Hello")
  seed_ready_with_baseline(
    directory, "ambiguous.md", "ambiguous-doc", "ambiguous-tab", baseline,
  )
  let fake = WorkflowAmbiguousHttpClient::{
    requests: [],
    responses: [
      docs_response(baseline, "ambiguous-doc", "rev-1", "ambiguous-tab"),
      drive_comments_response(0),
      success_response(),
      docs_response(baseline, "ambiguous-doc", "rev-1", "ambiguous-tab"),
    ],
  }
  guard publish_path_with_registry(
      "ambiguous.md",
      fn(_) { Ok("Local edit") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      false,
    )
    is Err(AmbiguousUpdate(document_id~, ..)) else {
    fail("an unconfirmed ambiguous update must stay ambiguous")
  }
  assert_eq(document_id, "ambiguous-doc")
  assert_eq(fake.requests.length(), 4)
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  assert_eq(
    @debug.to_string(document.entries[0].published_baseline.unwrap()),
    @debug.to_string(baseline),
  )
  clean_workflow_directory(directory)
}

///|
async test "dry-run reports barriers without posting or changing a ready registry" {
  let directory = workflow_directory("dry-update")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Hello")
  seed_ready_with_baseline(
    directory, "dry-update.md", "dry-doc", "dry-tab", baseline,
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(baseline, "dry-doc", "rev-dry-update", "dry-tab"),
      drive_comments_response(1),
    ],
  }
  guard publish_path_with_registry(
      "dry-update.md",
      fn(_) { Ok("Local edit") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
      true,
    )
    is Ok(DryRunUpdate(report~)) else {
    fail("dry run must inspect planned update and comments")
  }
  assert_eq(report.planned_units, 1)
  assert_eq(report.planned, ["paragraph 1"])
  assert_eq(report.conflicts, 0)
  assert_eq(report.conflicted, [])
  assert_eq(report.review_barriers, 1)
  assert_true(!report.concurrency_sensitive)
  assert_eq(fake.requests.length(), 2)
  for request in fake.requests {
    assert_true(!request.url.contains(":batchUpdate"))
  }
  guard @registry.load_registry_document(directory) is Ok(document) else {
    fail("registry must load")
  }
  assert_eq(
    @debug.to_string(document.entries[0].published_baseline.unwrap()),
    @debug.to_string(baseline),
  )
  clean_workflow_directory(directory)
}

///|
async test "dry run distinguishes unpublished provisional blocked and ready entries" {
  let directory = workflow_directory("dry")
  clean_workflow_directory(directory)
  let calls : Array[Unit] = []
  let empty = WorkflowFakeHttpClient::{ requests: [], responses: [] }
  guard publish_path_with_registry(
      "new.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() {
        calls.push(())
        Ok("p")
      },
      fn() {
        calls.push(())
        Ok("a")
      },
      empty,
      true,
    )
    is Ok(DryRunCreation(title="new")) else {
    fail("new dry run must report creation")
  }
  assert_eq(calls.length(), 0)
  assert_eq(empty.requests.length(), 0)
  // A dry run on a clean installation must not create the registry directory,
  // the registry file, or the lock file.
  assert_true(!@async_fs.exists(directory))
  assert_true(!@async_fs.exists(@registry.registry_lock_path(directory)))
  assert_true(!@async_fs.exists(@registry.registry_file_path(directory)))
  let provisional_canonical = @registry.canonical_source_path("provisional.md")
  let blocked_canonical = @registry.canonical_source_path("blocked.md")
  assert_eq(
    @registry.register_provisional_publication(
      directory,
      ready_entry(provisional_canonical, "pro-doc", "pro-tab"),
    ),
    Ok(()),
  )
  assert_eq(
    @registry.record_blocked_publication(directory, blocked_canonical),
    Ok(()),
  )
  guard publish_path_with_registry(
      "provisional.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      empty,
      true,
    )
    is Ok(DryRunProvisional(_)) else {
    fail("provisional dry run")
  }
  guard publish_path_with_registry(
      "blocked.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      empty,
      true,
    )
    is Ok(DryRunBlocked(_)) else {
    fail("blocked dry run")
  }
  seed_ready(directory, "ready.md", "ready-doc", "ready-tab")
  let docs = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(hello_document(), "ready-doc", "rev-dry", "ready-tab"),
      drive_comments_response(0),
    ],
  }
  guard publish_path_with_registry(
      "ready.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      docs,
      true,
    )
    is Ok(DryRunUpdate(report~)) else {
    fail("ready dry run update")
  }
  assert_eq(report.title, Some("Reviewer title"))
  assert_eq(report.planned_units, 0)
  assert_eq(report.conflicts, 0)
  assert_eq(docs.requests.length(), 2)
  assert_true(
    docs.requests[0].url.contains("ready-doc?includeTabsContent=true"),
  )
  clean_workflow_directory(directory)
}

///|
async test "dry run maps missing tabs permission and 404 without mutations" {
  let directory = workflow_directory("dry-errors")
  clean_workflow_directory(directory)
  seed_ready(directory, "ready.md", "doc", "tab")
  let missing_tab = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"documentId\":\"doc\",\"revisionId\":\"rev\",\"tabs\":[]}",
      ),
    ],
  }
  guard publish_path_with_registry(
      "ready.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      missing_tab,
      true,
    )
    is Err(RemoteMissing(..)) else {
    fail("missing tab must be remote missing")
  }
  let forbidden = WorkflowFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(403, {}, "{}")],
  }
  guard publish_path_with_registry(
      "ready.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      forbidden,
      true,
    )
    is Err(Permission(stage=DocumentRead, ..)) else {
    fail("403 must be DocumentRead permission")
  }
  let missing = WorkflowFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(404, {}, "{}")],
  }
  guard publish_path_with_registry(
      "ready.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      missing,
      true,
    )
    is Err(RemoteMissing(..)) else {
    fail("404 must be missing")
  }
  clean_workflow_directory(directory)
}

///|
async test "preflight and authentication happen before remote work" {
  let directory = workflow_directory("preflight")
  clean_workflow_directory(directory)
  let fake = WorkflowFakeHttpClient::{ requests: [], responses: [] }
  guard publish_path_with_registry(
      "nope.md",
      fn(_) { Err("nope") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      fake,
      false,
    )
    is Err(SourceAccess(..)) else {
    fail("source error")
  }
  guard publish_path_with_registry(
      "image.md",
      fn(_) { Ok("![x](y.png)") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Ok("a") },
      fake,
      false,
    )
    is Err(Rendering(_)) else {
    fail("render error")
  }
  assert_eq(fake.requests.length(), 0)
  guard publish_path_with_registry(
      "auth.md",
      fn(_) { Ok("Hello") },
      directory,
      Adc,
      fn() { Ok("p") },
      fn() { Err(CredentialsNotConfigured) },
      fake,
      false,
    )
    is Err(Authentication(problem=CredentialsNotConfigured, ..)) else {
    fail("authentication error")
  }
  assert_eq(fake.requests.length(), 0)
  assert_true(!@async_fs.exists(@registry.registry_file_path(directory)))
  clean_workflow_directory(directory)

  let file_directory = workflow_directory("registry-file")
  @async_fs.remove(file_directory) catch {
    _ => ()
  }
  @async_fs.write_file(
    file_directory,
    "not a directory",
    create_mode=@async_fs.CreateNew,
  )
  let token_calls : Array[Unit] = []
  guard publish_path_with_registry(
      "registry-file.md",
      fn(_) { Ok("Hello") },
      file_directory,
      Adc,
      fn() {
        token_calls.push(())
        Ok("p")
      },
      fn() {
        token_calls.push(())
        Ok("a")
      },
      fake,
      false,
    )
    is Err(Registry(_)) else {
    fail("registry path file must fail before authorization")
  }
  assert_eq(token_calls.length(), 0)
  assert_eq(fake.requests.length(), 0)
  @async_fs.remove(file_directory) catch {
    _ => ()
  }
}

///|
async test "inspection maps Drive and Docs states" {
  let entry = ready_entry("inspect.md", "inspect-doc", "inspect-tab")
  let ready = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"id\":\"inspect-doc\",\"name\":\"Drive name\",\"trashed\":false,\"capabilities\":{\"canEdit\":true}}",
      ),
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"documentId\":\"inspect-doc\",\"title\":\"Docs name\",\"tabs\":[{\"tabProperties\":{\"tabId\":\"inspect-tab\"}}]}",
      ),
    ],
  }
  let inspection = inspect_registered_publication("token", ready, entry)
  assert_eq(inspection.status, Ready)
  assert_eq(inspection.title, Some("Docs name"))
  assert_true(inspection.managed_tab_present)
  inspect(
    ready.requests[0].url,
    content="https://www.googleapis.com/drive/v3/files/inspect-doc?fields=id,name,trashed,capabilities(canEdit)",
  )
  inspect(
    ready.requests[1].url,
    content="https://docs.googleapis.com/v1/documents/inspect-doc?includeTabsContent=true",
  )
  inspect(
    ready.requests[0].headers.get("Authorization").unwrap(),
    content="Bearer token",
  )
  let trashed = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"id\":\"inspect-doc\",\"trashed\":true}",
      ),
    ],
  }
  assert_eq(
    inspect_registered_publication("token", trashed, entry).status,
    Trashed,
  )
  let read_only = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"id\":\"inspect-doc\",\"trashed\":false,\"capabilities\":{\"canEdit\":false}}",
      ),
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"documentId\":\"inspect-doc\",\"tabs\":[{\"tabProperties\":{\"tabId\":\"inspect-tab\"}}]}",
      ),
    ],
  }
  assert_eq(
    inspect_registered_publication("token", read_only, entry).status,
    ReadOnly,
  )
  let absent_tab = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"id\":\"inspect-doc\",\"trashed\":false}",
      ),
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"documentId\":\"inspect-doc\",\"tabs\":[]}",
      ),
    ],
  }
  assert_eq(
    inspect_registered_publication("token", absent_tab, entry).status,
    RemotePublicationStatus::RemoteMissing,
  )
  let missing = WorkflowFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(404, {}, "{}")],
  }
  assert_eq(
    inspect_registered_publication("token", missing, entry).status,
    RemotePublicationStatus::RemoteMissing,
  )
  let forbidden = WorkflowFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(403, {}, "{}")],
  }
  assert_eq(
    inspect_registered_publication("token", forbidden, entry).status,
    Inaccessible,
  )
  let unavailable = WorkflowNetworkFailureClient::{ requests: [] }
  assert_eq(
    inspect_registered_publication("token", unavailable, entry).status,
    Unavailable,
  )
}

///|
async test "pull writes source before advancing baseline and never writes Google Docs" {
  let directory = workflow_directory("pull-clean")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Original")
  let remote = workflow_document("Reviewer wording")
  seed_ready_with_baseline(
    directory, "pull-clean.md", "pull-doc", "pull-tab", baseline,
  )
  let source = ["Original"]
  let replacement_observed_old_baseline = [false]
  let registry_before = @async_fs.read_file(
    @registry.registry_file_path(directory),
  ).text()
  let docs = WorkflowFakeHttpClient::{
    requests: [],
    responses: [docs_response(remote, "pull-doc", "rev-pull", "pull-tab")],
  }
  guard pull_path_with_registry(
      "pull-clean.md",
      fn(_) { Ok(source[0]) },
      async fn(_, replacement) {
        replacement_observed_old_baseline[0] = @async_fs.read_file(
            @registry.registry_file_path(directory),
          ).text() ==
          registry_before
        source[0] = replacement
        Ok(())
      },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      docs,
      false,
    )
    is Ok(Pulled(report)) else {
    fail("clean pull must complete")
  }
  assert_eq(source[0], "Reviewer wording")
  assert_true(replacement_observed_old_baseline[0])
  assert_eq(report.plan.incoming, 1)
  assert_eq(docs.requests.length(), 1)
  assert_true(docs.requests[0].url.contains("pull-doc?includeTabsContent=true"))
  let updated = @registry.registry_snapshot(directory).unwrap().entries[0]
  assert_eq(
    @debug.to_string(updated.published_baseline),
    @debug.to_string(Some(report.plan.baseline)),
  )
  assert_eq(updated.last_successful_publish, Some("2026-08-05T12:00:00Z"))
  clean_workflow_directory(directory)
}

///|
async test "pull dry run performs the full read and plan without local mutation" {
  let directory = workflow_directory("pull-dry-run")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Original")
  seed_ready_with_baseline(
    directory, "pull-dry.md", "pull-dry-doc", "pull-dry-tab", baseline,
  )
  let before = @async_fs.read_file(@registry.registry_file_path(directory)).text()
  let writes : Array[String] = []
  let docs = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(
        workflow_document("Incoming"),
        "pull-dry-doc",
        "rev-dry",
        "pull-dry-tab",
      ),
    ],
  }
  guard pull_path_with_registry(
      "pull-dry.md",
      fn(_) { Ok("Original") },
      fn(_, replacement) {
        writes.push(replacement)
        Ok(())
      },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      docs,
      true,
    )
    is Ok(PullDryRun(report)) else {
    fail("dry-run pull must return its plan")
  }
  assert_eq(report.plan.incoming, 1)
  assert_eq(writes.length(), 0)
  assert_eq(docs.requests.length(), 1)
  assert_eq(
    @async_fs.read_file(@registry.registry_file_path(directory)).text(),
    before,
  )
  clean_workflow_directory(directory)
}

///|
async test "pull preserves disjoint local changes and persists Pending Merge before writing diff3 markers" {
  let directory = workflow_directory("pull-three-way")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Base\n\nKeep")
  seed_ready_with_baseline(
    directory, "pull-merge.md", "pull-merge-doc", "pull-merge-tab", baseline,
  )
  let source = ["Local\n\nKeep"]
  let writes : Array[String] = []
  let disjoint = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(
        workflow_document("Base\n\nRemote"),
        "pull-merge-doc",
        "rev-merge",
        "pull-merge-tab",
      ),
    ],
  }
  guard pull_path_with_registry(
      "pull-merge.md",
      fn(_) { Ok(source[0]) },
      fn(_, replacement) {
        source[0] = replacement
        writes.push(replacement)
        Ok(())
      },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      disjoint,
      false,
    )
    is Ok(Pulled(report)) else {
    fail("disjoint pull must merge")
  }
  assert_eq(source[0], "Local\n\nRemote")
  assert_eq(report.plan.incoming, 1)
  assert_eq(report.plan.preserved_local, 1)

  let registry_before_conflict = @async_fs.read_file(
    @registry.registry_file_path(directory),
  ).text()
  let replacement_observed_pending = [false]
  let conflicting = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(
        workflow_document("Reviewer\n\nRemote"),
        "pull-merge-doc",
        "rev-conflict",
        "pull-merge-tab",
      ),
    ],
  }
  guard pull_path_with_registry(
      "pull-merge.md",
      fn(_) { Ok("Author\n\nRemote") },
      async fn(_, replacement) {
        replacement_observed_pending[0] = @registry.load_registry_document(
            directory,
          ).unwrap().entries[0].pending_merge
          is Some(_)
        writes.push(replacement)
        Ok(())
      },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      conflicting,
      false,
    )
    is Ok(PullConflicted(conflict_report)) else {
    fail("overlap must be reported")
  }
  assert_eq(conflict_report.plan.conflicted, 1)
  assert_eq(writes.length(), 2)
  assert_true(
    writes[1].contains(
      "<<<<<<< local\nAuthor\n||||||| baseline\nBase\n=======\nReviewer\n>>>>>>> remote",
    ),
  )
  assert_true(replacement_observed_pending[0])
  let conflicted_entry = @registry.registry_snapshot(directory).unwrap().entries[0]
  guard conflicted_entry.pending_merge is Some(pending) else {
    fail("overlap must record a Pending Merge")
  }
  assert_eq(pending.pre_pull_source, "Author\n\nRemote")
  assert_eq(pending.marked_source, conflict_report.plan.source)
  assert_eq(pending.observed_revision_id, "rev-conflict")
  assert_true(pending.observed_remote_body.contains("Reviewer"))
  assert_true(
    @async_fs.read_file(@registry.registry_file_path(directory)).text() !=
    registry_before_conflict,
  )
  clean_workflow_directory(directory)
}

///|
async test "pull retry after interrupted baseline persistence converges without rewriting source" {
  let directory = workflow_directory("pull-retry")
  clean_workflow_directory(directory)
  seed_ready_with_baseline(
    directory,
    "pull-retry.md",
    "pull-retry-doc",
    "pull-retry-tab",
    workflow_document("Old"),
  )
  let writes : Array[String] = []
  let docs = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(
        workflow_document("Landed"),
        "pull-retry-doc",
        "rev-retry",
        "pull-retry-tab",
      ),
    ],
  }
  guard pull_path_with_registry(
      "pull-retry.md",
      fn(_) { Ok("Landed") },
      fn(_, replacement) {
        writes.push(replacement)
        Ok(())
      },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      docs,
      false,
    )
    is Ok(Pulled(report)) else {
    fail("converged retry must finish baseline persistence")
  }
  assert_eq(report.plan.converged, 1)
  assert_eq(writes.length(), 0)
  let entry = @registry.registry_snapshot(directory).unwrap().entries[0]
  assert_eq(
    @debug.to_string(entry.published_baseline),
    @debug.to_string(Some(report.plan.baseline)),
  )
  clean_workflow_directory(directory)
}

///|
async test "pull abort restores exact pre-pull bytes before clearing Pending Merge and is retryable" {
  let directory = workflow_directory("pull-abort")
  clean_workflow_directory(directory)
  seed_ready_with_baseline(
    directory,
    "pull-abort.md",
    "pull-abort-doc",
    "pull-abort-tab",
    workflow_document("Base"),
  )
  let canonical = @registry.canonical_source_path("pull-abort.md")
  let document = @registry.registry_snapshot(directory).unwrap()
  let pre_pull_source = "Local\r\n\r\nExact bytes\r\n"
  let marked = "<<<<<<< local\r\nLocal\r\n||||||| baseline\r\nBase\r\n=======\r\nRemote\r\n>>>>>>> remote\r\n"
  let pending : @registry.PendingMerge = {
    pre_pull_source,
    marked_source: marked,
    observed_remote_body: docs_response_json(
      workflow_document("Remote"),
      "pull-abort-doc",
      "rev-abort",
      "pull-abort-tab",
    ),
    observed_revision_id: "rev-abort",
  }
  let begun = @registry.document_with_pending_merge(
    document, canonical, pending,
  ).unwrap()
  assert_eq(@registry.save_registry_document(directory, begun), Ok(()))
  let source = [marked]
  guard abort_pull_with_registry(
      "pull-abort.md",
      fn(_, replacement) {
        source[0] = replacement
        Err("simulated interruption after replacement")
      },
      directory,
    )
    is Err(SourceWrite(..)) else {
    fail("an interrupted abort must retain its Pending Merge")
  }
  assert_eq(source[0], pre_pull_source)
  assert_true(
    @registry.registry_snapshot(directory).unwrap().entries[0].pending_merge
    is Some(_),
  )
  guard abort_pull_with_registry(
      "pull-abort.md",
      fn(_, replacement) {
        source[0] = replacement
        Ok(())
      },
      directory,
    )
    is Ok(_) else {
    fail("a retried abort must clear Pending Merge")
  }
  assert_eq(source[0], pre_pull_source)
  assert_eq(
    @registry.registry_snapshot(directory).unwrap().entries[0].pending_merge,
    None,
  )
  clean_workflow_directory(directory)
}

///|
async test "resolve requires Pending Merge and rejects remaining conflict markers before authorization" {
  let directory = workflow_directory("resolve-markers")
  clean_workflow_directory(directory)
  seed_ready_with_baseline(
    directory,
    "resolve-markers.md",
    "resolve-markers-doc",
    "resolve-markers-tab",
    workflow_document("Base"),
  )
  let canonical = @registry.canonical_source_path("resolve-markers.md")
  let document = @registry.registry_snapshot(directory).unwrap()
  let marked = "<<<<<<< local\nLocal\n||||||| baseline\nBase\n=======\nRemote\n>>>>>>> remote\n"
  let pending : @registry.PendingMerge = {
    pre_pull_source: "Local\n",
    marked_source: marked,
    observed_remote_body: docs_response_json(
      workflow_document("Remote"),
      "resolve-markers-doc",
      "rev-markers",
      "resolve-markers-tab",
    ),
    observed_revision_id: "rev-markers",
  }
  assert_eq(
    @registry.save_registry_document(
      directory,
      @registry.document_with_pending_merge(document, canonical, pending).unwrap(),
    ),
    Ok(()),
  )
  let fake = WorkflowFakeHttpClient::{ requests: [], responses: [] }
  let token_calls = [0]
  guard publish_path_with_registry(
      "resolve-markers.md",
      fn(_) { Ok("Resolved") },
      directory,
      Adc,
      fn() {
        token_calls[0] = token_calls[0] + 1
        Ok("project")
      },
      fn() {
        token_calls[0] = token_calls[0] + 1
        Ok("adc")
      },
      fake,
      false,
    )
    is Err(Registry(message)) else {
    fail("publish must be blocked by Pending Merge")
  }
  assert_true(message.contains("Pending Merge"))
  guard pull_path_with_registry(
      "resolve-markers.md",
      fn(_) { Ok("Resolved") },
      fn(_, _) { Ok(()) },
      directory,
      Adc,
      fn() {
        token_calls[0] = token_calls[0] + 1
        Ok("project")
      },
      fn() {
        token_calls[0] = token_calls[0] + 1
        Ok("adc")
      },
      fake,
      false,
    )
    is Err(Registry(pull_message)) else {
    fail("normal pull must be blocked by Pending Merge")
  }
  assert_true(pull_message.contains("Pending Merge"))
  guard resolve_path_with_registry(
      "resolve-markers.md",
      fn(_) { Ok(marked) },
      directory,
      Adc,
      fn() {
        token_calls[0] = token_calls[0] + 1
        Ok("project")
      },
      fn() {
        token_calls[0] = token_calls[0] + 1
        Ok("adc")
      },
      fake,
    )
    is Err(Planning(message)) else {
    fail("resolve must reject remaining markers")
  }
  assert_true(message.contains("conflict markers"))
  assert_eq(token_calls[0], 0)
  assert_eq(fake.requests.length(), 0)
  assert_true(
    @registry.registry_snapshot(directory).unwrap().entries[0].pending_merge
    is Some(_),
  )
  clean_workflow_directory(directory)
}

///|
async test "resolve revision-checks the edited resolution then advances baseline and clears Pending Merge" {
  let directory = workflow_directory("resolve-success")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Base")
  let remote = workflow_document("Remote")
  let resolved = workflow_document("Resolved")
  seed_ready_with_baseline(
    directory, "resolve-success.md", "resolve-success-doc", "resolve-success-tab",
    baseline,
  )
  let canonical = @registry.canonical_source_path("resolve-success.md")
  let document = @registry.registry_snapshot(directory).unwrap()
  let remote_body = docs_response_json(
    remote, "resolve-success-doc", "rev-resolve", "resolve-success-tab",
  )
  let pending : @registry.PendingMerge = {
    pre_pull_source: "Local\n",
    marked_source: "marked",
    observed_remote_body: remote_body,
    observed_revision_id: "rev-resolve",
  }
  assert_eq(
    @registry.save_registry_document(
      directory,
      @registry.document_with_pending_merge(document, canonical, pending).unwrap(),
    ),
    Ok(()),
  )
  let fake = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(
        remote, "resolve-success-doc", "rev-resolve", "resolve-success-tab",
      ),
      drive_comments_response(0),
      success_response(),
    ],
  }
  guard resolve_path_with_registry(
      "resolve-success.md",
      fn(_) { Ok("Resolved") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      fake,
    )
    is Ok(Updated(success, _)) else {
    fail("a valid edited resolution must update Google Docs")
  }
  assert_eq(success.document_id, "resolve-success-doc")
  assert_eq(fake.requests.length(), 3)
  assert_true(fake.requests[2].url.contains(":batchUpdate"))
  assert_true(fake.requests[2].body.unwrap().contains("rev-resolve"))
  let entry = @registry.registry_snapshot(directory).unwrap().entries[0]
  assert_eq(entry.pending_merge, None)
  assert_eq(
    @debug.to_string(entry.published_baseline),
    @debug.to_string(Some(resolved)),
  )
  clean_workflow_directory(directory)
}

///|
async test "resolve retains Pending Merge for stale remote state and unresolved comments" {
  let directory = workflow_directory("resolve-blocked")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Base")
  let remote = workflow_document("Remote")
  seed_ready_with_baseline(
    directory, "resolve-blocked.md", "resolve-blocked-doc", "resolve-blocked-tab",
    baseline,
  )
  let canonical = @registry.canonical_source_path("resolve-blocked.md")
  let document = @registry.registry_snapshot(directory).unwrap()
  let pending : @registry.PendingMerge = {
    pre_pull_source: "Local",
    marked_source: "marked",
    observed_remote_body: docs_response_json(
      remote, "resolve-blocked-doc", "rev-observed", "resolve-blocked-tab",
    ),
    observed_revision_id: "rev-observed",
  }
  assert_eq(
    @registry.save_registry_document(
      directory,
      @registry.document_with_pending_merge(document, canonical, pending).unwrap(),
    ),
    Ok(()),
  )
  let stale = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(
        workflow_document("Unexpected"),
        "resolve-blocked-doc",
        "rev-new",
        "resolve-blocked-tab",
      ),
    ],
  }
  guard resolve_path_with_registry(
      "resolve-blocked.md",
      fn(_) { Ok("Resolved") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      stale,
    )
    is Err(Concurrency(_)) else {
    fail("stale remote state must block resolve")
  }
  assert_eq(stale.requests.length(), 1)
  let stale_noop = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(
        workflow_document("Unexpected"),
        "resolve-blocked-doc",
        "rev-newer",
        "resolve-blocked-tab",
      ),
    ],
  }
  guard resolve_path_with_registry(
      "resolve-blocked.md",
      fn(_) { Ok("Remote") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      stale_noop,
    ) is Err(Concurrency(_)) else {
    fail("a no-write resolution must still reject incompatible stale state")
  }
  assert_eq(stale_noop.requests.length(), 1)
  let comments = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(
        remote, "resolve-blocked-doc", "rev-observed", "resolve-blocked-tab",
      ),
      drive_comments_response(1),
    ],
  }
  guard resolve_path_with_registry(
      "resolve-blocked.md",
      fn(_) { Ok("Resolved") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      comments,
    )
    is Err(ReviewBarrier(unresolved=1)) else {
    fail("unresolved comments must block resolve")
  }
  assert_eq(comments.requests.length(), 2)
  assert_true(
    @registry.registry_snapshot(directory).unwrap().entries[0].pending_merge
    is Some(_),
  )
  clean_workflow_directory(directory)
}

///|
async test "resolve diagnoses ambiguous updates and retries an already-landed resolution idempotently" {
  let directory = workflow_directory("resolve-ambiguous")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Base")
  let remote = workflow_document("Remote")
  let resolved = workflow_document("Resolved")
  seed_ready_with_baseline(
    directory, "resolve-ambiguous.md", "resolve-ambiguous-doc", "resolve-ambiguous-tab",
    baseline,
  )
  let canonical = @registry.canonical_source_path("resolve-ambiguous.md")
  let observed_body = docs_response_json(
    remote, "resolve-ambiguous-doc", "rev-before", "resolve-ambiguous-tab",
  )
  let pending : @registry.PendingMerge = {
    pre_pull_source: "Local",
    marked_source: "marked",
    observed_remote_body: observed_body,
    observed_revision_id: "rev-before",
  }
  let document = @registry.registry_snapshot(directory).unwrap()
  assert_eq(
    @registry.save_registry_document(
      directory,
      @registry.document_with_pending_merge(document, canonical, pending).unwrap(),
    ),
    Ok(()),
  )
  let ambiguous = WorkflowAmbiguousHttpClient::{
    requests: [],
    responses: [
      docs_response(
        remote, "resolve-ambiguous-doc", "rev-before", "resolve-ambiguous-tab",
      ),
      drive_comments_response(0),
      success_response(),
      docs_response(
        resolved, "resolve-ambiguous-doc", "rev-after", "resolve-ambiguous-tab",
      ),
    ],
  }
  guard resolve_path_with_registry(
      "resolve-ambiguous.md",
      fn(_) { Ok("Resolved") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      ambiguous,
    )
    is Ok(Updated(_, _)) else {
    fail("a reread-confirmed ambiguous resolve must commit")
  }
  assert_eq(ambiguous.requests.length(), 4)
  let committed = @registry.registry_snapshot(directory).unwrap()
  assert_eq(committed.entries[0].pending_merge, None)
  let interrupted : @registry.RegistryDocument = {
    entries: [{ ..committed.entries[0], pending_merge: Some(pending) }],
  }
  assert_eq(@registry.save_registry_document(directory, interrupted), Ok(()))
  let retry = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      docs_response(
        resolved, "resolve-ambiguous-doc", "rev-after", "resolve-ambiguous-tab",
      ),
      drive_comments_response(0),
    ],
  }
  guard resolve_path_with_registry(
      "resolve-ambiguous.md",
      fn(_) { Ok("Resolved") },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      retry,
    )
    is Ok(Updated(_, _)) else {
    fail("an already-landed resolution must finish without another write")
  }
  assert_eq(retry.requests.length(), 2)
  for request in retry.requests {
    assert_true(!request.url.contains(":batchUpdate"))
  }
  assert_eq(
    @registry.registry_snapshot(directory).unwrap().entries[0].pending_merge,
    None,
  )
  clean_workflow_directory(directory)
}

///|
async test "resolve blocks an unresolved suggestion overlapping the edited resolution" {
  let directory = workflow_directory("resolve-suggestion")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Base")
  let remote = workflow_document("Remote")
  seed_ready_with_baseline(
    directory, "resolve-suggestion.md", "resolve-suggestion-doc", "resolve-suggestion-tab",
    baseline,
  )
  let canonical = @registry.canonical_source_path("resolve-suggestion.md")
  let body = docs_response_json(
    remote, "resolve-suggestion-doc", "rev-suggestion", "resolve-suggestion-tab",
  ).replace_all(
    old="\"textRun\":{\"content\":\"Remote\"",
    new="\"textRun\":{\"content\":\"Remote\",\"suggestedDeletionIds\":[\"s-1\"]",
  )
  let pending : @registry.PendingMerge = {
    pre_pull_source: "Local",
    marked_source: "marked",
    observed_remote_body: body,
    observed_revision_id: "rev-suggestion",
  }
  let document = @registry.registry_snapshot(directory).unwrap()
  assert_eq(
    @registry.save_registry_document(
      directory,
      @registry.document_with_pending_merge(document, canonical, pending).unwrap(),
    ),
    Ok(()),
  )
  let fake = WorkflowFakeHttpClient::{ requests: [], responses: [] }
  let token_calls = [0]
  guard resolve_path_with_registry(
      "resolve-suggestion.md",
      fn(_) { Ok("Resolved") },
      directory,
      Adc,
      fn() {
        token_calls[0] = token_calls[0] + 1
        Ok("project")
      },
      fn() {
        token_calls[0] = token_calls[0] + 1
        Ok("adc")
      },
      fake,
    )
    is Err(MergeConflict(_)) else {
    fail("an overlapping unresolved suggestion must block resolve")
  }
  assert_eq(token_calls[0], 0)
  assert_eq(fake.requests.length(), 0)
  assert_true(
    @registry.registry_snapshot(directory).unwrap().entries[0].pending_merge
    is Some(_),
  )
  clean_workflow_directory(directory)
}

///|
async test "pull suggestions stay remote-only and do not inspect comments" {
  let directory = workflow_directory("pull-suggestion")
  clean_workflow_directory(directory)
  let baseline = workflow_document("Original")
  seed_ready_with_baseline(
    directory, "pull-suggestion.md", "pull-suggestion-doc", "pull-suggestion-tab",
    baseline,
  )
  let body = docs_response_json(
    baseline, "pull-suggestion-doc", "rev-suggestion", "pull-suggestion-tab",
  ).replace_all(
    old="\"textRun\":{\"content\":\"Original\"",
    new="\"textRun\":{\"content\":\"Original\",\"suggestedDeletionIds\":[\"s-1\"]",
  )
  let docs = WorkflowFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, body)],
  }
  let writes : Array[String] = []
  guard pull_path_with_registry(
      "pull-suggestion.md",
      fn(_) { Ok("Original") },
      fn(_, replacement) {
        writes.push(replacement)
        Ok(())
      },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      docs,
      false,
    )
    is Ok(PullNoOp(report)) else {
    fail("a suggested unit must be skipped without blocking pure pull")
  }
  assert_eq(report.plan.skipped, 1)
  assert_eq(report.plan.units[0].category, SkippedSuggestion)
  assert_eq(writes.length(), 0)
  assert_eq(docs.requests.length(), 1)
  clean_workflow_directory(directory)
}

///|
async test "pull keeps missing documents and Managed Tabs fail closed" {
  let directory = workflow_directory("pull-missing")
  clean_workflow_directory(directory)
  seed_ready(
    directory, "pull-missing.md", "pull-missing-doc", "pull-missing-tab",
  )
  let writes : Array[String] = []
  let missing_document = WorkflowFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(404, {}, "{}")],
  }
  guard pull_path_with_registry(
      "pull-missing.md",
      fn(_) { Ok("Hello") },
      fn(_, replacement) {
        writes.push(replacement)
        Ok(())
      },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      missing_document,
      false,
    )
    is Err(RemoteMissing(..)) else {
    fail("missing document must fail closed")
  }
  let missing_tab = WorkflowFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"documentId\":\"pull-missing-doc\",\"revisionId\":\"rev\",\"tabs\":[]}",
      ),
    ],
  }
  guard pull_path_with_registry(
      "pull-missing.md",
      fn(_) { Ok("Hello") },
      fn(_, replacement) {
        writes.push(replacement)
        Ok(())
      },
      directory,
      Adc,
      fn() { Ok("project") },
      fn() { Ok("adc") },
      missing_tab,
      false,
    )
    is Err(RemoteMissing(..)) else {
    fail("missing Managed Tab must fail closed")
  }
  assert_eq(writes.length(), 0)
  clean_workflow_directory(directory)
}

///|
async test "listing JSON is deterministic and refresh adds matching inspection" {
  let blocked : @registry.PublicationEntry = {
    source_path: "z.md",
    document_id: None,
    url: None,
    managed_tab_id: None,
    lifecycle: Blocked,
    last_successful_publish: None,
    published_baseline: None,
    pending_merge: None,
  }
  let ready = ready_entry("a.md", "a-doc", "a-tab")
  let document : @registry.RegistryDocument = { entries: [blocked, ready] }
  assert_eq(
    publication_list_json(document, fn(path) { path == "z.md" }),
    "{\"version\":1,\"publications\":[{\"source_path\":\"a.md\",\"document_id\":\"a-doc\",\"url\":\"https://docs.google.com/document/d/a-doc/edit\",\"managed_tab_id\":\"a-tab\",\"lifecycle\":\"provisional\",\"last_successful_publish\":null,\"source_missing\":false},{\"source_path\":\"z.md\",\"document_id\":null,\"url\":null,\"managed_tab_id\":null,\"lifecycle\":\"blocked\",\"last_successful_publish\":null,\"source_missing\":true}]}",
  )
  let refreshed = publication_refresh_json(document, fn(_) { false }, [
    {
      document_id: "a-doc",
      url: "ignored",
      title: Some("Remote"),
      trashed: false,
      editable: Some(true),
      managed_tab_present: true,
      status: Ready,
    },
  ])
  assert_true(refreshed.contains("\"title\":\"Remote\""))
  assert_true(refreshed.contains("\"remote_status\":\"ready\""))
  assert_true(!refreshed.contains("\"title\":null"))
  let conflicted : @registry.PublicationEntry = {
    ..ready,
    lifecycle: Ready,
    last_successful_publish: Some("before"),
    published_baseline: Some(workflow_document("Base")),
    pending_merge: Some({
      pre_pull_source: "Local",
      marked_source: "marked",
      observed_remote_body: "body",
      observed_revision_id: "rev",
    }),
  }
  assert_true(
    publication_list_json({ entries: [conflicted] }, fn(_) { false }).contains(
      "\"lifecycle\":\"merge-conflicted\"",
    ),
  )
}

///|
test "unix timestamp uses UTC" {
  // `date -u -r 1714227729` verifies this epoch as 2024-04-27T14:22:09Z.
  inspect(format_unix_timestamp(1714227729L), content="2024-04-27T14:22:09Z")
}
