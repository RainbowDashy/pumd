///|
pub(all) enum GoogleErrorKind {
  Unauthenticated
  PermissionDenied
  Throttled
} derive(Eq, @debug.Debug)

///|
/// Errors at the deliberately small Google Docs REST boundary.  Callers keep
/// creation and population stages distinct, while this adapter owns only HTTP
/// and the two response shapes it needs.
pub(all) enum DocsAdapterError {
  AdapterTransport(String)
  AdapterHttpStatus(status~ : Int, kind~ : GoogleErrorKind?)
  AdapterDecode(String)
} derive(@debug.Debug)

///|
pub fn DocsAdapterError::message(self : DocsAdapterError) -> String {
  match self {
    AdapterTransport(message) => "transport error: " + message
    AdapterHttpStatus(kind=Some(Throttled), ..) =>
      "Google Docs throttled the request; wait and retry later."
    AdapterHttpStatus(kind=Some(Unauthenticated), ..) =>
      "Google rejected the Application Default Credentials. Refresh ADC before retrying."
    AdapterHttpStatus(kind=Some(PermissionDenied), ..) =>
      "Google denied permission. Check that ADC includes https://www.googleapis.com/auth/drive.file."
    AdapterHttpStatus(status~, kind=None) =>
      "HTTP " + status.to_string() + ": Google Docs rejected the request."
    AdapterDecode(message) => "response decoding error: " + message
  }
}

///|
pub(all) enum UpdateBatchError {
  Adapter(DocsAdapterError)
  RevisionConflict
} derive(@debug.Debug)

///|
pub fn UpdateBatchError::message(self : UpdateBatchError) -> String {
  match self {
    Adapter(error) => error.message()
    RevisionConflict =>
      "Google Docs changed since it was read; reload the publication and retry."
  }
}

///|
fn google_error_kind_from_status(status : String) -> GoogleErrorKind? {
  match status {
    "UNAUTHENTICATED" => Some(Unauthenticated)
    "PERMISSION_DENIED" => Some(PermissionDenied)
    "RESOURCE_EXHAUSTED" => Some(Throttled)
    _ => None
  }
}

///|
fn legacy_google_error_kind(body : String) -> GoogleErrorKind? {
  let json = @json.parse(body) catch { _ => return None }
  let envelope : LegacyGoogleErrorEnvelope = @json.from_json(json) catch {
    _ => return None
  }
  for item in envelope.error.errors {
    match item.reason {
      "rateLimitExceeded" | "userRateLimitExceeded" | "quotaExceeded" =>
        return Some(Throttled)
      "insufficientPermissions" | "forbidden" => return Some(PermissionDenied)
      "authError" => return Some(Unauthenticated)
      _ => ()
    }
  }
  None
}

///|
fn safe_google_error_kind(status : Int, body : String) -> GoogleErrorKind? {
  match @google_core.parse_error_response(body) {
    Some(detail) =>
      match detail.status {
        Some(api_status) =>
          match google_error_kind_from_status(api_status) {
            Some(kind) => return Some(kind)
            None => ()
          }
        None => ()
      }
    None => ()
  }
  match legacy_google_error_kind(body) {
    Some(kind) => return Some(kind)
    None => ()
  }
  match status {
    401 => Some(Unauthenticated)
    403 => Some(PermissionDenied)
    429 => Some(Throttled)
    _ => None
  }
}

///|
/// The only document read model needed by the optional live smoke test.  The
/// raw response is retained so this adapter does not grow a generated Docs
/// read-model dependency.
pub(all) struct RetrievedDocument {
  document_id : String
  body : String
}

///|
priv struct CreatedDocumentResponse {
  documentId : String
} derive(@json.FromJson)

///|
/// A created Google Document and its initially managed tab.
pub(all) struct CreatedDocument {
  document_id : String
  managed_tab_id : String
}

///|
/// The small tab-aware document read model needed by publication inspection.
pub(all) struct RemoteDocumentView {
  document_id : String
  title : String?
  tab_ids : Array[String]
}

///|
/// The Drive file properties needed to determine whether a publication remains usable.
pub(all) struct DriveFileView {
  document_id : String
  name : String?
  trashed : Bool
  can_edit : Bool?
}

///|
priv struct DocumentTabPropertiesResponse {
  tabId : String
} derive(@json.FromJson)

///|
priv struct DocumentTabResponse {
  tabProperties : DocumentTabPropertiesResponse?
} derive(@json.FromJson)

///|
priv struct TabbedDocumentResponse {
  documentId : String
  title : String?
  tabs : Array[DocumentTabResponse]?
} derive(@json.FromJson)

///|
priv struct DriveCapabilitiesResponse {
  canEdit : Bool?
} derive(@json.FromJson)

