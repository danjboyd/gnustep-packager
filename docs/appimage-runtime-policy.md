# AppImage Runtime Policy

## Purpose
The AppImage runtime policy keeps Linux launch behavior expressed through the
shared launch contract instead of hard-coded per-app shell scripts.

## AppRun Responsibilities
The generated `AppRun`:

- resolves `APPDIR` and `usr/`
- maps shared roots into `APP_ROOT`, `RUNTIME_ROOT`, and `METADATA_ROOT`
- resolves the shared launch entry path and working directory
- prepends `launch.pathPrepend` entries to `PATH`
- exports `launch.env` values after token expansion and respects assignment
  policy such as `ifUnset`
- forwards manifest launch arguments before user-provided arguments
- executes the staged app entry point

## Token Expansion
The AppImage backend renders these shared tokens into shell expressions:

- `{@installRoot}` -> `${APPDIR}`
- `{@appRoot}` -> `${APP_ROOT}`
- `{@runtimeRoot}` -> `${RUNTIME_ROOT}`
- `{@metadataRoot}` -> `${METADATA_ROOT}`

## GNUstep Defaults
If the manifest does not supply `GNUSTEP_PATHPREFIX_LIST`, the backend defaults
it to `{@runtimeRoot}`.

If a bundled fontconfig tree exists under `runtime/etc/fonts`, `AppRun` also
exports:

- `FONTCONFIG_FILE`
- `FONTCONFIG_PATH`

## Current Boundary
The backend does not attempt dynamic Linux dependency harvesting. The consumer
must still stage the runtime tree and any required native dependencies before
packaging.

Validation now checks that extracted packaged ELF files:

- do not carry host-escaping `RUNPATH` or `RPATH` entries unless explicitly
  allowlisted
- do not retain unresolved dependencies under the packaged library search path
- optionally stay within an explicit host-system library allowlist
