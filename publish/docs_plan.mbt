///|
/// A transport-independent Google Docs update plan.  The adapter that owns
/// googleapis can lower these operations to wire requests without teaching the
/// renderer about HTTP or generated API types.
pub enum DocsUpdateRequest {
  InsertText(index~ : Int, text~ : String)
  UpdateParagraphStyle(
    start_index~ : Int,
    end_index~ : Int,
    style~ : @pumd.ParagraphStyle
  )
  CreateParagraphBullets(
    start_index~ : Int,
    end_index~ : Int,
    bullet~ : @pumd.BulletProperties
  )
  UpdateTextStyle(
    start_index~ : Int,
    end_index~ : Int,
    style~ : @pumd.TextStyle,
    link~ : @pumd.LinkIntent?
  )
  InsertTable(index~ : Int, rows~ : Int, columns~ : Int)
  InsertTableCellText(
    table_index~ : Int,
    row~ : Int,
    column~ : Int,
    text~ : String
  )
  UpdateTableCellStyle(
    table_index~ : Int,
    row~ : Int,
    column~ : Int,
    alignment~ : @pumd.TableAlignment,
    background_color~ : String?
  )
  UpdateTableCellParagraphStyle(
    table_index~ : Int,
    row~ : Int,
    column~ : Int,
    start_offset~ : Int,
    end_offset~ : Int,
    style~ : @pumd.ParagraphStyle
  )
  UpdateTableCellTextStyle(
    table_index~ : Int,
    row~ : Int,
    column~ : Int,
    start_offset~ : Int,
    end_offset~ : Int,
    style~ : @pumd.TextStyle,
    link~ : @pumd.LinkIntent?
  )
}

///|
pub struct DocsUpdatePlan {
  requests : Array[DocsUpdateRequest]
}

///|
pub(all) enum DocsPlanError {
  EmptyTable(table_index~ : Int)
  TableWithoutColumns(table_index~ : Int)
} derive(Eq, @debug.Debug)

///|
pub fn DocsPlanError::message(self : DocsPlanError) -> String {
  match self {
    EmptyTable(table_index~) =>
      "Desired Document table " + table_index.to_string() + " has no rows"
    TableWithoutColumns(table_index~) =>
      "Desired Document table " + table_index.to_string() + " has no columns"
  }
}

///|
/// The beginning of a Google Docs body segment.  Google Docs reserves index
/// zero for the implicit document boundary.
pub let google_docs_body_start_index : Int = 1

///|
fn append_paragraph(
  paragraph : @pumd.Paragraph,
  cursor : Int,
  requests : Array[DocsUpdateRequest],
) -> Int {
  let indent = match paragraph.bullet {
    Some(bullet) => list_indent_tabs(bullet.nesting_level)
    None => ""
  }
  let text = StringBuilder::new()
  text.write_string(indent)
  for run in paragraph.runs {
    text.write_string(run.content)
  }
  text.write_char('\n')
  let inserted = text.to_string()
  let insert_end_index = advance_google_docs_index(index=cursor, text=inserted)
  let indent_end_index = advance_google_docs_index(index=cursor, text=indent)
  let mut end_index = cursor
  for run in paragraph.runs {
    end_index = advance_google_docs_index(index=end_index, text=run.content)
  }
  end_index = advance_google_docs_index(index=end_index, text="\n")
  requests.push(InsertText(index=cursor, text=inserted))
  requests.push(
    UpdateParagraphStyle(
      start_index=cursor,
      end_index=insert_end_index,
      style=paragraph.style,
    ),
  )
  let mut run_start = indent_end_index
  for run in paragraph.runs {
    let run_end = advance_google_docs_index(index=run_start, text=run.content)
    if run_start != run_end {
      requests.push(
        UpdateTextStyle(
          start_index=run_start,
          end_index=run_end,
          style=run.style,
          link=run.link,
        ),
      )
    }
    run_start = run_end
  }
  match paragraph.bullet {
    Some(bullet) =>
      // Adapter contract: emit this operation in plan order and map the list
      // kind to a Docs bullet preset. Google Docs derives nesting from the
      // leading tabs already inserted above and consumes them here. Keep this
      // last: every earlier request uses pre-consumption indexes, while the
      // returned cursor uses the post-consumption index for the next paragraph.
      requests.push(
        CreateParagraphBullets(
          start_index=cursor,
          end_index=insert_end_index,
          bullet~,
        ),
      )
    None => ()
  }
  end_index
}

