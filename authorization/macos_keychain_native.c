#include <moonbit.h>

/*
 * This shim intentionally resolves Security/CoreFoundation at runtime. Moon's
 * native-stub linker settings apply to every native release target, whereas
 * Security.framework exists only on supported macOS targets.
 */
#if defined(__APPLE__) && defined(__MACH__) && defined(__aarch64__)

#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

typedef const void *CFTypeRef;
typedef const void *CFStringRef;
typedef const void *CFDataRef;
typedef const void *CFDictionaryRef;
typedef void *CFMutableDictionaryRef;
typedef int32_t OSStatus;

enum {
  PUMD_KEYCHAIN_NOT_CONFIGURED = -1,
  PUMD_KEYCHAIN_DENIED = -2,
  PUMD_KEYCHAIN_UNAVAILABLE = -3,
  PUMD_KEYCHAIN_MALFORMED = -4,
  PUMD_ERR_SEC_ITEM_NOT_FOUND = -25300,
  PUMD_ERR_SEC_DUPLICATE_ITEM = -25299,
  PUMD_ERR_SEC_AUTH_FAILED = -25293,
  PUMD_ERR_SEC_INTERACTION_NOT_ALLOWED = -25308,
  PUMD_ERR_SEC_USER_CANCELED = -128,
  PUMD_CF_STRING_ENCODING_UTF8 = 0x08000100,
};

struct pumd_security_api {
  void *security;
  void *core_foundation;
  CFStringRef (*string_from_utf8)(void *, const uint8_t *, int64_t, uint32_t, uint8_t);
  CFDataRef (*data_create)(void *, const uint8_t *, int64_t);
  CFMutableDictionaryRef (*dictionary_create)(
      void *, const void **, const void **, int64_t, const void *, const void *);
  void (*release)(CFTypeRef);
  int64_t (*data_length)(CFDataRef);
  const uint8_t *(*data_bytes)(CFDataRef);
  OSStatus (*item_copy)(CFDictionaryRef, CFTypeRef *);
  OSStatus (*item_add)(CFDictionaryRef, CFTypeRef *);
  OSStatus (*item_update)(CFDictionaryRef, CFDictionaryRef);
  OSStatus (*item_delete)(CFDictionaryRef);
  const void *dictionary_key_callbacks;
  const void *dictionary_value_callbacks;
  CFTypeRef boolean_true;
  CFTypeRef sec_class;
  CFTypeRef sec_class_generic_password;
  CFTypeRef sec_attr_service;
  CFTypeRef sec_attr_account;
  CFTypeRef sec_use_data_protection_keychain;
  CFTypeRef sec_return_data;
  CFTypeRef sec_match_limit;
  CFTypeRef sec_match_limit_one;
  CFTypeRef sec_value_data;
  CFTypeRef sec_attr_accessible;
  CFTypeRef sec_attr_accessible_when_unlocked_this_device_only;
};

static struct pumd_security_api pumd_api;
static int pumd_api_state = 0;

static CFTypeRef pumd_symbol_value(void *library, const char *name) {
  void *symbol = dlsym(library, name);
  return symbol == NULL ? NULL : *(CFTypeRef *)symbol;
}

