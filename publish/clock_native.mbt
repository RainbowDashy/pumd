///|
extern "C" fn unix_seconds_ffi() -> Int64 = "pumd_unix_seconds"

///|
pub fn current_unix_seconds() -> Int64 {
  unix_seconds_ffi()
}
