///| Block-level markdown parser

///| Line-driven state machine (Lezer-style)

///|
/// Parse result
pub(all) struct ParseResult {
  document : Document
  definitions : Array[LinkDefinition]
}

///| Parse markdown source into CST

///| When strict=true, uses full CommonMark compliance (slower)

///|
/// When strict=false (default), uses fast single-pass parser
pub fn parse(
  source : String,
  strict? : Bool = false,
  wikilinks? : Bool = false,
) -> ParseResult {
  let scanner = Scanner::new(source)
  let parser = BlockParser::new(scanner, strict, wikilinks)
  parser.parse_document()
}

///|
/// Block parser state
priv struct BlockParser {
  scanner : Scanner
  definitions : Array[LinkDefinition]
  strict : Bool
  wikilinks : Bool
}

///|
fn BlockParser::new(
  scanner : Scanner,
  strict : Bool,
  wikilinks : Bool,
) -> BlockParser {
  { scanner, definitions: [], strict, wikilinks }
}

///|
fn BlockParser::parse_inline_content(
  self : BlockParser,
  content : String,
) -> Array[Inline] {
  if self.scanner.is_bmp() {
    parse_inlines_known_bmp(
      content,
      strict=self.strict,
      wikilinks=self.wikilinks,
    )
  } else {
    parse_inlines(content, strict=self.strict, wikilinks=self.wikilinks)
  }
}

///|
/// Parse entire document
fn BlockParser::parse_document(self : BlockParser) -> ParseResult {
  let start = self.scanner.pos

  // Try to parse frontmatter
  let frontmatter = self.try_parse_frontmatter()

  // Parse blocks
  let children = self.parse_blocks()
  let document = Document::{
    frontmatter,
    children,
    span: Span::new(start, self.scanner.pos),
  }
  { document, definitions: self.definitions }
}

///|
/// Parse sequence of blocks
fn BlockParser::parse_blocks(self : BlockParser) -> Array[Block] {
  let blocks : Array[Block] = []
  while !self.scanner.is_eof() {
    // Skip and collect blank lines
    let blank_start = self.scanner.pos
    let mut blank_count = 0
    while !self.scanner.is_eof() && self.scanner.is_blank_line() {
      blank_count += 1
      self.scanner.skip_line()
    }
    if blank_count > 0 {
      blocks.push(
        Block::BlankLines(
          count=blank_count,
          span=Span::new(blank_start, self.scanner.pos),
        ),
      )
    }
    if self.scanner.is_eof() {
      break
    }

    // Parse next block
    match self.parse_block() {
      Some(block) => blocks.push(block)
      None =>
        // Skip problematic line
        self.scanner.skip_line()
    }
  }
  blocks
}

