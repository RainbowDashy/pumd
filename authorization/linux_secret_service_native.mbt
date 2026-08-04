///|
#borrow(buffer)
extern "C" fn linux_secret_service_load_ffi(
  buffer : Bytes,
  capacity : Int,
) -> Int = "pumd_linux_secret_service_load"

///|
#borrow(data)
extern "C" fn linux_secret_service_replace_ffi(
  data : Bytes,
  length : Int,
) -> Int = "pumd_linux_secret_service_replace"

///|
extern "C" fn linux_secret_service_delete_ffi() -> Int = "pumd_linux_secret_service_delete"

///|
extern "C" fn linux_secret_service_available_ffi() -> Int = "pumd_linux_secret_service_available"

///|
extern "C" fn linux_secret_service_probe_ffi() -> Int = "pumd_linux_secret_service_probe"

///|
fn native_linux_secret_service_available() -> Bool {
  linux_secret_service_available_ffi() == 1
}

///|
fn native_linux_secret_service_backend() -> CredentialDocumentBackend {
  {
    probe: fn() {
      let result = linux_secret_service_probe_ffi()
      if result == 0 {
        Ok(())
      } else {
        Err(native_credential_store_error(result))
      }
    },
    load: fn() {
      // Stored data is capped at 1 MiB. OAuth authorization documents are much
      // smaller; the cap prevents native data from driving an unbounded allocation.
      let buffer = Bytes::make(1048576, b'\x00')
      let result = linux_secret_service_load_ffi(buffer, buffer.length())
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
      let result = linux_secret_service_replace_ffi(data, data.length())
      if result == 0 {
        Ok(())
      } else {
        Err(native_credential_store_error(result))
      }
    },
    delete: fn() {
      let result = linux_secret_service_delete_ffi()
      if result == 0 {
        Ok(())
      } else {
        Err(native_credential_store_error(result))
      }
    },
  }
}
