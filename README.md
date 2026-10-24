# gnustep-packager

Package GNUstep desktop applications as a Windows MSI, a Linux AppImage, or a
macOS DMG, all from one manifest and one staged payload.

`gnustep-packager` takes packaging out of individual app repos. You describe
your app once in `package.manifest.json`. The packager then builds and stages it
and turns the staged payload into native distributables. It also smoke-tests
each result and writes metadata, provenance, and update-feed files beside each
artifact. You can run it from the command line or from a reusable GitHub Actions
workflow, and both paths behave the same.

| Backend | Host and toolchain | Output |
| --- | --- | --- |
| Windows MSI | Windows x64, MSYS2 `CLANG64` GNUstep, WiX 3.11 (fetched automatically) | `<name>-<version>-win64.msi` plus a portable `.zip` |
| Linux AppImage | Linux x64, clang-based GNUstep, `appimagetool` (fetched automatically) | `<name>-<version>-x86_64.AppImage` plus an optional `.zsync` |
| macOS DMG | macOS 13+, a native `.app` built with Xcode clang, Apple's built-in tools only | `<name>-<version>-macos-<arch>.dmg` |

See [docs/compatibility-matrix.md](docs/compatibility-matrix.md) for the full
support table.

## Features
- **Stage-first pipeline**: `build -> stage -> provision -> package -> validate`.
  The staged payload is the single source of truth for every backend.
- **Backend-neutral manifest**: a JSON Schema-validated
  `package.manifest.json` with layered defaults, built-in profiles for common
  GNUstep app shapes (`gnustep-gui`, `gnustep-document-viewer`,
  `gnustep-cmark`), and `platformOverrides` so one manifest can cover all three
  platforms.
- **Generated launchers**: a Windows bootstrap EXE or a Linux `AppRun` is
  rendered from one launch contract. Environment defaults such as `GSTheme`
  are applied only when the user has not already set them.
- **Runtime closure checks**: MSI and AppImage validation fails when a DLL or
  shared library the app needs is missing from the payload. You can allowlist
  known optional imports.
- **Smoke validation**: MSI install, launch, and uninstall; AppImage extract,
  desktop-entry, and launch checks; DMG `hdiutil verify`, `codesign`, and
  Gatekeeper assessment.
- **Theme provisioning**: `themeInputs` builds GNUstep themes (for example
  WinUITheme) from their own repos and bundles them, so apps don't need their
  own clone-and-copy scripts.
- **Release metadata**: each artifact gets a `.metadata.json`, a
  `.diagnostics.txt`, and a publishable `.provenance.json` (artifact hash,
  source and packager commits, bundled GNUstep libraries with ELF build IDs).
- **Signing**: Authenticode hooks for MSI; ad-hoc, identity, and Developer ID
  signing plus a notarization path for DMG.
- **Updater**: a Foundation-only Objective-C updater library, an optional
  AppKit UI, and a separate update helper. Apps that publish MSI and AppImage
  releases on GitHub can use them to update themselves.
- **Host dependencies**: manifest-declared MSYS2 and apt packages are checked
  or installed before packaging, both locally and in CI.

## Quick Start

### Requirements
- PowerShell 7+ (`pwsh`) on every host
- The host and toolchain for your backend, listed in the table above
- Linux AppImage validation also needs `squashfs-tools` and
  `desktop-file-utils`

### 1. Write a manifest
Copy a template from [examples/downstream/](examples/downstream/) into your app
repo, for example `packaging/package.manifest.json`. A minimal manifest
that passes `manifest-check`:

