///|
/// The reconciliation layer deliberately compares semantic, publishable
/// content rather than renderer provenance.  Its alignment is a deterministic
/// LCS: when duplicate units make another LCS possible, this implementation
/// picks the earliest pair.  Writes adjacent to an opaque unit are rejected,
/// which makes that tie-break safe instead of guessing across unsupported Docs
/// structures.
pub(all) enum UnitKind { Paragraph; Table; Opaque } derive(Eq, @debug.Debug)

///|
pub(all) struct UnitReport {
  kind : UnitKind
  index : Int
  local_change : Bool
  remote_change : Bool
  conflict : Bool
  description : String
} derive(Eq, @debug.Debug)

///|
pub(all) struct ReconciliationReport {
  units : Array[UnitReport]
  local_changes : Int
  remote_changes : Int
  conflicts : Int
} derive(Eq, @debug.Debug)

///|
pub(all) enum ReconcileOutcome {
  NoLocalChanges(ReconciliationReport)
  Planned(ReconciliationReport, DocsUpdatePlan)
  Conflict(ReconciliationReport)
}

///|
pub(all) enum ReconcileError {
  InvalidRemoteStructure(String)
  AmbiguousAlignment(String)
  PlanningFailed(String)
} derive(Eq, @debug.Debug)

///|
pub fn ReconcileError::user_message(self : ReconcileError) -> String {
  match self {
    InvalidRemoteStructure(message) => "Google Docs has an unsupported structure: " + message
    AmbiguousAlignment(message) => "Google Docs content cannot be aligned safely: " + message
    PlanningFailed(message) => "Google Docs update planning failed: " + message
  }
}

///|
priv struct LocalUnit {
  kind : UnitKind
  signature : String
  paragraph : @pumd.Paragraph?
  table : @pumd.Table?
}

///|
priv struct RemoteEntry {
  kind : UnitKind
  signature : String
  start_index : Int
  end_index : Int
  changed : Bool
  description : String
}

///|
priv struct Match { left : Int; right : Int }

///|
fn optional_string(value : String?, output : StringBuilder) -> Unit {
  match value { Some(text) => output.write_string(text); None => output.write_string("-") }
}

///|
/// Google Docs normalizes decoded RGB hex to lowercase, while a Style Profile
/// may retain its authored casing. Reconciliation compares semantic colors,
/// so its signatures use one canonical key without changing stored styles.
fn canonical_color_key(color : String) -> String {
  color.to_lower()
}

///|
fn optional_color_key(value : String?, output : StringBuilder) -> Unit {
  match value {
    Some(color) => output.write_string(canonical_color_key(color))
    None => output.write_string("-")
  }
}

///|
fn text_signature(style : @pumd.TextStyle, link : String?, output : StringBuilder) -> Unit {
  output.write_string(style.font_family); output.write_char('|')
  output.write_string(style.font_size_points.to_string()); output.write_char('|')
  output.write_string(style.bold.to_string()); output.write_char('|')
  output.write_string(style.italic.to_string()); output.write_char('|')
  output.write_string(style.underline.to_string()); output.write_char('|')
  optional_color_key(style.foreground_color, output); output.write_char('|')
  optional_color_key(style.background_color, output); output.write_char('|')
  optional_string(link, output); output.write_char(';')
}

///|
fn paragraph_style_signature(style : @pumd.ParagraphStyle, output : StringBuilder) -> Unit {
  output.write_string(@debug.to_string(style.named_style)); output.write_char('|')
  output.write_string(style.line_spacing_percent.to_string()); output.write_char('|')
  output.write_string(style.space_above_points.to_string()); output.write_char('|')
  output.write_string(style.space_below_points.to_string()); output.write_char('|')
  optional_color_key(style.background_color, output); output.write_char('|')
  match style.indent_start_points { Some(value) => output.write_string(value.to_string()); None => output.write_char('-') }; output.write_char('|')
  match style.indent_first_line_points { Some(value) => output.write_string(value.to_string()); None => output.write_char('-') }; output.write_char('|')
  match style.border_left {
    Some(border) => { output.write_string(canonical_color_key(border.color)); output.write_char('|'); output.write_string(border.width_points.to_string()); output.write_char('|'); output.write_string(border.padding_points.to_string()) }
    None => output.write_char('-')
  }
}

