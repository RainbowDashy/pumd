///|
fn markdown_repeat(text : String, count : Int) -> String {
  let output = StringBuilder::new()
  for index = 0; index < count; index = index + 1 {
    output.write_string(text)
  }
  output.to_string()
}

///|
fn markdown_escape(text : String, table_cell : Bool) -> String {
  let output = StringBuilder::new()
  for char in text {
    if char == '\\' || char == '*' || char == '_' || char == '`' ||
      char == '[' || char == ']' || (table_cell && char == '|') {
      output.write_char('\\')
    }
    if char == '\n' {
      output.write_string(if table_cell { "<br>" } else { " " })
    } else {
      output.write_char(char)
    }
  }
  output.to_string()
}

///|
fn serialize_semantic_run(run : SourceSemanticRun, table_cell : Bool) -> String {
  let mut text = markdown_escape(run.text, table_cell)
  if run.code {
    let fence = if run.text.contains("`") { "``" } else { "`" }
    text = fence + run.text + fence
  }
  if run.bold { text = "**" + text + "**" }
  if run.italic { text = "*" + text + "*" }
  match run.link { Some(url) => text = "[" + text + "](" + url + ")"; None => () }
  text
}

///|
fn serialize_semantic_inline(paragraph : SourceSemanticParagraph, table_cell : Bool) -> String {
  let output = StringBuilder::new()
  let mut offset = 0
  for run in paragraph.runs {
    for image in paragraph.images {
      if image.text_offset == offset { output.write_string("![](" + image.source_url + ")") }
    }
    output.write_string(serialize_semantic_run(run, table_cell))
    offset = offset + run.text.length()
  }
  for image in paragraph.images {
    if image.text_offset >= offset { output.write_string("![](" + image.source_url + ")") }
  }
  output.to_string()
}

///|
fn serialize_semantic_paragraph(
  paragraph : SourceSemanticParagraph,
  newline : String,
  table_cell : Bool,
) -> String {
  if paragraph.code_block {
    return "```" + newline + serialize_semantic_inline(paragraph, false) + newline + "```"
  }
  let prefix = StringBuilder::new()
  prefix.write_string(markdown_repeat("> ", paragraph.quote_depth))
  match paragraph.list {
    Some(Bullet) => {
      prefix.write_string(markdown_repeat("  ", paragraph.nesting_level))
      prefix.write_string("- ")
    }
    Some(Numbered) => {
      prefix.write_string(markdown_repeat("  ", paragraph.nesting_level))
      prefix.write_string("1. ")
    }
    None if paragraph.heading > 0 => {
      prefix.write_string(markdown_repeat("#", paragraph.heading))
      prefix.write_char(' ')
    }
    None => ()
  }
  let mut inline = serialize_semantic_inline(paragraph, table_cell)
  if paragraph.list is None && paragraph.heading == 0 && paragraph.quote_depth == 0 {
    let block_marker = inline.has_prefix("# ") || inline.has_prefix("> ") ||
      inline.has_prefix("- ") || inline.has_prefix("+ ")
    let mut ordered_marker = false
    let mut saw_digit = false
    for char in inline {
      if char >= '0' && char <= '9' {
        saw_digit = true
      } else {
        ordered_marker = saw_digit && (char == '.' || char == ')')
        break
      }
    }
    if block_marker || ordered_marker { inline = "\\" + inline }
  }
  prefix.to_string() + inline
}

///|
fn semantic_alignment(alignment : @pumd.TableAlignment) -> String {
  match alignment {
    @pumd.TableAlignment::Left => ":---"
    @pumd.TableAlignment::Center => ":---:"
    @pumd.TableAlignment::Right => "---:"
    @pumd.TableAlignment::Unspecified => "---"
  }
}

///|
fn serialize_semantic_cell(cell : SourceSemanticCell, newline : String) -> String {
  let output = StringBuilder::new()
  for index, paragraph in cell.paragraphs {
    if index > 0 { output.write_string("<br>") }
    output.write_string(serialize_semantic_paragraph(paragraph, newline, true))
  }
  output.to_string()
}

///|
fn serialize_semantic_table(table : SourceSemanticTable, newline : String) -> String {
  if table.rows.is_empty() { return "| |" + newline + "| --- |" }
  let output = StringBuilder::new()
  output.write_char('|')
  for cell in table.rows[0] {
    output.write_char(' ')
    output.write_string(serialize_semantic_cell(cell, newline))
    output.write_string(" |")
  }
  output.write_string(newline)
  output.write_char('|')
  for cell in table.rows[0] {
    output.write_char(' ')
    output.write_string(semantic_alignment(cell.alignment))
    output.write_string(" |")
  }
  for row_index = 1; row_index < table.rows.length(); row_index = row_index + 1 {
    output.write_string(newline)
    output.write_char('|')
    for cell in table.rows[row_index] {
      output.write_char(' ')
      output.write_string(serialize_semantic_cell(cell, newline))
      output.write_string(" |")
    }
  }
  output.to_string()
}

///|
pub fn serialize_source_semantic_unit(
  unit : SourceSemanticUnit,
  newline? : String = "\n",
) -> String {
  match unit {
    Paragraph(paragraph) => serialize_semantic_paragraph(paragraph, newline, false)
    Table(table) => serialize_semantic_table(table, newline)
  }
}
