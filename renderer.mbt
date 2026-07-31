///|
fn source_range(span : @markdown.Span) -> SourceRange {
  { start: span.from, end: span.to }
}

///|
fn unsupported(
  node_kind : String,
  span : @markdown.Span,
) -> RenderingDiagnostic {
  {
    kind: DiagnosticKind::UnsupportedConstruct,
    node_kind,
    provenance: Some(source_range(span)),
    message: "Unsupported Markdown construct: " + node_kind,
  }
}

///|
priv struct RenderContext {
  profile : StyleProfile
  definitions : Array[@markdown.LinkDefinition]
  diagnostics : Array[RenderingDiagnostic]
  content : Array[StructuralElement]
}

///|
fn with_italic(style : TextStyle) -> TextStyle {
  { ..style, italic: true }
}

///|
fn with_bold(style : TextStyle) -> TextStyle {
  { ..style, bold: true }
}

///|
fn with_link_style(style : TextStyle, profile : StyleProfile) -> TextStyle {
  { ..style, underline: true, foreground_color: Some(profile.link_color) }
}

///|
fn with_code_style(style : TextStyle, profile : StyleProfile) -> TextStyle {
  {
    ..profile.code_text,
    bold: style.bold,
    italic: style.italic,
    underline: style.underline,
    foreground_color: style.foreground_color,
  }
}

///|
fn text_run(
  content : String,
  style : TextStyle,
  link : LinkIntent?,
  span : @markdown.Span,
) -> TextRun {
  { content, style, link, provenance: Some(source_range(span)) }
}

///|
fn same_native_run(left : TextRun, right : TextRun) -> Bool {
  left.style == right.style && left.link == right.link
}

///|
fn merge_ranges(left : SourceRange?, right : SourceRange?) -> SourceRange? {
  match (left, right) {
    (Some(a), Some(b)) => Some({ start: a.start, end: b.end })
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (None, None) => None
  }
}

///|
fn canonicalize_runs(runs : Array[TextRun]) -> Array[TextRun] {
  let canonical : Array[TextRun] = []
  for run in runs {
    if !run.content.is_empty() {
      let last_index = canonical.length() - 1
      if last_index >= 0 && same_native_run(canonical[last_index], run) {
        let previous = canonical[last_index]
        canonical[last_index] = {
          content: previous.content + run.content,
          style: previous.style,
          link: previous.link,
          provenance: merge_ranges(previous.provenance, run.provenance),
        }
      } else {
        canonical.push(run)
      }
    }
  }
  canonical
}

///|
fn unescape_text(content : String) -> String {
  let buffer = StringBuilder::new()
  let mut escaped = false
  for char in content {
    if escaped {
      if @markdown.is_punctuation(char) {
        buffer.write_char(char)
      } else {
        buffer.write_char('\\')
        buffer.write_char(char)
      }
      escaped = false
    } else if char == '\\' {
      escaped = true
    } else {
      buffer.write_char(char)
    }
  }
  if escaped {
    buffer.write_char('\\')
  }
  buffer.to_string()
}

///|
fn find_definition(
  definitions : Array[@markdown.LinkDefinition],
  label : String,
) -> @markdown.LinkDefinition? {
  let wanted = label.to_lower()
  for definition in definitions {
    if definition.label.to_lower() == wanted {
      return Some(definition)
    }
  }
  None
}