///|
priv struct DriveFileResponse {
  id : String
  name : String?
  trashed : Bool?
  capabilities : DriveCapabilitiesResponse?
} derive(@json.FromJson)

///|
priv struct LegacyGoogleErrorReason {
  reason : String
} derive(@json.FromJson)

///|
priv struct LegacyGoogleErrorBody {
  errors : Array[LegacyGoogleErrorReason]
} derive(@json.FromJson)

///|
priv struct LegacyGoogleErrorEnvelope {
  error : LegacyGoogleErrorBody
} derive(@json.FromJson)

///|
priv struct TableLayout {
  logical_index : Int
  location : Int
  columns : Int
}

///|
priv struct CellInsertion {
  table_index : Int
  row : Int
  column : Int
  width : Int
}

///|
fn write_json_string(value : String, output : StringBuilder) -> Unit {
  output.write_char('"')
  for char in value {
    match char {
      '"' => output.write_string("\\\"")
      '\\' => output.write_string("\\\\")
      '\n' => output.write_string("\\n")
      '\r' => output.write_string("\\r")
      '\t' => output.write_string("\\t")
      '\b' => output.write_string("\\b")
      _ => {
        let code = char.to_int()
        if code == 0x0C {
          output.write_string("\\f")
        } else if code < 0x20 {
          output.write_string("\\u00")
          output.write_string(code.to_byte().to_hex())
        } else {
          output.write_char(char)
        }
      }
    }
  }
  output.write_char('"')
}