///|
fn desired_paragraph_signature(paragraph : @pumd.Paragraph) -> String {
  let output = StringBuilder::new()
  output.write_string("p:")
  for run in paragraph.runs { output.write_string(run.content); output.write_char('|'); text_signature(run.style, match run.link { Some(link) => Some(link.url); None => None }, output) }
  output.write_char('#'); paragraph_style_signature(paragraph.style, output); output.write_char('#')
  match paragraph.bullet {
    Some(bullet) => { match bullet.kind { @pumd.ListKind::Bullet => output.write_char('b'); @pumd.ListKind::Numbered(..) => output.write_char('n') }; output.write_string(bullet.nesting_level.to_string()) }
    None => output.write_char('-')
  }
  output.to_string()
}

///|
fn remote_paragraph_signature(paragraph : RemoteParagraph) -> String {
  let output = StringBuilder::new()
  output.write_string("p:")
  for run in paragraph.runs { output.write_string(run.text); output.write_char('|'); text_signature(run.style, run.link, output) }
  output.write_char('#'); paragraph_style_signature(paragraph.style, output); output.write_char('#')
  match paragraph.bullet { Some(bullet) => { if bullet.numeric { output.write_char('n') } else { output.write_char('b') }; output.write_string(bullet.nesting_level.to_string()) }; None => output.write_char('-') }
  output.to_string()
}

///|
fn cell_alignment_key(alignment : @pumd.TableAlignment) -> String {
  // The create-side lowering writes START for both Left and Unspecified, so
  // the remote read normalizes them to the same key.
  match alignment {
    @pumd.TableAlignment::Left | @pumd.TableAlignment::Unspecified => "start"
    @pumd.TableAlignment::Center => "center"
    @pumd.TableAlignment::Right => "end"
  }
}

///|
fn desired_table_signature(table : @pumd.Table) -> String {
  let output = StringBuilder::new(); output.write_string("t:")
  for row in table.rows {
    output.write_string("r:")
    for cell in row.cells {
      output.write_char('{')
      output.write_string(cell_alignment_key(cell.alignment))
      output.write_char('|')
      match cell.background_color {
        Some(color) => output.write_string(canonical_color_key(color))
        None => output.write_char('-')
      }
      output.write_char('|')
      for paragraph in cell.content { output.write_string(desired_paragraph_signature(paragraph)); output.write_char(',') }
      output.write_char('}')
    }
  }
  output.to_string()
}

///|
fn remote_table_signature(table : RemoteTable) -> String {
  let output = StringBuilder::new(); output.write_string("t:")
  for row in table.rows {
    output.write_string("r:")
    for cell in row.cells {
      output.write_char('{')
      output.write_string(cell_alignment_key(cell.alignment))
      output.write_char('|')
      match cell.background_color {
        Some(color) => output.write_string(canonical_color_key(color))
        None => output.write_char('-')
      }
      output.write_char('|')
      for paragraph in cell.paragraphs { output.write_string(remote_paragraph_signature(paragraph)); output.write_char(',') }
      output.write_char('}')
    }
  }
  output.to_string()
}

///|
fn local_units(document : @pumd.DesiredDocument) -> Array[LocalUnit] {
  let units : Array[LocalUnit] = []
  for element in document.content {
    match element {
      @pumd.StructuralElement::Paragraph(paragraph) => units.push({ kind: Paragraph, signature: desired_paragraph_signature(paragraph), paragraph: Some(paragraph), table: None })
      @pumd.StructuralElement::Table(table) => units.push({ kind: Table, signature: desired_table_signature(table), paragraph: None, table: Some(table) })
    }
  }
  units
}

///|
fn remote_has_warning(table : RemoteTable) -> Bool {
  if table.normalization_warning || !table.suggestions.is_empty() { return true }
  for row in table.rows { for cell in row.cells { if cell.normalization_warning || !cell.suggestions.is_empty() || !cell.opaque_units.is_empty() { return true }; for paragraph in cell.paragraphs { if paragraph.normalization_warning || !paragraph.suggestions.is_empty() { return true } } } }
  false
}

///|
fn is_final_newline_container(unit : RemoteUnit, is_last : Bool) -> Bool {
  match unit {
    Paragraph(paragraph) => is_last && paragraph.runs.is_empty() && paragraph.end_index == paragraph.start_index + 1
    _ => false
  }
}