///|
fn append_inline_runs(
  inlines : Array[@markdown.Inline],
  style : TextStyle,
  link : LinkIntent?,
  context : RenderContext,
  runs : Array[TextRun],
) -> Unit {
  for inline in inlines {
    match inline {
      @markdown.Inline::Text(content~, span~) =>
        runs.push(text_run(unescape_text(content), style, link, span))
      @markdown.Inline::SoftBreak(span~) =>
        runs.push(text_run(" ", style, link, span))
      @markdown.Inline::HardBreak(span~, ..) =>
        runs.push(text_run("\n", style, link, span))
      @markdown.Inline::Emphasis(children~, ..) =>
        append_inline_runs(children, with_italic(style), link, context, runs)
      @markdown.Inline::Strong(children~, ..) =>
        append_inline_runs(children, with_bold(style), link, context, runs)
      @markdown.Inline::Code(content~, span~, ..) =>
        runs.push(
          text_run(content, with_code_style(style, context.profile), link, span),
        )
      @markdown.Inline::Link(children~, url~, title~, ..) => {
        let title_intent = if title.is_empty() { None } else { Some(title) }
        append_inline_runs(
          children,
          with_link_style(style, context.profile),
          Some({ url, title: title_intent }),
          context,
          runs,
        )
      }
      @markdown.Inline::RefLink(children~, label~, span~) =>
        match find_definition(context.definitions, label) {
          Some(definition) => {
            let title = if definition.title.is_empty() {
              None
            } else {
              Some(definition.title)
            }
            append_inline_runs(
              children,
              with_link_style(style, context.profile),
              Some({ url: definition.url, title }),
              context,
              runs,
            )
          }
          None =>
            context.diagnostics.push({
              kind: DiagnosticKind::MissingDefinition,
              node_kind: "reference-link",
              provenance: Some(source_range(span)),
              message: "Missing link definition for label: " + label,
            })
        }
      @markdown.Inline::Autolink(url~, is_email~, span~) => {
        let destination = if is_email { "mailto:" + url } else { url }
        runs.push(
          text_run(
            url,
            with_link_style(style, context.profile),
            Some({ url: destination, title: None }),
            span,
          ),
        )
      }
      @markdown.Inline::Image(span~, ..) =>
        context.diagnostics.push(unsupported("image", span))
      @markdown.Inline::RefImage(span~, ..) =>
        context.diagnostics.push(unsupported("reference-image", span))
      @markdown.Inline::Strikethrough(span~, ..) =>
        context.diagnostics.push(unsupported("strikethrough", span))
      @markdown.Inline::HtmlInline(span~, ..) =>
        context.diagnostics.push(unsupported("html-inline", span))
      @markdown.Inline::WikiLink(span~, ..) =>
        context.diagnostics.push(unsupported("wiki-link", span))
      @markdown.Inline::FootnoteReference(span~, ..) =>
        context.diagnostics.push(unsupported("footnote-reference", span))
    }
  }
}

///|
fn render_inlines(
  inlines : Array[@markdown.Inline],
  style : TextStyle,
  context : RenderContext,
) -> Array[TextRun] {
  let runs : Array[TextRun] = []
  append_inline_runs(inlines, style, None, context, runs)
  canonicalize_runs(runs)
}

///|
fn heading_index(level : Int) -> Int {
  if level < 1 {
    0
  } else if level > 6 {
    5
  } else {
    level - 1
  }
}

///|
fn ordered_delimiter(delimiter : @markdown.OrderedDelimiter) -> String {
  match delimiter {
    Dot => "."
    Paren => ")"
  }
}

///|
fn table_alignment(alignment : @markdown.TableAlign) -> TableAlignment {
  match alignment {
    @markdown.TableAlign::Left => TableAlignment::Left
    @markdown.TableAlign::Center => TableAlignment::Center
    @markdown.TableAlign::Right => TableAlignment::Right
    @markdown.TableAlign::None => TableAlignment::Unspecified
  }
}

///|
fn render_table_cell(
  cell : @markdown.TableCell,
  alignment : TableAlignment,
  is_header : Bool,
  context : RenderContext,
) -> TableCell {
  let text_style = if is_header {
    context.profile.table_header_text
  } else {
    context.profile.body_text
  }
  {
    content: [
      {
        runs: render_inlines(cell.children, text_style, context),
        style: context.profile.table_cell,
        bullet: None,
        provenance: Some(source_range(cell.span)),
      },
    ],
    alignment,
    background_color: if is_header {
      Some(context.profile.table_header_fill)
    } else {
      None
    },
    provenance: Some(source_range(cell.span)),
  }
}

///|
fn render_table_row(
  cells : Array[@markdown.TableCell],
  alignments : Array[@markdown.TableAlign],
  is_header : Bool,
  context : RenderContext,
) -> TableRow {
  let desired_cells : Array[TableCell] = []
  for i, cell in cells {
    let alignment = if i < alignments.length() {
      table_alignment(alignments[i])
    } else {
      TableAlignment::Unspecified
    }
    desired_cells.push(render_table_cell(cell, alignment, is_header, context))
  }
  { cells: desired_cells, is_header, provenance: None }
}

///|
fn render_table(
  header : Array[@markdown.TableCell],
  alignments : Array[@markdown.TableAlign],
  rows : Array[Array[@markdown.TableCell]],
  span : @markdown.Span,
  context : RenderContext,
) -> Table {
  let desired_rows : Array[TableRow] = [
    render_table_row(header, alignments, true, context),
  ]
  for row in rows {
    desired_rows.push(render_table_row(row, alignments, false, context))
  }
  { rows: desired_rows, provenance: Some(source_range(span)) }
}

