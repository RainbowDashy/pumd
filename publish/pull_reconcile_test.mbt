///|
fn pull_rendered(source : String) -> @pumd.DesiredDocument {
  match @pumd.render_markdown(source) {
    Ok(document) => document
    Err(_) => abort("pull fixture must render")
  }
}

///|
fn pull_remote_paragraph(
  text : String,
  start : Int,
  style? : @pumd.ParagraphStyle,
  text_style? : @pumd.TextStyle,
  suggestions? : Array[RemoteSuggestion] = [],
) -> RemoteParagraph {
  let paragraph_style = style.unwrap_or(@pumd.builtin_style_profile().body)
  let run_style = text_style.unwrap_or(@pumd.builtin_style_profile().body_text)
  {
    start_index: start,
    end_index: start + text.length() + 1,
    runs: [
      {
        start_index: start,
        end_index: start + text.length(),
        text,
        style: run_style,
        link: None,
      },
    ],
    inline_images: [],
    style: paragraph_style,
    bullet: None,
    suggestions,
    normalization_warning: false,
  }
}

///|
test "pull imports remote Source Semantics and ignores cosmetic formatting" {
  let source = "[ref]: https://example.test\n\nOriginal\n\nTail\n"
  let baseline = pull_rendered(source)
  let remote_style = {
    ..@pumd.builtin_style_profile().body,
    font_family: "Comic Sans MS",
    line_spacing_percent: 177,
    space_below_points: 42,
  }
  let remote_text_style = {
    ..@pumd.builtin_style_profile().body_text,
    font_family: "Papyrus",
    font_size_points: 31,
    foreground_color: Some("#ff00ff"),
  }
  let remote : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(
        pull_remote_paragraph(
          "Reviewer wording",
          1,
          style=remote_style,
          text_style=remote_text_style,
        ),
      ),
      RemoteUnit::Paragraph(pull_remote_paragraph("Tail", 18)),
    ],
  }
  match plan_pull(source, baseline, baseline, remote) {
    Ok(plan) => {
      inspect(
        plan.source,
        content="[ref]: https://example.test\n\nReviewer wording\n\nTail\n",
      )
      assert_eq(plan.incoming, 1)
      assert_eq(plan.preserved_local, 0)
      assert_eq(plan.conflicted, 0)
      assert_eq(plan.skipped, 0)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
fn pull_two_paragraphs(first : String, second : String) -> RemoteContent {
  {
    units: [
      RemoteUnit::Paragraph(pull_remote_paragraph(first, 1)),
      RemoteUnit::Paragraph(pull_remote_paragraph(second, first.length() + 2)),
    ],
  }
}

///|
test "pull merges disjoint Source Semantics and preserves local-only work" {
  let baseline = pull_rendered("Base A\n\nBase B\n")
  let source = "Local A\n\nBase B\n"
  let desired = pull_rendered(source)
  match plan_pull(source, baseline, desired, pull_two_paragraphs("Base A", "Remote B")) {
    Ok(plan) => {
      inspect(plan.source, content="Local A\n\nRemote B\n")
      assert_eq(plan.incoming, 1)
      assert_eq(plan.preserved_local, 1)
      assert_eq(plan.conflicted, 0)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull treats identical independent edits as converged" {
  let baseline = pull_rendered("Base\n")
  let source = "Same\n"
  match plan_pull(
    source,
    baseline,
    pull_rendered(source),
    { units: [RemoteUnit::Paragraph(pull_remote_paragraph("Same", 1))] },
  ) {
    Ok(plan) => {
      inspect(plan.source, content="Same\n")
      assert_eq(plan.converged, 1)
      assert_eq(plan.conflicted, 0)
      assert_true(plan.baseline.semantic_eq(pull_rendered("Same")))
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull returns Merge Conflicts as a non-mutating plan" {
  let baseline = pull_rendered("Base\n")
  let source = "Local\n"
  match plan_pull(
    source,
    baseline,
    pull_rendered(source),
    { units: [RemoteUnit::Paragraph(pull_remote_paragraph("Remote", 1))] },
  ) {
    Ok(plan) => {
      inspect(plan.source, content="Local\n")
      assert_eq(plan.conflicted, 1)
      assert_true(plan.baseline.semantic_eq(baseline))
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull skips suggested units while importing disjoint committed edits" {
  let source = "Base A\n\nBase B\n"
  let baseline = pull_rendered(source)
  let suggested = pull_remote_paragraph(
    "Suggested A",
    1,
    suggestions=[InsertedText(start_index=1, end_index=2, text="x", suggestion_id="s")],
  )
  let remote : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(suggested),
      RemoteUnit::Paragraph(pull_remote_paragraph("Remote B", 14)),
    ],
  }
  match plan_pull(source, baseline, baseline, remote) {
    Ok(plan) => {
      inspect(plan.source, content="Base A\n\nRemote B\n")
      assert_eq(plan.incoming, 1)
      assert_eq(plan.skipped, 1)
      assert_eq(plan.units[0].category, SkippedSuggestion)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull preserves safely aligned opaque structures and blocks ambiguous reorders" {
  let source = "A\n\nB\n"
  let baseline = pull_rendered(source)
  let opaque_unit = RemoteUnit::Opaque({
    start_index: 3,
    end_index: 4,
    kind: "horizontalRule",
    description: None,
  })
  let safe : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(pull_remote_paragraph("A", 1)),
      opaque_unit,
      RemoteUnit::Paragraph(pull_remote_paragraph("Remote B", 4)),
    ],
  }
  match plan_pull(source, baseline, baseline, safe) {
    Ok(plan) => {
      inspect(plan.source, content="A\n\nRemote B\n")
      assert_eq(plan.incoming, 1)
      assert_eq(plan.skipped, 1)
    }
    Err(error) => abort(error.user_message())
  }
  let ambiguous : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(pull_remote_paragraph("B", 1)),
      opaque_unit,
      RemoteUnit::Paragraph(pull_remote_paragraph("A", 4)),
    ],
  }
  guard plan_pull(source, baseline, baseline, ambiguous) is Err(AmbiguousAlignment(_)) else {
    fail("an opaque-bracketed reorder must block")
  }
}

///|
test "canonical Source Semantics serialization is deterministic" {
  let unit = SourceSemanticUnit::Paragraph({
    runs: [
      { text: "bold", bold: true, italic: false, code: false, link: None },
      {
        text: " link",
        bold: false,
        italic: true,
        code: false,
        link: Some("https://example.test"),
      },
    ],
    images: [],
    heading: 2,
    list: None,
    nesting_level: 0,
    quote_depth: 0,
    code_block: false,
  })
  inspect(
    serialize_source_semantic_unit(unit),
    content="## **bold**[* link*](https://example.test)",
  )
  guard @pumd.render_markdown(serialize_source_semantic_unit(unit)) is Ok(_) else {
    fail("canonical Markdown must be accepted by the renderer")
  }
}

///|
test "pull generated units use CRLF without touching surrounding bytes" {
  let source = "[ref]: https://example.test\r\n\r\nBase\r\n"
  let baseline = pull_rendered(source)
  match plan_pull(
    source,
    baseline,
    baseline,
    { units: [RemoteUnit::Paragraph(pull_remote_paragraph("Remote", 1))] },
  ) {
    Ok(plan) => inspect(
      plan.source,
      content="[ref]: https://example.test\r\n\r\nRemote\r\n",
    )
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull patches Unicode code-point provenance without shifting untouched bytes" {
  let source = "🚀 界\n\nBase\n"
  let baseline = pull_rendered(source)
  match plan_pull(
    source,
    baseline,
    baseline,
    pull_two_paragraphs("🚀 界", "Remote"),
  ) {
    Ok(plan) => inspect(plan.source, content="🚀 界\n\nRemote\n")
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull treats a complete table as one reconciliation unit" {
  let baseline_source = "| Key | Value |\n| --- | --- |\n| A | Base |\n"
  let local_source = "| Key | Value |\n| --- | --- |\n| A | Local |\n"
  let baseline = pull_rendered(baseline_source)
  let remote = remote_from_document(baseline)
  match remote.units[0] {
    RemoteUnit::Table(table) => {
      let row = table.rows[1]
      let cell = row.cells[1]
      let paragraph = cell.paragraphs[0]
      let changed = changed_remote_paragraph(paragraph, "Remote")
      let changed_cell = { ..cell, paragraphs: [changed] }
      remote.units[0] = RemoteUnit::Table({
        ..table,
        rows: [table.rows[0], { cells: [row.cells[0], changed_cell] }],
      })
    }
    _ => fail("table fixture")
  }
  match plan_pull(local_source, baseline, pull_rendered(local_source), remote) {
    Ok(plan) => {
      assert_eq(plan.conflicted, 1)
      inspect(plan.source, content=local_source)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull serializes a remote-only whole-table edit canonically" {
  let source = "| Key | Value |\n| :--- | ---: |\n| A | Base |\n"
  let baseline = pull_rendered(source)
  let remote = remote_from_document(baseline)
  match remote.units[0] {
    RemoteUnit::Table(table) => {
      let row = table.rows[1]
      let cell = row.cells[1]
      let changed = changed_remote_paragraph(cell.paragraphs[0], "Remote")
      remote.units[0] = RemoteUnit::Table({
        ..table,
        rows: [table.rows[0], {
          cells: [row.cells[0], { ..cell, paragraphs: [changed] }],
        }],
      })
    }
    _ => fail("table fixture")
  }
  match plan_pull(source, baseline, baseline, remote) {
    Ok(plan) => {
      inspect(
        plan.source,
        content="| Key | Value |\n| :--- | ---: |\n| A | Remote |\n",
      )
      assert_eq(plan.incoming, 1)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull aligns unambiguous remote paragraph insertion and deletion" {
  let source = "A\n\nB\n"
  let baseline = pull_rendered(source)
  let inserted : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(pull_remote_paragraph("A", 1)),
      RemoteUnit::Paragraph(pull_remote_paragraph("X", 3)),
      RemoteUnit::Paragraph(pull_remote_paragraph("B", 5)),
    ],
  }
  match plan_pull(source, baseline, baseline, inserted) {
    Ok(plan) => {
      inspect(plan.source, content="A\n\nX\n\nB\n")
      assert_eq(plan.incoming, 1)
    }
    Err(error) => abort(error.user_message())
  }
  let deleted : RemoteContent = {
    units: [RemoteUnit::Paragraph(pull_remote_paragraph("A", 1))],
  }
  match plan_pull(source, baseline, baseline, deleted) {
    Ok(plan) => {
      inspect(plan.source, content="A\n\n")
      assert_eq(plan.incoming, 1)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull preserves local-only paragraph insertion and deletion" {
  let baseline = pull_rendered("A\n\nB\n")
  let remote = pull_two_paragraphs("A", "B")
  let inserted_source = "A\n\nLocal\n\nB\n"
  match plan_pull(inserted_source, baseline, pull_rendered(inserted_source), remote) {
    Ok(plan) => {
      inspect(plan.source, content=inserted_source)
      assert_eq(plan.preserved_local, 1)
    }
    Err(error) => abort(error.user_message())
  }
  let deleted_source = "A\n"
  match plan_pull(deleted_source, baseline, pull_rendered(deleted_source), remote) {
    Ok(plan) => {
      inspect(plan.source, content=deleted_source)
      assert_eq(plan.preserved_local, 1)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "skipped suggestions retain the affected Published Baseline unit" {
  let source = "Base A\n\nBase B\n"
  let baseline = pull_rendered(source)
  let remote : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(
        pull_remote_paragraph(
          "Suggested A",
          1,
          suggestions=[InsertedText(start_index=1, end_index=2, text="x", suggestion_id="s")],
        ),
      ),
      RemoteUnit::Paragraph(pull_remote_paragraph("Remote B", 14)),
    ],
  }
  match plan_pull(source, baseline, baseline, remote) {
    Ok(plan) => assert_true(
      plan.baseline.semantic_eq(pull_rendered("Base A\n\nRemote B")),
    )
    Err(error) => abort(error.user_message())
  }
}

///|
test "unchanged table has no incoming Source Semantics" {
  let source = "| Key | Value |\n| --- | --- |\n| A | Base |\n"
  let baseline = pull_rendered(source)
  match plan_pull(source, baseline, baseline, remote_from_document(baseline)) {
    Ok(plan) => {
      assert_eq(plan.incoming, 0)
      assert_eq(plan.conflicted, 0)
      inspect(plan.source, content=source)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "canonical plain paragraphs escape block-leading Markdown markers" {
  let markers = ["# heading", "> quote", "- item", "+ item", "12. item"]
  for marker in markers {
    let unit = SourceSemanticUnit::Paragraph({
      runs: [{ text: marker, bold: false, italic: false, code: false, link: None }],
      images: [],
      heading: 0,
      list: None,
      nesting_level: 0,
      quote_depth: 0,
      code_block: false,
    })
    let markdown = serialize_source_semantic_unit(unit)
    assert_true(markdown.has_prefix("\\"))
    guard @pumd.render_markdown(markdown) is Ok(document) else {
      fail("escaped paragraph must render")
    }
    match document.content[0] {
      @pumd.StructuralElement::Paragraph(paragraph) =>
        assert_eq(paragraph.style.named_style, @pumd.NamedStyle::NormalText)
      _ => fail("escaped plain text must stay a paragraph")
    }
  }
}

///|
test "pull conflicts instead of erasing Markdown-only metadata or fenced code" {
  let metadata_source = "[label](https://example.test \"title\")\n"
  let metadata = pull_rendered(metadata_source)
  match plan_pull(
    metadata_source,
    metadata,
    metadata,
    { units: [RemoteUnit::Paragraph(pull_remote_paragraph("changed", 1))] },
  ) {
    Ok(plan) => {
      assert_eq(plan.conflicted, 1)
      inspect(plan.source, content=metadata_source)
    }
    Err(error) => abort(error.user_message())
  }
  let code_source = "```js\nconst a = 1\nconst b = 2\n```\n"
  let code = pull_rendered(code_source)
  let remote = remote_from_document(code)
  match remote.units[0] {
    RemoteUnit::Paragraph(paragraph) =>
      remote.units[0] = RemoteUnit::Paragraph(changed_remote_paragraph(paragraph, "changed"))
    _ => fail("code fixture")
  }
  match plan_pull(code_source, code, code, remote) {
    Ok(plan) => {
      assert_true(plan.conflicted > 0)
      inspect(plan.source, content=code_source)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull merges local structural changes with disjoint remote edits" {
  let baseline = pull_rendered("A\n\nB\n")
  let inserted_source = "A\n\nLocal\n\nB\n"
  match plan_pull(
    inserted_source,
    baseline,
    pull_rendered(inserted_source),
    pull_two_paragraphs("A", "Remote B"),
  ) {
    Ok(plan) => {
      inspect(plan.source, content="A\n\nLocal\n\nRemote B\n")
      assert_eq(plan.preserved_local, 1)
      assert_eq(plan.incoming, 1)
      assert_eq(plan.conflicted, 0)
    }
    Err(error) => abort(error.user_message())
  }
  let deleted_source = "A\n"
  match plan_pull(
    deleted_source,
    baseline,
    pull_rendered(deleted_source),
    pull_two_paragraphs("Remote A", "B"),
  ) {
    Ok(plan) => {
      inspect(plan.source, content="Remote A\n")
      assert_eq(plan.preserved_local, 1)
      assert_eq(plan.incoming, 1)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull merges remote structural changes with disjoint local edits" {
  let baseline = pull_rendered("A\n\nB\n")
  let local_source = "Local A\n\nB\n"
  let remote_inserted : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(pull_remote_paragraph("A", 1)),
      RemoteUnit::Paragraph(pull_remote_paragraph("X", 3)),
      RemoteUnit::Paragraph(pull_remote_paragraph("B", 5)),
    ],
  }
  match plan_pull(local_source, baseline, pull_rendered(local_source), remote_inserted) {
    Ok(plan) => {
      inspect(plan.source, content="Local A\n\nX\n\nB\n")
      assert_eq(plan.preserved_local, 1)
      assert_eq(plan.incoming, 1)
      assert_eq(plan.conflicted, 0)
    }
    Err(error) => abort(error.user_message())
  }
  let remote_deleted : RemoteContent = {
    units: [RemoteUnit::Paragraph(pull_remote_paragraph("A", 1))],
  }
  match plan_pull(local_source, baseline, pull_rendered(local_source), remote_deleted) {
    Ok(plan) => {
      inspect(plan.source, content="Local A\n\n")
      assert_eq(plan.preserved_local, 1)
      assert_eq(plan.incoming, 1)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull merges disjoint local and remote structural insertions" {
  let baseline = pull_rendered("A\n\nB\n\nC\n")
  let source = "A\n\nLocal\n\nB\n\nC\n"
  let remote : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(pull_remote_paragraph("A", 1)),
      RemoteUnit::Paragraph(pull_remote_paragraph("B", 3)),
      RemoteUnit::Paragraph(pull_remote_paragraph("Remote", 5)),
      RemoteUnit::Paragraph(pull_remote_paragraph("C", 12)),
    ],
  }
  match plan_pull(source, baseline, pull_rendered(source), remote) {
    Ok(plan) => {
      inspect(plan.source, content="A\n\nLocal\n\nB\n\nRemote\n\nC\n")
      assert_eq(plan.preserved_local, 1)
      assert_eq(plan.incoming, 1)
      assert_eq(plan.conflicted, 0)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull merges disjoint local deletion and remote insertion" {
  let baseline = pull_rendered("A\n\nB\n\nC\n")
  let source = "B\n\nC\n"
  let remote : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(pull_remote_paragraph("A", 1)),
      RemoteUnit::Paragraph(pull_remote_paragraph("B", 3)),
      RemoteUnit::Paragraph(pull_remote_paragraph("Remote", 5)),
      RemoteUnit::Paragraph(pull_remote_paragraph("C", 12)),
    ],
  }
  match plan_pull(source, baseline, pull_rendered(source), remote) {
    Ok(plan) => {
      inspect(plan.source, content="B\n\nRemote\n\nC\n")
      assert_eq(plan.preserved_local, 1)
      assert_eq(plan.incoming, 1)
      assert_eq(plan.conflicted, 0)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull conflicts on overlapping local and remote structural edits" {
  let baseline = pull_rendered("A\n\nB\n")
  let source = "A\n\nLocal\n\nB\n"
  let remote : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(pull_remote_paragraph("A", 1)),
      RemoteUnit::Paragraph(pull_remote_paragraph("Remote", 3)),
      RemoteUnit::Paragraph(pull_remote_paragraph("B", 10)),
    ],
  }
  match plan_pull(source, baseline, pull_rendered(source), remote) {
    Ok(plan) => {
      inspect(plan.source, content=source)
      assert_true(plan.conflicted > 0)
      assert_true(plan.baseline.semantic_eq(baseline))
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull converges identical replacements beside disjoint structural edits" {
  let baseline = pull_rendered("A\n\nB\n\nC\n\nD\n")
  let source = "A\n\nLocal\n\nB\n\nC\n\nSame\n"
  let remote : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(pull_remote_paragraph("A", 1)),
      RemoteUnit::Paragraph(pull_remote_paragraph("B", 3)),
      RemoteUnit::Paragraph(pull_remote_paragraph("Remote", 5)),
      RemoteUnit::Paragraph(pull_remote_paragraph("C", 12)),
      RemoteUnit::Paragraph(pull_remote_paragraph("Same", 14)),
    ],
  }
  match plan_pull(source, baseline, pull_rendered(source), remote) {
    Ok(plan) => {
      inspect(
        plan.source,
        content="A\n\nLocal\n\nB\n\nRemote\n\nC\n\nSame\n",
      )
      assert_eq(plan.converged, 1)
      assert_eq(plan.preserved_local, 1)
      assert_eq(plan.incoming, 1)
      assert_eq(plan.conflicted, 0)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull converges identical insertions beside disjoint structural edits" {
  let baseline = pull_rendered("A\n\nB\n\nC\n")
  let source = "A\n\nSame\n\nB\n\nC\n\nLocal\n"
  let remote : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(pull_remote_paragraph("A", 1)),
      RemoteUnit::Paragraph(pull_remote_paragraph("Same", 3)),
      RemoteUnit::Paragraph(pull_remote_paragraph("B", 8)),
      RemoteUnit::Paragraph(pull_remote_paragraph("Remote", 10)),
      RemoteUnit::Paragraph(pull_remote_paragraph("C", 17)),
    ],
  }
  match plan_pull(source, baseline, pull_rendered(source), remote) {
    Ok(plan) => {
      inspect(plan.source, content="A\n\nSame\n\nB\n\nRemote\n\nC\n\nLocal\n")
      assert_eq(plan.converged, 1)
      assert_eq(plan.preserved_local, 1)
      assert_eq(plan.incoming, 1)
      assert_eq(plan.conflicted, 0)
    }
    Err(error) => abort(error.user_message())
  }
}

///|
test "pull converges identical deletions beside disjoint structural edits" {
  let baseline = pull_rendered("A\n\nB\n\nC\n\nD\n")
  let source = "A\n\nC\n\nLocal 1\n\nLocal 2\n\nD\n"
  let remote : RemoteContent = {
    units: [
      RemoteUnit::Paragraph(pull_remote_paragraph("A", 1)),
      RemoteUnit::Paragraph(pull_remote_paragraph("C", 3)),
      RemoteUnit::Paragraph(pull_remote_paragraph("D", 5)),
      RemoteUnit::Paragraph(pull_remote_paragraph("Remote 1", 7)),
      RemoteUnit::Paragraph(pull_remote_paragraph("Remote 2", 16)),
    ],
  }
  match plan_pull(source, baseline, pull_rendered(source), remote) {
    Ok(plan) => {
      inspect(
        plan.source,
        content="A\n\nC\n\nLocal 1\n\nLocal 2\n\nD\n\nRemote 1\n\nRemote 2\n",
      )
      assert_eq(plan.converged, 1)
      assert_eq(plan.preserved_local, 2)
      assert_eq(plan.incoming, 2)
      assert_eq(plan.conflicted, 0)
    }
    Err(error) => abort(error.user_message())
  }
}
