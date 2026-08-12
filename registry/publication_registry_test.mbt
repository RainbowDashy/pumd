///|
fn test_directory(name : String) -> String { "_build/registry-" + name }

///|
async fn clean_directory(directory : String) -> Unit {
  @async_fs.rmdir(directory, recursive=true) catch { _ => () }
}

///|
test "registry directory resolution follows XDG then Windows then HOME" {
  assert_eq(resolve_registry_directory(fn(name) { if name == "XDG_CONFIG_HOME" { Some("/xdg") } else { None } }), Ok("/xdg/pumd"))
  assert_eq(resolve_registry_directory(fn(name) { if name == "APPDATA" { Some("/appdata") } else { None } }), Ok("/appdata/pumd"))
  assert_eq(resolve_registry_directory(fn(name) { if name == "HOME" { Some("/home/user") } else { None } }), Ok("/home/user/.config/pumd"))
  guard resolve_registry_directory(fn(_) { None }) is Err(Unavailable(_)) else { fail("missing environment must fail") }
}

///|
async test "missing registry is empty and provisional publications round trip" {
  let directory = test_directory("round-trip")
  clean_directory(directory)
  guard load_registry_document(directory) is Ok(empty) else { fail("missing registry should load") }
  assert_eq(empty.entries.length(), 0)
  let entry : PublicationEntry = { source_path: "notes/a.md", document_id: Some("doc-a"), url: Some("https://docs/a"), managed_tab_id: Some("tab-a"), lifecycle: Provisional, last_successful_publish: None, published_baseline: None }
  assert_eq(register_provisional_publication(directory, entry), Ok(()))
  guard load_registry_document(directory) is Ok(loaded) else { fail("registry should load") }
  assert_eq(loaded.entries.length(), 1)
  assert_eq(loaded.entries[0].document_id, Some("doc-a"))
  clean_directory(directory)
}

///|
async test "registry rejects duplicates and fails closed on corruption" {
  let directory = test_directory("corruption")
  clean_directory(directory)
  let entry : PublicationEntry = { source_path: "notes/a.md", document_id: Some("doc-a"), url: Some("https://docs/a"), managed_tab_id: Some("tab-a"), lifecycle: Provisional, last_successful_publish: None, published_baseline: None }
  assert_eq(register_provisional_publication(directory, entry), Ok(()))
  guard register_provisional_publication(directory, entry) is Err(DuplicateSource("notes/a.md")) else { fail("duplicate source must fail") }
  @async_fs.write_file(registry_file_path(directory), "garbage", create_mode=@async_fs.TruncateExisting)
  let before = @async_fs.read_file(registry_file_path(directory)).text()
  guard record_blocked_publication(directory, "notes/b.md") is Err(Malformed(_)) else { fail("corruption must fail closed") }
  assert_eq(@async_fs.read_file(registry_file_path(directory)).text(), before)
  clean_directory(directory)
}

///|
async test "blocked, forget, reassociate and canonical path behavior" {
  let directory = test_directory("mutations")
  clean_directory(directory)
  assert_eq(record_blocked_publication(directory, "notes/blocked.md"), Ok(()))
  guard commit_ready_publication(directory, "notes/blocked.md", { metadata: { title: None, locale: None }, render_metadata: { style_profile_id: "default", style_profile_version: 1 }, content: [], provenance: None }, "now") is Err(BlockedPublication(_)) else { fail("blocked publication must not become ready") }
  assert_eq(forget_publication(directory, "notes/blocked.md"), Ok(true))
  assert_eq(forget_publication(directory, "notes/blocked.md"), Ok(false))
  let missing = "_build/registry-not-a-real-source.md"
  match @env.current_dir() {
    Some(cwd) =>
      assert_true(
        canonical_source_path(missing) == cwd + "/" + missing ||
        canonical_source_path(missing) == cwd + missing,
      )
    None => fail("current directory must resolve in tests")
  }
  clean_directory(directory)
}

