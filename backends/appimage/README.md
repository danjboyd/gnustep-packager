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
- emit optional updater runtime config and update-feed sidecars when updates are
  enabled
- pass native AppImage update information to `appimagetool` and surface `.zsync`
  sidecars when the active toolchain emits them
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
- `<name>-<version>-x86_64.AppImage.zsync` when the active `appimagetool` build
  emits a zsync sidecar for update-enabled packaging
- `<artifact-base>.metadata.json`
- `<artifact-base>.update-feed.json` when updates are enabled
- `<artifact-base>.diagnostics.txt`

The temporary AppDir is built under `dist/tmp/appimage/<timestamp>/`.

## Validation
Backend validation checks:
- AppImage extractability
- strict ELF runtime-closure validation by default
- required AppDir structure
- desktop entry rendering
- optional `desktop-file-validate` output when available
- smoke launch through the packaged AppImage

Supported smoke modes:

- `launch-only`
- `open-file`
- `custom-arguments`
- `marker-file`

## Known Limitations
- current artifact generation targets x86_64 only
- the staged Linux payload must still include its runtime closure; the backend validates that closure but does not harvest missing libraries for you
- the backend does not currently drive `linuxdeploy` or distro-specific helpers

## CI Usage
Use `.github/workflows/package-gnustep-app.yml` with `backend: appimage`.
By default the reusable workflow selects `["ubuntu-latest"]` and installs
`squashfs-tools` plus `desktop-file-utils` before calling the shared pipeline
wrapper.

Downstreams can override:

- `runs-on-appimage` for self-hosted runner labels
- `skip-default-host-setup` when the runner is already provisioned
- `appimage-apt-packages` to change the default apt package list
- `preflight-shell` and `preflight-command` for repo-specific bootstrap work

## Related Docs
- [../../docs/appimage-requirements.md](../../docs/appimage-requirements.md)
- [../../docs/appimage-metadata-mapping.md](../../docs/appimage-metadata-mapping.md)
- [../../docs/appimage-appdir-design.md](../../docs/appimage-appdir-design.md)
- [../../docs/appimage-runtime-policy.md](../../docs/appimage-runtime-policy.md)
