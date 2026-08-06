///|
pub(all) struct RemoteDocument {
  document_id : String
  title : String?
  revision_id : String
  tabs : Array[RemoteTab]
} derive(Eq, @debug.Debug)

///|
pub(all) struct RemoteTab {
  tab_id : String
  content : RemoteContent
} derive(Eq, @debug.Debug)

///|
pub(all) struct RemoteContent {
  units : Array[RemoteUnit]
} derive(Eq, @debug.Debug)

///|
pub(all) enum RemoteUnit {
  Paragraph(RemoteParagraph)
  Table(RemoteTable)
  Opaque(RemoteOpaque)
} derive(Eq, @debug.Debug)

///|
pub(all) struct RemoteParagraph {
  start_index : Int
  end_index : Int
  runs : Array[RemoteRun]
  style : @pumd.ParagraphStyle
  bullet : RemoteBullet?
  suggestions : Array[RemoteSuggestion]
  normalization_warning : Bool
} derive(Eq, @debug.Debug)

///|
pub(all) struct RemoteRun {
  start_index : Int
  end_index : Int
  text : String
  style : @pumd.TextStyle
  link : String?
} derive(Eq, @debug.Debug)

///|
pub(all) struct RemoteBullet {
  nesting_level : Int
  numeric : Bool
  glyph : String
} derive(Eq, @debug.Debug)

///|
pub(all) struct RemoteTable {
  start_index : Int
  end_index : Int
  rows : Array[RemoteTableRow]
  suggestions : Array[RemoteSuggestion]
  normalization_warning : Bool
} derive(Eq, @debug.Debug)

///|
pub(all) struct RemoteTableRow {
  cells : Array[RemoteTableCell]
} derive(Eq, @debug.Debug)

///|
pub(all) struct RemoteTableCell {
  start_index : Int
  end_index : Int
  paragraphs : Array[RemoteParagraph]
  opaque_units : Array[RemoteOpaque]
  suggestions : Array[RemoteSuggestion]
  alignment : @pumd.TableAlignment
  background_color : String?
  normalization_warning : Bool
} derive(Eq, @debug.Debug)

///|
pub(all) struct RemoteOpaque {
  start_index : Int
  end_index : Int
  kind : String
  description : String?
} derive(Eq, @debug.Debug)

///|
pub(all) enum RemoteSuggestion {
  InsertedText(start_index~ : Int, end_index~ : Int, text~ : String, suggestion_id~ : String)
  DeletedText(start_index~ : Int, end_index~ : Int, text~ : String, suggestion_id~ : String)
  StyleChange(start_index~ : Int, end_index~ : Int, suggestion_id~ : String)
} derive(Eq, @debug.Debug)

///|
pub(all) enum RemoteDecodeError {
  MalformedJson(String)
  InvalidDocument(String)
  MissingRevision(String)
  MissingManagedTab(String)
} derive(Eq, @debug.Debug)

///|
pub fn RemoteDecodeError::user_message(self : RemoteDecodeError) -> String {
  match self {
    MalformedJson(_) => "Google Docs returned malformed JSON."
    InvalidDocument(_) => "Google Docs returned an invalid document response."
    MissingRevision(_) => "Google Docs did not return a usable revision ID."
    MissingManagedTab(tab_id) =>
      "The managed Google Docs tab is missing: " + tab_id
  }
}

///|
/// The small derived envelope keeps root decoding consistent with the adapter.
priv struct RemoteDocumentEnvelope {
  documentId : String?
  title : String?
  revisionId : String?
  tabs : Array[Json]?
  body : Json?
} derive(@json.FromJson)

///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Object(object) => object.get(key)
    _ => None
  }
}