///|
fn test_run(content : String) -> @pumd.TextRun {
  {
    content,
    style: {
      font_family: "Arial",
      font_size_points: 11,
      bold: false,
      italic: false,
      underline: false,
      foreground_color: None,
      background_color: None,
    },
    link: None,
    provenance: None,
  }
}

///|
fn test_paragraph_style() -> @pumd.ParagraphStyle {
  {
    named_style: @pumd.NamedStyle::NormalText,
    font_family: "Arial",
    font_size_points: 11,
    line_spacing_percent: 115,
    space_above_points: 0,
    space_below_points: 0,
    background_color: None,
    indent_start_points: None,
    indent_first_line_points: None,
    border_left: None,
  }
}

///|
fn test_baseline() -> @pumd.DesiredDocument {
  {
    metadata: { title: Some("Design Notes"), locale: Some("en") },
    render_metadata: { style_profile_id: "pumd.default", style_profile_version: 2 },
    content: [
      @pumd.StructuralElement::Paragraph({
        runs: [
          {
            content: "Hello",
            style: {
              font_family: "Georgia",
              font_size_points: 14,
              bold: true,
              italic: true,
              underline: false,
              foreground_color: Some("#ff0000"),
              background_color: Some("#eeeeee"),
            },
            link: Some({ url: "https://example.com/a", title: Some("A") }),
            provenance: Some({ start: 0, end: 5 }),
          },
        ],
        inline_images: [],
        style: {
          named_style: @pumd.NamedStyle::Heading1,
          font_family: "Georgia",
          font_size_points: 20,
          line_spacing_percent: 100,
          space_above_points: 12,
          space_below_points: 6,
          background_color: None,
          indent_start_points: Some(36),
          indent_first_line_points: Some(18),
          border_left: Some({ color: "#000000", width_points: 3, padding_points: 4 }),
        },
        bullet: Some({ kind: @pumd.ListKind::Numbered(start=1, delimiter="."), nesting_level: 1 }),
        provenance: Some({ start: 0, end: 30 }),
      }),
      @pumd.StructuralElement::Table({
        rows: [
          {
            cells: [
              {
                content: [
                  { runs: [test_run("Cell A")], inline_images: [], style: test_paragraph_style(), bullet: None, provenance: None },
                ],
                alignment: @pumd.TableAlignment::Center,
                background_color: Some("#ffffff"),
                provenance: None,
              },
            ],
            is_header: true,
            provenance: None,
          },
        ],
        provenance: Some({ start: 31, end: 45 }),
      }),
    ],
    provenance: Some({ start: 0, end: 45 }),
  }
}

///|
fn updated_baseline(title : String) -> @pumd.DesiredDocument {
  { ..test_baseline(), metadata: { title: Some(title), locale: Some("en") } }
}

///|
async test "updating a ready publication replaces its baseline without changing other entries" {
  let original = test_baseline()
  let replacement = updated_baseline("Updated publication")
  let ready : PublicationEntry = {
    source_path: "notes/ready.md",
    document_id: Some("doc-ready"),
    url: Some("https://docs.google.com/document/d/doc-ready/edit"),
    managed_tab_id: Some("tab-ready"),
    lifecycle: Ready,
    last_successful_publish: Some("2026-08-05T09:30:00Z"),
    published_baseline: Some(original),
  }
  let untouched : PublicationEntry = {
    source_path: "notes/other.md",
    document_id: Some("doc-other"),
    url: Some("https://docs.google.com/document/d/doc-other/edit"),
    managed_tab_id: Some("tab-other"),
    lifecycle: Provisional,
    last_successful_publish: None,
    published_baseline: None,
  }
  let document : RegistryDocument = { entries: [ready, untouched] }
  guard document_with_updated_baseline(document, "notes/ready.md", replacement, "2026-08-06T09:30:00Z") is Ok(updated) else {
    fail("ready publication update must succeed")
  }
  let updated_ready = updated.entries[0]
  assert_eq(updated_ready.lifecycle, Ready)
  assert_eq(updated_ready.document_id, ready.document_id)
  assert_eq(updated_ready.url, ready.url)
  assert_eq(updated_ready.managed_tab_id, ready.managed_tab_id)
  assert_eq(updated_ready.last_successful_publish, Some("2026-08-06T09:30:00Z"))
  assert_eq(@debug.to_string(updated_ready.published_baseline), @debug.to_string(Some(replacement)))
  assert_eq(@debug.to_string(updated.entries[1]), @debug.to_string(untouched))
}

