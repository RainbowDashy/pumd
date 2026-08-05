#borrow(path)
extern "C" fn registry_file_mode_ffi(path : Bytes, length : Int) -> Int = "pumd_registry_file_mode"

///| Returns Unix permission bits for `path`, or -1 when it cannot be stat'ed.
pub fn registry_file_mode(path : String) -> Int {
  let bytes = @utf8.encode(path)
  registry_file_mode_ffi(bytes, bytes.length())
}