///|
fn remote_entries(content : RemoteContent) -> Array[RemoteEntry] {
  let entries : Array[RemoteEntry] = []
  for index, unit in content.units {
    if !is_final_newline_container(unit, index == content.units.length() - 1) {
      match unit {
        Paragraph(paragraph) => entries.push({ kind: Paragraph, signature: remote_paragraph_signature(paragraph), start_index: paragraph.start_index, end_index: paragraph.end_index, changed: paragraph.normalization_warning || !paragraph.suggestions.is_empty(), description: "paragraph " + (entries.length() + 1).to_string() })
        Table(table) => entries.push({ kind: Table, signature: remote_table_signature(table), start_index: table.start_index, end_index: table.end_index, changed: remote_has_warning(table), description: "table " + (entries.length() + 1).to_string() })
        Opaque(item) => entries.push({ kind: Opaque, signature: "", start_index: item.start_index, end_index: item.end_index, changed: true, description: "unsupported structure (" + item.kind + ")" })
      }
    }
  }
  entries
}

///|
fn lcs(left : Array[LocalUnit], right : Array[RemoteEntry]) -> Array[Match] {
  let rows = left.length() + 1
  let columns = right.length() + 1
  let table : Array[Array[Int]] = []
  for row_index = 0; row_index < rows; row_index = row_index + 1 {
    let row : Array[Int] = []
    for column_index = 0; column_index < columns; column_index = column_index + 1 { row.push(0) }
    table.push(row)
  }
  for i = 1; i < rows; i = i + 1 {
    for j = 1; j < columns; j = j + 1 {
      if left[i - 1].kind == right[j - 1].kind && left[i - 1].signature == right[j - 1].signature {
        table[i][j] = table[i - 1][j - 1] + 1
      } else if table[i - 1][j] >= table[i][j - 1] {
        table[i][j] = table[i - 1][j]
      } else { table[i][j] = table[i][j - 1] }
    }
  }
  let result : Array[Match] = []
  let mut i = left.length()
  let mut j = right.length()
  while i > 0 && j > 0 {
    if left[i - 1].kind == right[j - 1].kind && left[i - 1].signature == right[j - 1].signature {
      result.push({ left: i - 1, right: j - 1 }); i = i - 1; j = j - 1
    } else if table[i - 1][j] >= table[i][j - 1] { i = i - 1 } else { j = j - 1 }
  }
  let ordered : Array[Match] = []
  let mut k = result.length()
  while k > 0 { k = k - 1; ordered.push(result[k]) }
  ordered
}

///|
fn local_lcs(left : Array[LocalUnit], right : Array[LocalUnit]) -> Array[Match] {
  let remote : Array[RemoteEntry] = []
  for item in right { remote.push({ kind: item.kind, signature: item.signature, start_index: 0, end_index: 0, changed: false, description: "" }) }
  lcs(left, remote)
}

///|
fn unit_description(kind : UnitKind, ordinal : Int) -> String { match kind { Paragraph => "paragraph " + ordinal.to_string(); Table => "table " + ordinal.to_string(); Opaque => "unsupported structure" } }

///|
fn validate_desired(document : @pumd.DesiredDocument) -> Result[Unit, ReconcileError] {
  match prepare_docs_update_plan(document) { Ok(_) => Ok(()); Err(error) => Err(PlanningFailed(error.message())) }
}

///|
fn indent_tabs(level : Int) -> String { if level <= 0 { "" } else { "\t" + indent_tabs(level - 1) } }
///|
fn has_decoration(style : @pumd.ParagraphStyle) -> Bool { style.indent_start_points is Some(_) || style.indent_first_line_points is Some(_) || style.border_left is Some(_) }

///|
fn append_paragraph_write(paragraph : @pumd.Paragraph, cursor : Int, include_newline : Bool, requests : Array[DocsUpdateRequest]) -> Unit {
  let indent = match paragraph.bullet { Some(bullet) => indent_tabs(bullet.nesting_level); None => "" }
  let contents = StringBuilder::new(); contents.write_string(indent); for run in paragraph.runs { contents.write_string(run.content) }
  let text = contents.to_string(); let inserted = if include_newline { text + "\n" } else { text }
  requests.push(InsertText(index=cursor, text=inserted))
  let style_end = advance_google_docs_index(index=cursor, text=text)
  requests.push(UpdateParagraphStyle(start_index=cursor, end_index=style_end, style=paragraph.style))
  let mut run_start = advance_google_docs_index(index=cursor, text=indent)
  for run in paragraph.runs { let run_end = advance_google_docs_index(index=run_start, text=run.content); if run_start != run_end { requests.push(UpdateTextStyle(start_index=run_start, end_index=run_end, style=run.style, link=run.link)) }; run_start = run_end }
  match paragraph.bullet { Some(bullet) => { requests.push(CreateParagraphBullets(start_index=cursor, end_index=style_end, bullet~)); if has_decoration(paragraph.style) { requests.push(UpdateParagraphDecoration(start_index=cursor, end_index=style_end, style=paragraph.style)) } }; None => () }
}

