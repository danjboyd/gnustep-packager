#include "GPUpdaterWinHTTP.h"

#if defined(_WIN32)

#include <windows.h>
#include <winhttp.h>
#include <stdlib.h>
#include <string.h>

// Copies length characters of s into a new NUL terminated string.
static wchar_t *GPCopyWide(const wchar_t *s, DWORD length) {
  wchar_t *copy = calloc(length + 1, sizeof(wchar_t));
  if (copy != NULL && length > 0) {
    memcpy(copy, s, length * sizeof(wchar_t));
  }
  return copy;
}

int GPUpdaterWinHTTPGet(const wchar_t *url, GPUpdaterWinHTTPSink sink, void *context,
                        unsigned long *status, unsigned long *systemError) {
  URL_COMPONENTS components;
  HINTERNET session = NULL;
  HINTERNET connection = NULL;
  HINTERNET request = NULL;
  wchar_t *host = NULL;
  wchar_t *path = NULL;
  DWORD httpStatus = 0;
  DWORD size = sizeof(httpStatus);
  int ok = 0;

  *status = 0;
  *systemError = 0;

  memset(&components, 0, sizeof(components));
  components.dwStructSize = sizeof(components);
  components.dwSchemeLength = (DWORD)-1;
  components.dwHostNameLength = (DWORD)-1;
  components.dwUrlPathLength = (DWORD)-1;
  components.dwExtraInfoLength = (DWORD)-1;
  if (!WinHttpCrackUrl(url, 0, 0, &components)) {
    *systemError = GetLastError();
    return 0;
  }
  host = GPCopyWide(components.lpszHostName, components.dwHostNameLength);
  // The path and the query, which follows it in the URL.
  path = GPCopyWide(components.lpszUrlPath,
                    components.dwUrlPathLength + components.dwExtraInfoLength);
  if (host == NULL || path == NULL) {
    goto done;
  }

  // The system's proxy settings (Windows 8.1 and later), else WinHTTP's own.
  session = WinHttpOpen(L"gnustep-packager-updater/1", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                        WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (session == NULL) {
    session = WinHttpOpen(L"gnustep-packager-updater/1", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                          WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  }
  if (session == NULL) {
    *systemError = GetLastError();
    goto done;
  }
  connection = WinHttpConnect(session, host, components.nPort, 0);
  if (connection == NULL) {
    *systemError = GetLastError();
    goto done;
  }
  // WinHTTP follows redirects itself, except from HTTPS to HTTP, and checks
  // certificates against the system's store.
  request = WinHttpOpenRequest(connection, L"GET", path[0] ? path : L"/", NULL,
                               WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                               components.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0);
  if (request == NULL
      || !WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0)
      || !WinHttpReceiveResponse(request, NULL)) {
    *systemError = GetLastError();
    goto done;
  }
  if (!WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                           WINHTTP_HEADER_NAME_BY_INDEX, &httpStatus, &size, WINHTTP_NO_HEADER_INDEX)) {
    *systemError = GetLastError();
    goto done;
  }
  *status = httpStatus;
  if (httpStatus != 200) {
    goto done;
  }

  {
    static const DWORD bufferSize = 65536;
    char *buffer = malloc(bufferSize);

    if (buffer == NULL) {
      goto done;
    }
    ok = 1;
    for (;;) {
      DWORD available = 0;
      DWORD read = 0;

      if (!WinHttpQueryDataAvailable(request, &available)) {
        *systemError = GetLastError();
        ok = 0;
        break;
      }
      if (available == 0) {
        break;
      }
      if (available > bufferSize) {
        available = bufferSize;
      }
      if (!WinHttpReadData(request, buffer, available, &read)) {
        *systemError = GetLastError();
        ok = 0;
        break;
      }
      if (read == 0) {
        break;
      }
      if (!sink(context, buffer, read)) {
        ok = 0;
        break;
      }
    }
    free(buffer);
  }

done:
  if (request != NULL) {
    WinHttpCloseHandle(request);
  }
  if (connection != NULL) {
    WinHttpCloseHandle(connection);
  }
  if (session != NULL) {
    WinHttpCloseHandle(session);
  }
  free(host);
  free(path);
  return ok;
}

#endif
