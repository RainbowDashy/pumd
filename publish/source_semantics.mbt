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
    @pumd.NamedStyle::Heading1 => 1
    @pumd.NamedStyle::Heading2 => 2
    @pumd.NamedStyle::Heading3 => 3
    @pumd.NamedStyle::Heading4 => 4
    @pumd.NamedStyle::Heading5 => 5
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
  style.font_size_points == code.font_size_points &&
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
  {
    runs: paragraph.runs.map(fn(run) {
      SourceSemanticRun::{
        text: run.content,
        bold: run.style.bold,
        italic: run.style.italic,
        code: semantic_code_text(run.style),
        link: run.link.map(fn(value) { value.url }),
      }
    }),
    images: paragraph.inline_images.map(fn(image) {
      SourceSemanticImage::{ source_url: image.source_url, text_offset: image.text_offset }
    }),
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
              { ..semantic, runs: semantic.runs.map(fn(run) { { ..run, bold: false } }) }
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
fn local_semantic_units(document : @pumd.DesiredDocument) -> Array[LocalSemanticUnit] {
  let result : Array[LocalSemanticUnit] = []
  for element in document.content {
    match element {
      @pumd.StructuralElement::Paragraph(paragraph) => result.push({
        semantic: Paragraph(desired_paragraph_semantics(paragraph)),
        provenance: paragraph.provenance,
      })
      @pumd.StructuralElement::Table(table) => result.push({
        semantic: Table(desired_table_semantics(table)),
        provenance: table.provenance,
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
fn remote_paragraph_semantics(paragraph : RemoteParagraph) -> SourceSemanticParagraph {
  let (list, nesting_level) = remote_list(paragraph.bullet)
  {
    runs: paragraph.runs.map(fn(run) {
      SourceSemanticRun::{
        text: run.text,
        bold: run.style.bold,
        italic: run.style.italic,
        code: semantic_code_text(run.style),
        link: run.link,
      }
    }),
    images: paragraph.inline_images.map(fn(image) {
      SourceSemanticImage::{ source_url: image.source_url, text_offset: image.text_offset }
    }),
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
              { ..semantic, runs: semantic.runs.map(fn(run) { { ..run, bold: false } }) }
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
        let implicit_final = index == content.units.length() - 1 &&
          paragraph.runs.is_empty() && paragraph.end_index == paragraph.start_index + 1
        if !implicit_final {
          result.push({
            semantic: Some(Paragraph(remote_paragraph_semantics(paragraph))),
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