///|
fn append_table_write(table : @pumd.Table, cursor : Int, requests : Array[DocsUpdateRequest]) -> Unit {
  let mut columns = 0; for row in table.rows { if row.cells.length() > columns { columns = row.cells.length() } }
  requests.push(InsertTable(index=cursor, rows=table.rows.length(), columns~))
  for row_index, row in table.rows { for column_index, cell in row.cells {
    let content = StringBuilder::new(); for paragraph_index, paragraph in cell.content { if paragraph_index > 0 { content.write_char('\n') }; for run in paragraph.runs { content.write_string(run.content) } }
    requests.push(InsertTableCellText(table_index=cursor, row=row_index, column=column_index, text=content.to_string()))
    let mut paragraph_start = 0
    for paragraph in cell.content { let mut paragraph_end = paragraph_start + 1; for run in paragraph.runs { paragraph_end = advance_google_docs_index(index=paragraph_end, text=run.content) }; requests.push(UpdateTableCellParagraphStyle(table_index=cursor, row=row_index, column=column_index, start_offset=paragraph_start, end_offset=paragraph_end, style=paragraph.style)); let mut run_start = paragraph_start; for run in paragraph.runs { let run_end = advance_google_docs_index(index=run_start, text=run.content); if run_start != run_end { requests.push(UpdateTableCellTextStyle(table_index=cursor, row=row_index, column=column_index, start_offset=run_start, end_offset=run_end, style=run.style, link=run.link)) }; run_start = run_end }; paragraph_start = paragraph_end }
    requests.push(UpdateTableCellStyle(table_index=cursor, row=row_index, column=column_index, alignment=cell.alignment, background_color=cell.background_color))
  } }
}

///|
///| An update op group: the document index its requests are relative to,
///| whether the group is a deletion, and the creation order used to break
///| ties at equal anchors deterministically.
priv struct OpGroup {
  anchor : Int
  deletes : Bool
  order : Int
  requests : Array[DocsUpdateRequest]
}

///|
fn remote_has_trailing_container(content : RemoteContent) -> Bool {
  let units = content.units
  if units.is_empty() {
    false
  } else {
    is_final_newline_container(units[units.length() - 1], true)
  }
}

///|
fn is_last_real(entry_index : Int, remote : Array[RemoteEntry], has_trailing_container : Bool) -> Bool {
  entry_index == remote.length() - 1 && !has_trailing_container
}

///|
/// The document index at which an inserted desired unit lands. Anchors to the
/// next anchored remote unit (matched, or an in-place replacement) when one
/// follows, otherwise to the previous anchored unit's end, otherwise the
/// document start. Replacements occupy the full range of the unit they
/// replace, so a following insertion lands after that range.
fn insertion_boundary(desired_index : Int, desired_to_baseline : Array[Int?], base_to_desired : Array[Int?], baseline_to_remote : Array[Int?], remote : Array[RemoteEntry]) -> Int {
  for index = desired_index + 1; index < desired_to_baseline.length(); index = index + 1 {
    match desired_to_baseline[index] {
      Some(baseline_index) =>
        match baseline_to_remote[baseline_index] {
          Some(remote_index) => return remote[remote_index].start_index
          None => ()
        }
      None =>
        if index < base_to_desired.length() && base_to_desired[index] is None {
          match baseline_to_remote[index] {
            Some(remote_index) => return remote[remote_index].start_index
            None => ()
          }
        }
    }
  }
  for index = desired_index - 1; index >= 0; index = index - 1 {
    match desired_to_baseline[index] {
      Some(baseline_index) =>
        match baseline_to_remote[baseline_index] {
          Some(remote_index) => return remote[remote_index].end_index
          None => ()
        }
      None =>
        if index < base_to_desired.length() && base_to_desired[index] is None {
          match baseline_to_remote[index] {
            Some(remote_index) => return remote[remote_index].end_index
            None => ()
          }
        }
    }
  }
  1
}

