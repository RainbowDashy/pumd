#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include "moonbit.h"

MOONBIT_FFI_EXPORT int pumd_registry_file_mode(moonbit_bytes_t path, int32_t length) {
  char buffer[4096];
  struct stat status;
  if (length < 0 || length >= (int32_t)sizeof(buffer)) return -1;
  memcpy(buffer, path, (size_t)length);
  buffer[length] = '\0';
  if (stat(buffer, &status) != 0) return -1;
  return (int)(status.st_mode & 0777);
}
