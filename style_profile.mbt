pub(all) struct StyleProfile {
  id : String
  version : Int
  body : ParagraphStyle
  body_text : TextStyle
  headings : Array[ParagraphStyle]
  heading_text : Array[TextStyle]
  link_color : String
  code_text : TextStyle
  code_block : ParagraphStyle
  table_cell : ParagraphStyle
  table_header_text : TextStyle
  table_header_fill : String
} derive(Eq, @debug.Debug)

fn make_text_style(font_family : String, font_size_points : Int) -> TextStyle {
  {
    font_family,
    font_size_points,
    bold: false,
    italic: false,
    underline: false,
    foreground_color: None,
    background_color: None,
  }
}

fn make_paragraph_style(
  named_style : NamedStyle,
  font_size_points : Int,
  space_above_points : Int,
  space_below_points : Int,
) -> ParagraphStyle {
  {
    named_style,
    font_family: "Arial",
    font_size_points,
    line_spacing_percent: 115,
    space_above_points,
    space_below_points,
    background_color: None,
  }
}

/// The sole version-one Style Profile.
pub fn builtin_style_profile() -> StyleProfile {
  let heading_sizes = [24, 18, 14, 12, 11, 10]
  let heading_before = [20, 18, 16, 14, 12, 10]
  let heading_after = [8, 6, 4, 4, 3, 3]
  let named = [
    NamedStyle::Heading1,
    NamedStyle::Heading2,
    NamedStyle::Heading3,
    NamedStyle::Heading4,
    NamedStyle::Heading5,
    NamedStyle::Heading6,
  ]
  let headings : Array[ParagraphStyle] = []
  let heading_text : Array[TextStyle] = []
  for i = 0; i < 6; i = i + 1 {
    headings.push(
      make_paragraph_style(
        named[i],
        heading_sizes[i],
        heading_before[i],
        heading_after[i],
      ),
    )
    heading_text.push(make_text_style("Arial", heading_sizes[i]))
  }
  {
    id: "pumd.default",
    version: 1,
    body: make_paragraph_style(NamedStyle::NormalText, 11, 0, 6),
    body_text: make_text_style("Arial", 11),
    headings,
    heading_text,
    link_color: "#1155CC",
    code_text: {
      font_family: "Roboto Mono",
      font_size_points: 10,
      bold: false,
      italic: false,
      underline: false,
      foreground_color: None,
      background_color: Some("#F1F3F4"),
    },
    code_block: {
      named_style: NamedStyle::NormalText,
      font_family: "Roboto Mono",
      font_size_points: 10,
      line_spacing_percent: 100,
      space_above_points: 0,
      space_below_points: 0,
      background_color: Some("#F1F3F4"),
    },
    table_cell: make_paragraph_style(NamedStyle::NormalText, 11, 0, 0),
    table_header_text: { ..make_text_style("Arial", 11), bold: true },
    table_header_fill: "#F1F3F4",
  }
}
