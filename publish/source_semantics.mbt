///|
pub(all) struct SourceSemanticRun {
  text : String
  bold : Bool
  italic : Bool
  code : Bool
  link : String?
} derive(Eq, @debug.Debug)

///|
pub(all) struct SourceSemanticImage {
  source_url : String
  text_offset : Int
} derive(Eq, @debug.Debug)

///|
pub(all) enum SourceSemanticList { Bullet; Numbered } derive(Eq, @debug.Debug)

///|
pub(all) struct SourceSemanticParagraph {
  runs : Array[SourceSemanticRun]
  images : Array[SourceSemanticImage]
  heading : Int
  list : SourceSemanticList?
  nesting_level : Int
  quote_depth : Int
  code_block : Bool
} derive(Eq, @debug.Debug)

///|
pub(all) struct SourceSemanticCell {
  paragraphs : Array[SourceSemanticParagraph]
  alignment : @pumd.TableAlignment
  header : Bool
} derive(Eq, @debug.Debug)

///|
pub(all) struct SourceSemanticTable { rows : Array[Array[SourceSemanticCell]] } derive(Eq, @debug.Debug)

///|
pub(all) enum SourceSemanticUnit {
  Paragraph(SourceSemanticParagraph)
  Table(SourceSemanticTable)
} derive(Eq, @debug.Debug)

///|
priv struct LocalSemanticUnit {
  semantic : SourceSemanticUnit
  provenance : @pumd.SourceRange?
  remote_rewrite_lossy : Bool
}

///|
priv struct RemoteSemanticEntry {
  semantic : SourceSemanticUnit?
  suggestions : Bool
  unsupported : Bool
  description : String
}

///|
fn semantic_heading(style : @pumd.NamedStyle) -> Int {
  match style {
    @pumd.NamedStyle::NormalText => 0
    @pumd.NamedStyle::Title => 1
    @pumd.NamedStyle::Heading1 => 2
    @pumd.NamedStyle::Heading2 => 3
    @pumd.NamedStyle::Heading3 => 4
    @pumd.NamedStyle::Heading4 => 5
    @pumd.NamedStyle::Heading5 => 6
    // Markdown has no heading level beyond six. Preserve reviewer-authored
    // Heading 6 as a representable level-six source heading; republishing it
    // safely normalizes to the supported Heading 5 body role.
    @pumd.NamedStyle::Heading6 => 6
  }
}

///|
fn semantic_quote_depth(style : @pumd.ParagraphStyle) -> Int {
  match style.indent_start_points {
    Some(points) if style.border_left is Some(_) => {
      let width = @pumd.builtin_style_profile().quote_indent_per_level_points
      if points <= 0 || width <= 0 { 0 } else { (points + width - 1) / width }
    }
    _ => 0
  }
}

///|
fn semantic_code_text(style : @pumd.TextStyle) -> Bool {
  let code = @pumd.builtin_style_profile().code_text
  style.font_family == code.font_family &&
  style.background_color.map(fn(c) { c.to_lower() }) ==
    code.background_color.map(fn(c) { c.to_lower() })
}

///|
fn semantic_code_block(style : @pumd.ParagraphStyle) -> Bool {
  let code = @pumd.builtin_style_profile().code_block
  style.font_family == code.font_family &&
  style.font_size_points == code.font_size_points &&
  style.background_color.map(fn(c) { c.to_lower() }) ==
    code.background_color.map(fn(c) { c.to_lower() })
}

///|
fn semantic_runs_mergeable(
  left : SourceSemanticRun,
  right : SourceSemanticRun,
) -> Bool {
  left.bold == right.bold &&
  left.italic == right.italic &&
  left.code == right.code &&
  left.link == right.link
}

///|
fn semantic_image_at_offset(
  images : Array[SourceSemanticImage],
  offset : Int,
) -> Bool {
  for image in images {
    if image.text_offset == offset { return true }
  }
  false
}

///|
fn normalize_semantic_runs(
  runs : Array[SourceSemanticRun],
  images? : Array[SourceSemanticImage] = [],
) -> Array[SourceSemanticRun] {
  let normalized : Array[SourceSemanticRun] = []
  let mut text_offset = 0
  for run in runs {
    if run.text.is_empty() {
      continue
    }
    let last = normalized.length() - 1
    if last >= 0 &&
      !semantic_image_at_offset(images, text_offset) &&
      semantic_runs_mergeable(normalized[last], run) {
      normalized[last] = {
        ..normalized[last],
        text: normalized[last].text + run.text,
      }
    } else {
      normalized.push(run)
    }
    text_offset = advance_google_docs_index(index=text_offset, text=run.text)
  }
  normalized
}

