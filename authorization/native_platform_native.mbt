///|
extern "C" fn native_credential_platform_ffi() -> Int = "pumd_native_credential_platform"

///|
fn native_credential_platform_code() -> Int {
  native_credential_platform_ffi()
}
