# MSI Runtime Policy

## Purpose
This document defines how the Windows MSI backend treats GNUstep runtime
content staged from an MSYS2 `CLANG64` toolchain.

## Install Layout
The backend installs a private runtime under the app root:

```text
<install-root>\
  <launcher>.exe
  <launcher>.launcher.ini
  app\
  runtime\
  metadata\
```

The runtime stays app-private by default. The backend does not install into a
shared machine-wide `C:\clang64` tree.

## Stage Ownership
The consumer repo's `stage` command remains responsible for staging:

- the GNUstep app payload under `app/`
- primary runtime content under `runtime/`
- shared metadata under `metadata/`

The MSI backend is allowed to augment runtime DLL closure, but it should not
discover the app from raw build output.

## Inclusion Rules
The backend copies these stage roots into the install tree when present:

- `payload.appRoot`
- `payload.runtimeRoot`
- `payload.metadataRoot`

It excludes packaging-only directories such as stage logs unless the manifest
explicitly points to them.

## Dependency Closure
The backend performs DLL closure for:

- the launch entry executable
- files listed in `payload.runtimeSeedPaths`
- already-staged runtime DLLs and EXEs

Missing non-system DLLs are searched under `backends.msi.runtimeSearchRoots`
and copied into `runtime/bin` when found.

Installed-runtime validation audits only the installed payload tree. Standard
Windows OS imports are classified centrally as system dependencies and are not
expected to be bundled under `runtime/`.

If unresolved non-system DLLs remain after closure analysis, packaging fails by
default.

The manifest may opt into an explicit compatibility override:

- `backends.msi.unresolvedDependencyPolicy: warn`
  Continue packaging but keep logging unresolved imports.
- `backends.msi.ignoredRuntimeDependencies[]`
  Suppress known optional imports from the effective failure set while still
  keeping the closure logic explicit.

## Support Assets
GNUstep support assets such as themes, bundles, and fontconfig data should
already be staged under `runtime/`. The backend preserves them as staged rather
than reconstructing them through WiX-specific rules.

When `packagedDefaults.appDomain` is declared, the staged runtime must also
include `runtime/bin/defaults.exe`. The launcher uses that bundled tool to seed
app-domain defaults on first launch only when the packaged app has not already
stored the key.

`packagedDefaults.defaultTheme` also uses that packaged defaults tool to seed
`GSTheme` into the packaged app's defaults domain on first launch, while
preserving the launcher env fallback for immediate startup behavior.

This mechanism is intentionally scoped to the packaged app's own defaults
domain. The MSI backend does not provide generic GNUstep global-domain
preference writes.

## Fallback Runtime
The launcher prefers the bundled `runtime\` tree. A fallback runtime root may
be used only when configured through `backends.msi.fallbackRuntimeRoot`.

The fallback is a compatibility escape hatch, not the default runtime model.
