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
fn markdown_code_delimiter(text : String) -> String {
  let mut longest_run = 0
  let mut current_run = 0
  for char in text {
    if char == '`' {
      current_run = current_run + 1
      if current_run > longest_run { longest_run = current_run }
    } else {
      current_run = 0
    }
  }
  markdown_repeat("`", longest_run + 1)
}

///|
fn markdown_link_destination(url : String) -> String {
  for char in url {
    if char == ' ' || char == '\t' || char == '(' || char == ')' || char == '\\' {
      return "<" + url + ">"
    }
  }
  url
}

///|
fn serialize_semantic_code_block(
  paragraph : SourceSemanticParagraph,
  newline : String,
) -> String {
  let content = StringBuilder::new()
  for run in paragraph.runs { content.write_string(run.text) }
  let text = content.to_string()
  let delimiter = markdown_code_delimiter(text)
  let fence = if delimiter.length() < 3 { "```" } else { delimiter }
  fence + newline + text + newline + fence
}

///|
fn serialize_semantic_run(run : SourceSemanticRun, table_cell : Bool) -> String {
  let mut text = markdown_escape(run.text, table_cell)
  if run.code {
    let fence = markdown_code_delimiter(run.text)
    let padding = if run.text.has_prefix("`") || run.text.has_suffix("`") {
      " "
    } else {
      ""
    }
    text = fence + padding + run.text + padding + fence
  }
  if run.bold { text = "**" + text + "**" }
  if run.italic { text = "*" + text + "*" }
  match run.link {
    Some(url) => text = "[" + text + "](" + markdown_link_destination(url) + ")"
    None => ()
  }
  text
}

///|
fn serialize_semantic_inline(paragraph : SourceSemanticParagraph, table_cell : Bool) -> String {
  let output = StringBuilder::new()
  let mut offset = 0
  for run in paragraph.runs {
    for image in paragraph.images {
      if image.text_offset == offset {
        output.write_string("![](" + markdown_link_destination(image.source_url) + ")")
      }
    }
    output.write_string(serialize_semantic_run(run, table_cell))
    offset = offset + run.text.length()
  }
  for image in paragraph.images {
    if image.text_offset >= offset {
      output.write_string("![](" + markdown_link_destination(image.source_url) + ")")
    }
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
    return serialize_semantic_code_block(paragraph, newline)
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
