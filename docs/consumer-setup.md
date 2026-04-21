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
- `gnustep-cmark`

These profiles are intentionally small. They provide common runtime PATH,
resource, category, and reusable host dependency defaults without hiding the
manifest shape.

## Packaged Defaults And Contracts
Consumers can now declare a few semantic packaging expectations directly in the
manifest instead of scattering them across backend-specific tests:

- `packagedDefaults.defaultTheme`
  Declares the default `GSTheme` the generated launcher should carry with
  `ifUnset` semantics.
- `validation.packageContract.requiredContent`
  Declares semantic packaged-content expectations such as notice reports,
  updater runtime config, bundled themes, metadata files, or updater helpers.
- `validation.installedResult`
  Declares the installed or extracted result checks that should still hold
  after MSI install or AppImage extraction.

Use `packagedDefaults.defaultTheme` for launcher behavior and `bundled-theme`
for theme payload presence. They are related but intentionally separate.
`bundled-theme` currently covers the common GNUstep runtime theme roots under
`runtime/System/Library/Themes`, `runtime/lib/GNUstep/Themes`, and
`runtime/share/GNUstep/Themes`.

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
7. declare app-specific MSYS2 host packages under
   `hostDependencies.windows.msys2Packages` when the default GNUstep baseline
   is not enough

The reusable workflow's default MSI host setup installs a GNUstep-capable MSYS2
`CLANG64` bootstrap shell and then provisions the GNUstep toolchain through
`gnustep-cli-new`. Downstream apps remain responsible for app-specific
dependencies such as `mingw-w64-clang-x86_64-cmark`, either directly under
`hostDependencies.windows.msys2Packages` or through a reusable profile such as
`gnustep-cmark`.

## Linux AppImage Onboarding
For the AppImage backend, the consumer should:

1. build on a Linux x64 host with PowerShell 7+
2. stage a self-contained payload under `app/`, `runtime/`, and `metadata/`
3. stage a packaged `.png` icon and point `backends.appimage.iconRelativePath`
   at it
4. enable `backends.appimage`
5. provide a stable `desktopEntryName`
6. choose an AppImage smoke mode under `backends.appimage.smoke`
7. declare extra Linux host packages under `hostDependencies.linux.aptPackages`
   when the documented AppImage host baseline is not enough, or layer in a
   reusable dependency profile such as `gnustep-cmark`
8. install `squashfs-tools` and `desktop-file-utils` before local validation or
   let the reusable workflow install them in CI

The supported CI path uses `gnustep-cli-new` to provision and smoke-test the
GNUstep build toolchain before running MSI or AppImage build, stage, package,
and validation commands. Downstream build and stage commands can assume the
selected `gnustep-cli-new` root has been added to `PATH` when
`skip-default-host-setup` is left at its default `false` value.

Use the reusable workflow's `gnustep-cli-manifest-url` and
`gnustep-cli-bootstrap-url` inputs when validating a newly published
`gnustep-cli-new` release manifest or bootstrap change. On self-hosted runners
with `skip-default-host-setup: true`, the consumer owns that bootstrap and
should fail preflight if the expected `gnustep` command is unavailable.

When migrating older downstream workflows, remove hosted-runner steps that
install GNUstep directly through MSYS2 or apt. Keep app-specific prerequisites
in the manifest, and let the reusable workflow provide the default
`gnustep-cli-new` toolchain bootstrap.

For hosted Windows runners, the migration target is the reusable MSI workflow
with default host setup enabled. The workflow installs an MSYS2 `CLANG64`
bootstrap shell, runs the `gnustep-cli-new` smoke, and only then runs build,
stage, package, and validation. A failed `gnustep-cli-new` smoke is a release
gate failure, not a reason to fall back to direct GNUstep MSYS2 package
installation.

For self-hosted Windows runners, set `runs-on-msi` to your runner labels and
use `skip-default-host-setup: true` only when the runner already provides the
expected MSYS2/GNUstep baseline. Add a `preflight-command` that proves the
selected `gnustep` command and app-specific host packages are present, and keep
those app-specific packages declared under
`hostDependencies.windows.msys2Packages`.

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
  "profiles": ["gnustep-gui", "gnustep-cmark"],
  "packagedDefaults": {
    "defaultTheme": "WinUXTheme"
  },
  "validation": {
    "packageContract": {
      "requiredContent": [
        { "kind": "notice-report" }
      ]
    },
    "installedResult": {
      "requiredContent": [
        { "kind": "notice-report" }
      ]
    }
  },
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
  -InstallHostDependencies `
  -RunSmoke
```

Manifest-declared host dependencies are implemented for shared local preflight,
remote-host validation, and reusable-workflow setup in the current repo state.
On self-hosted runs with `skip-default-host-setup: true`, the workflow still
expects manifest-declared dependencies for verification, but it will not apply
workflow-only additive package inputs.

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
and inject repo-owned preflight commands without forking the workflow. When
default host setup is disabled, keep app-specific dependencies in the manifest
or install them in that preflight step instead of relying on workflow-only
package-list inputs.

Related docs:
- [manifest.md](manifest.md)
- [validation-contract.md](validation-contract.md)
- [compliance-notices.md](compliance-notices.md)
- [windows-msi-triage.md](windows-msi-triage.md)
- [../backends/appimage/README.md](../backends/appimage/README.md)
- [updater-consumer-guide.md](updater-consumer-guide.md)
