#ifndef GPUpdaterUIShell_h
#define GPUpdaterUIShell_h

#if defined(_WIN32)

#include <wchar.h>

// Opens a URL or file with its default handler through ShellExecuteW, in
// plain C: windows.h can't be included next to GNUstep's AppKit headers.
// GNUstep's NSWorkspace has no http(s) handler on win32 ("No service
// matching 'OpenURL'"). Returns 1 when Windows started a handler, else 0.
int GPUpdaterUIShellOpen(const wchar_t *target);

#endif

#endif
