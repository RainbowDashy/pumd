///|
#borrow(buffer)
extern "C" fn macos_keychain_load_ffi(buffer : Bytes, capacity : Int) -> Int = "pumd_macos_keychain_load"

///|
#borrow(data)
extern "C" fn macos_keychain_replace_ffi(data : Bytes, length : Int) -> Int = "pumd_macos_keychain_replace"

///|
extern "C" fn macos_keychain_delete_ffi() -> Int = "pumd_macos_keychain_delete"

///|
extern "C" fn macos_keychain_available_ffi() -> Int = "pumd_macos_keychain_available"

///|
extern "C" fn macos_keychain_probe_ffi() -> Int = "pumd_macos_keychain_probe"

///|
fn native_macos_keychain_available() -> Bool {
  macos_keychain_available_ffi() == 1
}

///|
fn native_macos_keychain_backend() -> CredentialDocumentBackend {
  {
    probe: fn() {
      let result = macos_keychain_probe_ffi()
      if result == 0 {
        Ok(())
      } else {
        Err(native_credential_store_error(result))
      }
    },
    load: fn() {
      // Generic-password data is capped at 1 MiB. This is far above an OAuth
      // authorization document while preventing an unbounded allocation.
      let buffer = Bytes::make(1048576, b'\x00')
      let result = macos_keychain_load_ffi(buffer, buffer.length())
      if result <= 0 {
        return Err(native_credential_store_error(result))
      }
      let length = result - 1
      if length <= 0 || length > buffer.length() {
        return Err(CredentialStoreError::Malformed)
      }
      let document = @utf8.decode(buffer[:length]) catch {
        _ => return Err(CredentialStoreError::Malformed)
      }
      Ok(document)
    },
    replace: fn(document) {
      let data = @utf8.encode(document)
      let result = macos_keychain_replace_ffi(data, data.length())
      if result == 0 {
        Ok(())
      } else {
        Err(native_credential_store_error(result))
      }
    },
    delete: fn() {
      let result = macos_keychain_delete_ffi()
      if result == 0 {
        Ok(())
      } else {
        Err(native_credential_store_error(result))
      }
    },
  }
}