static int pumd_initialize(void) {
  if (pumd_api_state != 0) return pumd_api_state == 1;
  pumd_api_state = -1;
  pumd_api.security = dlopen(
      "/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY | RTLD_LOCAL);
  pumd_api.core_foundation = dlopen(
      "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY | RTLD_LOCAL);
  if (pumd_api.security == NULL || pumd_api.core_foundation == NULL) return 0;
#define PUMD_FUNCTION(field, library, symbol) \
  pumd_api.field = dlsym(library, symbol); \
  if (pumd_api.field == NULL) return 0
  PUMD_FUNCTION(string_from_utf8, pumd_api.core_foundation, "CFStringCreateWithBytes");
  PUMD_FUNCTION(data_create, pumd_api.core_foundation, "CFDataCreate");
  PUMD_FUNCTION(dictionary_create, pumd_api.core_foundation, "CFDictionaryCreate");
  PUMD_FUNCTION(release, pumd_api.core_foundation, "CFRelease");
  PUMD_FUNCTION(data_length, pumd_api.core_foundation, "CFDataGetLength");
  PUMD_FUNCTION(data_bytes, pumd_api.core_foundation, "CFDataGetBytePtr");
  PUMD_FUNCTION(item_copy, pumd_api.security, "SecItemCopyMatching");
  PUMD_FUNCTION(item_add, pumd_api.security, "SecItemAdd");
  PUMD_FUNCTION(item_update, pumd_api.security, "SecItemUpdate");
  PUMD_FUNCTION(item_delete, pumd_api.security, "SecItemDelete");
#undef PUMD_FUNCTION
#define PUMD_VALUE(field, library, symbol) \
  pumd_api.field = pumd_symbol_value(library, symbol); \
  if (pumd_api.field == NULL) return 0
  pumd_api.dictionary_key_callbacks = dlsym(pumd_api.core_foundation, "kCFTypeDictionaryKeyCallBacks");
  pumd_api.dictionary_value_callbacks = dlsym(pumd_api.core_foundation, "kCFTypeDictionaryValueCallBacks");
  if (pumd_api.dictionary_key_callbacks == NULL || pumd_api.dictionary_value_callbacks == NULL) return 0;
  PUMD_VALUE(boolean_true, pumd_api.core_foundation, "kCFBooleanTrue");
  PUMD_VALUE(sec_class, pumd_api.security, "kSecClass");
  PUMD_VALUE(sec_class_generic_password, pumd_api.security, "kSecClassGenericPassword");
  PUMD_VALUE(sec_attr_service, pumd_api.security, "kSecAttrService");
  PUMD_VALUE(sec_attr_account, pumd_api.security, "kSecAttrAccount");
  PUMD_VALUE(sec_use_data_protection_keychain, pumd_api.security, "kSecUseDataProtectionKeychain");
  PUMD_VALUE(sec_return_data, pumd_api.security, "kSecReturnData");
  PUMD_VALUE(sec_match_limit, pumd_api.security, "kSecMatchLimit");
  PUMD_VALUE(sec_match_limit_one, pumd_api.security, "kSecMatchLimitOne");
  PUMD_VALUE(sec_value_data, pumd_api.security, "kSecValueData");
  PUMD_VALUE(sec_attr_accessible, pumd_api.security, "kSecAttrAccessible");
  PUMD_VALUE(sec_attr_accessible_when_unlocked_this_device_only, pumd_api.security,
             "kSecAttrAccessibleWhenUnlockedThisDeviceOnly");
#undef PUMD_VALUE
  pumd_api_state = 1;
  return 1;
}

static int pumd_result(OSStatus status) {
  if (status == 0) return 0;
  if (status == PUMD_ERR_SEC_ITEM_NOT_FOUND) return PUMD_KEYCHAIN_NOT_CONFIGURED;
  if (status == PUMD_ERR_SEC_AUTH_FAILED ||
      status == PUMD_ERR_SEC_INTERACTION_NOT_ALLOWED ||
      status == PUMD_ERR_SEC_USER_CANCELED) return PUMD_KEYCHAIN_DENIED;
  return PUMD_KEYCHAIN_UNAVAILABLE;
}

static CFStringRef pumd_string(const char *value) {
  return pumd_api.string_from_utf8(NULL, (const uint8_t *)value,
                                   (int64_t)strlen(value),
                                   PUMD_CF_STRING_ENCODING_UTF8, 0);
}

static CFMutableDictionaryRef pumd_query(int return_data, CFDataRef value,
                                          int accessible) {
  CFStringRef service = pumd_string("io.github.rainbowdashy.pumd.project-authorization");
  CFStringRef account = pumd_string("active-v1");
  if (service == NULL || account == NULL) {
    if (service != NULL) pumd_api.release(service);
    if (account != NULL) pumd_api.release(account);
    return NULL;
  }
  const void *keys[7];
  const void *values[7];
  int64_t count = 0;
#define PUMD_PAIR(key, value) do { keys[count] = (key); values[count] = (value); ++count; } while (0)
  PUMD_PAIR(pumd_api.sec_class, pumd_api.sec_class_generic_password);
  PUMD_PAIR(pumd_api.sec_attr_service, service);
  PUMD_PAIR(pumd_api.sec_attr_account, account);
  PUMD_PAIR(pumd_api.sec_use_data_protection_keychain, pumd_api.boolean_true);
  if (return_data) {
    PUMD_PAIR(pumd_api.sec_return_data, pumd_api.boolean_true);
    PUMD_PAIR(pumd_api.sec_match_limit, pumd_api.sec_match_limit_one);
  }
  if (value != NULL) PUMD_PAIR(pumd_api.sec_value_data, value);
  if (accessible) {
    PUMD_PAIR(pumd_api.sec_attr_accessible,
              pumd_api.sec_attr_accessible_when_unlocked_this_device_only);
  }
#undef PUMD_PAIR
  CFMutableDictionaryRef result = pumd_api.dictionary_create(
      NULL, keys, values, count, pumd_api.dictionary_key_callbacks,
      pumd_api.dictionary_value_callbacks);
  pumd_api.release(service);
  pumd_api.release(account);
  return result;
}

/* SecItemUpdate accepts only attributes to change, never the primary-key query. */
static CFMutableDictionaryRef pumd_update_attributes(CFDataRef value) {
  const void *keys[] = { pumd_api.sec_value_data };
  const void *values[] = { value };
  return pumd_api.dictionary_create(
      NULL, keys, values, 1, pumd_api.dictionary_key_callbacks,
      pumd_api.dictionary_value_callbacks);
}

MOONBIT_FFI_EXPORT int pumd_macos_keychain_available(void) {
  return pumd_initialize() ? 1 : 0;
}

MOONBIT_FFI_EXPORT int pumd_macos_keychain_load(
    moonbit_bytes_t buffer, int capacity) {
  if (!pumd_initialize() || buffer == NULL || capacity <= 0) return PUMD_KEYCHAIN_UNAVAILABLE;
  CFMutableDictionaryRef query = pumd_query(1, NULL, 0);
  if (query == NULL) return PUMD_KEYCHAIN_UNAVAILABLE;
  CFTypeRef data = NULL;
  OSStatus status = pumd_api.item_copy(query, &data);
  pumd_api.release(query);
  if (status != 0) return pumd_result(status);
  int64_t length = pumd_api.data_length((CFDataRef)data);
  const uint8_t *bytes = pumd_api.data_bytes((CFDataRef)data);
  if (length < 0 || length >= capacity || (length > 0 && bytes == NULL)) {
    pumd_api.release(data);
    return PUMD_KEYCHAIN_MALFORMED;
  }
  if (length > 0) memcpy(buffer, bytes, (size_t)length);
  pumd_api.release(data);
  return (int)length + 1;
}

MOONBIT_FFI_EXPORT int pumd_macos_keychain_replace(
    moonbit_bytes_t value, int length) {
  if (!pumd_initialize() || value == NULL || length <= 0) return PUMD_KEYCHAIN_UNAVAILABLE;
  CFDataRef data = pumd_api.data_create(NULL, value, length);
  if (data == NULL) return PUMD_KEYCHAIN_UNAVAILABLE;
  CFMutableDictionaryRef selector = pumd_query(0, NULL, 0);
  CFMutableDictionaryRef updates = pumd_update_attributes(data);
  if (selector == NULL || updates == NULL) {
    if (selector != NULL) pumd_api.release(selector);
    if (updates != NULL) pumd_api.release(updates);
    pumd_api.release(data);
    return PUMD_KEYCHAIN_UNAVAILABLE;
  }
  OSStatus status = pumd_api.item_update(selector, updates);
  pumd_api.release(selector);
  pumd_api.release(updates);
  if (status == 0) {
    pumd_api.release(data);
    return 0;
  }
  if (status != PUMD_ERR_SEC_ITEM_NOT_FOUND) {
    pumd_api.release(data);
    return pumd_result(status);
  }
  CFMutableDictionaryRef attributes = pumd_query(0, data, 1);
  if (attributes == NULL) {
    pumd_api.release(data);
    return PUMD_KEYCHAIN_UNAVAILABLE;
  }
  status = pumd_api.item_add(attributes, NULL);
  pumd_api.release(attributes);
  if (status == PUMD_ERR_SEC_DUPLICATE_ITEM) {
    selector = pumd_query(0, NULL, 0);
    updates = pumd_update_attributes(data);
    if (selector == NULL || updates == NULL) {
      if (selector != NULL) pumd_api.release(selector);
      if (updates != NULL) pumd_api.release(updates);
      pumd_api.release(data);
      return PUMD_KEYCHAIN_UNAVAILABLE;
    }
    status = pumd_api.item_update(selector, updates);
    pumd_api.release(selector);
    pumd_api.release(updates);
  }
  pumd_api.release(data);
  return pumd_result(status);
}

MOONBIT_FFI_EXPORT int pumd_macos_keychain_delete(void) {
  if (!pumd_initialize()) return PUMD_KEYCHAIN_UNAVAILABLE;
  CFMutableDictionaryRef selector = pumd_query(0, NULL, 0);
  if (selector == NULL) return PUMD_KEYCHAIN_UNAVAILABLE;
  OSStatus status = pumd_api.item_delete(selector);
  pumd_api.release(selector);
  return status == PUMD_ERR_SEC_ITEM_NOT_FOUND ? 0 : pumd_result(status);
}

#else

MOONBIT_FFI_EXPORT int pumd_macos_keychain_available(void) { return 0; }
MOONBIT_FFI_EXPORT int pumd_macos_keychain_load(moonbit_bytes_t buffer, int capacity) {
  (void)buffer; (void)capacity; return -3;
}
MOONBIT_FFI_EXPORT int pumd_macos_keychain_replace(moonbit_bytes_t value, int length) {
  (void)value; (void)length; return -3;
}
MOONBIT_FFI_EXPORT int pumd_macos_keychain_delete(void) { return -3; }

#endif
