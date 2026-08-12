///|
fn rendered(markdown : String) -> @pumd.DesiredDocument {
  match @pumd.render_markdown(markdown) {
    Ok(document) => document
    Err(_) => abort("fixture must render")
  }
}

///|
/// Models the pre-syntax-highlighting baseline for an otherwise identical
/// fenced-code rendering.  Version-two code blocks retained all code styling
/// except per-token foreground colors.
fn version_two_code_baseline(current : @pumd.DesiredDocument) -> @pumd.DesiredDocument {
  let content : Array[@pumd.StructuralElement] = []
  for element in current.content {
    match element {
      @pumd.StructuralElement::Paragraph(paragraph) => {
        let runs : Array[@pumd.TextRun] = []
        if !paragraph.runs.is_empty() {
          let content = StringBuilder::new()
          for run in paragraph.runs { content.write_string(run.content) }
          let first = paragraph.runs[0]
          runs.push({ ..first, content: content.to_string(), style: { ..first.style, foreground_color: None } })
        }
        content.push(@pumd.StructuralElement::Paragraph({ ..paragraph, runs }))
      }
      @pumd.StructuralElement::Table(_) => content.push(element)
    }
  }
  {
    ..current,
    render_metadata: {
      ..current.render_metadata,
      style_profile_version: 2,
    },
    content,
  }
}

///|
fn remote_bullet(bullet : @pumd.BulletProperties?) -> RemoteBullet? {
  match bullet {
    Some(properties) => match properties.kind {
      @pumd.ListKind::Bullet => Some({ nesting_level: properties.nesting_level, numeric: false, glyph: "•" })
      @pumd.ListKind::Numbered(..) => Some({ nesting_level: properties.nesting_level, numeric: true, glyph: "1." })
    }
    None => None
  }
}

///|
fn remote_paragraph_from_desired(paragraph : @pumd.Paragraph, start : Int) -> RemoteParagraph {
  let runs : Array[RemoteRun] = []
  let mut cursor = start
  for run in paragraph.runs {
    let end_index = advance_google_docs_index(index=cursor, text=run.content)
    runs.push({ start_index: cursor, end_index, text: run.content, style: run.style, link: match run.link { Some(link) => Some(link.url); None => None } })
    cursor = end_index
  }
  { start_index: start, end_index: advance_google_docs_index(index=cursor, text="\n") + paragraph.inline_images.length(), runs, inline_images: paragraph.inline_images.map(fn(image) { { start_index: start + image.text_offset, end_index: start + image.text_offset + 1, source_url: image.source_url, text_offset: image.text_offset } }), style: paragraph.style, bullet: remote_bullet(paragraph.bullet), suggestions: [], normalization_warning: false }
}

///|
fn remote_from_document(document : @pumd.DesiredDocument) -> RemoteContent {
  let units : Array[RemoteUnit] = []
  let mut cursor = 1
  for element in document.content {
    match element {
      @pumd.StructuralElement::Paragraph(paragraph) => {
        let remote_paragraph = remote_paragraph_from_desired(paragraph, cursor)
        cursor = remote_paragraph.end_index
        units.push(RemoteUnit::Paragraph(remote_paragraph))
      }
      @pumd.StructuralElement::Table(table) => {
        let mut columns = 0
        for row in table.rows { if row.cells.length() > columns { columns = row.cells.length() } }
        let table_start = cursor
        let rows : Array[RemoteTableRow] = []
        let mut cell_cursor = cursor + 4
        for row in table.rows {
          let cells : Array[RemoteTableCell] = []
          for cell in row.cells {
            let paragraphs : Array[RemoteParagraph] = []
            let cell_start = cell_cursor
            for paragraph in cell.content {
              let remote_paragraph = remote_paragraph_from_desired(paragraph, cell_cursor)
              cell_cursor = remote_paragraph.end_index
              paragraphs.push(remote_paragraph)
            }
            cell_cursor = cell_cursor + 2
            cells.push({ start_index: cell_start, end_index: cell_cursor, paragraphs, opaque_units: [], suggestions: [], alignment: cell.alignment, background_color: cell.background_color, normalization_warning: false })
          }
          cell_cursor = cell_cursor + 1
          rows.push({ cells, })
        }
        // The precise cell offsets are relevant to adapter lowering, while the
        // enclosing element's end additionally includes inserted cell text.
        let mut text_width = 0
        for row in table.rows { for cell in row.cells { for paragraph in cell.content { for run in paragraph.runs { text_width = text_width + advance_google_docs_index(index=0, text=run.content) } } } }
        cursor = cursor + table.rows.length() * (columns * 2 + 1) + 3 + text_width
        units.push(RemoteUnit::Table({ start_index: table_start, end_index: cursor, rows, suggestions: [], normalization_warning: false }))
      }
    }
  }
  { units, }
}