```json
{
  "$schema": "https://raw.githubusercontent.com/danjboyd/gnustep-packager/main/schemas/gnustep-packager.schema.json",
  "schemaVersion": 1,
  "profiles": ["gnustep-gui"],
  "package": {
    "id": "com.example.MyGNUstepApp",
    "name": "MyGNUstepApp",
    "displayName": "My GNUstep App",
    "version": "0.1.0",
    "manufacturer": "Example Org",
    "license": "MIT"
  },
  "pipeline": {
    "workingDirectory": ".",
    "shell": { "kind": "pwsh", "bootstrapCommands": [], "environment": {} },
    "build": { "command": "./scripts/build.ps1" },
    "stage": {
      "command": "./scripts/stage.ps1 -StageRoot dist/stage",
      "outputRoot": "dist/stage"
    }
  },
  "payload": {
    "layoutVersion": 1,
    "stageRoot": "dist/stage",
    "appRoot": "app",
    "runtimeRoot": "runtime"
  },
  "launch": {
    "entryRelativePath": "app/MyGNUstepApp.app/MyGNUstepApp.exe",
    "workingDirectory": "."
  },
  "outputs": {
    "root": "dist",
    "packageRoot": "dist/packages",
    "logRoot": "dist/logs",
    "tempRoot": "dist/tmp",
    "validationRoot": "dist/validation"
  },
  "validation": {
    "smoke": { "enabled": true, "kind": "staged-layout", "requiredPaths": [], "timeoutSeconds": 30 },
    "logs": { "retainOnSuccess": true }
  },
  "backends": {
    "msi": { "enabled": true, "upgradeCode": "<your-stable-guid>" },
    "appimage": {
      "enabled": true,
      "desktopEntryName": "my-gnustep-app.desktop",
      "iconRelativePath": "metadata/icons/app.png"
    }
  }
}
```

Your `build` command compiles the app. Your `stage` command lays out a
self-contained payload under `app/`, `runtime/`, and `metadata/`. See
[docs/staging-contract.md](docs/staging-contract.md) and
[docs/manifest.md](docs/manifest.md).

### 2. Package locally
From a checkout of this repo:

```powershell
$m = '../my-app/packaging/package.manifest.json'
./scripts/gnustep-packager.ps1 -Command build    -Manifest $m
./scripts/gnustep-packager.ps1 -Command stage    -Manifest $m
./scripts/gnustep-packager.ps1 -Command package  -Manifest $m -Backend appimage
./scripts/gnustep-packager.ps1 -Command validate -Manifest $m -Backend appimage -RunSmoke
```

Use `-Backend msi` on Windows or `-Backend dmg` on macOS.
`scripts/run-packaging-pipeline.ps1` runs every step in one call, the same way
CI does.

### 3. Package in GitHub Actions
Call the reusable workflow from your app repo, pinned to a release tag:

```yaml
jobs:
  package-linux:
    uses: danjboyd/gnustep-packager/.github/workflows/package-gnustep-app.yml@v0.1.5
    with:
      manifest-path: packaging/package.manifest.json
      backend: appimage            # or msi, dmg
      package-version: ${{ github.ref_name }}
      run-validation: true
      run-smoke: true
      artifact-name: my-app-linux
```

The workflow checks out the packager scripts at the same commit as the tag in
`uses:`. `packager-repository` and `packager-ref` are optional overrides for
testing packager changes from another repository or ref; on `@v0.1.0`, which
predates that fallback, pass both. For signing secrets, self-hosted runners,
preflight hooks, and an end-to-end release-with-updates example, see
[docs/github-actions.md](docs/github-actions.md) and
[examples/downstream/](examples/downstream/).

## Example Output
Output from running the bundled Linux fixture (`examples/sample-linux`)
through `package` and `validate`:

```text
$ ./scripts/gnustep-packager.ps1 -Command package -Manifest examples/sample-linux/package.manifest.json -Backend appimage
AppImage created: .../dist/packages/SampleGNUstepLinuxApp-0.1.0-x86_64.AppImage
Artifact metadata: .../dist/packages/SampleGNUstepLinuxApp-0.1.0-x86_64.metadata.json
Diagnostics summary: .../dist/packages/SampleGNUstepLinuxApp-0.1.0-x86_64.diagnostics.txt
AppRun: .../SampleGNUstepLinuxApp.AppDir/AppRun
Desktop entry: .../SampleGNUstepLinuxApp.AppDir/usr/share/applications/sample-gnustep-linux.desktop
Notice report: .../SampleGNUstepLinuxApp.AppDir/usr/metadata/THIRD-PARTY-NOTICES.txt
Backend package command completed.

$ ./scripts/gnustep-packager.ps1 -Command validate -Manifest examples/sample-linux/package.manifest.json -Backend appimage -RunSmoke
AppImage validation completed.
Backend validation completed.

$ ls dist/packages
SampleGNUstepLinuxApp-0.1.0-x86_64.AppImage
SampleGNUstepLinuxApp-0.1.0-x86_64.AppImage.zsync
SampleGNUstepLinuxApp-0.1.0-x86_64.diagnostics.txt
SampleGNUstepLinuxApp-0.1.0-x86_64.metadata.json
SampleGNUstepLinuxApp-0.1.0-x86_64.provenance.json
SampleGNUstepLinuxApp-0.1.0-x86_64.update-feed.json
```

