///|
#borrow(language, source, output)
extern "C" fn syntax_highlight_write_ffi(
  language : Bytes,
  language_length : Int,
  source : Bytes,
  source_length : Int,
  output : Bytes,
  output_capacity : Int,
) -> Int = "pumd_highlight_write"