///|
/// Google Docs always exposes one implicit final newline container beyond the
/// authored paragraphs. Keep this realism local to style-migration fixtures:
/// fenced code intentionally has an authored empty trailing code paragraph.
fn remote_from_style_migration_baseline(document : @pumd.DesiredDocument) -> RemoteContent {
  let remote = remote_from_document(document)
  let start_index = match remote.units[remote.units.length() - 1] {
    RemoteUnit::Paragraph(paragraph) => paragraph.end_index
    RemoteUnit::Table(table) => table.end_index
    RemoteUnit::Opaque(item) => item.end_index
  }
  remote.units.push(RemoteUnit::Paragraph({
    start_index,
    end_index: start_index + 1,
    runs: [],
    inline_images: [],
    style: @pumd.builtin_style_profile().body,
    bullet: None,
    suggestions: [],
    normalization_warning: false,
  }))
  remote
}

test "unchanged HTTPS image reconciles without a remote edit" {
  let document = rendered("Before ![diagram](https://example.test/diagram.png) after")
  match reconcile_document(document, document, remote_from_document(document)) { Ok(NoLocalChanges(report)) => { assert_eq(report.local_changes, 0); assert_eq(report.remote_changes, 0) }; _ => fail("unchanged image must reconcile as native content") }
}

test "changing an HTTPS image plans a native image replacement" {
  let baseline = rendered("![old](https://example.test/old.png)")
  let desired = rendered("![new](https://example.test/new.png)")
  match reconcile_document(baseline, desired, remote_from_document(baseline)) {
    Ok(Planned(report, plan)) => {
      assert_eq(report.local_changes, 1)
      let snapshot = plan.to_snapshot()
      assert_true(snapshot.contains("delete-content-range 1..2"))
      assert_true(snapshot.contains("insert-inline-image 1 source=\"https://example.test/new.png\""))
      assert_true(snapshot.contains("paragraph-style 1..2"))
    }
    _ => fail("changed image must produce a native replacement plan")
  }
}

///|
fn changed_remote_paragraph(paragraph : RemoteParagraph, text : String) -> RemoteParagraph {
  let original = paragraph.runs[0]
  let end_index = advance_google_docs_index(index=original.start_index, text=text)
  { ..paragraph, end_index: advance_google_docs_index(index=end_index, text="\n"), runs: [{ ..original, end_index, text }] }
}

///|
fn outcome(baseline : @pumd.DesiredDocument, desired : @pumd.DesiredDocument, remote : RemoteContent) -> ReconcileOutcome {
  match reconcile_document(baseline, desired, remote) {
    Ok(value) => value
    Err(error) => abort(error.user_message())
  }
}

///|
async test "no-op has no changes" {
  let document = rendered("A\n\nB")
  match outcome(document, document, remote_from_document(document)) {
    NoLocalChanges(report) => { assert_eq(report.local_changes, 0); assert_eq(report.remote_changes, 0) }
    _ => fail("no-op must not plan")
  }
}

///|
async test "remote-only text edit does not publish" {
  let document = rendered("A\n\nB")
  let remote = remote_from_document(document)
  match remote.units[1] { RemoteUnit::Paragraph(paragraph) => remote.units[1] = RemoteUnit::Paragraph(changed_remote_paragraph(paragraph, "remote")); _ => fail("paragraph fixture") }
  match outcome(document, document, remote) { NoLocalChanges(report) => assert_true(report.remote_changes > 0); _ => fail("remote-only edits must not write") }
}

///|
async test "suggestions are remote changes but do not publish alone" {
  let document = rendered("A")
  let remote = remote_from_document(document)
  match remote.units[0] { RemoteUnit::Paragraph(paragraph) => remote.units[0] = RemoteUnit::Paragraph({ ..paragraph, suggestions: [InsertedText(start_index=1, end_index=2, text="x", suggestion_id="s")] }); _ => fail("paragraph fixture") }
  match outcome(document, document, remote) { NoLocalChanges(report) => assert_eq(report.remote_changes, 1); _ => fail("suggestion must not publish") }
}