The provenance sidecar can be published next to the release asset:

```json
{
  "formatVersion": 1,
  "backend": "appimage",
  "package": { "id": "com.example.SampleGNUstepLinuxApp", "name": "SampleGNUstepLinuxApp", "version": "0.1.0" },
  "artifact": {
    "name": "SampleGNUstepLinuxApp-0.1.0-x86_64.AppImage",
    "sizeBytes": 952824,
    "sha256": "69dd9891205362e8b42517121405f2771f0097786aaffc60114ff1df68aa1a0e"
  },
  "source":   { "commit": "7ac44ad7d16ecb3cb2af4f6eda1249ad97af8ef1", "dirty": false },
  "packager": { "commit": "7ac44ad7d16ecb3cb2af4f6eda1249ad97af8ef1", "dirty": false },
  "files": [ { "path": "usr/app/SampleGNUstepLinuxApp.app/SampleGNUstepLinuxApp", "role": "entry", "...": "..." } ]
}
```

Fixtures for the other backends live in `examples/sample-gui` (Windows MSI) and
`examples/sample-macos` (macOS DMG).

## Repository Layout
- `scripts/`: the `gnustep-packager.ps1` CLI, the pipeline wrapper, and shared libraries
- `schemas/`: the manifest JSON Schema
- `defaults/`: built-in defaults and profiles
- `backends/msi/`, `backends/appimage/`, `backends/dmg/`: backend implementations
- `updater/`: the Objective-C updater library, UI, and update helper
- `examples/`: reference fixtures and downstream templates
- `tests/`: Pester suites (`scripts/test-repo.ps1` runs the shared tests and the host's platform tests)
- `docs/`: design notes and consumer guides
- `.github/workflows/`: the reusable `package-gnustep-app.yml` and repo CI

## Documentation
Getting started:
- [docs/consumer-setup.md](docs/consumer-setup.md)
- [docs/manifest.md](docs/manifest.md)
- [docs/staging-contract.md](docs/staging-contract.md)
- [docs/shared-cli.md](docs/shared-cli.md)
- [docs/github-actions.md](docs/github-actions.md)
- [docs/compatibility-matrix.md](docs/compatibility-matrix.md)

Backends:
- MSI: [boundary](docs/msi-boundary.md), [runtime policy](docs/msi-runtime-policy.md),
  [launcher](docs/msi-launcher-design.md), [WiX rendering](docs/msi-wix-rendering.md),
  [triage](docs/windows-msi-triage.md)
- AppImage: [requirements](docs/appimage-requirements.md),
  [metadata mapping](docs/appimage-metadata-mapping.md),
  [AppDir design](docs/appimage-appdir-design.md),
  [runtime policy](docs/appimage-runtime-policy.md),
  [backend README](backends/appimage/README.md)
- DMG: [docs/dmg-backend.md](docs/dmg-backend.md), [backend README](backends/dmg/README.md)

Releases, signing, and updates:
- [docs/versioning-release.md](docs/versioning-release.md)
- [docs/release-gate.md](docs/release-gate.md)
- [docs/signing.md](docs/signing.md)
- [docs/compliance-notices.md](docs/compliance-notices.md)
- [docs/update-architecture.md](docs/update-architecture.md)
- [docs/updater-consumer-guide.md](docs/updater-consumer-guide.md)
- [docs/updater-release-publishing.md](docs/updater-release-publishing.md)

Toolchain bootstrap:
- [docs/gnustep-cli-new-integration.md](docs/gnustep-cli-new-integration.md)
- [docs/windows-gnustep-cli-new-hardening.md](docs/windows-gnustep-cli-new-hardening.md)

## Known Limitations
- Only the toolchains listed above are supported: MSYS2 `CLANG64` on Windows
  and clang-based GNUstep on Linux x64. The DMG backend expects a native macOS
  `.app`.
- DMG notarization is implemented but has not yet been exercised against
  Apple's notary service.
- Packaged app-domain defaults are implemented for MSI and AppImage only.

## Roadmap
[CHANGELOG.md](CHANGELOG.md) lists the changes in each release.

[Roadmap.md](Roadmap.md) records the implementation phases, what has landed,
and what is next.

## License
gnustep-packager, including the updater in `updater/`, is released under the
[MIT License](LICENSE). Monocypher, bundled with `gp-update-helper`, keeps its
own license (BSD-2-Clause or CC0;
`updater/objc/gp-update-helper/Source/monocypher/LICENCE.md`).
