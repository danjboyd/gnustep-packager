# Consumer Setup

## Minimal Consumer Shape
A downstream app repo needs:

- a `package.manifest.json`
- a `build` command that produces app output
- a `stage` command that produces the normalized stage layout
- a staged payload that already includes the runtime notices and icons you want
  to ship

## Built-In Profiles
The manifest may opt into small built-in defaults layers through `profiles`.

Current profiles:
- `gnustep-gui`
- `gnustep-document-viewer`

These profiles are intentionally small. They provide common runtime PATH,
resource, and category defaults without hiding the manifest shape.

## Expected Stage Layout

```text
<stage-root>/
  app/
  runtime/
  metadata/
```

Recommended metadata subdirectories:

```text
<stage-root>/metadata/
  icons/
  licenses/
```

## Windows MSI Onboarding
For the current MSI backend, the consumer should:

1. build with MSYS2 `CLANG64`
2. stage a self-contained GNUstep payload under `runtime/`
3. stage any shipped notice files under `metadata/licenses/`
4. enable `backends.msi`
5. provide a stable `upgradeCode`
6. run the shared pipeline wrapper locally before wiring CI

## Linux AppImage Onboarding
For the AppImage backend, the consumer should:

1. build on a Linux x64 host with PowerShell 7+
2. stage a self-contained payload under `app/`, `runtime/`, and `metadata/`
3. stage a packaged `.png` icon and point `backends.appimage.iconRelativePath`
   at it
4. enable `backends.appimage`
5. provide a stable `desktopEntryName`
6. install `squashfs-tools` and `desktop-file-utils` before local validation or
   CI runs

The backend bootstraps `appimagetool` automatically when it is not already on
`PATH`.

## Recommended Manifest Baseline

```json
{
  "profiles": ["gnustep-gui"],
  "compliance": {
    "runtimeNotices": [
      {
        "name": "GNUstep Base",
        "license": "LGPL-2.1-or-later",
        "stageRelativePath": "metadata/licenses/gnustep-base.txt"
      }
    ]
  }
}
```

## Recommended First Run

```powershell
./scripts/run-packaging-pipeline.ps1 `
  -Manifest packaging/package.manifest.json `
  -Backend msi `
  -RunSmoke
```

```powershell
./scripts/run-packaging-pipeline.ps1 `
  -Manifest packaging/package.manifest.json `
  -Backend appimage `
  -RunSmoke
```

## GitHub Actions
Once the local run works, call the reusable workflow documented in
[github-actions.md](github-actions.md).

Related docs:
- [manifest.md](manifest.md)
- [compliance-notices.md](compliance-notices.md)
- [windows-msi-triage.md](windows-msi-triage.md)
- [../backends/appimage/README.md](../backends/appimage/README.md)
