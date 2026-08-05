#include <moonbit.h>
#include <time.h>

MOONBIT_FFI_EXPORT int64_t pumd_unix_seconds(void) {
  return (int64_t)time(NULL);
}