///|
fn paragraph_insert_requests(unit : LocalUnit, cursor : Int, trailing_newline : Bool, requests : Array[DocsUpdateRequest]) -> Unit {
  match unit.kind {
    Paragraph =>
      match unit.paragraph {
        Some(paragraph) =>
          append_paragraph_write(paragraph, cursor, trailing_newline, requests)
        None => ()
      }
    Table =>
      match unit.table {
        Some(table) => append_table_write(table, cursor, requests)
        None => ()
      }
    UnitKind::Opaque => ()
  }
}

///|
/// Delete requests for one remote paragraph. Deleting the full element range
/// removes the paragraph and its break; the empty side of the merge is the
/// paragraph itself, so the neighbors stay separate. Only the final newline
/// is protected: the last paragraph's text is deleted and its newline remains
/// as the mandatory final-newline container.
fn paragraph_delete_requests(old : RemoteEntry, remote : Array[RemoteEntry], entry_index : Int, has_trailing_container : Bool, requests : Array[DocsUpdateRequest]) -> Unit {
  let is_last = is_last_real(entry_index, remote, has_trailing_container)
  if is_last {
    requests.push(DeleteContentRange(start_index=old.start_index, end_index=old.end_index - 1))
  } else {
    requests.push(DeleteContentRange(start_index=old.start_index, end_index=old.end_index))
  }
}

///|
fn delete_requests(old : RemoteEntry, remote : Array[RemoteEntry], entry_index : Int, has_trailing_container : Bool, requests : Array[DocsUpdateRequest]) -> Unit {
  match old.kind {
    Paragraph =>
      paragraph_delete_requests(old, remote, entry_index, has_trailing_container, requests)
    Table =>
      requests.push(DeleteContentRange(start_index=old.start_index, end_index=old.end_index))
    UnitKind::Opaque => ()
  }
}

///|
/// A paragraph replaced by a table needs the paragraph element fully removed;
/// the table lands at the restored paragraph boundary.
fn paragraph_to_table_replacement_requests(old : RemoteEntry, remote : Array[RemoteEntry], entry_index : Int, has_trailing_container : Bool, unit : LocalUnit, delete_group : Array[DocsUpdateRequest], insert_group : Array[DocsUpdateRequest]) -> Unit {
  let is_last = is_last_real(entry_index, remote, has_trailing_container)
  if is_last {
    // Keep the final newline; the emptied paragraph becomes the trailing
    // final-newline container after the table.
    delete_group.push(DeleteContentRange(start_index=old.start_index, end_index=old.end_index - 1))
    paragraph_insert_requests(unit, old.start_index, false, insert_group)
  } else {
    delete_group.push(DeleteContentRange(start_index=old.start_index, end_index=old.end_index))
    paragraph_insert_requests(unit, old.start_index, false, insert_group)
  }
}

///|
fn replacement_requests(old : RemoteEntry, remote : Array[RemoteEntry], entry_index : Int, has_trailing_container : Bool, unit : LocalUnit, delete_group : Array[DocsUpdateRequest], insert_group : Array[DocsUpdateRequest]) -> Unit {
  match (old.kind, unit.kind) {
    (Paragraph, Paragraph) => {
      delete_group.push(DeleteContentRange(start_index=old.start_index, end_index=old.end_index - 1))
      paragraph_insert_requests(unit, old.start_index, false, insert_group)
    }
    (Paragraph, Table) =>
      paragraph_to_table_replacement_requests(old, remote, entry_index, has_trailing_container, unit, delete_group, insert_group)
    (Table, _) => {
      delete_group.push(DeleteContentRange(start_index=old.start_index, end_index=old.end_index))
      paragraph_insert_requests(unit, old.start_index, false, insert_group)
    }
    _ => ()
  }
}