///|
fn render_list(
  items : Array[@markdown.ListItem],
  kind : ListKind,
  nesting_level : Int,
  context : RenderContext,
) -> Unit {
  for item in items {
    match item.checked {
      Some(_) =>
        context.diagnostics.push(unsupported("task-list-item", item.span))
      None => {
        let properties = Some({ kind, nesting_level })
        for child in item.children {
          match child {
            @markdown.Block::BulletList(items~, ..) =>
              render_list(items, ListKind::Bullet, nesting_level + 1, context)
            @markdown.Block::OrderedList(start~, delimiter~, items~, ..) =>
              render_list(
                items,
                ListKind::Numbered(
                  start~,
                  delimiter=ordered_delimiter(delimiter),
                ),
                nesting_level + 1,
                context,
              )
            _ => render_block(child, properties, context)
          }
        }
      }
    }
  }
}

///|
fn render_block(
  block : @markdown.Block,
  bullet : BulletProperties?,
  context : RenderContext,
) -> Unit {
  match block {
    @markdown.Block::Heading(level~, children~, span~, ..) => {
      let index = heading_index(level)
      let paragraph = {
        runs: render_inlines(
          children,
          context.profile.heading_text[index],
          context,
        ),
        style: context.profile.headings[index],
        bullet,
        provenance: Some(source_range(span)),
      }
      context.content.push(StructuralElement::Paragraph(paragraph))
    }
    @markdown.Block::Paragraph(children~, span~, ..) => {
      let paragraph = {
        runs: render_inlines(children, context.profile.body_text, context),
        style: context.profile.body,
        bullet,
        provenance: Some(source_range(span)),
      }
      context.content.push(StructuralElement::Paragraph(paragraph))
    }
    @markdown.Block::BulletList(items~, ..) =>
      render_list(
        items,
        ListKind::Bullet,
        match bullet {
          Some(properties) => properties.nesting_level + 1
          None => 0
        },
        context,
      )
    @markdown.Block::OrderedList(start~, delimiter~, items~, ..) =>
      render_list(
        items,
        ListKind::Numbered(start~, delimiter=ordered_delimiter(delimiter)),
        match bullet {
          Some(properties) => properties.nesting_level + 1
          None => 0
        },
        context,
      )
    @markdown.Block::BlankLines(..) => ()
    @markdown.Block::FencedCode(code~, span~, ..) => {
      let lines = code.split("\n").collect()
      for line in lines {
        let runs : Array[TextRun] = []
        if !line.is_empty() {
          runs.push(
            text_run(line.to_owned(), context.profile.code_text, None, span),
          )
        }
        context.content.push(
          StructuralElement::Paragraph({
            runs,
            style: context.profile.code_block,
            bullet,
            provenance: Some(source_range(span)),
          }),
        )
      }
    }
    @markdown.Block::Table(header~, alignments~, rows~, span~, ..) =>
      context.content.push(
        StructuralElement::Table(
          render_table(header, alignments, rows, span, context),
        ),
      )
    @markdown.Block::ThematicBreak(span~, ..) =>
      context.diagnostics.push(unsupported("thematic-break", span))
    @markdown.Block::IndentedCode(span~, ..) =>
      context.diagnostics.push(unsupported("indented-code", span))
    @markdown.Block::Blockquote(span~, ..) =>
      context.diagnostics.push(unsupported("blockquote", span))
    @markdown.Block::HtmlBlock(span~, ..) =>
      context.diagnostics.push(unsupported("html-block", span))
    @markdown.Block::FootnoteDefinition(span~, ..) =>
      context.diagnostics.push(unsupported("footnote-definition", span))
  }
}

///|
/// Parse Markdown and render the complete canonical Desired Document, or
/// return diagnostics without a partial document.
pub fn render_markdown(
  source : String,
) -> Result[DesiredDocument, Array[RenderingDiagnostic]] {
  let parsed = @markdown.parse(source)
  let profile = builtin_style_profile()
  let diagnostics : Array[RenderingDiagnostic] = []
  let content : Array[StructuralElement] = []
  let context : RenderContext = {
    profile,
    definitions: parsed.definitions,
    diagnostics,
    content,
  }
  match parsed.document.frontmatter {
    Some(frontmatter) =>
      context.diagnostics.push(unsupported("frontmatter", frontmatter.span))
    None => ()
  }
  for block in parsed.document.children {
    render_block(block, None, context)
  }
  if context.diagnostics.is_empty() {
    Ok({
      metadata: { title: None, locale: None },
      render_metadata: {
        style_profile_id: profile.id,
        style_profile_version: profile.version,
      },
      content: context.content,
      provenance: Some(source_range(parsed.document.span)),
    })
  } else {
    Err(context.diagnostics)
  }
}