///|
async test "local text replacement deletes then inserts one paragraph" {
  let baseline = rendered("Old\n\nKeep")
  let desired = rendered("New\n\nKeep")
  match outcome(baseline, desired, remote_from_document(baseline)) {
    Planned(_, plan) => { let snapshot = plan.to_snapshot(); assert_true(snapshot.contains("delete-content-range 1..4")); assert_true(snapshot.contains("insert-text 1 \"New\"")) }
    _ => fail("local edit must plan")
  }
}

///|
async test "local style replacement plans text style" {
  let baseline = rendered("Hello")
  let desired = rendered("**Hello**")
  match outcome(baseline, desired, remote_from_document(baseline)) { Planned(_, plan) => assert_true(plan.to_snapshot().contains("text-style 1..6 bold")); _ => fail("style edit must plan") }
}

///|
async test "v2 plain code baseline reconciles to v3 token foreground styles" {
  let desired = rendered("```javascript\nconst answer = \"yes\"\n```")
  let baseline = version_two_code_baseline(desired)
  match outcome(baseline, desired, remote_from_style_migration_baseline(baseline)) {
    Planned(report, plan) => {
      assert_eq(report.local_changes, 1)
      assert_eq(report.remote_changes, 0)
      let snapshot = plan.to_snapshot()
      assert_true(snapshot.contains("text-foreground-color"))
      assert_true(!snapshot.contains("text-style"))
      assert_true(snapshot.contains("color=#"))
    }
    _ => fail("style migration must plan native text-style updates")
  }
}

///|
async test "color casing alone is not a remote change" {
  let baseline = rendered("A")
  match baseline.content[0] {
    @pumd.StructuralElement::Paragraph(paragraph) => {
      let run = paragraph.runs[0]
      baseline.content[0] = @pumd.StructuralElement::Paragraph({
        ..paragraph,
        runs: [{
          ..run,
          style: {
            ..run.style,
            foreground_color: Some("#AABBCC"),
            background_color: Some("#DDEEFF"),
          },
        }],
      })
    }
    _ => fail("paragraph fixture")
  }
  let remote = remote_from_document(baseline)
  match remote.units[0] {
    RemoteUnit::Paragraph(paragraph) => {
      let run = paragraph.runs[0]
      remote.units[0] = RemoteUnit::Paragraph({
        ..paragraph,
        runs: [{
          ..run,
          style: {
            ..run.style,
            foreground_color: Some("#aabbcc"),
            background_color: Some("#ddeeff"),
          },
        }],
      })
    }
    _ => fail("paragraph fixture")
  }
  match outcome(baseline, baseline, remote) {
    NoLocalChanges(report) => assert_eq(report.remote_changes, 0)
    _ => fail("case-only colors must not count as a remote edit")
  }
}

///|
async test "different colors remain remote changes" {
  let baseline = rendered("A")
  match baseline.content[0] {
    @pumd.StructuralElement::Paragraph(paragraph) => {
      let run = paragraph.runs[0]
      baseline.content[0] = @pumd.StructuralElement::Paragraph({
        ..paragraph,
        runs: [{ ..run, style: { ..run.style, foreground_color: Some("#AABBCC") } }],
      })
    }
    _ => fail("paragraph fixture")
  }
  let remote = remote_from_document(baseline)
  match remote.units[0] {
    RemoteUnit::Paragraph(paragraph) => {
      let run = paragraph.runs[0]
      remote.units[0] = RemoteUnit::Paragraph({
        ..paragraph,
        runs: [{ ..run, style: { ..run.style, foreground_color: Some("#aabbcd") } }],
      })
    }
    _ => fail("paragraph fixture")
  }
  match outcome(baseline, baseline, remote) {
    NoLocalChanges(report) => assert_eq(report.remote_changes, 1)
    _ => fail("different colors must count as a remote edit")
  }
}

///|
async test "middle insertion uses following paragraph boundary" {
  let baseline = rendered("A\n\nC")
  let desired = rendered("A\n\nB\n\nC")
  match outcome(baseline, desired, remote_from_document(baseline)) { Planned(_, plan) => { let snapshot = plan.to_snapshot(); assert_true(snapshot.contains("insert-text 3 \"B\\n\"")); assert_true(!snapshot.contains("delete-content-range")) }; _ => fail("insertion must plan") }
}