///|
async test "updating provisional, blocked, or missing publications is rejected" {
  let provisional : PublicationEntry = {
    source_path: "notes/provisional.md",
    document_id: Some("doc-provisional"),
    url: Some("https://docs.google.com/document/d/doc-provisional/edit"),
    managed_tab_id: Some("tab-provisional"),
    lifecycle: Provisional,
    last_successful_publish: None,
    published_baseline: None,
  }
  let blocked : PublicationEntry = {
    source_path: "notes/blocked.md",
    document_id: None,
    url: None,
    managed_tab_id: None,
    lifecycle: Blocked,
    last_successful_publish: None,
    published_baseline: None,
  }
  let document : RegistryDocument = { entries: [provisional, blocked] }
  guard document_with_updated_baseline(document, "notes/provisional.md", test_baseline(), "now") is Err(Invalid(_)) else {
    fail("provisional publication update must be invalid")
  }
  guard document_with_updated_baseline(document, "notes/blocked.md", test_baseline(), "now") is Err(Invalid(_)) else {
    fail("blocked publication update must be invalid")
  }
  guard document_with_updated_baseline(document, "notes/missing.md", test_baseline(), "now") is Err(NotFound("notes/missing.md")) else {
    fail("missing publication update must be not found")
  }
}

///|
async test "updating a publication baseline persists a valid registry" {
  let directory = test_directory("update-persistence")
  clean_directory(directory)
  let entry : PublicationEntry = {
    source_path: "notes/persist.md",
    document_id: Some("doc-persist"),
    url: Some("https://docs.google.com/document/d/doc-persist/edit"),
    managed_tab_id: Some("tab-persist"),
    lifecycle: Provisional,
    last_successful_publish: None,
    published_baseline: None,
  }
  assert_eq(register_provisional_publication(directory, entry), Ok(()))
  assert_eq(commit_ready_publication(directory, "notes/persist.md", test_baseline(), "first"), Ok(()))
  let replacement = updated_baseline("Persisted update")
  assert_eq(update_publication_baseline(directory, "notes/persist.md", replacement, "second"), Ok(()))
  guard load_registry_document(directory) is Ok(loaded) else {
    fail("updated registry must load")
  }
  assert_eq(validate_registry_document(loaded), Ok(()))
  let updated = loaded.entries[0]
  assert_eq(updated.last_successful_publish, Some("second"))
  assert_eq(@debug.to_string(updated.published_baseline), @debug.to_string(Some(replacement)))
  clean_directory(directory)
}

///|
async test "updating twice replaces the previous published baseline" {
  let first = updated_baseline("First update")
  let second = updated_baseline("Second update")
  let ready : PublicationEntry = {
    source_path: "notes/twice.md",
    document_id: Some("doc-twice"),
    url: Some("https://docs.google.com/document/d/doc-twice/edit"),
    managed_tab_id: Some("tab-twice"),
    lifecycle: Ready,
    last_successful_publish: Some("original"),
    published_baseline: Some(test_baseline()),
  }
  guard document_with_updated_baseline({ entries: [ready] }, "notes/twice.md", first, "first") is Ok(after_first) else {
    fail("first update must succeed")
  }
  guard document_with_updated_baseline(after_first, "notes/twice.md", second, "second") is Ok(after_second) else {
    fail("second update must succeed")
  }
  assert_eq(after_second.entries[0].last_successful_publish, Some("second"))
  assert_eq(@debug.to_string(after_second.entries[0].published_baseline), @debug.to_string(Some(second)))
}

