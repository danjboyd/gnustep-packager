# GPUpdaterUI

`GPUpdaterUI` is the optional AppKit layer for apps that want a default update
experience instead of building their own dialogs around `GPUpdaterCore`.

It provides:

- default `Check for Updates...` handling
- update-available and up-to-date dialogs
- helper-driven prepare progress polling through a machine-readable state file
- restart-to-update and failure handling
- delegate hooks for string overrides and release-note presentation

It does not apply updates in process. The controller writes a helper plan and
launches `gp-update-helper` for download and installation work.

Build the static library with:

```sh
make
```

The build expects `gnustep-config`, `clang`, and the GNUstep GUI development
headers and libraries to be available on the host.