///|
async test "end insertion appends after the final newline" {
  let baseline = rendered("A")
  let desired = rendered("A\n\nB")
  match outcome(baseline, desired, remote_from_document(baseline)) { Planned(_, plan) => assert_true(plan.to_snapshot().contains("insert-text 3 \"B\\n\"")); _ => fail("end insertion must plan") }
}

///|
async test "beginning insertion uses body start" {
  let baseline = rendered("B")
  let desired = rendered("A\n\nB")
  match outcome(baseline, desired, remote_from_document(baseline)) { Planned(_, plan) => assert_true(plan.to_snapshot().contains("insert-text 1 \"A\\n\"")); _ => fail("beginning insertion must plan") }
}

///|
async test "middle deletion removes the full paragraph range" {
  let baseline = rendered("A\n\nB\n\nC")
  let desired = rendered("A\n\nC")
  match outcome(baseline, desired, remote_from_document(baseline)) { Planned(_, plan) => { let snapshot = plan.to_snapshot(); assert_true(snapshot.contains("delete-content-range 3..5")); assert_true(!snapshot.contains("insert-text 3 \"\\n\"")) }; _ => fail("deletion must plan") }
}

///|
async test "last paragraph deletion preserves final newline" {
  let baseline = rendered("A\n\nB")
  let desired = rendered("A")
  match outcome(baseline, desired, remote_from_document(baseline)) { Planned(_, plan) => assert_true(plan.to_snapshot().contains("delete-content-range 3..4")); _ => fail("last deletion must plan") }
}

///|
async test "local table replacement replays table creation" {
  let baseline = rendered("| A |\n| --- |\n| old |")
  let desired = rendered("| A |\n| --- |\n| new |")
  match outcome(baseline, desired, remote_from_document(baseline)) { Planned(_, plan) => { let snapshot = plan.to_snapshot(); assert_true(snapshot.contains("delete-content-range 1..")); assert_true(snapshot.contains("insert-table 1")); assert_true(snapshot.contains("insert-cell-text")) }; _ => fail("table edit must plan") }
}

///|
async test "local table deletion emits a table delete" {
  let baseline = rendered("| A |\n| --- |\n| B |")
  let desired = rendered("")
  match outcome(baseline, desired, remote_from_document(baseline)) { Planned(_, plan) => assert_true(plan.to_snapshot().contains("delete-content-range 1..")); _ => fail("table deletion must plan") }
}

///|
async test "local table insertion at the end appends after the final newline" {
  let baseline = rendered("A")
  let desired = rendered("A\n\n| H |\n| --- |\n| C |")
  match outcome(baseline, desired, remote_from_document(baseline)) { Planned(_, plan) => assert_true(plan.to_snapshot().contains("insert-table 3")); _ => fail("table insertion must plan") }
}

///|
async test "reordering paragraphs is planned without a whole-body delete" {
  let baseline = rendered("A\n\nB")
  let desired = rendered("B\n\nA")
  match outcome(baseline, desired, remote_from_document(baseline)) { Planned(_, plan) => assert_true(!plan.to_snapshot().contains("delete-content-range 1..5")); _ => fail("reorder must plan") }
}

///|
async test "same paragraph local and remote edits conflict" {
  let baseline = rendered("A")
  let desired = rendered("local")
  let remote = remote_from_document(baseline)
  match remote.units[0] { RemoteUnit::Paragraph(paragraph) => remote.units[0] = RemoteUnit::Paragraph(changed_remote_paragraph(paragraph, "remote")); _ => fail("paragraph fixture") }
  match outcome(baseline, desired, remote) { Conflict(report) => assert_eq(report.conflicts, 1); _ => fail("competing writes must conflict") }
}

///|
async test "local edit and suggestion conflict" {
  let baseline = rendered("A")
  let desired = rendered("B")
  let remote = remote_from_document(baseline)
  match remote.units[0] { RemoteUnit::Paragraph(paragraph) => remote.units[0] = RemoteUnit::Paragraph({ ..paragraph, suggestions: [StyleChange(start_index=1, end_index=2, suggestion_id="s")] }); _ => fail("paragraph fixture") }
  match outcome(baseline, desired, remote) { Conflict(_) => (); _ => fail("suggestion must conflict with local edit") }
}

///|
async test "disjoint local and remote changes plan only local range" {
  let baseline = rendered("A\n\nB")
  let desired = rendered("local\n\nB")
  let remote = remote_from_document(baseline)
  match remote.units[1] { RemoteUnit::Paragraph(paragraph) => remote.units[1] = RemoteUnit::Paragraph(changed_remote_paragraph(paragraph, "remote")); _ => fail("paragraph fixture") }
  match outcome(baseline, desired, remote) { Planned(_, plan) => { let snapshot = plan.to_snapshot(); assert_true(snapshot.contains("delete-content-range 1..2")); assert_true(!snapshot.contains("delete-content-range 3")) }; _ => fail("disjoint edit must plan") }
}

