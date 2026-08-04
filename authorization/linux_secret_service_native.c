#include <moonbit.h>

enum {
  PUMD_SECRET_SERVICE_NOT_CONFIGURED = -1,
  PUMD_SECRET_SERVICE_DENIED = -2,
  PUMD_SECRET_SERVICE_UNAVAILABLE = -3,
  PUMD_SECRET_SERVICE_MALFORMED = -4,
  PUMD_SECRET_SERVICE_UNSUPPORTED = -5,
  PUMD_SECRET_SERVICE_LOCKED = -7,
  PUMD_SECRET_SERVICE_CLEANUP_FAILED = -8,
};

#if defined(__linux__) && defined(__x86_64__)

#include <dlfcn.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct _SecretSchema SecretSchema;
typedef struct _GError GError;
typedef uint32_t GQuark;

enum {
  PUMD_SECRET_ERROR_IS_LOCKED = 1,
  PUMD_G_IO_ERROR_PERMISSION_DENIED = 14,
  PUMD_G_IO_ERROR_CANCELLED = 19,
  PUMD_G_DBUS_ERROR_ACCESS_DENIED = 9,
  PUMD_G_DBUS_ERROR_AUTH_FAILED = 10,
  PUMD_SECRET_SCHEMA_ATTRIBUTE_STRING = 0,
};

struct pumd_secret_service_api {
  void *library;
  SecretSchema *(*schema_new)(const char *, int, ...);
  char *(*password_lookup_sync)(const SecretSchema *, void *, GError **, ...);
  int (*password_store_sync)(
      const SecretSchema *, const char *, const char *, const char *, void *,
      GError **, ...);
  int (*password_clear_sync)(const SecretSchema *, void *, GError **, ...);
  void (*password_free)(char *);
  GQuark (*secret_error_get_quark)(void);
  GQuark (*io_error_quark)(void);
  GQuark (*dbus_error_quark)(void);
  int (*error_matches)(const GError *, GQuark, int);
  void (*error_free)(GError *);
  SecretSchema *schema;
};

static struct pumd_secret_service_api pumd_api;
static int pumd_api_state = 0;

static int pumd_initialize(void) {
  if (pumd_api_state != 0) return pumd_api_state == 1;
  pumd_api_state = -1;
  pumd_api.library = dlopen("libsecret-1.so.0", RTLD_NOW | RTLD_LOCAL);
  if (pumd_api.library == NULL) {
    pumd_api.library = dlopen("libsecret-1.so", RTLD_NOW | RTLD_LOCAL);
  }
  if (pumd_api.library == NULL) return 0;
#define PUMD_FUNCTION(field, symbol) \
  pumd_api.field = dlsym(pumd_api.library, symbol); \
  if (pumd_api.field == NULL) return 0
  PUMD_FUNCTION(schema_new, "secret_schema_new");
  PUMD_FUNCTION(password_lookup_sync, "secret_password_lookup_sync");
  PUMD_FUNCTION(password_store_sync, "secret_password_store_sync");
  PUMD_FUNCTION(password_clear_sync, "secret_password_clear_sync");
  PUMD_FUNCTION(password_free, "secret_password_free");
  PUMD_FUNCTION(secret_error_get_quark, "secret_error_get_quark");
  PUMD_FUNCTION(io_error_quark, "g_io_error_quark");
  PUMD_FUNCTION(dbus_error_quark, "g_dbus_error_quark");
  PUMD_FUNCTION(error_matches, "g_error_matches");
  PUMD_FUNCTION(error_free, "g_error_free");
#undef PUMD_FUNCTION
  pumd_api.schema = pumd_api.schema_new(
      "io.github.rainbowdashy.pumd.ProjectAuthorization", 0,
      "account", PUMD_SECRET_SCHEMA_ATTRIBUTE_STRING, NULL);
  if (pumd_api.schema == NULL) return 0;
  pumd_api_state = 1;
  return 1;
}

static int pumd_error_result(GError *error) {
  int result = PUMD_SECRET_SERVICE_UNAVAILABLE;
  if (error != NULL) {
    if (pumd_api.error_matches(
            error, pumd_api.secret_error_get_quark(),
            PUMD_SECRET_ERROR_IS_LOCKED)) {
      result = PUMD_SECRET_SERVICE_LOCKED;
    } else if (pumd_api.error_matches(
            error, pumd_api.io_error_quark(),
            PUMD_G_IO_ERROR_PERMISSION_DENIED) ||
        pumd_api.error_matches(
            error, pumd_api.io_error_quark(), PUMD_G_IO_ERROR_CANCELLED) ||
        pumd_api.error_matches(
            error, pumd_api.dbus_error_quark(),
            PUMD_G_DBUS_ERROR_ACCESS_DENIED) ||
        pumd_api.error_matches(
            error, pumd_api.dbus_error_quark(),
            PUMD_G_DBUS_ERROR_AUTH_FAILED)) {
      result = PUMD_SECRET_SERVICE_DENIED;
    }
    pumd_api.error_free(error);
  }
  return result;
}

