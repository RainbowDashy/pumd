///|
fn write_escaped(value : String, buffer : StringBuilder) -> Unit {
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
fn named_style_name(style : NamedStyle) -> String {
  match style {
    NormalText => "normal"
    Heading1 => "heading-1"
    Heading2 => "heading-2"
    Heading3 => "heading-3"
    Heading4 => "heading-4"
    Heading5 => "heading-5"
    Heading6 => "heading-6"
  }
}

///|
fn write_text_style(style : TextStyle, buffer : StringBuilder) -> Unit {
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
}

///|
fn write_paragraph(
  paragraph : Paragraph,
  buffer : StringBuilder,
  indent? : String = "",
) -> Unit {
  let style = paragraph.style
  buffer.write_string(indent)
  buffer.write_string("paragraph ")
  buffer.write_string(named_style_name(style.named_style))
  buffer.write_string(" font=")
  buffer.write_string(style.font_family)
  buffer.write_string(" size=")
  buffer.write_string(style.font_size_points.to_string())
  buffer.write_string(" line=")
  if style.line_spacing_percent == 115 {
    buffer.write_string("1.15")
  } else if style.line_spacing_percent == 100 {
    buffer.write_string("1.0")
  } else {
    buffer.write_string(style.line_spacing_percent.to_string())
  }
  buffer.write_string(" before=")
  buffer.write_string(style.space_above_points.to_string())
  buffer.write_string(" after=")
  buffer.write_string(style.space_below_points.to_string())
  match style.background_color {
    Some(color) => {
      buffer.write_string(" background=")
      buffer.write_string(color)
    }
    None => ()
  }
  match paragraph.bullet {
    Some(properties) => {
      buffer.write_string(" list=")
      match properties.kind {
        Bullet => buffer.write_string("bullet")
        Numbered(start~, delimiter~) => {
          buffer.write_string("numbered(")
          buffer.write_string(start.to_string())
          buffer.write_string(delimiter)
          buffer.write_char(')')
        }
      }
      buffer.write_string(" level=")
      buffer.write_string(properties.nesting_level.to_string())
    }
    None => ()
  }
  buffer.write_char('\n')
  for run in paragraph.runs {
    buffer.write_string(indent)
    buffer.write_string("  text ")
    write_escaped(run.content, buffer)
    write_text_style(run.style, buffer)
    match run.link {
      Some(link) => {
        buffer.write_string(" link=")
        write_escaped(link.url, buffer)
        match link.title {
          Some(title) => {
            buffer.write_string(" title=")
            write_escaped(title, buffer)
          }
          None => ()
        }
      }
      None => ()
    }
    buffer.write_char('\n')
  }
}

///|
fn write_native_content(
  document : DesiredDocument,
  buffer : StringBuilder,
) -> Unit {
  for element in document.content {
    match element {
      StructuralElement::Paragraph(paragraph) =>
        write_paragraph(paragraph, buffer)
      StructuralElement::Table(table) => {
        buffer.write_string("table\n")
        for row in table.rows {
          if row.is_header {
            buffer.write_string("  header-row\n")
          } else {
            buffer.write_string("  row\n")
          }
          for cell in row.cells {
            buffer.write_string("    cell alignment=")
            match cell.alignment {
              Left => buffer.write_string("left")
              Center => buffer.write_string("center")
              Right => buffer.write_string("right")
              Unspecified => buffer.write_string("unspecified")
            }
            match cell.background_color {
              Some(color) => {
                buffer.write_string(" background=")
                buffer.write_string(color)
              }
              None => ()
            }
            buffer.write_char('\n')
            for paragraph in cell.content {
              write_paragraph(paragraph, buffer, indent="      ")
            }
          }
        }
      }
    }
  }
}

///|
/// Human-readable canonical serialization used by golden tests. Source
/// provenance is intentionally omitted.
pub fn DesiredDocument::to_snapshot(self : DesiredDocument) -> String {
  let buffer = StringBuilder::new()
  buffer.write_string("profile ")
  buffer.write_string(self.render_metadata.style_profile_id)
  buffer.write_char('@')
  buffer.write_string(self.render_metadata.style_profile_version.to_string())
  buffer.write_char('\n')
  write_native_content(self, buffer)
  buffer.to_string()
}

///|
/// Compares native content while excluding source provenance and Style Profile
/// version metadata.
pub fn DesiredDocument::semantic_eq(
  self : DesiredDocument,
  other : DesiredDocument,
) -> Bool {
  let left = StringBuilder::new()
  let right = StringBuilder::new()
  if self.metadata != other.metadata {
    return false
  }
  write_native_content(self, left)
  write_native_content(other, right)
  left.to_string() == right.to_string()
}

///|
pub impl Eq for DesiredDocument with fn equal(left, right) {
  left.semantic_eq(right)
}
