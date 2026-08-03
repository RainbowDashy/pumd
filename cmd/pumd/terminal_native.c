#include <moonbit.h>

#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#include <io.h>
#define PUMD_ISATTY _isatty
#define PUMD_FILENO _fileno
#else
#include <unistd.h>
#define PUMD_ISATTY isatty
#define PUMD_FILENO fileno
#endif

MOONBIT_FFI_EXPORT int pumd_terminal_is_interactive(void) {
  return PUMD_ISATTY(PUMD_FILENO(stdin)) ? 1 : 0;
}

MOONBIT_FFI_EXPORT int pumd_terminal_read_line(
    moonbit_bytes_t buffer, int capacity) {
  if (buffer == NULL || capacity <= 1) return -1;
  if (fgets((char *)buffer, capacity, stdin) == NULL) return -1;
  return (int)strlen((char *)buffer);
}
