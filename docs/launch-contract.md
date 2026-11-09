# Launch Contract

## Purpose
The launch contract is the backend-neutral description of how the packaged app
starts from the staged payload.

It answers:
- what executable should launch
- what should be the working directory
- what path entries should be prepended
- which resource roots matter at startup
- which environment variables must be set
- whether an environment value is unconditional or only a default

## Inputs
The current launch contract is built from:
- `payload.stageRoot`
- `payload.appRoot`
- `payload.runtimeRoot`
- `payload.metadataRoot`
- `payload.resourceRoots`
- `launch.entryRelativePath`
- `launch.workingDirectory`
- `launch.arguments`
- `launch.pathPrepend`
- `launch.resourceRoots`
- `launch.env`

## Output Shape
The normalized launch contract includes:
- stage root path
- entry path
- working directory path
- native path-prepend entries
- native resource-root entries
- startup environment variables normalized to `{ value, policy }`
- backend-formatted path variants

Plain string `launch.env` entries normalize to `policy: override`.

Current assignment policies:
- `override`
  Always set the variable in the backend launcher.
- `ifUnset`
  Set the variable only when the variable is not already defined in the
  process environment.
- `prepend`
  Put the value in front of the variable's current value, joined with `:`
  (AppImage) or `;` (MSI), for search paths such as `XDG_DATA_DIRS` that
  must keep the host's entries. An optional `hostDefault` (AppImage) is the
  host value assumed when the variable is unset, such as
  `/usr/local/share:/usr/share` for `XDG_DATA_DIRS`.

## Runtime Tokens
Backend renderers may expand these tokens inside launch-environment values:

- `{@installRoot}`
- `{@appRoot}`
- `{@runtimeRoot}`
- `{@metadataRoot}`
- `{@userRuntimeDir}` (AppImage only; see `appimage-runtime-policy.md`. Other backends
  leave it as written, so set it under `platformOverrides.linux.launch.env`.)

Those tokens let one manifest describe launch requirements without hard-coding
Windows install paths or Linux mount paths.

## Why It Exists
This is the shared abstraction that should later feed:
- a Windows bootstrap launcher for MSI
- an `AppRun` launcher for AppImage

Without this layer, Windows launch details would hard-code assumptions that
make the Linux backend harder to add cleanly.

## AppImage: the Caller's Environment (`GP_HOST_*`)

From v0.1.9, the AppImage `AppRun` saves the caller's environment before it
changes anything. The saved values are a stable interface: an app, or a
program it starts, can use them to give a child process the environment the
AppImage was started with. The bundled `gp-bin/xdg-open` uses them that way.

### What Is Saved

The first thing `AppRun` does, before it sets `GNUSTEP_CONFIG_FILE`, `PATH`,
`LD_LIBRARY_PATH`, the fontconfig variables or any `launch.env` entry, is to
record these variables:

- `PATH`, `LD_LIBRARY_PATH`, `GNUSTEP_CONFIG_FILE`, `FONTCONFIG_FILE` and
  `FONTCONFIG_PATH`, always;
- every `launch.env` key, whatever its policy.

For each one:

| Caller's variable | Result |
| --- | --- |
| set, even to an empty string | `GP_HOST_<name>` is exported with the caller's value |
| unset | `<name>` is added to `GP_HOST_UNSET` |

`AppRun` also exports:

- `GP_HOST_VARS`: every name in the list above, separated by spaces;
- `GP_HOST_UNSET`: the unset names, separated by spaces (it may be empty);
- `GP_HOST_PWD`: the caller's working directory.

All of these are exported, so the app and every process it starts inherit
them.

`AppRun` saves nothing else. Apart from those and its own `GP_*` variables
(`GP_HOST_*`, and `GP_USER_RUNTIME_DIR` when a value uses `{@userRuntimeDir}`),
`AppRun` exports nothing, so any other variable still has the caller's value.
`launch.pathPrepend` changes `PATH`, which is saved. The AppImage
runtime sets `APPDIR`, `APPIMAGE`, `ARGV0` and `OWD` before `AppRun` runs; they
aren't saved, and the caller never had them.

### Relaunching

`AppRun` saves only when `GP_HOST_VARS` is absent from its environment. An app
relaunched from inside the AppImage, after an update or from a different
mount, keeps the first launch's values instead of saving the bundled ones.

This has a consequence: a process that inherits `GP_HOST_*` and starts
*another* AppImage makes that AppImage skip saving, too. That's why removing
the markers is part of restoring the environment (below).

### Read `GP_HOST_UNSET` First

A `launch.env` key with policy `prepend` also gets its own `GP_HOST_<key>`
(introduced before v0.1.9 so that a relaunch doesn't stack packaged entries).
When the caller had that variable unset, the key is in `GP_HOST_UNSET`, *and*
`GP_HOST_<key>` is exported as an empty string. So a consumer must decide
from `GP_HOST_UNSET`, not from whether `GP_HOST_<key>` exists:

- name in `GP_HOST_UNSET`: the caller had it unset;
- otherwise, `GP_HOST_<name>` set: the caller's value, possibly empty.

### Restoring the Caller's Environment

To start a host program with the caller's environment, do what
`gp-bin/xdg-open` does, in this order:

1. for each name in `GP_HOST_VARS` with `GP_HOST_<name>` set, export the name
   with that value;
2. for each name in `GP_HOST_UNSET`, unset it (this comes after step 1, so it
   wins for `prepend` keys);
3. optionally, change to `GP_HOST_PWD`;
4. unset every `GP_HOST_*` variable, plus `GP_HOST_VARS`, `GP_HOST_UNSET`,
   `GP_HOST_PWD`, `APPDIR`, `APPIMAGE`, `ARGV0` and `OWD`.

Skip any name that isn't a shell identifier (`[A-Za-z0-9_]`). Step 4 keeps an
AppImage started by that program from treating it as a relaunch.

In C or Objective-C, read the same variables with `getenv`, and build the
child's environment (for `NSTask`, its `environment` dictionary) the same way.

### Before v0.1.9

Up to v0.1.8, only `launch.env` keys with policy `prepend` had a
`GP_HOST_<key>`, set to `${<key>:-}`, so an empty value and an unset one look
the same. `GNUSTEP_CONFIG_FILE` and the other variables above weren't saved.
An app pinned to v0.1.8 or earlier that needs the caller's values must save
them in a wrapper of its own that runs before `AppRun`.

### Sources

- `Write-GpAppImageAppRun` in `backends/appimage/lib/appimage.ps1`: the saving
  block at the top of `AppRun`, and the `prepend` policy.
- `Write-GpAppImageHostToolWrappers` in the same file: `gp-bin/xdg-open`, the
  reference restorer.
- `tests/linux/AppImageBackend.Tests.ps1`: "starts xdg-open children with the
  host's environment and directory" covers the restorer, and "passes the
  caller's environment to the app as GP_HOST_*" covers what the app receives.
