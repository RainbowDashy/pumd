#include <moonbit.h>

#if defined(_WIN64) && (defined(_M_X64) || defined(__x86_64__))

#include <windows.h>
#include <wincred.h>
#include <stdint.h>
#include <string.h>

enum {
  PUMD_WINDOWS_NOT_CONFIGURED = -1,
  PUMD_WINDOWS_DENIED = -2,
  PUMD_WINDOWS_UNAVAILABLE = -3,
  PUMD_WINDOWS_MALFORMED = -4,
};

typedef BOOL (WINAPI *pumd_cred_read_w)(LPCWSTR, DWORD, DWORD, PCREDENTIALW *);
typedef BOOL (WINAPI *pumd_cred_write_w)(PCREDENTIALW, DWORD);
typedef BOOL (WINAPI *pumd_cred_delete_w)(LPCWSTR, DWORD, DWORD);
typedef VOID (WINAPI *pumd_cred_free)(PVOID);

struct pumd_windows_credential_api {
  HMODULE advapi32;
  pumd_cred_read_w read;
  pumd_cred_write_w write;
  pumd_cred_delete_w delete;
  pumd_cred_free free;
};

static struct pumd_windows_credential_api pumd_api;
static int pumd_api_state = 0;
static const WCHAR pumd_target[] =
    L"io.github.rainbowdashy.pumd.project-authorization:active-v1";
static const WCHAR pumd_user_name[] = L"active-v1";

static int pumd_initialize(void) {
  if (pumd_api_state != 0) return pumd_api_state == 1;
  pumd_api_state = -1;
  pumd_api.advapi32 = LoadLibraryW(L"advapi32.dll");
  if (pumd_api.advapi32 == NULL) return 0;
  pumd_api.read =
      (pumd_cred_read_w)GetProcAddress(pumd_api.advapi32, "CredReadW");
  pumd_api.write =
      (pumd_cred_write_w)GetProcAddress(pumd_api.advapi32, "CredWriteW");
  pumd_api.delete =
      (pumd_cred_delete_w)GetProcAddress(pumd_api.advapi32, "CredDeleteW");
  pumd_api.free =
      (pumd_cred_free)GetProcAddress(pumd_api.advapi32, "CredFree");
  if (pumd_api.read == NULL || pumd_api.write == NULL ||
      pumd_api.delete == NULL || pumd_api.free == NULL) {
    FreeLibrary(pumd_api.advapi32);
    memset(&pumd_api, 0, sizeof(pumd_api));
    return 0;
  }
  pumd_api_state = 1;
  return 1;
}

static int pumd_result(DWORD error) {
  if (error == ERROR_ACCESS_DENIED || error == ERROR_CANCELLED ||
      error == ERROR_LOGON_FAILURE || error == ERROR_PRIVILEGE_NOT_HELD) {
    return PUMD_WINDOWS_DENIED;
  }
  return PUMD_WINDOWS_UNAVAILABLE;
}

MOONBIT_FFI_EXPORT int pumd_windows_credential_manager_available(void) {
  return pumd_initialize() ? 1 : 0;
}

MOONBIT_FFI_EXPORT int pumd_windows_credential_manager_load(
    moonbit_bytes_t buffer, int capacity) {
  if (!pumd_initialize() || buffer == NULL || capacity <= 0) {
    return PUMD_WINDOWS_UNAVAILABLE;
  }
  PCREDENTIALW credential = NULL;
  if (!pumd_api.read(pumd_target, CRED_TYPE_GENERIC, 0, &credential)) {
    DWORD error = GetLastError();
    return error == ERROR_NOT_FOUND ? PUMD_WINDOWS_NOT_CONFIGURED
                                    : pumd_result(error);
  }
  DWORD length = credential->CredentialBlobSize;
  if (length == 0 || length > (DWORD)capacity ||
      credential->CredentialBlob == NULL) {
    if (credential->CredentialBlob != NULL && length > 0) {
      SecureZeroMemory(credential->CredentialBlob, length);
    }
    pumd_api.free(credential);
    return PUMD_WINDOWS_MALFORMED;
  }
  memcpy(buffer, credential->CredentialBlob, length);
  SecureZeroMemory(credential->CredentialBlob, length);
  pumd_api.free(credential);
  return (int)length + 1;
}

MOONBIT_FFI_EXPORT int pumd_windows_credential_manager_replace(
    moonbit_bytes_t value, int length) {
  if (!pumd_initialize()) return PUMD_WINDOWS_UNAVAILABLE;
  if (value == NULL || length <= 0 ||
      length > CRED_MAX_CREDENTIAL_BLOB_SIZE) {
    return PUMD_WINDOWS_MALFORMED;
  }
  CREDENTIALW credential;
  memset(&credential, 0, sizeof(credential));
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = (LPWSTR)pumd_target;
  credential.CredentialBlobSize = (DWORD)length;
  credential.CredentialBlob = (LPBYTE)value;
  credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
  credential.UserName = (LPWSTR)pumd_user_name;
  /* CredWrite replaces a matching generic credential as one vault operation. */
  BOOL written = pumd_api.write(&credential, 0);
  DWORD error = written ? ERROR_SUCCESS : GetLastError();
  SecureZeroMemory(&credential, sizeof(credential));
  return written ? 0 : pumd_result(error);
}

MOONBIT_FFI_EXPORT int pumd_windows_credential_manager_delete(void) {
  if (!pumd_initialize()) return PUMD_WINDOWS_UNAVAILABLE;
  if (pumd_api.delete(pumd_target, CRED_TYPE_GENERIC, 0)) return 0;
  DWORD error = GetLastError();
  return error == ERROR_NOT_FOUND ? 0 : pumd_result(error);
}

#else

MOONBIT_FFI_EXPORT int pumd_windows_credential_manager_available(void) {
  return 0;
}
MOONBIT_FFI_EXPORT int pumd_windows_credential_manager_load(
    moonbit_bytes_t buffer, int capacity) {
  (void)buffer;
  (void)capacity;
  return -5;
}
MOONBIT_FFI_EXPORT int pumd_windows_credential_manager_replace(
    moonbit_bytes_t value, int length) {
  (void)value;
  (void)length;
  return -5;
}
MOONBIT_FFI_EXPORT int pumd_windows_credential_manager_delete(void) {
  return -5;
}

#endif
