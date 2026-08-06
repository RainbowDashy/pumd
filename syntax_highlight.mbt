///|
priv enum SemanticToken {
  Keyword
  String
  Type
  Function
  Property
  Literal
  Comment
  Tag
  Attribute
  Operator
  Punctuation
}

///|
priv struct HighlightSpan {
  start_byte : Int
  end_byte : Int
  token : SemanticToken
}

///|
fn semantic_token(id : Int) -> SemanticToken? {
  match id {
    1 => Some(Keyword)
    2 => Some(String)
    3 => Some(Type)
    4 => Some(Function)
    5 => Some(Property)
    6 => Some(Literal)
    7 => Some(Comment)
    8 => Some(Tag)
    9 => Some(Attribute)
    10 => Some(Operator)
    11 => Some(Punctuation)
    _ => None
  }
}

///|
fn little_endian_u32(bytes : Bytes, offset : Int) -> Int {
  bytes[offset].to_int() |
  (bytes[offset + 1].to_int() << 8) |
  (bytes[offset + 2].to_int() << 16) |
  (bytes[offset + 3].to_int() << 24)
}

///|
fn utf8_boundary(bytes : Bytes, offset : Int) -> Bool {
  offset >= 0 &&
  offset <= bytes.length() &&
  (offset == bytes.length() || (bytes[offset].to_int() & 0xC0) != 0x80)
}

///|
fn scalar_at(bytes : Bytes, offset : Int) -> Int? {
  if !utf8_boundary(bytes, offset) || offset == bytes.length() {
    return None
  }
  let first = bytes[offset].to_int()
  if first <= 0x7F {
    return Some(first)
  }
  if first >= 0xC2 && first <= 0xDF && offset + 1 < bytes.length() {
    return Some(((first & 0x1F) << 6) | (bytes[offset + 1].to_int() & 0x3F))
  }
  if first >= 0xE0 && first <= 0xEF && offset + 2 < bytes.length() {
    return Some(
      ((first & 0x0F) << 12) |
      ((bytes[offset + 1].to_int() & 0x3F) << 6) |
      (bytes[offset + 2].to_int() & 0x3F),
    )
  }
  if first >= 0xF0 && first <= 0xF4 && offset + 3 < bytes.length() {
    return Some(
      ((first & 0x07) << 18) |
      ((bytes[offset + 1].to_int() & 0x3F) << 12) |
      ((bytes[offset + 2].to_int() & 0x3F) << 6) |
      (bytes[offset + 3].to_int() & 0x3F),
    )
  }
  None
}

///|
fn scalar_before(bytes : Bytes, offset : Int) -> Int? {
  if offset <= 0 || offset > bytes.length() {
    return None
  }
  let mut start = offset - 1
  while start > 0 && (bytes[start].to_int() & 0xC0) == 0x80 {
    start = start - 1
  }
  scalar_at(bytes, start)
}

///|
fn attaches_to_adjacent_scalar(codepoint : Int) -> Bool {
  (codepoint >= 0x0300 && codepoint <= 0x036F) ||
  (codepoint >= 0x1AB0 && codepoint <= 0x1AFF) ||
  (codepoint >= 0x1DC0 && codepoint <= 0x1DFF) ||
  (codepoint >= 0x20D0 && codepoint <= 0x20FF) ||
  (codepoint >= 0xFE00 && codepoint <= 0xFE0F) ||
  (codepoint >= 0xFE20 && codepoint <= 0xFE2F) ||
  (codepoint >= 0xE0100 && codepoint <= 0xE01EF) ||
  (codepoint >= 0x1F3FB && codepoint <= 0x1F3FF) ||
  codepoint == 0x200D
}

///|
fn safe_text_boundary(bytes : Bytes, offset : Int) -> Bool {
  if !utf8_boundary(bytes, offset) {
    return false
  }
  match scalar_before(bytes, offset) {
    Some(codepoint) if attaches_to_adjacent_scalar(codepoint) => return false
    _ => ()
  }
  match scalar_at(bytes, offset) {
    Some(codepoint) if attaches_to_adjacent_scalar(codepoint) => false
    _ => true
  }
}

///|
fn decode_spans(
  source : Bytes,
  output : Bytes,
  written : Int,
) -> Array[HighlightSpan]? {
  if written < 0 || written > output.length() || written % 12 != 0 {
    return None
  }
  let spans : Array[HighlightSpan] = []
  let mut previous_end = 0
  let mut offset = 0
  while offset < written {
    let start_byte = little_endian_u32(output, offset)
    let end_byte = little_endian_u32(output, offset + 4)
    let token_id = little_endian_u32(output, offset + 8)
    if start_byte >= end_byte ||
      end_byte > source.length() ||
      start_byte < previous_end ||
      !safe_text_boundary(source, start_byte) ||
      !safe_text_boundary(source, end_byte) {
      return None
    }
    match semantic_token(token_id) {
      Some(token) => spans.push({ start_byte, end_byte, token })
      None => return None
    }
    previous_end = end_byte
    offset = offset + 12
  }
  Some(spans)
}

///|
/// Returns validated semantic spans for the raw fenced-code language tag.
/// A negative native result (including unsupported tags) deliberately returns
/// `None`, which leaves fenced code in its established plain native-text
/// treatment.
fn highlight_fenced_code(
  tag : String,
  source : String,
) -> Array[HighlightSpan]? {
  let language_bytes = @utf8.encode(tag)
  let source_bytes = @utf8.encode(source)
  let source_length = source_bytes.length()
  // Keep the multiplication and the native C int32 capacity representable.
  if source_length > 178956970 {
    return None
  }
  let output = Bytes::make(source_length * 12, b'\x00')
  let written = syntax_highlight_write_ffi(
    language_bytes,
    language_bytes.length(),
    source_bytes,
    source_length,
    output,
    output.length(),
  )
  decode_spans(source_bytes, output, written)
}
