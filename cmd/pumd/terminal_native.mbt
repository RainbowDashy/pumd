///|
extern "C" fn terminal_is_interactive_ffi() -> Int = "pumd_terminal_is_interactive"

///|
#borrow(buffer)
extern "C" fn terminal_read_line_ffi(buffer : Bytes, capacity : Int) -> Int = "pumd_terminal_read_line"

///|
fn terminal_is_interactive() -> Bool {
  terminal_is_interactive_ffi() == 1
}

///|
fn terminal_read_line() -> String? {
  let buffer = Bytes::make(4096, b'\x00')
  let length = terminal_read_line_ffi(buffer, buffer.length())
  if length < 0 || length >= buffer.length() {
    return None
  }
  let line = @utf8.decode(buffer[:length]) catch { _ => return None }
  Some(line.trim(chars=" \t\r\n").to_owned())
}