///|
/// A local reorder brackets an opaque unit when a deleted unit's old remote
/// range and its same-signature reinsertion point surround the opaque; that
/// alignment is ambiguous.
fn reorder_brackets_opaque(
  base_index : Int,
  base : Array[LocalUnit],
  want : Array[LocalUnit],
  desired_to_baseline : Array[Int?],
  base_to_desired : Array[Int?],
  baseline_to_remote : Array[Int?],
  current : Array[RemoteEntry],
) -> Bool {
  let old_remote = match baseline_to_remote[base_index] {
    Some(value) => value
    None => return false
  }
  let mut desired_index = -1
  for index = 0; index < want.length(); index = index + 1 {
    if desired_to_baseline[index] is None &&
      want[index].kind == base[base_index].kind &&
      want[index].signature == base[base_index].signature {
      desired_index = index
      break
    }
  }
  if desired_index < 0 {
    return false
  }
  let new_anchor = insertion_boundary(
    desired_index, desired_to_baseline, base_to_desired, baseline_to_remote, current,
  )
  let old_start = current[old_remote].start_index
  let old_end = current[old_remote].end_index
  let low = if old_start < new_anchor { old_start } else { new_anchor }
  let high = if old_end > new_anchor { old_end } else { new_anchor }
  for entry in current {
    if entry.kind is Opaque && entry.start_index >= low && entry.end_index <= high {
      return true
    }
  }
  false
}

///|
pub fn reconcile_document(baseline : @pumd.DesiredDocument, desired : @pumd.DesiredDocument, remote : RemoteContent) -> Result[ReconcileOutcome, ReconcileError] {
  match validate_desired(desired) { Err(error) => return Err(error); Ok(_) => () }
  let base = local_units(baseline); let want = local_units(desired); let current = remote_entries(remote)
  let local_matches = local_lcs(base, want); let remote_matches = lcs(base, current)
  let base_to_desired : Array[Int?] = []; let desired_to_base : Array[Int?] = []; let base_to_remote : Array[Int?] = []
  for base_index = 0; base_index < base.length(); base_index = base_index + 1 { base_to_desired.push(None); base_to_remote.push(None) }
  for desired_index = 0; desired_index < want.length(); desired_index = desired_index + 1 { desired_to_base.push(None) }
  for pair in local_matches { base_to_desired[pair.left] = Some(pair.right); desired_to_base[pair.right] = Some(pair.left) }
  for pair in remote_matches { base_to_remote[pair.left] = Some(pair.right) }
  let reports : Array[UnitReport] = []; let mut local_count = 0; let mut remote_count = 0; let mut conflicts = 0
  for index = 0; index < base.length(); index = index + 1 {
    // Matched units are unchanged: LCS position shifts are insertion or
    // deletion artifacts, not moves. Genuine reorders surface as unmatched
    // delete/insert pairs.
    let local_changed = base_to_desired[index] is None
    let remote_changed = match base_to_remote[index] { Some(target) => current[target].changed; None => true }
    let mut conflict = local_changed && remote_changed
    if local_changed &&
      reorder_brackets_opaque(index, base, want, desired_to_base, base_to_desired, base_to_remote, current) {
      conflict = true
    }
    if local_changed { local_count = local_count + 1 }; if remote_changed { remote_count = remote_count + 1 }; if conflict { conflicts = conflicts + 1 }
    reports.push({ kind: base[index].kind, index: index + 1, local_change: local_changed, remote_change: remote_changed, conflict, description: unit_description(base[index].kind, index + 1) })
  }
  for index = 0; index < want.length(); index = index + 1 {
    if desired_to_base[index] is None {
      let replaces_same_position = index < base.length() && base_to_desired[index] is None && base_to_remote[index] is Some(_)
      if !replaces_same_position {
        local_count = local_count + 1
        reports.push({ kind: want[index].kind, index: index + 1, local_change: true, remote_change: false, conflict: false, description: unit_description(want[index].kind, index + 1) })
      }
    }
  }
  for index = 0; index < current.length(); index = index + 1 { if current[index].kind == Opaque { remote_count = remote_count + 1; reports.push({ kind: Opaque, index: index + 1, local_change: false, remote_change: true, conflict: false, description: current[index].description }) } }
  let report = { units: reports, local_changes: local_count, remote_changes: remote_count, conflicts }
  if conflicts > 0 { return Ok(Conflict(report)) }
  if local_count == 0 { return Ok(NoLocalChanges(report)) }
  let has_trailing_container = remote_has_trailing_container(remote)
  let groups : Array[OpGroup] = []
  let claimed_base : Array[Bool] = []
  for base_index = 0; base_index < base.length(); base_index = base_index + 1 { claimed_base.push(false) }
  // Build op groups in reverse desired order so same-anchor insertions land in
  // desired order, then sort by descending anchor with deletions first.
  let mut order = 0
  let mut desired_index = want.length()
  while desired_index > 0 {
    desired_index = desired_index - 1
    if desired_to_base[desired_index] is Some(_) {
      continue
    }
    // An unmatched unit at a position whose remote counterpart exists and
    // whose base counterpart is also unmatched replaces that unit in place.
    let claims = desired_index < base.length() && base_to_desired[desired_index] is None
    if claims {
      match base_to_remote[desired_index] {
        Some(remote_index) => {
          claimed_base[desired_index] = true
          let delete_group : Array[DocsUpdateRequest] = []
          let insert_group : Array[DocsUpdateRequest] = []
          replacement_requests(current[remote_index], current, remote_index, has_trailing_container, want[desired_index], delete_group, insert_group)
          order = order + 1
          groups.push({ anchor: current[remote_index].start_index, deletes: true, order, requests: delete_group })
          order = order + 1
          groups.push({ anchor: current[remote_index].start_index, deletes: false, order, requests: insert_group })
          continue
        }
        None => ()
      }
    }
    let anchor = insertion_boundary(desired_index, desired_to_base, base_to_desired, base_to_remote, current)
    let insert_group : Array[DocsUpdateRequest] = []
    paragraph_insert_requests(want[desired_index], anchor, true, insert_group)
    order = order + 1
    groups.push({ anchor, deletes: false, order, requests: insert_group })
  }
  let mut base_index = base.length()
  while base_index > 0 {
    base_index = base_index - 1
    if base_to_desired[base_index] is None && !claimed_base[base_index] {
      match base_to_remote[base_index] {
        Some(remote_index) => {
          let delete_group : Array[DocsUpdateRequest] = []
          delete_requests(current[remote_index], current, remote_index, has_trailing_container, delete_group)
          order = order + 1
          groups.push({ anchor: current[remote_index].start_index, deletes: true, order, requests: delete_group })
        }
        None => ()
      }
    }
  }
  groups.sort_by(fn(a, b) {
    if a.anchor != b.anchor {
      b.anchor - a.anchor
    } else if a.deletes != b.deletes {
      if a.deletes { -1 } else { 1 }
    } else {
      a.order - b.order
    }
  })
  let requests : Array[DocsUpdateRequest] = []
  for group in groups {
    requests.push_iter(group.requests.iter())
  }
  Ok(Planned(report, { requests, }))
}

