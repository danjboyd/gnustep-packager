# Windows MSI Triage

## Primary Outputs
After `package -Backend msi`, inspect these first:

- the main package log under `dist/logs/package-msi/`
- `<artifact-base>.diagnostics.txt`
- `<artifact-base>.metadata.json`
- the installed-payload notice report under `metadata/THIRD-PARTY-NOTICES.txt`

After `validate -Backend msi`, inspect:

- the main validation log under `dist/logs/validate-msi/`
- `install.log`
- `uninstall.log`

## Common Failure Areas

### Launcher Compilation
Symptoms:
- missing `clang`
- missing `windres`
- launcher EXE not generated

First checks:
- confirm MSYS2 `CLANG64` tools are installed
- confirm the configured staged `.ico` exists when `iconRelativePath` is set
- compiler or linker warnings written to stderr are logged but should not fail
  packaging by themselves; treat a nonzero native exit code as the actual
  failure signal

### Runtime Closure
Symptoms:
- package stops with an unresolved dependency failure
- smoke launch starts but app process never appears

First checks:
- inspect `UnresolvedDependencies` in `<artifact-base>.metadata.json`
- inspect `runtime.closureMissingGroups` in `<artifact-base>.metadata.json`
- inspect grouped target and missing-DLL summaries in
  `<artifact-base>.diagnostics.txt`
- confirm `runtimeSearchRoots` covers the intended GNUstep runtime tree
- use `ignoredRuntimeDependencies` only for genuinely optional imports
- use `unresolvedDependencyPolicy=warn` only as an explicit compatibility escape hatch

If diagnostics name a target under `runtime/lib/...` rather than `runtime/bin/`,
the missing dependency is coming from a runtime-extension DLL such as a GNUstep
bundle, theme, or plugin.

### WiX Bootstrap or Build
Symptoms:
- `heat`, `candle`, or `light` failures
- MSI never appears in `dist/packages`

First checks:
- confirm WiX download or local tool bootstrap succeeded
- inspect the generated WiX sources under the temp work root recorded in the
  metadata sidecar
- if ICE execution is broken on the host, reproduce with
  `GP_WIX_SUPPRESS_ICES=ICE01,ICE02,...` only as an explicit local override,
  not as a default repo policy
- if the host cannot execute any ICE actions at all, `GP_WIX_SKIP_VALIDATION=1`
  is the last-resort local override

### Signing
Symptoms:
- launcher or MSI signing fails

First checks:
- verify `GP_SIGN_*` environment variables or manifest signing settings
- confirm `signtool.exe` is discoverable

### Validation
Symptoms:
- install/uninstall exit code failures
- smoke timeout
- packaged app never stays running
- validation reports an installed runtime-closure audit failure before smoke
- validation reports a launcher success but no packaged app process observed

First checks:
- inspect `install.log` and `uninstall.log`
- compare expected install path, launcher path, and app path in the validation
  log
- inspect the validation log for `Installed runtime audit:` lines; these now
  group missing non-system dependencies by the DLL that required them
- if the reported import is a standard Windows OS library such as
  `dwrite.dll`, `gdiplus.dll`, `msimg32.dll`, `opengl32.dll`, `usp10.dll`,
  `winhttp.dll`, `winspool.drv`, or `wsock32.dll`, treat that as a backend
  classification gap rather than a consumer staging miss

## Reproduction Commands

```powershell
./scripts/gnustep-packager.ps1 -Command package -Manifest packaging/package.manifest.json -Backend msi
./scripts/gnustep-packager.ps1 -Command validate -Manifest packaging/package.manifest.json -Backend msi -RunSmoke
```
