#ifndef GPUpdaterWinHTTP_h
#define GPUpdaterWinHTTP_h

#if defined(_WIN32)

#include <wchar.h>

// A GET through WinHTTP, in plain C: winhttp.h can't be included next to
// GNUstep's Foundation headers on Windows (both define the WinINet types).
//
// The body is passed to sink in chunks; sink returns 0 to stop. Returns 1
// when the server answered 200 and the whole body was passed on, else 0 with
// *status (the HTTP status, 0 if there was none) and *systemError
// (GetLastError(), 0 if there was none) describing why.
typedef int (*GPUpdaterWinHTTPSink)(void *context, const void *bytes, unsigned long length);

int GPUpdaterWinHTTPGet(const wchar_t *url, GPUpdaterWinHTTPSink sink, void *context,
                        unsigned long *status, unsigned long *systemError);

#endif

#endif