///|
fn named_style_type(style : @pumd.NamedStyle) -> String {
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
fn hex_digit(value : Char) -> Int? {
  match value {
    '0'..='9' => Some(value.to_int() - '0'.to_int())
    'a'..='f' => Some(value.to_int() - 'a'.to_int() + 10)
    'A'..='F' => Some(value.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}

///|
fn docs_adapter_hex_component(first : Char, second : Char) -> Int? {
  match hex_digit(first) {
    Some(high) =>
      match hex_digit(second) {
        Some(low) => Some(high * 16 + low)
        None => None
      }
    None => None
  }
}

///|
fn write_rgb_color(value : String, output : StringBuilder) -> Bool {
  let chars = value.to_array()
  if chars.length() != 7 || chars[0] != '#' {
    return false
  }
  match
    (
      docs_adapter_hex_component(chars[1], chars[2]),
      docs_adapter_hex_component(chars[3], chars[4]),
      docs_adapter_hex_component(chars[5], chars[6]),
    ) {
    (Some(red), Some(green), Some(blue)) => {
      output.write_string("{\"color\":{\"rgbColor\":{\"red\":")
      output.write_string((red.to_double() / 255.0).to_string())
      output.write_string(",\"green\":")
      output.write_string((green.to_double() / 255.0).to_string())
      output.write_string(",\"blue\":")
      output.write_string((blue.to_double() / 255.0).to_string())
      output.write_string("}}}")
      true
    }
    _ => false
  }
}

///|
fn write_dimension(points : Int, output : StringBuilder) -> Unit {
  output.write_string("{\"magnitude\":")
  output.write_string(points.to_string())
  output.write_string(",\"unit\":\"PT\"}")
}

///|
fn write_range(
  start_index : Int,
  end_index : Int,
  tab_id : String?,
  output : StringBuilder,
) -> Unit {
  output.write_string("{\"startIndex\":")
  output.write_string(start_index.to_string())
  output.write_string(",\"endIndex\":")
  output.write_string(end_index.to_string())
  match tab_id {
    Some(tab_id) => {
      output.write_string(",\"tabId\":")
      write_json_string(tab_id, output)
    }
    None => ()
  }
  output.write_char('}')
}

///|
fn write_location(
  index : Int,
  tab_id : String?,
  output : StringBuilder,
) -> Unit {
  output.write_string("{\"index\":")
  output.write_string(index.to_string())
  match tab_id {
    Some(tab_id) => {
      output.write_string(",\"tabId\":")
      write_json_string(tab_id, output)
    }
    None => ()
  }
  output.write_char('}')
}

///|
fn write_paragraph_style(
  style : @pumd.ParagraphStyle,
  output : StringBuilder,
) -> Unit {
  output.write_string("{\"namedStyleType\":")
  write_json_string(named_style_type(style.named_style), output)
  output.write_string(",\"lineSpacing\":")
  output.write_string(style.line_spacing_percent.to_string())
  output.write_string(",\"spaceAbove\":")
  write_dimension(style.space_above_points, output)
  output.write_string(",\"spaceBelow\":")
  write_dimension(style.space_below_points, output)
  match style.background_color {
    Some(color) => {
      let color_json = StringBuilder::new()
      if write_rgb_color(color, color_json) {
        output.write_string(",\"shading\":{\"backgroundColor\":")
        output.write_string(color_json.to_string())
        output.write_char('}')
      }
    }
    None => ()
  }
  match style.indent_start_points {
    Some(points) => {
      output.write_string(",\"indentStart\":")
      write_dimension(points, output)
    }
    None => ()
  }
  match style.indent_first_line_points {
    Some(points) => {
      output.write_string(",\"indentFirstLine\":")
      write_dimension(points, output)
    }
    None => ()
  }
  match style.border_left {
    Some(border) => {
      let color_json = StringBuilder::new()
      if write_rgb_color(border.color, color_json) {
        output.write_string(",\"borderLeft\":{\"color\":")
        output.write_string(color_json.to_string())
        output.write_string(",\"width\":")
        write_dimension(border.width_points, output)
        output.write_string(",\"padding\":")
        write_dimension(border.padding_points, output)
        output.write_string(",\"dashStyle\":\"SOLID\"}")
      }
    }
    None => ()
  }
  output.write_char('}')
}

///|
fn paragraph_style_fields(style : @pumd.ParagraphStyle) -> String {
  let fields = StringBuilder::new()
  fields.write_string("namedStyleType,lineSpacing,spaceAbove,spaceBelow")
  match style.background_color {
    Some(color) if color.length() == 7 =>
      fields.write_string(",shading.backgroundColor")
    _ => ()
  }
  match style.indent_start_points {
    Some(_) => fields.write_string(",indentStart")
    None => ()
  }
  match style.indent_first_line_points {
    Some(_) => fields.write_string(",indentFirstLine")
    None => ()
  }
  match style.border_left {
    Some(border) if border.color.length() == 7 =>
      fields.write_string(",borderLeft")
    _ => ()
  }
  fields.to_string()
}

///|
fn write_paragraph_decoration(
  style : @pumd.ParagraphStyle,
  output : StringBuilder,
) -> String {
  let fields = StringBuilder::new()
  output.write_char('{')
  let mut first = true
  match style.indent_start_points {
    Some(points) => {
      output.write_string("\"indentStart\":")
      write_dimension(points, output)
      fields.write_string("indentStart")
      first = false
    }
    None => ()
  }
  match style.indent_first_line_points {
    Some(points) => {
      if !first {
        output.write_char(',')
        fields.write_char(',')
      }
      output.write_string("\"indentFirstLine\":")
      write_dimension(points, output)
      fields.write_string("indentFirstLine")
      first = false
    }
    None => ()
  }
  match style.border_left {
    Some(border) => {
      let color_json = StringBuilder::new()
      if write_rgb_color(border.color, color_json) {
        if !first {
          output.write_char(',')
          fields.write_char(',')
        }
        output.write_string("\"borderLeft\":{\"color\":")
        output.write_string(color_json.to_string())
        output.write_string(",\"width\":")
        write_dimension(border.width_points, output)
        output.write_string(",\"padding\":")
        write_dimension(border.padding_points, output)
        output.write_string(",\"dashStyle\":\"SOLID\"}")
        fields.write_string("borderLeft")
      }
    }
    None => ()
  }
  output.write_char('}')
  fields.to_string()
}

///|
fn write_text_style(
  style : @pumd.TextStyle,
  link : @pumd.LinkIntent?,
  output : StringBuilder,
) -> String {
  let fields = StringBuilder::new()
  output.write_string("{\"bold\":")
  output.write_string(if style.bold { "true" } else { "false" })
  fields.write_string("bold")
  output.write_string(",\"italic\":")
  output.write_string(if style.italic { "true" } else { "false" })
  fields.write_string(",italic")
  output.write_string(",\"underline\":")
  output.write_string(if style.underline { "true" } else { "false" })
  fields.write_string(",underline")
  output.write_string(",\"weightedFontFamily\":{\"fontFamily\":")
  write_json_string(style.font_family, output)
  output.write_string("}")
  fields.write_string(",weightedFontFamily")
  output.write_string(",\"fontSize\":")
  write_dimension(style.font_size_points, output)
  fields.write_string(",fontSize")
  match style.foreground_color {
    Some(color) => {
      let color_json = StringBuilder::new()
      if write_rgb_color(color, color_json) {
        output.write_string(",\"foregroundColor\":")
        output.write_string(color_json.to_string())
        fields.write_string(",foregroundColor")
      }
    }
    None => ()
  }
  match style.background_color {
    Some(color) => {
      let color_json = StringBuilder::new()
      if write_rgb_color(color, color_json) {
        output.write_string(",\"backgroundColor\":")
        output.write_string(color_json.to_string())
        fields.write_string(",backgroundColor")
      }
    }
    None => ()
  }
  match link {
    Some(intent) => {
      // The Docs Link resource has a URL but no title field. Keeping the
      // title out makes this a valid Docs request rather than an ignored or
      // rejected custom field.
      output.write_string(",\"link\":{\"url\":")
      write_json_string(intent.url, output)
      output.write_string("}")
      fields.write_string(",link")
    }
    None => ()
  }
  output.write_char('}')
  fields.to_string()
}

///|
fn bullet_preset(bullet : @pumd.BulletProperties) -> String {
  match bullet.kind {
    Bullet => "BULLET_DISC_CIRCLE_SQUARE"
    Numbered(delimiter~, ..) =>
      if delimiter == ")" {
        "NUMBERED_DECIMAL_ALPHA_ROMAN_PARENS"
      } else {
        "NUMBERED_DECIMAL_ALPHA_ROMAN"
      }
  }
}

///|
fn table_alignment(alignment : @pumd.TableAlignment) -> String {
  match alignment {
    Left => "START"
    Center => "CENTER"
    Right => "END"
    Unspecified => "START"
  }
}

///|
fn lookup_table(
  layouts : Array[TableLayout],
  table_index : Int,
) -> TableLayout? {
  for layout in layouts {
    if layout.logical_index == table_index {
      return Some(layout)
    }
  }
  None
}

///|
fn resolve_cell_index(
  layout : TableLayout,
  row : Int,
  column : Int,
  insertions : Array[CellInsertion],
) -> Int {
  let wanted = row * layout.columns + column
  // InsertTable introduces a preceding newline. Each cell has two structural
  // positions and every row has one separator position; the plan compiler
  // already advances later body positions by this complete physical width.
  let mut index = layout.location +
    4 +
    row * (2 * layout.columns + 1) +
    column * 2
  for insertion in insertions {
    if insertion.table_index == layout.logical_index &&
      insertion.row * layout.columns + insertion.column < wanted {
      index += insertion.width
    }
  }
  index
}

///|
fn cell_inserted_width(
  layout : TableLayout,
  row : Int,
  column : Int,
  insertions : Array[CellInsertion],
) -> Int {
  let mut width = 0
  for insertion in insertions {
    if insertion.table_index == layout.logical_index &&
      insertion.row == row &&
      insertion.column == column {
      width += insertion.width
    }
  }
  width
}

///|
fn begin_request(output : StringBuilder, first : Bool) -> Bool {
  if !first {
    output.write_char(',')
  }
  false
}

///|
fn write_update_paragraph_request(
  start_index : Int,
  end_index : Int,
  style : @pumd.ParagraphStyle,
  tab_id : String?,
  output : StringBuilder,
  first : Bool,
) -> Bool {
  let next_first = begin_request(output, first)
  output.write_string("{\"updateParagraphStyle\":{\"range\":")
  write_range(start_index, end_index, tab_id, output)
  output.write_string(",\"paragraphStyle\":")
  write_paragraph_style(style, output)
  output.write_string(",\"fields\":")
  write_json_string(paragraph_style_fields(style), output)
  output.write_string("}}")
  // Font family and size are text properties in the Docs REST schema, while
  // the desired paragraph style intentionally owns the corresponding profile
  // defaults. Lower them as the companion native text-style update.
  write_update_paragraph_text_style_request(
    start_index, end_index, style, tab_id, output, next_first,
  )
}

///|
fn write_update_paragraph_text_style_request(
  start_index : Int,
  end_index : Int,
  style : @pumd.ParagraphStyle,
  tab_id : String?,
  output : StringBuilder,
  first : Bool,
) -> Bool {
  let next_first = begin_request(output, first)
  output.write_string("{\"updateTextStyle\":{\"range\":")
  write_range(start_index, end_index, tab_id, output)
  output.write_string(",\"textStyle\":{\"weightedFontFamily\":{\"fontFamily\":")
  write_json_string(style.font_family, output)
  output.write_string("},\"fontSize\":")
  write_dimension(style.font_size_points, output)
  output.write_string("},\"fields\":\"weightedFontFamily,fontSize\"}}")
  next_first
}

///|
fn write_update_paragraph_decoration_request(
  start_index : Int,
  end_index : Int,
  style : @pumd.ParagraphStyle,
  tab_id : String?,
  output : StringBuilder,
  first : Bool,
) -> Bool {
  let next_first = begin_request(output, first)
  let decoration = StringBuilder::new()
  let fields = write_paragraph_decoration(style, decoration)
  output.write_string("{\"updateParagraphStyle\":{\"range\":")
  write_range(start_index, end_index, tab_id, output)
  output.write_string(",\"paragraphStyle\":")
  output.write_string(decoration.to_string())
  output.write_string(",\"fields\":")
  write_json_string(fields, output)
  output.write_string("}}")
  next_first
}

///|
fn write_update_text_request(
  start_index : Int,
  end_index : Int,
  style : @pumd.TextStyle,
  link : @pumd.LinkIntent?,
  tab_id : String?,
  output : StringBuilder,
  first : Bool,
) -> Bool {
  let next_first = begin_request(output, first)
  let text_style = StringBuilder::new()
  let fields = write_text_style(style, link, text_style)
  output.write_string("{\"updateTextStyle\":{\"range\":")
  write_range(start_index, end_index, tab_id, output)
  output.write_string(",\"textStyle\":")
  output.write_string(text_style.to_string())
  output.write_string(",\"fields\":")
  write_json_string(fields, output)
  output.write_string("}}")
  next_first
}

///|
fn write_update_foreground_color_request(
  start_index : Int,
  end_index : Int,
  color : String,
  tab_id : String?,
  output : StringBuilder,
  first : Bool,
) -> Bool {
  let color_json = StringBuilder::new()
  if !write_rgb_color(color, color_json) { return first }
  let next_first = begin_request(output, first)
  output.write_string("{\"updateTextStyle\":{\"range\":")
  write_range(start_index, end_index, tab_id, output)
  output.write_string(",\"textStyle\":{\"foregroundColor\":")
  output.write_string(color_json.to_string())
  output.write_string("},\"fields\":\"foregroundColor\"}}")
  next_first
}

///|
fn write_update_cell_background_request(
  layout : TableLayout,
  row : Int,
  column : Int,
  color : String,
  tab_id : String?,
  output : StringBuilder,
  first : Bool,
) -> Bool {
  let color_json = StringBuilder::new()
  if !write_rgb_color(color, color_json) {
    return first
  }
  let next_first = begin_request(output, first)
  output.write_string(
    "{\"updateTableCellStyle\":{\"tableRange\":{\"tableCellLocation\":{\"tableStartLocation\":",
  )
  write_location(layout.location + 1, tab_id, output)
  output.write_string(",\"rowIndex\":")
  output.write_string(row.to_string())
  output.write_string(",\"columnIndex\":")
  output.write_string(column.to_string())
  output.write_string(
    "},\"rowSpan\":1,\"columnSpan\":1},\"tableCellStyle\":{\"backgroundColor\":",
  )
  output.write_string(color_json.to_string())
  output.write_string("},\"fields\":\"backgroundColor\"}}")
  next_first
}

///|
fn lower_plan_for_tab(plan : DocsUpdatePlan, tab_id : String?) -> String {
  let output = StringBuilder::new()
  let layouts : Array[TableLayout] = []
  let insertions : Array[CellInsertion] = []
  output.write_string("{\"requests\":[")
  let mut first = true
  for request in plan.requests {
    match request {
      InsertText(index~, text~) => {
        first = begin_request(output, first)
        output.write_string("{\"insertText\":{\"location\":")
        write_location(index, tab_id, output)
        output.write_string(",\"text\":")
        write_json_string(text, output)
        output.write_string("}}")
      }
      UpdateParagraphStyle(start_index~, end_index~, style~) =>
        first = write_update_paragraph_request(
          start_index, end_index, style, tab_id, output, first,
        )
      UpdateParagraphDecoration(start_index~, end_index~, style~) =>
        first = write_update_paragraph_decoration_request(
          start_index, end_index, style, tab_id, output, first,
        )
      CreateParagraphBullets(start_index~, end_index~, bullet~) => {
        first = begin_request(output, first)
        output.write_string("{\"createParagraphBullets\":{\"range\":")
        write_range(start_index, end_index, tab_id, output)
        output.write_string(",\"bulletPreset\":")
        write_json_string(bullet_preset(bullet), output)
        output.write_string("}}")
      }
      UpdateTextStyle(start_index~, end_index~, style~, link~) =>
        first = write_update_text_request(
          start_index, end_index, style, link, tab_id, output, first,
        )
      UpdateTextForegroundColor(start_index~, end_index~, color~) =>
        first = write_update_foreground_color_request(
          start_index, end_index, color, tab_id, output, first,
        )
      InsertInlineImage(index~, image~) => {
        first = begin_request(output, first); output.write_string("{\"insertInlineImage\":{\"uri\":"); write_json_string(image.source_url, output); output.write_string(",\"location\":"); write_location(index, tab_id, output); output.write_string("}}")
      }
      InsertTable(index~, rows~, columns~) => {
        let location = index
        layouts.push({ logical_index: index, location, columns })
        first = begin_request(output, first)
        output.write_string("{\"insertTable\":{\"rows\":")
        output.write_string(rows.to_string())
        output.write_string(",\"columns\":")
        output.write_string(columns.to_string())
        output.write_string(",\"location\":")
        write_location(location, tab_id, output)
        output.write_string("}}")
      }
      InsertTableCellText(table_index~, row~, column~, text~) =>
        match lookup_table(layouts, table_index) {
          Some(layout) => {
            let index = resolve_cell_index(layout, row, column, insertions)
            first = begin_request(output, first)
            output.write_string("{\"insertText\":{\"location\":")
            write_location(index, tab_id, output)
            output.write_string(",\"text\":")
            write_json_string(text, output)
            output.write_string("}}")
            insertions.push({
              table_index,
              row,
              column,
              width: advance_google_docs_index(index=0, text~),
            })
          }
          None => ()
        }
      UpdateTableCellStyle(
        table_index~,
        row~,
        column~,
        alignment~,
        background_color~
      ) =>
        match lookup_table(layouts, table_index) {
          Some(layout) => {
            match background_color {
              Some(color) =>
                first = write_update_cell_background_request(
                  layout, row, column, color, tab_id, output, first,
                )
              None => ()
            }
            let cell_start = resolve_cell_index(layout, row, column, insertions)
            let cell_end = cell_start +
              1 +
              cell_inserted_width(layout, row, column, insertions)
            first = begin_request(output, first)
            output.write_string("{\"updateParagraphStyle\":{\"range\":")
            write_range(cell_start, cell_end, tab_id, output)
            output.write_string(",\"paragraphStyle\":{\"alignment\":")
            write_json_string(table_alignment(alignment), output)
            output.write_string("},\"fields\":\"alignment\"}}")
          }
          None => ()
        }
      UpdateTableCellParagraphStyle(
        table_index~,
        row~,
        column~,
        start_offset~,
        end_offset~,
        style~
      ) =>
        match lookup_table(layouts, table_index) {
          Some(layout) => {
            let cell_start = resolve_cell_index(layout, row, column, insertions)
            first = write_update_paragraph_request(
              cell_start + start_offset,
              cell_start + end_offset,
              style,
              tab_id,
              output,
              first,
            )
          }
          None => ()
        }
      UpdateTableCellTextStyle(
        table_index~,
        row~,
        column~,
        start_offset~,
        end_offset~,
        style~,
        link~
      ) =>
        match lookup_table(layouts, table_index) {
          Some(layout) => {
            let cell_start = resolve_cell_index(layout, row, column, insertions)
            first = write_update_text_request(
              cell_start + start_offset,
              cell_start + end_offset,
              style,
              link,
              tab_id,
              output,
              first,
            )
          }
          None => ()
        }
      DeleteContentRange(start_index~, end_index~) => {
        first = begin_request(output, first)
        output.write_string("{\"deleteContentRange\":{\"range\":")
        write_range(start_index, end_index, tab_id, output)
        output.write_string("}}")
      }
    }
  }
  output.write_string("]}")
  output.to_string()
}

///|
fn lower_plan(plan : DocsUpdatePlan) -> String {
  lower_plan_for_tab(plan, None)
}

///|
pub fn lower_update_plan(plan : DocsUpdatePlan, tab_id : String) -> String {
  lower_plan_for_tab(plan, Some(tab_id))
}

///|
async fn send_post(
  client : @google_core.GoogleClient,
  url : String,
  body : String,
) -> Result[@google_http.HttpResponse, DocsAdapterError] {
  let request = @google_http.HttpRequest::new(
    url,
    @google_http.HttpMethod::POST,
    { "Content-Type": "application/json" },
    body=Some(body),
  )
  let response = client.request(request) catch {
    @google_http.HttpError::NetworkError(message) =>
      return Err(AdapterTransport(message))
    @google_http.HttpError::TimeoutError(message) =>
      return Err(AdapterTransport(message))
    @google_http.HttpError::InvalidUrl(message) =>
      return Err(AdapterTransport(message))
  }
  if response.status_code < 200 || response.status_code >= 300 {
    Err(
      AdapterHttpStatus(
        status=response.status_code,
        kind=safe_google_error_kind(response.status_code, response.body),
      ),
    )
  } else {
    Ok(response)
  }
}

///|
async fn send_get(
  client : @google_core.GoogleClient,
  url : String,
) -> Result[@google_http.HttpResponse, DocsAdapterError] {
  let request = @google_http.HttpRequest::new(
    url,
    @google_http.HttpMethod::GET,
    {},
  )
  let response = client.request(request) catch {
    @google_http.HttpError::NetworkError(message) =>
      return Err(AdapterTransport(message))
    @google_http.HttpError::TimeoutError(message) =>
      return Err(AdapterTransport(message))
    @google_http.HttpError::InvalidUrl(message) =>
      return Err(AdapterTransport(message))
  }
  if response.status_code < 200 || response.status_code >= 300 {
    Err(
      AdapterHttpStatus(
        status=response.status_code,
        kind=safe_google_error_kind(response.status_code, response.body),
      ),
    )
  } else {
    Ok(response)
  }
}

///|
pub async fn create_document(
  client : @google_core.GoogleClient,
  title : String,
) -> Result[String, DocsAdapterError] {
  let body = StringBuilder::new()
  body.write_string("{\"title\":")
  write_json_string(title, body)
  body.write_char('}')
  let response = send_post(
    client,
    "https://docs.googleapis.com/v1/documents",
    body.to_string(),
  )
  match response {
    Ok(response) => {
      let document = @json.parse(response.body) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      let decoded : CreatedDocumentResponse = @json.from_json(document) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      if decoded.documentId.is_empty() {
        Err(
          AdapterDecode("Google Docs create response has an empty documentId"),
        )
      } else {
        Ok(decoded.documentId)
      }
    }
    Err(error) => Err(error)
  }
}

///|
/// Create a document and retain the initially established tab as its Managed Tab.
pub async fn create_document_with_managed_tab(
  client : @google_core.GoogleClient,
  title : String,
) -> Result[CreatedDocument, DocsAdapterError] {
  let body = StringBuilder::new()
  body.write_string("{\"title\":")
  write_json_string(title, body)
  body.write_char('}')
  let response = send_post(
    client,
    "https://docs.googleapis.com/v1/documents",
    body.to_string(),
  )
  let decoded = match response {
    Ok(response) => {
      let document = @json.parse(response.body) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      let decoded : TabbedDocumentResponse = @json.from_json(document) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      decoded
    }
    Err(error) => return Err(error)
  }
  if decoded.documentId.is_empty() {
    return Err(
      AdapterDecode("Google Docs create response has an empty documentId"),
    )
  }
  match decoded.tabs {
    Some(tabs) =>
      match first_managed_tab(tabs) {
        Some(tab_id) =>
          Ok({ document_id: decoded.documentId, managed_tab_id: tab_id })
        None => resolve_managed_tab(client, decoded.documentId)
      }
    None => resolve_managed_tab(client, decoded.documentId)
  }
}

///|
fn first_managed_tab(tabs : Array[DocumentTabResponse]) -> String? {
  for tab in tabs {
    match tab.tabProperties {
      Some(properties) if !properties.tabId.is_empty() =>
        return Some(properties.tabId)
      _ => ()
    }
  }
  None
}

///|
async fn resolve_managed_tab(
  client : @google_core.GoogleClient,
  document_id : String,
) -> Result[CreatedDocument, DocsAdapterError] {
  match get_document_view(client, document_id) {
    Ok(view) if !view.tab_ids.is_empty() =>
      Ok({ document_id, managed_tab_id: view.tab_ids[0] })
    Ok(_) => Err(AdapterDecode("created document has no managed tab"))
    Err(error) => Err(error)
  }
}

///|
pub async fn batch_update_document(
  client : @google_core.GoogleClient,
  document_id : String,
  plan : DocsUpdatePlan,
) -> Result[Unit, DocsAdapterError] {
  let response = send_post(
    client,
    "https://docs.googleapis.com/v1/documents/" + document_id + ":batchUpdate",
    lower_plan(plan),
  )
  match response {
    Ok(response) => {
      let _ = @json.parse(response.body) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
/// Populates a recorded Managed Tab without relying on Google Docs' implicit
/// first-tab routing.
pub async fn batch_update_document_in_tab(
  client : @google_core.GoogleClient,
  document_id : String,
  tab_id : String,
  plan : DocsUpdatePlan,
) -> Result[Unit, DocsAdapterError] {
  let response = send_post(
    client,
    "https://docs.googleapis.com/v1/documents/" + document_id + ":batchUpdate",
    lower_update_plan(plan, tab_id),
  )
  match response {
    Ok(response) => {
      let _ = @json.parse(response.body) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
fn lower_update_plan_with_revision(
  plan : DocsUpdatePlan,
  tab_id : String,
  required_revision_id : String,
) -> String {
  let lowered = lower_update_plan(plan, tab_id)
  let body = StringBuilder::new()
  body.write_string(lowered[:lowered.length() - 1].to_owned())
  body.write_string(",\"writeControl\":{\"requiredRevisionId\":")
  write_json_string(required_revision_id, body)
  body.write_string("}}")
  body.to_string()
}

///|
pub async fn batch_update_document_with_revision(
  client : @google_core.GoogleClient,
  document_id : String,
  tab_id : String,
  plan : DocsUpdatePlan,
  required_revision_id : String,
) -> Result[Unit, UpdateBatchError] {
  let url = "https://docs.googleapis.com/v1/documents/" +
    document_id +
    ":batchUpdate"
  let request = @google_http.HttpRequest::new(
    url,
    @google_http.HttpMethod::POST,
    { "Content-Type": "application/json" },
    body=Some(
      lower_update_plan_with_revision(plan, tab_id, required_revision_id),
    ),
  )
  let response = client.request(request) catch {
    @google_http.HttpError::NetworkError(message) =>
      return Err(Adapter(AdapterTransport(message)))
    @google_http.HttpError::TimeoutError(message) =>
      return Err(Adapter(AdapterTransport(message)))
    @google_http.HttpError::InvalidUrl(message) =>
      return Err(Adapter(AdapterTransport(message)))
  }
  if response.status_code == 400 {
    return Err(RevisionConflict)
  }
  if response.status_code < 200 || response.status_code >= 300 {
    return Err(
      Adapter(
        AdapterHttpStatus(
          status=response.status_code,
          kind=safe_google_error_kind(response.status_code, response.body),
        ),
      ),
    )
  }
  let _ = @json.parse(response.body) catch {
    error => return Err(Adapter(AdapterDecode(error.to_string())))
  }
  Ok(())
}

///|
/// Retrieves the document after publication for opt-in live verification.
/// `includeTabsContent=true` ensures the native body is present in the raw
/// response for documents using the current Google Docs tab model.
pub async fn get_document(
  client : @google_core.GoogleClient,
  document_id : String,
) -> Result[RetrievedDocument, DocsAdapterError] {
  let response = send_get(
    client,
    "https://docs.googleapis.com/v1/documents/" +
    document_id +
    "?includeTabsContent=true",
  )
  match response {
    Ok(response) => {
      let document = @json.parse(response.body) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      let decoded : CreatedDocumentResponse = @json.from_json(document) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      if decoded.documentId.is_empty() {
        Err(AdapterDecode("Google Docs get response has an empty documentId"))
      } else {
        Ok({ document_id: decoded.documentId, body: response.body })
      }
    }
    Err(error) => Err(error)
  }
}

///|
/// Retrieves a document body with suggested edits represented inline.
pub async fn get_remote_document_body(
  client : @google_core.GoogleClient,
  document_id : String,
) -> Result[RetrievedDocument, DocsAdapterError] {
  let response = send_get(
    client,
    "https://docs.googleapis.com/v1/documents/" +
    document_id +
    "?includeTabsContent=true&suggestionsViewMode=SUGGESTIONS_INLINE",
  )
  match response {
    Ok(response) => {
      let document = @json.parse(response.body) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      let decoded : CreatedDocumentResponse = @json.from_json(document) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      if decoded.documentId.is_empty() {
        Err(AdapterDecode("Google Docs get response has an empty documentId"))
      } else {
        Ok({ document_id: decoded.documentId, body: response.body })
      }
    }
    Err(error) => Err(error)
  }
}

///|
/// Retrieve a document's identity, title, and tab identifiers.
pub async fn get_document_view(
  client : @google_core.GoogleClient,
  document_id : String,
) -> Result[RemoteDocumentView, DocsAdapterError] {
  let response = send_get(
    client,
    "https://docs.googleapis.com/v1/documents/" +
    document_id +
    "?includeTabsContent=true",
  )
  match response {
    Ok(response) => {
      let document = @json.parse(response.body) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      let decoded : TabbedDocumentResponse = @json.from_json(document) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      if decoded.documentId.is_empty() {
        return Err(
          AdapterDecode("Google Docs get response has an empty documentId"),
        )
      }
      let tab_ids = []
      match decoded.tabs {
        Some(tabs) =>
          for tab in tabs {
            match tab.tabProperties {
              Some(properties) if !properties.tabId.is_empty() =>
                tab_ids.push(properties.tabId)
              _ => ()
            }
          }
        None => ()
      }
      Ok({ document_id: decoded.documentId, title: decoded.title, tab_ids })
    }
    Err(error) => Err(error)
  }
}

///|
/// Retrieve the Drive properties relevant to publication inspection.
pub async fn get_drive_file(
  client : @google_core.GoogleClient,
  document_id : String,
) -> Result[DriveFileView, DocsAdapterError] {
  let response = send_get(
    client,
    "https://www.googleapis.com/drive/v3/files/" +
    document_id +
    "?fields=id,name,trashed,capabilities(canEdit)",
  )
  match response {
    Ok(response) => {
      let file = @json.parse(response.body) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      let decoded : DriveFileResponse = @json.from_json(file) catch {
        error => return Err(AdapterDecode(error.to_string()))
      }
      if decoded.id.is_empty() {
        return Err(AdapterDecode("Google Drive get response has an empty id"))
      }
      let can_edit = match decoded.capabilities {
        Some(capabilities) => capabilities.canEdit
        None => None
      }
      Ok({
        document_id: decoded.id,
        name: decoded.name,
        trashed: decoded.trashed.unwrap_or(false),
        can_edit,
      })
    }
    Err(error) => Err(error)
  }
}