///|
/// Google Docs uses one leading tab per nesting level when creating native
/// bullets. The tab sequence is intentionally part of InsertText and is later
/// consumed by CreateParagraphBullets.
fn list_indent_tabs(nesting_level : Int) -> String {
  if nesting_level <= 0 {
    ""
  } else {
    "\t" + list_indent_tabs(nesting_level - 1)
  }
}

///|
fn append_table_cell(
  table_index : Int,
  row : Int,
  column : Int,
  cell : @pumd.TableCell,
  requests : Array[DocsUpdateRequest],
) -> Int {
  let text = StringBuilder::new()
  for paragraph_index, paragraph in cell.content {
    if paragraph_index > 0 {
      text.write_char('\n')
    }
    for run in paragraph.runs {
      text.write_string(run.content)
    }
  }
  let inserted = text.to_string()
  requests.push(InsertTableCellText(table_index~, row~, column~, text=inserted))
  let mut paragraph_start = 0
  for paragraph in cell.content {
    let mut paragraph_end = paragraph_start + 1
    for run in paragraph.runs {
      paragraph_end = advance_google_docs_index(
        index=paragraph_end,
        text=run.content,
      )
    }
    requests.push(
      UpdateTableCellParagraphStyle(
        table_index~,
        row~,
        column~,
        start_offset=paragraph_start,
        end_offset=paragraph_end,
        style=paragraph.style,
      ),
    )
    let mut run_start = paragraph_start
    for run in paragraph.runs {
      let run_end = advance_google_docs_index(index=run_start, text=run.content)
      if run_start != run_end {
        requests.push(
          UpdateTableCellTextStyle(
            table_index~,
            row~,
            column~,
            start_offset=run_start,
            end_offset=run_end,
            style=run.style,
            link=run.link,
          ),
        )
      }
      run_start = run_end
    }
    paragraph_start = paragraph_end
  }
  // Named paragraph styles can reset alignment, so apply the cell's alignment
  // only after every paragraph style in the cell has been established.
  requests.push(
    UpdateTableCellStyle(
      table_index~,
      row~,
      column~,
      alignment=cell.alignment,
      background_color=cell.background_color,
    ),
  )
  advance_google_docs_index(index=0, text=inserted)
}

///|
fn append_table(
  table : @pumd.Table,
  cursor : Int,
  requests : Array[DocsUpdateRequest],
) -> Int {
  let mut columns = 0
  for row in table.rows {
    if row.cells.length() > columns {
      columns = row.cells.length()
    }
  }
  requests.push(InsertTable(index=cursor, rows=table.rows.length(), columns~))
  let mut inserted_text_width = 0
  for row_index, row in table.rows {
    for column_index, cell in row.cells {
      inserted_text_width += append_table_cell(
        cursor, row_index, column_index, cell, requests,
      )
    }
  }
  // InsertTable adds one preceding newline. Its first cell begins four code
  // units after the location; every cell takes two structural units and every
  // later row adds one. The final two units close the last cell/table. Cell
  // text is inserted into those cells and increases the following body index
  // by its UTF-16 width.
  let empty_table_width = table.rows.length() * (columns * 2 + 1) + 3
  cursor + empty_table_width + inserted_text_width
}

///|
/// Compiles the Desired Document into deterministic append-only updates. Table
/// cell formatting is anchored to a table coordinate, because Google assigns
/// the physical cell indexes as part of inserting that table.
pub fn compile_docs_update_plan(
  document : @pumd.DesiredDocument,
) -> DocsUpdatePlan {
  let requests : Array[DocsUpdateRequest] = []
  let mut cursor = google_docs_body_start_index
  for element in document.content {
    match element {
      @pumd.StructuralElement::Paragraph(paragraph) =>
        cursor = append_paragraph(paragraph, cursor, requests)
      @pumd.StructuralElement::Table(table) =>
        cursor = append_table(table, cursor, requests)
    }
  }
  { requests, }
}

