///|
pub(all) struct SyntaxPalette {
  comment : String
  keyword : String
  string : String
  literal : String
  type_tag : String
  function : String
  property_attribute : String
} derive(Eq, @debug.Debug)

///|
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
  syntax_palette : SyntaxPalette
  table_cell : ParagraphStyle
  table_header_text : TextStyle
  table_header_fill : String
  quote_indent_per_level_points : Int
  quote_border : ParagraphBorder
} derive(Eq, @debug.Debug)

///|
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

///|
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
    indent_start_points: None,
    indent_first_line_points: None,
    border_left: None,
  }
}

///|
/// The sole version-three Style Profile.
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
    version: 3,
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
      indent_start_points: None,
      indent_first_line_points: None,
      border_left: None,
    },
    syntax_palette: {
      comment: "#5F6368",
      keyword: "#6A1B9A",
      string: "#08783F",
      literal: "#9B5200",
      type_tag: "#0057B8",
      function: "#0B57D0",
      property_attribute: "#7A3E00",
    },
    table_cell: make_paragraph_style(NamedStyle::NormalText, 11, 0, 0),
    table_header_text: { ..make_text_style("Arial", 11), bold: true },
    table_header_fill: "#F1F3F4",
    quote_indent_per_level_points: 18,
    quote_border: { color: "#B7B7B7", width_points: 1, padding_points: 6 },
  }
}