///|
async test "updating a publication never changes its destination identity" {
  let ready : PublicationEntry = {
    source_path: "notes/identity.md",
    document_id: Some("doc-identity"),
    url: Some("https://docs.google.com/document/d/doc-identity/edit"),
    managed_tab_id: Some("tab-identity"),
    lifecycle: Ready,
    last_successful_publish: Some("before"),
    published_baseline: Some(test_baseline()),
  }
  guard document_with_updated_baseline({ entries: [ready] }, "notes/identity.md", updated_baseline("Identity update"), "after") is Ok(updated) else {
    fail("ready publication update must succeed")
  }
  assert_eq(updated.entries[0].document_id, ready.document_id)
  assert_eq(updated.entries[0].url, ready.url)
  assert_eq(updated.entries[0].managed_tab_id, ready.managed_tab_id)
}

///|
async test "ready publication round-trips a complete Published Baseline" {
  let directory = test_directory("baseline")
  clean_directory(directory)
  let entry : PublicationEntry = {
    source_path: "notes/design.md",
    document_id: Some("doc-baseline"),
    url: Some("https://docs.google.com/document/d/doc-baseline/edit"),
    managed_tab_id: Some("tab-baseline"),
    lifecycle: Provisional,
    last_successful_publish: None,
    published_baseline: None,
  }
  assert_eq(register_provisional_publication(directory, entry), Ok(()))
  assert_eq(
    commit_ready_publication(
      directory,
      "notes/design.md",
      test_baseline(),
      "2026-08-05T09:30:00Z",
    ),
    Ok(()),
  )
  guard load_registry_document(directory) is Ok(loaded) else {
    fail("registry must load after commit")
  }
  assert_eq(loaded.entries.length(), 1)
  let ready = loaded.entries[0]
  assert_eq(ready.lifecycle, Ready)
  assert_eq(ready.document_id, Some("doc-baseline"))
  assert_eq(ready.managed_tab_id, Some("tab-baseline"))
  assert_eq(ready.last_successful_publish, Some("2026-08-05T09:30:00Z"))
  match ready.published_baseline {
    Some(baseline) =>
      assert_eq(@debug.to_string(baseline), @debug.to_string(test_baseline()))
    None => fail("published baseline must round trip")
  }
  guard commit_ready_publication(
    directory,
    "notes/design.md",
    test_baseline(),
    "2026-08-05T09:31:00Z",
  ) is Err(Invalid(_)) else {
    fail("committing an already-ready publication must fail")
  }
  clean_directory(directory)
}

///|
async test "registry directory and file are owner-only on non-Windows" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let directory = test_directory("permissions")
  clean_directory(directory)
  let entry : PublicationEntry = {
    source_path: "notes/perms.md",
    document_id: Some("doc-perms"),
    url: Some("https://docs.google.com/document/d/doc-perms/edit"),
    managed_tab_id: Some("tab-perms"),
    lifecycle: Provisional,
    last_successful_publish: None,
    published_baseline: None,
  }
  assert_eq(register_provisional_publication(directory, entry), Ok(()))
  assert_eq(registry_file_mode(directory), 0o700)
  assert_eq(registry_file_mode(registry_file_path(directory)), 0o600)
  clean_directory(directory)
}

async test "version-one baselines without image fields remain readable" {
  let directory = test_directory("legacy-baseline"); clean_directory(directory); @async_fs.mkdir(directory, permission=0o700, recursive=true)
  let baseline = Json::Json(test_baseline()).stringify(); let legacy = baseline.replace_all(old=",\"inline_images\":[]", new="")
  let registry = "{\"version\":1,\"publications\":[{\"source_path\":\"notes/legacy.md\",\"document_id\":\"doc\",\"url\":\"u\",\"managed_tab_id\":\"tab\",\"lifecycle\":\"ready\",\"last_successful_publish\":\"now\",\"published_baseline\":" + legacy + "}]}"
  @async_fs.write_file(registry_file_path(directory), registry, create_mode=@async_fs.CreateNew)
  guard load_registry_document(directory) is Ok(document) else { fail("legacy baseline must load") }; guard document.entries[0].published_baseline is Some(baseline) else { fail("legacy baseline must be restored") }
  match baseline.content[0] { @pumd.StructuralElement::Paragraph(paragraph) => assert_true(paragraph.inline_images.is_empty()); _ => fail("expected paragraph") }; clean_directory(directory)
}

