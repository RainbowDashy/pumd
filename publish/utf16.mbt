///|
/// Advances a Google Docs body index past `text` inside the publishing adapter.
///
/// Google Docs indexes text as UTF-16 code units. BMP code points (including
/// CJK, combining marks, and newlines) consume one unit; non-BMP code points
/// consume the surrogate-pair width of two units.
pub fn advance_google_docs_index(index~ : Int, text~ : String) -> Int {
  let mut next_index = index
  for char in text {
    next_index += if char.to_int() > 0xFFFF { 2 } else { 1 }
  }
  next_index
}
