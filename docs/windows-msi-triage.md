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

### Runtime Closure
Symptoms:
- unresolved dependency list in the package log
- smoke launch starts but app process never appears

First checks:
- inspect `UnresolvedDependencies` in `<artifact-base>.metadata.json`
- confirm `runtimeSearchRoots` covers the intended GNUstep runtime tree

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

First checks:
- inspect `install.log` and `uninstall.log`
- compare expected install path, launcher path, and app path in the validation
  log

## Reproduction Commands

```powershell
./scripts/gnustep-packager.ps1 -Command package -Manifest packaging/package.manifest.json -Backend msi
./scripts/gnustep-packager.ps1 -Command validate -Manifest packaging/package.manifest.json -Backend msi -RunSmoke
```
