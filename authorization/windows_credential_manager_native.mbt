///|
#borrow(buffer)
extern "C" fn windows_credential_manager_load_ffi(
  buffer : Bytes,
  capacity : Int,
) -> Int = "pumd_windows_credential_manager_load"

///|
#borrow(data)
extern "C" fn windows_credential_manager_replace_ffi(
  data : Bytes,
  length : Int,
) -> Int = "pumd_windows_credential_manager_replace"

///|
extern "C" fn windows_credential_manager_delete_ffi() -> Int = "pumd_windows_credential_manager_delete"

///|
extern "C" fn windows_credential_manager_available_ffi() -> Int = "pumd_windows_credential_manager_available"

///|
extern "C" fn windows_credential_manager_probe_ffi() -> Int = "pumd_windows_credential_manager_probe"

///|
fn native_windows_credential_manager_available() -> Bool {
  windows_credential_manager_available_ffi() == 1
}

///|
fn native_windows_credential_manager_backend() -> CredentialDocumentBackend {
  {
    probe: fn() {
      let result = windows_credential_manager_probe_ffi()
      if result == 0 {
        Ok(())
      } else {
        Err(native_credential_store_error(result))
      }
    },
    load: fn() {
      // Windows generic credentials are capped by
      // CRED_MAX_CREDENTIAL_BLOB_SIZE (5 * 512 bytes).
      let buffer = Bytes::make(2560, b'\x00')
      let result = windows_credential_manager_load_ffi(buffer, buffer.length())
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
      let result = windows_credential_manager_replace_ffi(data, data.length())
      if result == 0 {
        Ok(())
      } else {
        Err(native_credential_store_error(result))
      }
    },
    delete: fn() {
      let result = windows_credential_manager_delete_ffi()
      if result == 0 {
        Ok(())
      } else {
        Err(native_credential_store_error(result))
      }
    },
  }
}