///|
fn string_field(value : Json, key : String) -> String? {
  match field(value, key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
fn array_field(value : Json, key : String) -> Array[Json]? {
  match field(value, key) {
    Some(Array(values)) => Some(values)
    _ => None
  }
}

///|
fn index_field(value : Json, key : String) -> Int {
  match field(value, key) {
    Some(Number(number, ..)) => number.to_int()
    _ => 0
  }
}

///|
fn strings(value : Json, key : String) -> (Array[String], Bool) {
  match field(value, key) {
    None => ([], false)
    Some(Array(values)) => {
      let result : Array[String] = []
      let mut warning = false
      for value in values {
        match value {
          String(text) => result.push(text)
          _ => warning = true
        }
      }
      (result, warning)
    }
    _ => ([], true)
  }
}

///|
fn number(value : Json?, fallback : Int) -> (Int, Bool) {
  match value {
    None => (fallback, false)
    Some(Number(magnitude, ..)) => (magnitude.to_int(), false)
    _ => (fallback, true)
  }
}

///|
fn boolean(value : Json?, fallback : Bool) -> (Bool, Bool) {
  match value {
    None => (fallback, false)
    Some(True) => (true, false)
    Some(False) => (false, false)
    _ => (fallback, true)
  }
}

///|
fn dimension(value : Json?, fallback : Int?) -> (Int?, Bool) {
  match value {
    None => (fallback, false)
    Some(dimension) => {
      let magnitude = field(dimension, "magnitude")
      match magnitude {
        Some(Number(value, ..)) => (Some(value.to_int()), false)
        None => (fallback, false)
        _ => (fallback, true)
      }
    }
  }
}

///|
fn remote_hex_component(value : Double) -> String {
  value.round().to_int().to_byte().to_hex()
}

///|
fn color(value : Json?) -> (String?, Bool) {
  match value {
    None => (None, false)
    Some(color_value) => {
      let rgb = match field(color_value, "color") {
        Some(inner) => field(inner, "rgbColor")
        None => field(color_value, "rgbColor")
      }
      match rgb {
        None => (None, false)
        Some(rgb) =>
          match (field(rgb, "red"), field(rgb, "green"), field(rgb, "blue")) {
            (
              Some(Number(red, ..)),
              Some(Number(green, ..)),
              Some(Number(blue, ..)),
            ) if red >= 0.0 &&
              red <= 1.0 &&
              green >= 0.0 &&
              green <= 1.0 &&
              blue >= 0.0 &&
              blue <= 1.0 =>
              (
                Some(
                  "#" +
                  remote_hex_component(red * 255.0) +
                  remote_hex_component(green * 255.0) +
                  remote_hex_component(blue * 255.0),
                ),
                false,
              )
            _ => (None, true)
          }
      }
    }
  }
}

///|
fn description(value : Json) -> String? {
  match string_field(value, "title") {
    Some(text) if !text.is_empty() => Some(text)
    _ =>
      match string_field(value, "description") {
        Some(text) if !text.is_empty() => Some(text)
        _ =>
          match string_field(value, "url") {
            Some(text) if !text.is_empty() => Some(text)
            _ =>
              match field(value, "inlineObjectProperties") {
                Some(properties) => description(properties)
                None =>
                  match field(value, "embeddedObject") {
                    Some(embedded) => description(embedded)
                    None =>
                      match field(value, "embeddedObjectProperties") {
                        Some(properties) => description(properties)
                        None => None
                      }
                  }
              }
          }
      }
  }
}

///|
fn opaque_kind(value : Json) -> String {
  match value {
    Object(object) => {
      for key, _ in object {
        match key {
          "startIndex"
          | "endIndex"
          | "suggestedInsertionIds"
          | "suggestedDeletionIds" => ()
          _ => return key
        }
      }
      "unknown"
    }
    _ => "unknown"
  }
}

///|
fn remote_opaque(value : Json, kind? : String) -> RemoteOpaque {
  let kind = match kind {
    Some(kind) => kind
    None => opaque_kind(value)
  }
  let detail = match field(value, kind) {
    Some(item) => description(item)
    None => description(value)
  }
  {
    start_index: index_field(value, "startIndex"),
    end_index: index_field(value, "endIndex"),
    kind,
    description: detail,
  }
}

///|
fn text_style(value : Json?) -> (@pumd.TextStyle, Bool) {
  let style = match value {
    Some(style) => style
    None => Json::empty_object()
  }
  let (foreground, foreground_warning) = color(field(style, "foregroundColor"))
  let (background, background_warning) = color(field(style, "backgroundColor"))
  let font = match field(style, "weightedFontFamily") {
    Some(font) => font
    None => Json::empty_object()
  }
  let (size, size_warning) = match field(style, "fontSize") {
    Some(font_size) => dimension(Some(font_size), Some(0))
    None => (Some(0), false)
  }
  let (bold, bold_warning) = boolean(field(style, "bold"), false)
  let (italic, italic_warning) = boolean(field(style, "italic"), false)
  let (underline, underline_warning) = boolean(field(style, "underline"), false)
  ({
    font_family: string_field(font, "fontFamily").unwrap_or(""),
    font_size_points: size.unwrap_or(0),
    bold,
    italic,
    underline,
    foreground_color: foreground,
    background_color: background,
  }, foreground_warning || background_warning || size_warning || bold_warning || italic_warning || underline_warning)
}

///|
fn paragraph_style(value : Json?, runs : Array[RemoteRun]) -> (@pumd.ParagraphStyle, Bool) {
  let style = match value {
    Some(style) => style
    None => Json::empty_object()
  }
  let (named_style, named_warning) = match string_field(style, "namedStyleType").unwrap_or("NORMAL_TEXT") {
    "NORMAL_TEXT" => (@pumd.NamedStyle::NormalText, false)
    "HEADING_1" => (@pumd.NamedStyle::Heading1, false)
    "HEADING_2" => (@pumd.NamedStyle::Heading2, false)
    "HEADING_3" => (@pumd.NamedStyle::Heading3, false)
    "HEADING_4" => (@pumd.NamedStyle::Heading4, false)
    "HEADING_5" => (@pumd.NamedStyle::Heading5, false)
    "HEADING_6" => (@pumd.NamedStyle::Heading6, false)
    _ => (@pumd.NamedStyle::NormalText, true)
  }
  let (line_spacing, line_warning) = number(field(style, "lineSpacing"), 100)
  let (above, above_warning) = dimension(field(style, "spaceAbove"), Some(0))
  let (below, below_warning) = dimension(field(style, "spaceBelow"), Some(0))
  let (indent_start, indent_start_warning) = dimension(field(style, "indentStart"), None)
  let (indent_first, indent_first_warning) = dimension(field(style, "indentFirstLine"), None)
  let shading = field(style, "shading")
  let (background, background_warning) = match shading {
    Some(shading) => color(field(shading, "backgroundColor"))
    None => (None, false)
  }
  let (border, border_warning) = match field(style, "borderLeft") {
    None => (None, false)
    Some(border) => {
      let (border_color, color_warning) = color(field(border, "color"))
      let (width, width_warning) = dimension(field(border, "width"), Some(0))
      let (padding, padding_warning) = dimension(field(border, "padding"), Some(0))
      (match border_color {
        Some(color) => Some(@pumd.ParagraphBorder::{
          color,
          width_points: width.unwrap_or(0),
          padding_points: padding.unwrap_or(0),
        })
        None => None
      }, color_warning || width_warning || padding_warning)
    }
  }
  let mut font_family = ""
  let mut font_size_points = 0
  for run in runs {
    if font_family.is_empty() && !run.text.is_empty() {
      font_family = run.style.font_family
      font_size_points = run.style.font_size_points
    }
  }
  ({
    named_style,
    font_family,
    font_size_points,
    line_spacing_percent: line_spacing,
    space_above_points: above.unwrap_or(0),
    space_below_points: below.unwrap_or(0),
    background_color: background,
    indent_start_points: indent_start,
    indent_first_line_points: indent_first,
    border_left: border,
  }, named_warning || line_warning || above_warning || below_warning || indent_start_warning || indent_first_warning || background_warning || border_warning)
}

///|
fn numeric_glyph(glyph : String) -> Bool {
  let glyph = glyph.trim()
  match glyph.get_char(0) {
    Some('0'..='9') => true
    _ => false
  }
}

///|
fn bullet(value : Json?) -> (RemoteBullet?, Bool) {
  match value {
    None => (None, false)
    Some(value) => {
      let (nesting_level, nesting_warning) = number(field(value, "nestingLevel"), 0)
      match array_field(value, "glyphs") {
        Some([first, ..]) => match string_field(first, "glyph") {
          Some(glyph) => (Some({ nesting_level, numeric: numeric_glyph(glyph), glyph }), nesting_warning)
          None => (Some({ nesting_level, numeric: false, glyph: "" }), true)
        }
        _ => (Some({ nesting_level, numeric: false, glyph: "" }), true)
      }
    }
  }
}

///|
fn collect_suggestions(value : Json, start_index : Int, end_index : Int, text : String) -> (Array[RemoteSuggestion], Bool) {
  let (inserted, inserted_warning) = strings(value, "suggestedInsertionIds")
  let (deleted, deleted_warning) = strings(value, "suggestedDeletionIds")
  let result : Array[RemoteSuggestion] = []
  for suggestion_id in inserted {
    result.push(InsertedText(start_index~, end_index~, text~, suggestion_id~))
  }
  for suggestion_id in deleted {
    result.push(DeletedText(start_index~, end_index~, text~, suggestion_id~))
  }
  (result, inserted_warning || deleted_warning)
}

///|
fn append_style_suggestions(
  value : Json,
  start_index : Int,
  end_index : Int,
  result : Array[RemoteSuggestion],
) -> Bool {
  let mut warning = false
  match array_field(value, "suggestedTextRunStyles") {
    None => ()
    Some(styles) => {
      for style in styles {
        match string_field(style, "suggestionId") {
          Some(suggestion_id) if !suggestion_id.is_empty() =>
            result.push(StyleChange(start_index~, end_index~, suggestion_id~))
          _ => warning = true
        }
      }
    }
  }
  // Google Docs exposes suggested style changes as a map keyed by suggestion
  // ID on the text run (`suggestedTextStyleChanges`), in addition to the
  // array form above; both participate as remote changes.
  match field(value, "suggestedTextStyleChanges") {
    Some(Object(changes)) =>
      for suggestion_id, _ in changes {
        if suggestion_id.is_empty() {
          warning = true
        } else {
          result.push(StyleChange(start_index~, end_index~, suggestion_id~))
        }
      }
    _ => ()
  }
  warning
}

///|
fn decode_paragraph(element : Json, paragraph : Json) -> RemoteParagraph {
  let start_index = index_field(element, "startIndex")
  let end_index = index_field(element, "endIndex")
  let runs : Array[RemoteRun] = []
  let (suggestions, suggestion_warning) = collect_suggestions(element, start_index, end_index, "")
  let (paragraph_insertions, paragraph_insertion_warning) = strings(element, "suggestedInsertionIds")
  let mut warning = suggestion_warning || paragraph_insertion_warning || !paragraph_insertions.is_empty()
  match array_field(paragraph, "elements") {
    Some(elements) => for item in elements {
      match field(item, "textRun") {
        Some(text_run) => {
          let text = string_field(text_run, "content").unwrap_or("")
          if field(text_run, "content") is None { warning = true }
          let (run_style, style_warning) = text_style(field(text_run, "textStyle"))
          let link = match field(text_run, "textStyle") {
            Some(style) => match field(style, "link") {
              Some(link) => string_field(link, "url")
              None => None
            }
            None => None
          }
          let run_start = index_field(item, "startIndex")
          let run_end = index_field(item, "endIndex")
          let (inserted, inserted_warning) = strings(text_run, "suggestedInsertionIds")
          let (deleted, deleted_warning) = strings(text_run, "suggestedDeletionIds")
          warning = warning || style_warning || inserted_warning || deleted_warning
          if inserted.is_empty() {
            runs.push({ start_index: run_start, end_index: run_end, text, style: run_style, link })
          }
          for suggestion_id in inserted {
            suggestions.push(InsertedText(start_index=run_start, end_index=run_end, text=text, suggestion_id=suggestion_id))
          }
          for suggestion_id in deleted {
            suggestions.push(DeletedText(start_index=run_start, end_index=run_end, text=text, suggestion_id=suggestion_id))
          }
          warning = warning || append_style_suggestions(text_run, run_start, run_end, suggestions)
        }
        None => warning = true
      }
    }
    None => warning = true
  }
  let paragraph_text = StringBuilder::new()
  for run in runs { paragraph_text.write_string(run.text) }
  let (paragraph_suggestions, paragraph_suggestion_warning) = collect_suggestions(paragraph, start_index, end_index, paragraph_text.to_string())
  suggestions.push_iter(paragraph_suggestions.iter())
  let (nested_paragraph_insertions, nested_paragraph_insertion_warning) = strings(paragraph, "suggestedInsertionIds")
  let (style, style_warning) = paragraph_style(field(paragraph, "paragraphStyle"), runs)
  let (bullet, bullet_warning) = bullet(field(paragraph, "bullet"))
  {
    start_index,
    end_index,
    runs,
    style,
    bullet,
    suggestions,
    normalization_warning: warning || paragraph_suggestion_warning || nested_paragraph_insertion_warning || !nested_paragraph_insertions.is_empty() || style_warning || bullet_warning,
  }
}

///|
fn decode_cell(value : Json) -> RemoteTableCell {
  let start_index = index_field(value, "startIndex")
  let end_index = index_field(value, "endIndex")
  let paragraphs : Array[RemoteParagraph] = []
  let opaque_items : Array[RemoteOpaque] = []
  let (suggestions, suggestion_warning) = collect_suggestions(value, start_index, end_index, "")
  let mut warning = suggestion_warning
  let cell_style = field(value, "tableCellStyle")
  let (alignment, alignment_warning) = match cell_style {
    Some(style) =>
      match string_field(style, "alignment") {
        None => (@pumd.TableAlignment::Unspecified, false)
        Some("START") => (@pumd.TableAlignment::Left, false)
        Some("CENTER") => (@pumd.TableAlignment::Center, false)
        Some("END") => (@pumd.TableAlignment::Right, false)
        Some(_) => (@pumd.TableAlignment::Unspecified, true)
      }
    None => (@pumd.TableAlignment::Unspecified, false)
  }
  let (background, background_warning) = match cell_style {
    Some(style) => color(field(style, "backgroundColor"))
    None => (None, false)
  }
  warning = warning || alignment_warning || background_warning
  match array_field(value, "content") {
    Some(content) => for item in content {
      match field(item, "paragraph") {
        Some(paragraph) => {
          let decoded = decode_paragraph(item, paragraph)
          warning = warning || decoded.normalization_warning
          suggestions.push_iter(decoded.suggestions.iter())
          paragraphs.push(decoded)
        }
        None => {
          opaque_items.push(remote_opaque(item))
          warning = true
        }
      }
    }
    None => warning = true
  }
  { start_index, end_index, paragraphs, opaque_units: opaque_items, suggestions, alignment, background_color: background, normalization_warning: warning }
}

///|
fn decode_table(element : Json, table : Json) -> RemoteTable? {
  let start_index = index_field(element, "startIndex")
  let end_index = index_field(element, "endIndex")
  let rows = match array_field(table, "tableRows") {
    Some(rows) => rows
    None => return None
  }
  let decoded_rows : Array[RemoteTableRow] = []
  let (result_suggestions, suggestion_warning) = collect_suggestions(element, start_index, end_index, "")
  let (table_suggestions, table_suggestion_warning) = collect_suggestions(table, start_index, end_index, "")
  result_suggestions.push_iter(table_suggestions.iter())
  let mut warning = suggestion_warning || table_suggestion_warning
  for row in rows {
    let cells = match array_field(row, "tableCells") {
      Some(cells) => cells
      None => return None
    }
    let decoded_cells : Array[RemoteTableCell] = []
    for cell in cells {
      let decoded = decode_cell(cell)
      warning = warning || decoded.normalization_warning || !decoded.opaque_units.is_empty()
      result_suggestions.push_iter(decoded.suggestions.iter())
      decoded_cells.push(decoded)
    }
    decoded_rows.push({ cells: decoded_cells })
  }
  Some({ start_index, end_index, rows: decoded_rows, suggestions: result_suggestions, normalization_warning: warning })
}

///|
fn decode_content(items : Array[Json]) -> RemoteContent {
  let units : Array[RemoteUnit] = []
  for item in items {
    match field(item, "paragraph") {
      Some(paragraph) =>
        units.push(Paragraph(decode_paragraph(item, paragraph)))
      None =>
        match field(item, "table") {
          Some(table) =>
            match decode_table(item, table) {
              Some(decoded) => units.push(Table(decoded))
              None => units.push(Opaque(remote_opaque(item, kind="table")))
            }
          None => units.push(Opaque(remote_opaque(item)))
        }
    }
  }
  { units, }
}

///|
pub fn decode_remote_document(body : String, document_id : String) -> Result[RemoteDocument, RemoteDecodeError] {
  let json = @json.parse(body) catch { _ => return Err(MalformedJson(document_id)) }
  let envelope : RemoteDocumentEnvelope = @json.from_json(json) catch {
    _ => return Err(InvalidDocument(document_id))
  }
  let response_document_id = match envelope.documentId {
    Some(id) if !id.is_empty() => id
    _ => return Err(InvalidDocument(document_id))
  }
  let revision_id = match envelope.revisionId {
    Some(revision) if !revision.is_empty() => revision
    _ => return Err(MissingRevision(response_document_id))
  }
  let tabs : Array[RemoteTab] = []
  match envelope.tabs {
    Some(raw_tabs) if !raw_tabs.is_empty() => for tab in raw_tabs {
      let tab_id = match field(tab, "tabProperties") {
        Some(properties) => string_field(properties, "tabId").unwrap_or("")
        None => ""
      }
      if tab_id.is_empty() { return Err(InvalidDocument(response_document_id)) }
      let content = match field(tab, "documentTab") {
        Some(document_tab) => match field(document_tab, "body") {
          Some(body) => array_field(body, "content").unwrap_or([])
          None => []
        }
        None => []
      }
      tabs.push({ tab_id, content: decode_content(content) })
    }
    _ => {
      let content = match envelope.body {
        Some(body) => array_field(body, "content").unwrap_or([])
        None => []
      }
      tabs.push({ tab_id: "", content: decode_content(content) })
    }
  }
  Ok({ document_id: response_document_id, title: envelope.title, revision_id, tabs })
}

///|
pub fn remote_tab_content(
  document : RemoteDocument,
  tab_id : String,
) -> RemoteContent? {
  for tab in document.tabs {
    if tab.tab_id == tab_id { return Some(tab.content) }
  }
  None
}

///|
pub fn remote_revision_id(document : RemoteDocument) -> String {
  document.revision_id
}