///|
async test "opaque remote unit is reported without local write" {
  let document = rendered("A")
  let remote = remote_from_document(document)
  remote.units.push(RemoteUnit::Opaque({ start_index: 2, end_index: 3, kind: "sectionBreak", description: None }))
  match outcome(document, document, remote) { NoLocalChanges(report) => assert_true(report.remote_changes > 0); _ => fail("opaque only must not write") }
}

///|
async test "normalization warning conflicts with a local paragraph edit" {
  let baseline = rendered("A")
  let desired = rendered("B")
  let remote = remote_from_document(baseline)
  match remote.units[0] { RemoteUnit::Paragraph(paragraph) => remote.units[0] = RemoteUnit::Paragraph({ ..paragraph, normalization_warning: true }); _ => fail("paragraph fixture") }
  match outcome(baseline, desired, remote) { Conflict(_) => (); _ => fail("normalization warning must fail closed") }
}

///|
async test "trailing final newline container is ignored" {
  let document = rendered("A\n\nB")
  let remote = remote_from_document(document)
  remote.units.push(RemoteUnit::Paragraph({ start_index: 5, end_index: 6, runs: [], inline_images: [], style: @pumd.builtin_style_profile().body, bullet: None, suggestions: [], normalization_warning: false }))
  match outcome(document, document, remote) { NoLocalChanges(report) => assert_eq(report.remote_changes, 0); _ => fail("final newline container must be ignored") }
}

///|
async test "trailing final newline container does not move local indexes" {
  let baseline = rendered("A")
  let desired = rendered("B")
  let remote = remote_from_document(baseline)
  remote.units.push(RemoteUnit::Paragraph({ start_index: 2, end_index: 3, runs: [], inline_images: [], style: @pumd.builtin_style_profile().body, bullet: None, suggestions: [], normalization_warning: false }))
  match outcome(baseline, desired, remote) { Planned(_, plan) => assert_true(plan.to_snapshot().contains("delete-content-range 1..2")); _ => fail("trailing container must not change local indexes") }
}

///|
async test "opaque beside an edited paragraph stays untouched" {
  let baseline = rendered("A")
  let desired = rendered("B")
  let remote = remote_from_document(baseline)
  remote.units.push(RemoteUnit::Opaque({ start_index: 2, end_index: 3, kind: "inlineObject", description: None }))
  match outcome(baseline, desired, remote) {
    Planned(_, plan) => {
      let snapshot = plan.to_snapshot()
      assert_true(snapshot.contains("delete-content-range 1..2"))
      assert_true(!snapshot.contains("delete-content-range 2.."))
    }
    _ => fail("a local edit beside an opaque unit must plan without touching it")
  }
}

///|
async test "reorder bracketing an opaque unit conflicts" {
  let baseline = rendered("A\n\nB")
  let desired = rendered("B\n\nA")
  let remote = remote_from_document(baseline)
  let a = match remote.units[0] { RemoteUnit::Paragraph(paragraph) => paragraph; _ => abort("paragraph fixture") }
  let b = match remote.units[1] { RemoteUnit::Paragraph(paragraph) => paragraph; _ => abort("paragraph fixture") }
  let units = [
    RemoteUnit::Paragraph(a),
    RemoteUnit::Opaque({ start_index: 3, end_index: 4, kind: "sectionBreak", description: None }),
    RemoteUnit::Paragraph(b),
  ]
  let remote_with_opaque : RemoteContent = { units, }
  match outcome(baseline, desired, remote_with_opaque) { Conflict(_) => (); _ => fail("a move across an opaque unit must conflict") }
}

///|
fn desired_body(document : @pumd.DesiredDocument) -> String {
  let output = StringBuilder::new()
  for element in document.content {
    match element {
      @pumd.StructuralElement::Paragraph(paragraph) => {
        for run in paragraph.runs { output.write_string(run.content) }
        output.write_char('\n')
      }
      _ => ()
    }
  }
  output.to_string()
}