///|
/// Parse a single block
fn BlockParser::parse_block(self : BlockParser) -> Block? {
  let start = self.scanner.pos
  let indent = self.scanner.count_leading_spaces()

  // Try each block type in order of precedence

  // Thematic break (must check before lists due to ---)
  match self.try_parse_thematic_break(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // ATX heading
  match self.try_parse_atx_heading(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // Fenced code block
  match self.try_parse_fenced_code(start, indent) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // Blockquote
  match self.try_parse_blockquote(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // List (bullet or ordered)
  match self.try_parse_list(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // Indented code block (4+ spaces)
  if indent >= 4 {
    match self.try_parse_indented_code(start) {
      Some(block) => return Some(block)
      None => self.scanner.restore(start)
    }
  }

  // Setext heading (underlined)
  match self.try_parse_setext_heading(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // HTML block
  match self.try_parse_html_block(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // GFM Table
  match self.try_parse_table(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // GFM Footnote definition
  match self.try_parse_footnote_definition(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // Link reference definition
  match self.try_parse_link_definition(start) {
    Some(_) => return None // Definitions don't produce blocks
    None => self.scanner.restore(start)
  }

  // Default: paragraph
  self.parse_paragraph(start)
}

///|
/// Try to parse thematic break (---, ***, ___)
fn BlockParser::try_parse_thematic_break(
  self : BlockParser,
  start : Int,
) -> Block? {
  let leading = self.read_leading_trivia()
  let marker = match self.scanner.peek() {
    Some(c) if c == '-' || c == '*' || c == '_' => c
    _ => return None
  }
  let mut count = 0
  while !self.scanner.is_eof() {
    match self.scanner.peek() {
      Some('\n') => break
      Some(c) if c == marker => {
        count += 1
        self.scanner.advance(1)
      }
      Some(c) if c == ' ' || c == '\t' => self.scanner.advance(1)
      _ => return None // Invalid character
    }
  }
  if count < 3 {
    return None
  }
  let trailing = self.read_trailing_trivia()
  Some(
    Block::ThematicBreak(
      marker~,
      count~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=trailing,
    ),
  )
}

///|
priv struct BlockquoteSourceMap {
  starts : Array[Int]
  ends : Array[Int]
}

///|
/// Try to parse blockquote
fn BlockParser::try_parse_blockquote(self : BlockParser, start : Int) -> Block? {
  let leading = self.read_leading_trivia()
  if !char_is(self.scanner.peek(), '>') {
    return None
  }

  // Collect blockquote content and record where each virtual source character
  // came from. Parsing the stripped content recursively is convenient, but its
  // nodes must retain positions in the original document.
  let content_buf = StringBuilder()
  let source_map : BlockquoteSourceMap = { starts: [], ends: [] }
  let mut first = true
  let mut previous_line_end = self.scanner.pos
  let mut last_content_end = self.scanner.pos
  while !self.scanner.is_eof() {
    let line_start = self.scanner.pos
    let _ = self.scanner.skip_spaces()
    if char_is(self.scanner.peek(), '>') {
      self.scanner.advance(1)
      // Optional space after >
      if char_is(self.scanner.peek(), ' ') {
        self.scanner.advance(1)
      }
      if !first {
        content_buf.write_char('\n')
        source_map.append_char(previous_line_end, previous_line_end + 1)
      }
      let content_start = self.scanner.pos
      self.scanner.append_line_to(content_buf)
      let content_end = self.scanner.pos
      source_map.append_range(content_start, content_end)
      first = false
      last_content_end = content_end
      if char_is(self.scanner.peek(), '\n') {
        previous_line_end = self.scanner.pos
        self.scanner.advance(1)
      }
    } else {
      self.scanner.restore(line_start)
      if !self.can_lazily_continue_blockquote(content_buf.to_string()) {
        break
      }
      if !first {
        content_buf.write_char('\n')
        source_map.append_char(previous_line_end, previous_line_end + 1)
      }
      let content_start = self.scanner.pos
      self.scanner.append_line_to(content_buf)
      let content_end = self.scanner.pos
      source_map.append_range(content_start, content_end)
      first = false
      last_content_end = content_end
      if char_is(self.scanner.peek(), '\n') {
        previous_line_end = self.scanner.pos
        self.scanner.advance(1)
      }
    }
  }

  source_map.starts.push(last_content_end)

  // Parse blockquote content recursively
  let content = content_buf.to_string()
  let inner_scanner = if self.scanner.is_bmp() {
    Scanner::new_bmp(content)
  } else {
    Scanner::new(content)
  }
  let inner_parser = BlockParser::new(
    inner_scanner,
    self.strict,
    self.wikilinks,
  )
  let inner_result = inner_parser.parse_document()

  // Merge definitions
  for def in inner_result.definitions {
    self.definitions.push(remap_blockquote_definition(def, source_map))
  }
  Some(
    Block::Blockquote(
      children=remap_blockquote_blocks(
        inner_result.document.children,
        source_map,
      ),
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// A markerless line may lazily continue only an open paragraph. Lines that
/// would interrupt that paragraph still end the blockquote.
fn BlockParser::can_lazily_continue_blockquote(
  self : BlockParser,
  content : String,
) -> Bool {
  let content_scanner = if self.scanner.is_bmp() {
    Scanner::new_bmp(content)
  } else {
    Scanner::new(content)
  }
  let content_parser = BlockParser::new(
    content_scanner,
    self.strict,
    self.wikilinks,
  )
  let content_result = content_parser.parse_document()
  match content_result.document.children.last() {
    Some(Block::Paragraph(..)) => ()
    _ => return false
  }

  let line_start = self.scanner.pos
  let _ = self.scanner.skip_spaces()
  let interrupts = match self.scanner.peek() {
    Some('\n') | None => true
    Some('#') | Some('>') => true
    Some('`') =>
      self.scanner.peek_at(1) == Some('`') &&
      self.scanner.peek_at(2) == Some('`')
    Some('~') =>
      self.scanner.peek_at(1) == Some('~') &&
      self.scanner.peek_at(2) == Some('~')
    Some('-') | Some('*') | Some('_') => {
      let thematic = self.try_parse_thematic_break(line_start) is Some(_)
      self.scanner.restore(line_start)
      let list = self.detect_list_marker() is Some(_)
      thematic || list
    }
    Some(c) if is_digit(c) => self.detect_list_marker() is Some(_)
    Some('[') => {
      let candidate = self.scanner.remaining()
      let candidate_scanner = if self.scanner.is_bmp() {
        Scanner::new_bmp(candidate)
      } else {
        Scanner::new(candidate)
      }
      let candidate_parser = BlockParser::new(
        candidate_scanner,
        self.strict,
        self.wikilinks,
      )
      candidate_parser.try_parse_link_definition(0) is Some(_)
    }
    _ => false
  }
  self.scanner.restore(line_start)
  !interrupts
}

///|
/// Add one virtual character and its original-document range to a source map.
fn BlockquoteSourceMap::append_char(
  self : BlockquoteSourceMap,
  source_start : Int,
  source_end : Int,
) -> Unit {
  self.starts.push(source_start)
  if self.ends.is_empty() {
    self.ends.push(source_start)
  }
  self.ends.push(source_end)
}

///|
/// Add a same-length source range to a blockquote source map.
fn BlockquoteSourceMap::append_range(
  self : BlockquoteSourceMap,
  source_start : Int,
  source_end : Int,
) -> Unit {
  for offset = 0; offset < source_end - source_start; offset = offset + 1 {
    self.append_char(source_start + offset, source_start + offset + 1)
  }
}

///|
/// Translate a span in the stripped blockquote buffer back to the document.
fn BlockquoteSourceMap::remap_span(
  self : BlockquoteSourceMap,
  span : Span,
) -> Span {
  let from = if span.from < 0 {
    0
  } else if span.from >= self.starts.length() {
    self.starts.length() - 1
  } else {
    span.from
  }
  let to = if span.to < 0 {
    0
  } else if span.to >= self.ends.length() {
    self.ends.length() - 1
  } else {
    span.to
  }
  Span::new(self.starts[from], self.ends[to])
}

///|
fn remap_blockquote_inlines(
  inlines : Array[Inline],
  source_map : BlockquoteSourceMap,
) -> Array[Inline] {
  let result : Array[Inline] = []
  for inline in inlines {
    result.push(remap_blockquote_inline(inline, source_map))
  }
  result
}

///|
fn remap_blockquote_inline(
  inline : Inline,
  source_map : BlockquoteSourceMap,
) -> Inline {
  match inline {
    Inline::Text(content~, span~) =>
      Inline::Text(content~, span=source_map.remap_span(span))
    Inline::SoftBreak(span~) =>
      Inline::SoftBreak(span=source_map.remap_span(span))
    Inline::HardBreak(style~, span~) =>
      Inline::HardBreak(style~, span=source_map.remap_span(span))
    Inline::Emphasis(marker~, children~, span~) =>
      Inline::Emphasis(
        marker~,
        children=remap_blockquote_inlines(children, source_map),
        span=source_map.remap_span(span),
      )
    Inline::Strong(marker~, children~, span~) =>
      Inline::Strong(
        marker~,
        children=remap_blockquote_inlines(children, source_map),
        span=source_map.remap_span(span),
      )
    Inline::Strikethrough(children~, span~) =>
      Inline::Strikethrough(
        children=remap_blockquote_inlines(children, source_map),
        span=source_map.remap_span(span),
      )
    Inline::Code(content~, backtick_count~, span~) =>
      Inline::Code(content~, backtick_count~, span=source_map.remap_span(span))
    Inline::WikiLink(target~, label~, fragment~, span~) =>
      Inline::WikiLink(
        target~,
        label~,
        fragment~,
        span=source_map.remap_span(span),
      )
    Inline::Link(children~, url~, title~, span~) =>
      Inline::Link(
        children=remap_blockquote_inlines(children, source_map),
        url~,
        title~,
        span=source_map.remap_span(span),
      )
    Inline::RefLink(children~, label~, span~) =>
      Inline::RefLink(
        children=remap_blockquote_inlines(children, source_map),
        label~,
        span=source_map.remap_span(span),
      )
    Inline::Autolink(url~, is_email~, span~) =>
      Inline::Autolink(url~, is_email~, span=source_map.remap_span(span))
    Inline::Image(alt~, url~, title~, span~) =>
      Inline::Image(alt~, url~, title~, span=source_map.remap_span(span))
    Inline::RefImage(alt~, label~, span~) =>
      Inline::RefImage(alt~, label~, span=source_map.remap_span(span))
    Inline::HtmlInline(html~, span~) =>
      Inline::HtmlInline(html~, span=source_map.remap_span(span))
    Inline::FootnoteReference(label~, span~) =>
      Inline::FootnoteReference(label~, span=source_map.remap_span(span))
  }
}

///|
fn remap_blockquote_table_cells(
  cells : Array[TableCell],
  source_map : BlockquoteSourceMap,
) -> Array[TableCell] {
  let result : Array[TableCell] = []
  for cell in cells {
    result.push({
      children: remap_blockquote_inlines(cell.children, source_map),
      span: source_map.remap_span(cell.span),
    })
  }
  result
}

///|
fn remap_blockquote_list_items(
  items : Array[ListItem],
  source_map : BlockquoteSourceMap,
) -> Array[ListItem] {
  let result : Array[ListItem] = []
  for item in items {
    result.push({
      children: remap_blockquote_blocks(item.children, source_map),
      checked: item.checked,
      marker_offset: item.marker_offset,
      content_offset: item.content_offset,
      span: source_map.remap_span(item.span),
    })
  }
  result
}

///|
fn remap_blockquote_blocks(
  blocks : Array[Block],
  source_map : BlockquoteSourceMap,
) -> Array[Block] {
  let result : Array[Block] = []
  for block in blocks {
    match block {
      Block::ThematicBreak(
        marker~,
        count~,
        span~,
        leading_trivia~,
        trailing_trivia~
      ) =>
        result.push(
          Block::ThematicBreak(
            marker~,
            count~,
            span=source_map.remap_span(span),
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      Block::Heading(
        level~,
        style~,
        children~,
        closing_hashes~,
        span~,
        leading_trivia~,
        trailing_trivia~
      ) =>
        result.push(
          Block::Heading(
            level~,
            style~,
            children=remap_blockquote_inlines(children, source_map),
            closing_hashes~,
            span=source_map.remap_span(span),
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      Block::Paragraph(children~, span~, leading_trivia~, trailing_trivia~) =>
        result.push(
          Block::Paragraph(
            children=remap_blockquote_inlines(children, source_map),
            span=source_map.remap_span(span),
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      Block::FencedCode(
        fence_marker~,
        fence_length~,
        info~,
        code~,
        indent~,
        span~,
        leading_trivia~,
        trailing_trivia~
      ) =>
        result.push(
          Block::FencedCode(
            fence_marker~,
            fence_length~,
            info~,
            code~,
            indent~,
            span=source_map.remap_span(span),
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      Block::IndentedCode(code~, span~, leading_trivia~, trailing_trivia~) =>
        result.push(
          Block::IndentedCode(
            code~,
            span=source_map.remap_span(span),
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      Block::Blockquote(children~, span~, leading_trivia~, trailing_trivia~) =>
        result.push(
          Block::Blockquote(
            children=remap_blockquote_blocks(children, source_map),
            span=source_map.remap_span(span),
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      Block::BulletList(
        marker~,
        tight~,
        items~,
        span~,
        leading_trivia~,
        trailing_trivia~
      ) =>
        result.push(
          Block::BulletList(
            marker~,
            tight~,
            items=remap_blockquote_list_items(items, source_map),
            span=source_map.remap_span(span),
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      Block::OrderedList(
        start~,
        delimiter~,
        tight~,
        items~,
        span~,
        leading_trivia~,
        trailing_trivia~
      ) =>
        result.push(
          Block::OrderedList(
            start~,
            delimiter~,
            tight~,
            items=remap_blockquote_list_items(items, source_map),
            span=source_map.remap_span(span),
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      Block::HtmlBlock(html~, span~, leading_trivia~, trailing_trivia~) =>
        result.push(
          Block::HtmlBlock(
            html~,
            span=source_map.remap_span(span),
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      Block::Table(
        header~,
        alignments~,
        rows~,
        span~,
        leading_trivia~,
        trailing_trivia~
      ) => {
        let remapped_rows : Array[Array[TableCell]] = []
        for row in rows {
          remapped_rows.push(remap_blockquote_table_cells(row, source_map))
        }
        result.push(
          Block::Table(
            header=remap_blockquote_table_cells(header, source_map),
            alignments~,
            rows=remapped_rows,
            span=source_map.remap_span(span),
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      }
      Block::BlankLines(count~, span~) =>
        result.push(Block::BlankLines(count~, span=source_map.remap_span(span)))
      Block::FootnoteDefinition(
        label~,
        children~,
        span~,
        leading_trivia~,
        trailing_trivia~
      ) =>
        result.push(
          Block::FootnoteDefinition(
            label~,
            children=remap_blockquote_blocks(children, source_map),
            span=source_map.remap_span(span),
            leading_trivia~,
            trailing_trivia~,
          ),
        )
    }
  }
  result
}

///|
fn remap_blockquote_definition(
  definition : LinkDefinition,
  source_map : BlockquoteSourceMap,
) -> LinkDefinition {
  {
    label: definition.label,
    url: definition.url,
    title: definition.title,
    span: source_map.remap_span(definition.span),
  }
}

///|
/// Parse paragraph (default block type)
fn BlockParser::parse_paragraph(self : BlockParser, start : Int) -> Block? {
  let leading = self.read_leading_trivia()
  let content_buf = StringBuilder()
  let mut first = true
  while !self.scanner.is_eof() {
    if self.scanner.is_blank_line() {
      break
    }

    // Check for block-level interrupts
    let saved = self.scanner.pos
    let _ = self.scanner.skip_spaces()
    match self.scanner.peek() {
      Some('#') | Some('>') => {
        self.scanner.restore(saved)
        break
      }
      // Only break for fenced code if 3+ backticks/tildes
      // Use peek_at for O(1) check instead of count_char
      Some('`') if self.scanner.peek_at(1) == Some('`') &&
        self.scanner.peek_at(2) == Some('`') => {
        self.scanner.restore(saved)
        break
      }
      Some('~') if self.scanner.peek_at(1) == Some('~') &&
        self.scanner.peek_at(2) == Some('~') => {
        self.scanner.restore(saved)
        break
      }
      Some('-') | Some('*') | Some('_') => {
        // Could be thematic break or list
        match self.try_parse_thematic_break(saved) {
          Some(_) => {
            self.scanner.restore(saved)
            break
          }
          None => ()
        }
        self.scanner.restore(saved)
        match self.detect_list_marker() {
          Some(_) => break
          None => ()
        }
      }
      Some(c) if is_digit(c) => {
        self.scanner.restore(saved)
        match self.detect_list_marker() {
          Some(_) => break
          None => ()
        }
      }
      _ => ()
    }
    self.scanner.restore(saved)
    if !first {
      content_buf.write_char('\n')
    }
    self.scanner.append_line_to(content_buf)
    first = false
    if char_is(self.scanner.peek(), '\n') {
      self.scanner.advance(1)
    }
  }
  let content = content_buf.to_string()
  if content.trim(chars=" \t\n\r").is_empty() {
    return None
  }
  let children = self.parse_inline_content(content)
  Some(
    Block::Paragraph(
      children~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Read leading trivia (whitespace before content)
fn BlockParser::read_leading_trivia(self : BlockParser) -> Trivia {
  let start = self.scanner.pos
  let count = self.scanner.skip_spaces()
  if count > 0 {
    Trivia::new(self.scanner.substring(start, start + count))
  } else {
    Trivia::empty()
  }
}

///|
/// Read trailing trivia (whitespace after content including newline)
fn BlockParser::read_trailing_trivia(self : BlockParser) -> Trivia {
  let start = self.scanner.pos
  let _ = self.scanner.skip_spaces()
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }
  if self.scanner.pos > start {
    Trivia::new(self.scanner.substring(start, self.scanner.pos))
  } else {
    Trivia::empty()
  }
}