///|
fn unit_at(units : Array[LocalUnit], kind : UnitKind, ordinal : Int) -> LocalUnit? {
  let mut seen = 0
  for unit in units {
    if unit.kind == kind {
      seen = seen + 1
      if seen == ordinal {
        return Some(unit)
      }
    }
  }
  None
}

///|
fn remote_entry_at(entries : Array[RemoteEntry], kind : UnitKind, ordinal : Int) -> RemoteEntry? {
  let mut seen = 0
  for entry in entries {
    if entry.kind == kind {
      seen = seen + 1
      if seen == ordinal {
        return Some(entry)
      }
    }
  }
  None
}

///|
/// Whether the remote Managed Tab now matches the desired document for every
/// unit the original reconciliation planned to change. The update batch is
/// atomic, so all planned units landed or none did; checking the planned
/// positions specifically means unrelated remote-only changes do not affect
/// the diagnosis. Used to confirm an ambiguous transport outcome before
/// committing the new Published Baseline.
pub fn update_intended_state_landed(
  baseline : @pumd.DesiredDocument,
  desired : @pumd.DesiredDocument,
  remote : RemoteContent,
  report : ReconciliationReport,
) -> Bool {
  let base = local_units(baseline)
  let want = local_units(desired)
  let current = remote_entries(remote)
  for unit in report.units {
    if unit.local_change && !unit.conflict {
      match unit_at(want, unit.kind, unit.index) {
        Some(planned) => {
          // Replacement or insertion: the intended unit must now occupy its
          // planned slot, unmodified.
          match remote_entry_at(current, unit.kind, unit.index) {
            Some(entry) =>
              if entry.signature != planned.signature || entry.changed {
                return false
              }
            None => return false
          }
        }
        None => {
          // Deletion: the removed unit must no longer be present anywhere.
          match unit_at(base, unit.kind, unit.index) {
            Some(removed) =>
              for entry in current {
                if entry.kind == unit.kind && entry.signature == removed.signature {
                  return false
                }
              }
            None => ()
          }
        }
      }
    }
  }
  true
}
