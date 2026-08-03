#include <moonbit.h>

MOONBIT_FFI_EXPORT int pumd_native_credential_platform(void) {
#if defined(__APPLE__) && defined(__aarch64__)
  return 1;
#elif defined(__linux__) && defined(__x86_64__)
  return 2;
#elif defined(_WIN64) && (defined(_M_X64) || defined(__x86_64__))
  return 3;
#else
  return 0;
#endif
}