///|
/// Applies a paragraph-only plan to a string model of the remote body and
/// returns the resulting body text, proving the compiled indexes and ordering
/// produce exactly the desired document.
fn simulate_paragraph_plan(remote : RemoteContent, plan : DocsUpdatePlan) -> String {
  let body = StringBuilder::new()
  body.write_char('\u0000')
  for unit in remote.units {
    match unit {
      RemoteUnit::Paragraph(paragraph) => {
        for run in paragraph.runs { body.write_string(run.text) }
        body.write_char('\n')
      }
      _ => ()
    }
  }
  let mut document_text = body.to_string()
  for request in plan.requests {
    match request {
      DeleteContentRange(start_index~, end_index~) => {
        let before = document_text.unsafe_substring(start=0, end=start_index)
        let after = document_text.unsafe_substring(start=end_index, end=document_text.length())
        document_text = before + after
      }
      InsertText(index~, text~) => {
        let before = document_text.unsafe_substring(start=0, end=index)
        let after = document_text.unsafe_substring(start=index, end=document_text.length())
        document_text = before + text + after
      }
      _ => ()
    }
  }
  let mut body = document_text.unsafe_substring(start=1, end=document_text.length())
  // The final newline container is semantically equivalent to the last
  // paragraph's own final newline; normalize it away like the reconciler does.
  while body.has_suffix("\n\n") {
    body = body.unsafe_substring(start=0, end=body.length() - 1)
  }
  body
}

///|
fn simulated_body_of(baseline : @pumd.DesiredDocument, desired : @pumd.DesiredDocument, remote : RemoteContent) -> String {
  match outcome(baseline, desired, remote) {
    Planned(_, plan) => simulate_paragraph_plan(remote, plan)
    _ => abort("expected a planned update")
  }
}

///|
async test "simulated reorder produces the desired body" {
  assert_eq(simulated_body_of(rendered("A\n\nB"), rendered("B\n\nA"), remote_from_document(rendered("A\n\nB"))), desired_body(rendered("B\n\nA")))
}

///|
async test "simulated three-way reorder produces the desired body" {
  assert_eq(simulated_body_of(rendered("A\n\nB\n\nC"), rendered("A\n\nC\n\nB"), remote_from_document(rendered("A\n\nB\n\nC"))), desired_body(rendered("A\n\nC\n\nB")))
}

///|
async test "simulated rotate produces the desired body" {
  assert_eq(simulated_body_of(rendered("A\n\nB\n\nC"), rendered("B\n\nC\n\nA"), remote_from_document(rendered("A\n\nB\n\nC"))), desired_body(rendered("B\n\nC\n\nA")))
}

///|
async test "simulated delete plus reorder produces the desired body" {
  assert_eq(simulated_body_of(rendered("A\n\nB\n\nC"), rendered("C\n\nA"), remote_from_document(rendered("A\n\nB\n\nC"))), desired_body(rendered("C\n\nA")))
}

///|
async test "simulated insert and replacement produce the desired body" {
  assert_eq(simulated_body_of(rendered("A\n\nB"), rendered("A\n\nX\n\nY"), remote_from_document(rendered("A\n\nB"))), desired_body(rendered("A\n\nX\n\nY")))
}

///|
async test "simulated adjacent deletions produce the desired body" {
  assert_eq(simulated_body_of(rendered("A\n\nB\n\nC\n\nD"), rendered("A\n\nD"), remote_from_document(rendered("A\n\nB\n\nC\n\nD"))), desired_body(rendered("A\n\nD")))
}

///|
async test "emoji replacement uses UTF-16 indexes" {
  let baseline = rendered("😀")
  let desired = rendered("🚀")
  match outcome(baseline, desired, remote_from_document(baseline)) { Planned(_, plan) => assert_true(plan.to_snapshot().contains("paragraph-style 1..3")); _ => fail("emoji plan must use UTF-16 width") }
}

///|
async test "unsupported numbered list start fails planning" {
  let baseline = rendered("A")
  let desired = rendered("3. three")
  match reconcile_document(baseline, desired, remote_from_document(baseline)) { Err(PlanningFailed(message)) => assert_true(message.contains("starting at 3")); _ => fail("unsupported list must not plan") }
}

///|
async test "empty desired table fails planning" {
  let baseline = rendered("A")
  let desired : @pumd.DesiredDocument = { ..baseline, content: [@pumd.StructuralElement::Table({ rows: [], provenance: None })] }
  match reconcile_document(baseline, desired, remote_from_document(baseline)) { Err(PlanningFailed(message)) => assert_true(message.contains("no rows")); _ => fail("empty table must not plan") }
}