static void pumd_wipe(char *value, size_t length) {
  volatile unsigned char *cursor = (volatile unsigned char *)value;
  while (length-- > 0) *cursor++ = 0;
}

MOONBIT_FFI_EXPORT int pumd_linux_secret_service_available(void) {
  return pumd_initialize() ? 1 : 0;
}

MOONBIT_FFI_EXPORT int pumd_linux_secret_service_probe(void) {
  static const char account[] = "capability-probe-v1";
  static const char marker[] = "p";
  if (!pumd_initialize()) return PUMD_SECRET_SERVICE_UNAVAILABLE;

  GError *error = NULL;
  (void)pumd_api.password_clear_sync(
      pumd_api.schema, NULL, &error, "account", account, NULL);
  if (error != NULL) return pumd_error_result(error);

  int stored = pumd_api.password_store_sync(
      pumd_api.schema, NULL, "pumd credential-store capability probe", marker,
      NULL, &error, "account", account, NULL);
  if (!stored) return pumd_error_result(error);
  if (error != NULL) pumd_api.error_free(error);

  error = NULL;
  char *password = pumd_api.password_lookup_sync(
      pumd_api.schema, NULL, &error, "account", account, NULL);
  int result = 0;
  if (password == NULL) {
    result = error == NULL ? PUMD_SECRET_SERVICE_MALFORMED
                           : pumd_error_result(error);
  } else {
    if (strcmp(password, marker) != 0) result = PUMD_SECRET_SERVICE_MALFORMED;
    pumd_api.password_free(password);
  }

  error = NULL;
  (void)pumd_api.password_clear_sync(
      pumd_api.schema, NULL, &error, "account", account, NULL);
  if (error != NULL) {
    pumd_api.error_free(error);
    return PUMD_SECRET_SERVICE_CLEANUP_FAILED;
  }
  return result;
}

MOONBIT_FFI_EXPORT int pumd_linux_secret_service_load(
    moonbit_bytes_t buffer, int capacity) {
  if (!pumd_initialize()) return PUMD_SECRET_SERVICE_UNAVAILABLE;
  if (buffer == NULL || capacity <= 0) return PUMD_SECRET_SERVICE_MALFORMED;
  GError *error = NULL;
  char *password = pumd_api.password_lookup_sync(
      pumd_api.schema, NULL, &error, "account", "active-v1", NULL);
  if (password == NULL) {
    return error == NULL ? PUMD_SECRET_SERVICE_NOT_CONFIGURED
                         : pumd_error_result(error);
  }
  size_t length = strlen(password);
  if (length == 0 || length >= (size_t)capacity) {
    pumd_api.password_free(password);
    return PUMD_SECRET_SERVICE_MALFORMED;
  }
  memcpy(buffer, password, length);
  pumd_api.password_free(password);
  return (int)length + 1;
}

MOONBIT_FFI_EXPORT int pumd_linux_secret_service_replace(
    moonbit_bytes_t value, int length) {
  if (!pumd_initialize()) return PUMD_SECRET_SERVICE_UNAVAILABLE;
  if (value == NULL || length <= 0) return PUMD_SECRET_SERVICE_MALFORMED;
  char *password = malloc((size_t)length + 1);
  if (password == NULL) return PUMD_SECRET_SERVICE_UNAVAILABLE;
  memcpy(password, value, (size_t)length);
  password[length] = '\0';
  GError *error = NULL;
  int stored = pumd_api.password_store_sync(
      pumd_api.schema, NULL, "pumd Project Authorization", password, NULL,
      &error, "account", "active-v1", NULL);
  pumd_wipe(password, (size_t)length);
  free(password);
  if (stored) {
    if (error != NULL) pumd_api.error_free(error);
    return 0;
  }
  return pumd_error_result(error);
}

MOONBIT_FFI_EXPORT int pumd_linux_secret_service_delete(void) {
  if (!pumd_initialize()) return PUMD_SECRET_SERVICE_UNAVAILABLE;
  GError *error = NULL;
  int removed = pumd_api.password_clear_sync(
      pumd_api.schema, NULL, &error, "account", "active-v1", NULL);
  if (error != NULL) return pumd_error_result(error);
  (void)removed;
  return 0;
}

#else

MOONBIT_FFI_EXPORT int pumd_linux_secret_service_available(void) { return 0; }
MOONBIT_FFI_EXPORT int pumd_linux_secret_service_probe(void) {
  return PUMD_SECRET_SERVICE_UNSUPPORTED;
}
MOONBIT_FFI_EXPORT int pumd_linux_secret_service_load(
    moonbit_bytes_t buffer, int capacity) {
  (void)buffer;
  (void)capacity;
  return PUMD_SECRET_SERVICE_UNSUPPORTED;
}
MOONBIT_FFI_EXPORT int pumd_linux_secret_service_replace(
    moonbit_bytes_t value, int length) {
  (void)value;
  (void)length;
  return PUMD_SECRET_SERVICE_UNSUPPORTED;
}
MOONBIT_FFI_EXPORT int pumd_linux_secret_service_delete(void) {
  return PUMD_SECRET_SERVICE_UNSUPPORTED;
}

#endif
