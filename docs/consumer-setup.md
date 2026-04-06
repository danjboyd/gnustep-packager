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
7. add app-specific MSYS2 packages in reusable-workflow calls through
   `msys2-packages` when the default GNUstep baseline is not enough

The reusable workflow's default MSI host setup installs a GNUstep-capable MSYS2
`CLANG64` baseline. Downstream apps remain responsible for app-specific
dependencies such as `mingw-w64-clang-x86_64-cmark`.

## Linux AppImage Onboarding
For the AppImage backend, the consumer should:

1. build on a Linux x64 host with PowerShell 7+
2. stage a self-contained payload under `app/`, `runtime/`, and `metadata/`
3. stage a packaged `.png` icon and point `backends.appimage.iconRelativePath`
   at it
4. enable `backends.appimage`
5. provide a stable `desktopEntryName`
6. choose an AppImage smoke mode under `backends.appimage.smoke`
7. install `squashfs-tools` and `desktop-file-utils` before local validation or
   let the reusable workflow install them in CI

Recommended AppImage smoke modes:

- `launch-only` for normal GUI apps that should just start successfully
- `open-file` for document apps that should open a staged sample document
- `custom-arguments` for app-specific automation flags
- `marker-file` only when the app intentionally participates in that harness

The backend bootstraps `appimagetool` automatically when it is not already on
`PATH`.

## Updater Onboarding
Once packaging works locally, an app can opt into the updater companion path:

1. enable the manifest `updates` block
2. configure stable backend feed URLs
3. ship `GPUpdaterCore`
4. optionally ship `GPUpdaterUI` and `gp-update-helper`
5. publish the generated `.update-feed.json` sidecars to stable feed URLs

Recommended updater docs:

- [update-architecture.md](update-architecture.md)
- [update-feed-contract.md](update-feed-contract.md)
- [updater-consumer-guide.md](updater-consumer-guide.md)
- [updater-release-publishing.md](updater-release-publishing.md)

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

Hosted-runner consumers can usually rely on the workflow defaults. Self-hosted
or more advanced consumers can override `runs-on-*`, disable default host setup,
and inject repo-owned preflight commands without forking the workflow.

Related docs:
- [manifest.md](manifest.md)
- [compliance-notices.md](compliance-notices.md)
- [windows-msi-triage.md](windows-msi-triage.md)
- [../backends/appimage/README.md](../backends/appimage/README.md)
- [updater-consumer-guide.md](updater-consumer-guide.md)