///|
/// Validates the Desired Document structures required by the Docs API before
/// compiling any remote write. This remains separate from rendering so the
/// renderer never owns API indexes or request ordering.
pub fn prepare_docs_update_plan(
  document : @pumd.DesiredDocument,
) -> Result[DocsUpdatePlan, DocsPlanError] {
  let mut table_index = 0
  for element in document.content {
    match element {
      @pumd.StructuralElement::Paragraph(_) => ()
      @pumd.StructuralElement::Table(table) => {
        if table.rows.is_empty() {
          return Err(EmptyTable(table_index~))
        }
        let mut columns = 0
        for row in table.rows {
          if row.cells.length() > columns {
            columns = row.cells.length()
          }
        }
        if columns == 0 {
          return Err(TableWithoutColumns(table_index~))
        }
        table_index = table_index + 1
      }
    }
  }
  Ok(compile_docs_update_plan(document))
}

///|
fn write_plan_escaped(value : String, buffer : StringBuilder) -> Unit {
  buffer.write_char('"')
  for char in value {
    match char {
      '"' => buffer.write_string("\\\"")
      '\\' => buffer.write_string("\\\\")
      '\n' => buffer.write_string("\\n")
      '\r' => buffer.write_string("\\r")
      '\t' => buffer.write_string("\\t")
      _ => buffer.write_char(char)
    }
  }
  buffer.write_char('"')
}

///|
fn write_plan_paragraph_style(
  style : @pumd.ParagraphStyle,
  buffer : StringBuilder,
) -> Unit {
  match style.named_style {
    NormalText => buffer.write_string("normal")
    Heading1 => buffer.write_string("heading-1")
    Heading2 => buffer.write_string("heading-2")
    Heading3 => buffer.write_string("heading-3")
    Heading4 => buffer.write_string("heading-4")
    Heading5 => buffer.write_string("heading-5")
    Heading6 => buffer.write_string("heading-6")
  }
  buffer.write_string(" font=")
  buffer.write_string(style.font_family)
  buffer.write_string(" size=")
  buffer.write_string(style.font_size_points.to_string())
  buffer.write_string(" line=")
  buffer.write_string(style.line_spacing_percent.to_string())
  buffer.write_string(" before=")
  buffer.write_string(style.space_above_points.to_string())
  buffer.write_string(" after=")
  buffer.write_string(style.space_below_points.to_string())
}

///|
fn write_bullet_properties(
  bullet : @pumd.BulletProperties,
  buffer : StringBuilder,
) -> Unit {
  match bullet.kind {
    Bullet => buffer.write_string("bullet")
    Numbered(start~, delimiter~) => {
      buffer.write_string("numbered(")
      buffer.write_string(start.to_string())
      buffer.write_string(delimiter)
      buffer.write_char(')')
    }
  }
  buffer.write_string(" level=")
  buffer.write_string(bullet.nesting_level.to_string())
}

///|
fn write_table_alignment(
  alignment : @pumd.TableAlignment,
  buffer : StringBuilder,
) -> Unit {
  match alignment {
    Left => buffer.write_string("left")
    Center => buffer.write_string("center")
    Right => buffer.write_string("right")
    Unspecified => buffer.write_string("unspecified")
  }
}

///|
fn write_table_cell_target(
  table_index : Int,
  row : Int,
  column : Int,
  buffer : StringBuilder,
) -> Unit {
  buffer.write_string("table=")
  buffer.write_string(table_index.to_string())
  buffer.write_string(" row=")
  buffer.write_string(row.to_string())
  buffer.write_string(" column=")
  buffer.write_string(column.to_string())
}