///|
async test "duplicate document IDs are rejected in mutation and load" {
  let directory = test_directory("duplicate-document")
  clean_directory(directory)
  let first : PublicationEntry = {
    source_path: "notes/a.md",
    document_id: Some("doc-shared"),
    url: Some("https://docs.google.com/document/d/doc-shared/edit"),
    managed_tab_id: Some("tab-a"),
    lifecycle: Provisional,
    last_successful_publish: None,
    published_baseline: None,
  }
  assert_eq(register_provisional_publication(directory, first), Ok(()))
  let second : PublicationEntry = {
    ..first,
    source_path: "notes/b.md",
    managed_tab_id: Some("tab-b"),
  }
  guard register_provisional_publication(directory, second) is Err(
    DuplicateDocument("doc-shared"),
  ) else {
    fail("a document ID must belong to at most one publication")
  }
  let text = "{\"version\":1,\"publications\":[{\"source_path\":\"x.md\",\"document_id\":\"dup\",\"url\":\"u\",\"managed_tab_id\":\"t\",\"lifecycle\":\"provisional\",\"last_successful_publish\":null,\"published_baseline\":null},{\"source_path\":\"y.md\",\"document_id\":\"dup\",\"url\":\"u\",\"managed_tab_id\":\"t\",\"lifecycle\":\"provisional\",\"last_successful_publish\":null,\"published_baseline\":null}]}"
  @async_fs.write_file(registry_file_path(directory), text, create_mode=@async_fs.TruncateExisting)
  guard load_registry_document(directory) is Err(Malformed(_)) else {
    fail("a file with duplicate document IDs must fail closed")
  }
  clean_directory(directory)
}

///|
async test "unsupported versions and empty files fail closed without rewriting" {
  let directory = test_directory("versions")
  clean_directory(directory)
  @async_fs.mkdir(directory, permission=0o700, recursive=true) catch { _ => () }
  @async_fs.write_file(registry_file_path(directory), "{\"version\":2,\"publications\":[]}", create_mode=@async_fs.CreateNew)
  guard load_registry_document(directory) is Err(UnsupportedVersion(2)) else {
    fail("version 2 must be rejected")
  }
  @async_fs.write_file(registry_file_path(directory), "", create_mode=@async_fs.TruncateExisting)
  guard load_registry_document(directory) is Err(Malformed(_)) else {
    fail("an empty registry must be malformed")
  }
  let before = @async_fs.read_file(registry_file_path(directory)).text()
  guard record_blocked_publication(directory, "notes/b.md") is Err(_) else {
    fail("mutation on an unsupported registry must fail closed")
  }
  assert_eq(@async_fs.read_file(registry_file_path(directory)).text(), before)
  clean_directory(directory)
}

///|
async test "atomic replacement leaves no temporary files and tolerates crash residue" {
  let directory = test_directory("atomic")
  clean_directory(directory)
  let entry : PublicationEntry = {
    source_path: "notes/atomic.md",
    document_id: Some("doc-atomic"),
    url: Some("https://docs.google.com/document/d/doc-atomic/edit"),
    managed_tab_id: Some("tab-atomic"),
    lifecycle: Provisional,
    last_successful_publish: None,
    published_baseline: None,
  }
  assert_eq(register_provisional_publication(directory, entry), Ok(()))
  let residue = registry_file_path(directory) + ".tmp-interrupted"
  @async_fs.write_file(residue, "junk", create_mode=@async_fs.CreateNew)
  assert_eq(
    commit_ready_publication(directory, "notes/atomic.md", test_baseline(), "2026-08-05T10:00:00Z"),
    Ok(()),
  )
  guard load_registry_document(directory) is Ok(loaded) else {
    fail("stray temporary residue must not corrupt the registry")
  }
  assert_eq(loaded.entries.length(), 1)
  let names = @async_fs.readdir(directory)
  for name in names {
    if name.has_prefix("publications.json.tmp-") && name != "publications.json.tmp-interrupted" {
      fail("no temporary files may remain after an atomic save")
    }
  }
  clean_directory(directory)
}