///|
fn semantic_table_header_paragraph(
  semantic : SourceSemanticParagraph,
) -> SourceSemanticParagraph {
  {
    ..semantic,
    runs: normalize_semantic_runs(
      semantic.runs.map(fn(run) { { ..run, bold: false } }),
      images=semantic.images,
    ),
  }
}

///|
fn desired_list(bullet : @pumd.BulletProperties?) -> (SourceSemanticList?, Int) {
  match bullet {
    Some(value) => {
      let kind = match value.kind {
        @pumd.ListKind::Bullet => SourceSemanticList::Bullet
        @pumd.ListKind::Numbered(..) => SourceSemanticList::Numbered
      }
      (Some(kind), value.nesting_level)
    }
    None => (None, 0)
  }
}

///|
fn desired_paragraph_semantics(paragraph : @pumd.Paragraph) -> SourceSemanticParagraph {
  let (list, nesting_level) = desired_list(paragraph.bullet)
  let images = paragraph.inline_images.map(fn(image) {
    SourceSemanticImage::{ source_url: image.source_url, text_offset: image.text_offset }
  })
  {
    runs: normalize_semantic_runs(
      paragraph.runs.map(fn(run) {
        SourceSemanticRun::{
          text: run.content,
          bold: run.style.bold,
          italic: run.style.italic,
          code: semantic_code_text(run.style),
          link: run.link.map(fn(value) { value.url }),
        }
      }),
      images=images,
    ),
    images,
    heading: semantic_heading(paragraph.style.named_style),
    list,
    nesting_level,
    quote_depth: semantic_quote_depth(paragraph.style),
    code_block: semantic_code_block(paragraph.style),
  }
}

///|
fn desired_table_semantics(table : @pumd.Table) -> SourceSemanticTable {
  {
    rows: table.rows.map(fn(row) {
      row.cells.map(fn(cell) {
        SourceSemanticCell::{
          paragraphs: cell.content.map(fn(paragraph) {
            let semantic = desired_paragraph_semantics(paragraph)
            if row.is_header {
              semantic_table_header_paragraph(semantic)
            } else {
              semantic
            }
          }),
          alignment: cell.alignment,
          header: row.is_header,
        }
      })
    }),
  }
}

///|
fn paragraph_remote_rewrite_lossy(paragraph : @pumd.Paragraph) -> Bool {
  if semantic_code_block(paragraph.style) { return true }
  for run in paragraph.runs {
    match run.link { Some(link) if link.title is Some(_) => return true; _ => () }
  }
  for image in paragraph.inline_images {
    if !image.alt_text.is_empty() || image.title is Some(_) { return true }
  }
  match paragraph.bullet {
    Some({ kind: @pumd.ListKind::Numbered(start~, delimiter~), .. }) =>
      start != 1 || delimiter != "."
    _ => false
  }
}

///|
fn table_remote_rewrite_lossy(table : @pumd.Table) -> Bool {
  for row in table.rows {
    for cell in row.cells {
      for paragraph in cell.content {
        if paragraph_remote_rewrite_lossy(paragraph) { return true }
      }
    }
  }
  false
}

///|
fn local_semantic_units(document : @pumd.DesiredDocument) -> Array[LocalSemanticUnit] {
  let result : Array[LocalSemanticUnit] = []
  for element in document.content {
    match element {
      @pumd.StructuralElement::Paragraph(paragraph) => result.push({
        semantic: Paragraph(desired_paragraph_semantics(paragraph)),
        provenance: paragraph.provenance,
        remote_rewrite_lossy: paragraph_remote_rewrite_lossy(paragraph),
      })
      @pumd.StructuralElement::Table(table) => result.push({
        semantic: Table(desired_table_semantics(table)),
        provenance: table.provenance,
        remote_rewrite_lossy: table_remote_rewrite_lossy(table),
      })
    }
  }
  result
}

///|
fn remote_list(bullet : RemoteBullet?) -> (SourceSemanticList?, Int) {
  match bullet {
    Some(value) => (Some(if value.numeric { Numbered } else { Bullet }), value.nesting_level)
    None => (None, 0)
  }
}

