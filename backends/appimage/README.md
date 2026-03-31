# AppImage Backend

## Purpose
The AppImage backend packages a staged GNUstep application into a Linux
AppImage using the shared stage-first packaging model.

## Supported Target
- clang-based GNUstep builds on Linux
- x86_64 AppImage artifacts
- PowerShell 7+ orchestration on Linux hosts

## Shared Inputs
- package manifest
- staged payload
- launch contract

## Backend Responsibilities
- transform the staged payload into an AppDir
- generate `AppRun`
- render desktop metadata and icons
- generate MIME metadata from extension associations
- emit notice, metadata, and diagnostics sidecars
- emit AppImage artifacts and validation logs

## Host Requirements
- Linux x64 host
- `pwsh` 7+
- `squashfs-tools`
- `desktop-file-utils` for repo CI and recommended local validation
- `appimagetool` on `PATH`, or let the backend bootstrap it into
  `tools/appimage`

## Commands

```powershell
./scripts/gnustep-packager.ps1 -Command package -Manifest examples/sample-linux/package.manifest.json -Backend appimage
./scripts/gnustep-packager.ps1 -Command validate -Manifest examples/sample-linux/package.manifest.json -Backend appimage -RunSmoke
./scripts/run-packaging-pipeline.ps1 -Manifest examples/sample-linux/package.manifest.json -Backend appimage -RunSmoke
```

## Artifact Layout
The package step emits:
- `<name>-<version>-x86_64.AppImage`
- `<artifact-base>.metadata.json`
- `<artifact-base>.diagnostics.txt`

The temporary AppDir is built under `dist/tmp/appimage/<timestamp>/`.

## Validation
Backend validation checks:
- AppImage extractability
- required AppDir structure
- desktop entry rendering
- optional `desktop-file-validate` output when available
- smoke launch through the packaged AppImage

## Known Limitations
- current artifact generation targets x86_64 only
- the staged Linux payload must already include its runtime closure
- the backend does not currently drive `linuxdeploy` or distro-specific helpers

## CI Usage
Use `.github/workflows/package-gnustep-app.yml` with `backend: appimage`.
The reusable workflow selects `ubuntu-latest` and installs Linux prerequisites
before calling the shared pipeline wrapper.

## Related Docs
- [../../docs/appimage-requirements.md](../../docs/appimage-requirements.md)
- [../../docs/appimage-metadata-mapping.md](../../docs/appimage-metadata-mapping.md)
- [../../docs/appimage-appdir-design.md](../../docs/appimage-appdir-design.md)
- [../../docs/appimage-runtime-policy.md](../../docs/appimage-runtime-policy.md)