///|
fn write_plan_text_style(
  style : @pumd.TextStyle,
  link : @pumd.LinkIntent?,
  buffer : StringBuilder,
) -> Unit {
  if style.bold {
    buffer.write_string(" bold")
  }
  if style.italic {
    buffer.write_string(" italic")
  }
  if style.underline {
    buffer.write_string(" underline")
  }
  buffer.write_string(" font=")
  buffer.write_string(style.font_family)
  buffer.write_string(" size=")
  buffer.write_string(style.font_size_points.to_string())
  match style.foreground_color {
    Some(color) => {
      buffer.write_string(" color=")
      buffer.write_string(color)
    }
    None => ()
  }
  match style.background_color {
    Some(color) => {
      buffer.write_string(" background=")
      buffer.write_string(color)
    }
    None => ()
  }
  match link {
    Some(intent) => {
      buffer.write_string(" link=")
      write_plan_escaped(intent.url, buffer)
      match intent.title {
        Some(title) => {
          buffer.write_string(" title=")
          write_plan_escaped(title, buffer)
        }
        None => ()
      }
    }
    None => ()
  }
}

///|
pub fn DocsUpdatePlan::to_snapshot(self : DocsUpdatePlan) -> String {
  let buffer = StringBuilder::new()
  for request in self.requests {
    match request {
      InsertText(index~, text~) => {
        buffer.write_string("insert-text ")
        buffer.write_string(index.to_string())
        buffer.write_char(' ')
        write_plan_escaped(text, buffer)
      }
      UpdateParagraphStyle(start_index~, end_index~, style~) => {
        buffer.write_string("paragraph-style ")
        buffer.write_string(start_index.to_string())
        buffer.write_string("..")
        buffer.write_string(end_index.to_string())
        buffer.write_char(' ')
        write_plan_paragraph_style(style, buffer)
      }
      CreateParagraphBullets(start_index~, end_index~, bullet~) => {
        buffer.write_string("paragraph-bullets ")
        buffer.write_string(start_index.to_string())
        buffer.write_string("..")
        buffer.write_string(end_index.to_string())
        buffer.write_char(' ')
        write_bullet_properties(bullet, buffer)
      }
      UpdateTextStyle(start_index~, end_index~, style~, link~) => {
        buffer.write_string("text-style ")
        buffer.write_string(start_index.to_string())
        buffer.write_string("..")
        buffer.write_string(end_index.to_string())
        write_plan_text_style(style, link, buffer)
      }
      InsertTable(index~, rows~, columns~) => {
        buffer.write_string("insert-table ")
        buffer.write_string(index.to_string())
        buffer.write_string(" rows=")
        buffer.write_string(rows.to_string())
        buffer.write_string(" columns=")
        buffer.write_string(columns.to_string())
      }
      InsertTableCellText(table_index~, row~, column~, text~) => {
        buffer.write_string("insert-cell-text ")
        write_table_cell_target(table_index, row, column, buffer)
        buffer.write_char(' ')
        write_plan_escaped(text, buffer)
      }
      UpdateTableCellStyle(
        table_index~,
        row~,
        column~,
        alignment~,
        background_color~
      ) => {
        buffer.write_string("cell-style ")
        write_table_cell_target(table_index, row, column, buffer)
        buffer.write_string(" alignment=")
        write_table_alignment(alignment, buffer)
        match background_color {
          Some(color) => {
            buffer.write_string(" background=")
            buffer.write_string(color)
          }
          None => ()
        }
      }
      UpdateTableCellParagraphStyle(
        table_index~,
        row~,
        column~,
        start_offset~,
        end_offset~,
        style~
      ) => {
        buffer.write_string("cell-paragraph-style ")
        write_table_cell_target(table_index, row, column, buffer)
        buffer.write_char(' ')
        buffer.write_string(start_offset.to_string())
        buffer.write_string("..")
        buffer.write_string(end_offset.to_string())
        buffer.write_char(' ')
        write_plan_paragraph_style(style, buffer)
      }
      UpdateTableCellTextStyle(
        table_index~,
        row~,
        column~,
        start_offset~,
        end_offset~,
        style~,
        link~
      ) => {
        buffer.write_string("cell-text-style ")
        write_table_cell_target(table_index, row, column, buffer)
        buffer.write_char(' ')
        buffer.write_string(start_offset.to_string())
        buffer.write_string("..")
        buffer.write_string(end_offset.to_string())
        write_plan_text_style(style, link, buffer)
      }
    }
    buffer.write_char('\n')
  }
  buffer.to_string()
}
