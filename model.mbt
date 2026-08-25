///|
/// A parser-provided, zero-based, end-exclusive Unicode code-point range.
/// Nested parser ranges can be relative to the fragment the parser used for
/// that node; consumers must not treat this metadata as stable identity.
pub(all) struct SourceRange {
  start : Int
  end : Int
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct DocumentMetadata {
  title : String?
  locale : String?
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
/// Renderer provenance that is deliberately outside native document content.
pub(all) struct RenderMetadata {
  style_profile_id : String
  style_profile_version : Int
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) enum NamedStyle {
  NormalText
  Title
  Heading1
  Heading2
  Heading3
  Heading4
  Heading5
  Heading6
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct TextStyle {
  font_family : String
  font_size_points : Int
  bold : Bool
  italic : Bool
  underline : Bool
  foreground_color : String?
  background_color : String?
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct ParagraphBorder {
  color : String
  width_points : Int
  padding_points : Int
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct ParagraphStyle {
  named_style : NamedStyle
  font_family : String
  font_size_points : Int
  line_spacing_percent : Int
  space_above_points : Int
  space_below_points : Int
  background_color : String?
  indent_start_points : Int?
  indent_first_line_points : Int?
  border_left : ParagraphBorder?
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct LinkIntent {
  url : String
  title : String?
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) enum ListKind {
  Bullet
  Numbered(start~ : Int, delimiter~ : String)
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct BulletProperties {
  kind : ListKind
  nesting_level : Int
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct TextRun {
  content : String
  style : TextStyle
  link : LinkIntent?
  provenance : SourceRange?
} derive(@debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct InlineImage {
  source_url : String
  alt_text : String
  title : String?
  text_offset : Int
  provenance : SourceRange?
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct Paragraph {
  runs : Array[TextRun]
  inline_images : Array[InlineImage]
  style : ParagraphStyle
  bullet : BulletProperties?
  provenance : SourceRange?
} derive(@debug.Debug, ToJson, @json.FromJson)

///|
pub(all) enum TableAlignment {
  Left
  Center
  Right
  Unspecified
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct TableCell {
  content : Array[Paragraph]
  alignment : TableAlignment
  background_color : String?
  provenance : SourceRange?
} derive(@debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct TableRow {
  cells : Array[TableCell]
  is_header : Bool
  provenance : SourceRange?
} derive(@debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct Table {
  rows : Array[TableRow]
  provenance : SourceRange?
} derive(@debug.Debug, ToJson, @json.FromJson)

///|
pub(all) enum StructuralElement {
  Paragraph(Paragraph)
  Table(Table)
} derive(@debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct DesiredDocument {
  metadata : DocumentMetadata
  render_metadata : RenderMetadata
  content : Array[StructuralElement]
  provenance : SourceRange?
} derive(@debug.Debug, ToJson, @json.FromJson)

///|
pub(all) enum DiagnosticKind {
  UnsupportedConstruct
  MissingDefinition
} derive(Eq, @debug.Debug)

///|
pub(all) struct RenderingDiagnostic {
  kind : DiagnosticKind
  node_kind : String
  provenance : SourceRange?
  message : String
} derive(Eq, @debug.Debug)