///|
async test "concurrent registration serializes through the registry lock" {
  let directory = test_directory("concurrency")
  clean_directory(directory)
  let outcomes : Array[Result[Unit, RegistryError]] = []
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      let entry : PublicationEntry = {
        source_path: "notes/race.md",
        document_id: Some("doc-race"),
        url: Some("https://docs.google.com/document/d/doc-race/edit"),
        managed_tab_id: Some("tab-race"),
        lifecycle: Provisional,
        last_successful_publish: None,
        published_baseline: None,
      }
      outcomes.push(register_provisional_publication(directory, entry))
    }
    group.spawn_bg() <| () => {
      let entry : PublicationEntry = {
        source_path: "notes/race.md",
        document_id: Some("doc-race"),
        url: Some("https://docs.google.com/document/d/doc-race/edit"),
        managed_tab_id: Some("tab-race"),
        lifecycle: Provisional,
        last_successful_publish: None,
        published_baseline: None,
      }
      outcomes.push(register_provisional_publication(directory, entry))
    }
    ()
  }
  assert_eq(outcomes.length(), 2)
  let mut successes = 0
  let mut duplicate_sources = 0
  for outcome in outcomes {
    match outcome {
      Ok(_) => successes = successes + 1
      Err(DuplicateSource(_)) => duplicate_sources = duplicate_sources + 1
      Err(error) => fail("unexpected concurrency error: " + error.user_message())
    }
  }
  assert_eq(successes, 1)
  assert_eq(duplicate_sources, 1)
  clean_directory(directory)
}

///|
async test "reassociation validates destination ownership and blocked refusals" {
  let directory = test_directory("reassociation")
  clean_directory(directory)
  let first : PublicationEntry = {
    source_path: "notes/old.md",
    document_id: Some("doc-move"),
    url: Some("https://docs.google.com/document/d/doc-move/edit"),
    managed_tab_id: Some("tab-move"),
    lifecycle: Provisional,
    last_successful_publish: None,
    published_baseline: None,
  }
  assert_eq(register_provisional_publication(directory, first), Ok(()))
  assert_eq(record_blocked_publication(directory, "notes/taken.md"), Ok(()))
  guard reassociate_publication(directory, "notes/old.md", "notes/taken.md") is Err(
    DestinationOccupied("notes/taken.md"),
  ) else {
    fail("an occupied destination must be rejected")
  }
  guard reassociate_publication(directory, "notes/absent.md", "notes/new.md") is Err(
    NotFound("notes/absent.md"),
  ) else {
    fail("an unknown source must be rejected")
  }
  assert_eq(reassociate_publication(directory, "notes/old.md", "notes/new.md"), Ok(()))
  guard load_registry_document(directory) is Ok(loaded) else {
    fail("registry must load after reassociation")
  }
  assert_eq(publication_for_source(loaded, "notes/new.md").map(fn(entry) { entry.document_id }), Some(Some("doc-move")))
  guard publication_for_source(loaded, "notes/old.md") is None else {
    fail("the old source must be free after reassociation")
  }
  let blocked : PublicationEntry = {
    source_path: "notes/taken.md",
    document_id: Some("doc-blocked"),
    url: Some("https://docs.google.com/document/d/doc-blocked/edit"),
    managed_tab_id: Some("tab-blocked"),
    lifecycle: Provisional,
    last_successful_publish: None,
    published_baseline: None,
  }
  guard document_with_provisional(loaded, blocked) is Err(
    BlockedPublication("notes/taken.md"),
  ) else {
    fail("a blocked source must refuse provisional registration")
  }
  clean_directory(directory)
}
