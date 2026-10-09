# GPUpdaterCore

`GPUpdaterCore` is the Foundation-only runtime layer for phase 10A-D.

It is responsible for:

- loading the packaged updater runtime config emitted by `gnustep-packager`
- reading a channel feed document
- comparing the current package version against published releases
- selecting the asset that matches the current backend
- persisting user choices such as skipped versions and automatic-check state

It is intentionally not responsible for:

- presenting update dialogs
- downloading payloads with progress UI
- replacing the running executable
- launching MSI installers or applying AppImage replacements

Current public entry points:

- `+[GPUpdaterConfiguration packagedConfigurationWithError:]`
- `-initWithConfiguration:`
- `-start`
- `-checkForUpdates`
- `-checkForUpdatesSynchronously:`
- `GPUpdaterDownloadData()` and `GPUpdaterDownloadToFile()`
  (`GPUpdaterDownload.h`), which the feed check and `gp-update-helper` use

Downloads don't use `-[NSData dataWithContentsOfURL:]`: GNUstep's doesn't
follow HTTP redirects, and GitHub serves release assets through one. On
Windows they go through WinHTTP (`GPUpdaterWinHTTP.c`, plain C because
`winhttp.h` clashes with GNUstep's headers there), so they use the system's
certificate store rather than gnustep-base's bundled list, the system's proxy
settings, and stream the payload to disk; link with `-lwinhttp`. Elsewhere they
use `NSURLHandle` and follow up to ten redirects. `file:` URLs are read
directly.

Build the static library with:

```sh
make
```

The build expects `gnustep-config`, `clang`, and the GNUstep Base development
headers and libraries to be available on the host.