///|
fn remote_run_source_text(run : RemoteRun, is_last : Bool) -> String {
  if is_last && run.text.has_suffix("\n") {
      run.text.unsafe_substring(start=0, end=run.text.length() - 1)
  } else {
    run.text
  }
}

///|
fn remote_semantic_runs(
  paragraph : RemoteParagraph,
  images : Array[SourceSemanticImage],
) -> Array[SourceSemanticRun] {
  let semantic : Array[SourceSemanticRun] = []
  for index, run in paragraph.runs {
    let text = remote_run_source_text(
      run,
      index == paragraph.runs.length() - 1,
    )
    semantic.push({
      text,
      bold: run.style.bold,
      italic: run.style.italic,
      code: semantic_code_text(run.style),
      link: run.link,
    })
  }
  normalize_semantic_runs(semantic, images=images)
}

///|
fn remote_paragraph_semantics(paragraph : RemoteParagraph) -> SourceSemanticParagraph {
  let (list, nesting_level) = remote_list(paragraph.bullet)
  let images = paragraph.inline_images.map(fn(image) {
    SourceSemanticImage::{ source_url: image.source_url, text_offset: image.text_offset }
  })
  {
    runs: remote_semantic_runs(paragraph, images),
    images,
    heading: semantic_heading(paragraph.style.named_style),
    list,
    nesting_level,
    quote_depth: semantic_quote_depth(paragraph.style),
    code_block: semantic_code_block(paragraph.style),
  }
}

///|
fn remote_table_has_suggestions(table : RemoteTable) -> Bool {
  if !table.suggestions.is_empty() { return true }
  for row in table.rows {
    for cell in row.cells {
      if !cell.suggestions.is_empty() { return true }
      for paragraph in cell.paragraphs {
        if !paragraph.suggestions.is_empty() { return true }
      }
    }
  }
  false
}

///|
fn remote_table_is_unsupported(table : RemoteTable) -> Bool {
  if table.normalization_warning { return true }
  for row in table.rows {
    for cell in row.cells {
      if cell.normalization_warning || !cell.opaque_units.is_empty() { return true }
      for paragraph in cell.paragraphs {
        if paragraph.normalization_warning { return true }
      }
    }
  }
  false
}

///|
fn remote_table_semantics(table : RemoteTable) -> SourceSemanticTable {
  let rows : Array[Array[SourceSemanticCell]] = []
  for row_index, row in table.rows {
    rows.push(
      row.cells.map(fn(cell) {
        SourceSemanticCell::{
          paragraphs: cell.paragraphs.map(fn(paragraph) {
            let semantic = remote_paragraph_semantics(paragraph)
            if row_index == 0 {
              semantic_table_header_paragraph(semantic)
            } else {
              semantic
            }
          }),
          alignment: cell.alignment,
          header: row_index == 0,
        }
      }),
    )
  }
  { rows, }
}

///|
fn remote_semantic_entries(content : RemoteContent) -> Array[RemoteSemanticEntry] {
  let result : Array[RemoteSemanticEntry] = []
  for index, unit in content.units {
    match unit {
      RemoteUnit::Paragraph(paragraph) => {
        let semantic = remote_paragraph_semantics(paragraph)
        let implicit_final = index == content.units.length() - 1 &&
          semantic.runs.is_empty() &&
          semantic.images.is_empty() &&
          paragraph.end_index == paragraph.start_index + 1 &&
          !semantic_code_block(paragraph.style)
        if !implicit_final {
          result.push({
            semantic: Some(Paragraph(semantic)),
            suggestions: !paragraph.suggestions.is_empty(),
            unsupported: paragraph.normalization_warning,
            description: "paragraph " + (result.length() + 1).to_string(),
          })
        }
      }
      RemoteUnit::Table(table) => result.push({
        semantic: Some(Table(remote_table_semantics(table))),
        suggestions: remote_table_has_suggestions(table),
        unsupported: remote_table_is_unsupported(table),
        description: "table " + (result.length() + 1).to_string(),
      })
      RemoteUnit::Opaque(item) => result.push({
        semantic: None,
        suggestions: false,
        unsupported: true,
        description: "unsupported structure (" + item.kind + ")",
      })
    }
  }
  result
}
