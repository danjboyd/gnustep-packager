#if defined(_WIN32)

#include <windows.h>
#include <shellapi.h>

#include "GPUpdaterUIShell.h"

int GPUpdaterUIShellOpen(const wchar_t *target) {
  if (target == NULL || target[0] == 0) {
    return 0;
  }
  // ShellExecute returns a value above 32 on success.
  HINSTANCE result = ShellExecuteW(NULL, L"open", target, NULL, NULL, SW_SHOWNORMAL);
  return (INT_PTR)result > 32 ? 1 : 0;
}

#endif
