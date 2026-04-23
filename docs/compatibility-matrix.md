# Compatibility Matrix

## Current Support Status

| Area | Baseline | Status | Notes |
| --- | --- | --- | --- |
| Host OS | Windows x64 | Supported | MSI backend local and CI validation path |
| Host OS | Linux x64 (`ubuntu-latest` default runner) | Supported | AppImage backend local and CI validation path |
| Host OS | Linux x64 self-hosted GNUstep runner | Supported | Reusable workflow accepts caller-supplied `runs-on-appimage` labels |
| PowerShell | PowerShell 7+ | Supported | Shared scripts and tests use `pwsh` |
| Toolchain | MSYS2 `CLANG64` x64 | Supported | Current runtime discovery and launcher assumptions target this layout |
| Toolchain | clang-based GNUstep stage on Linux x64 | Supported | AppImage backend expects a self-contained staged payload |
| WiX | WiX 3.11.x | Supported | Bootstrapped automatically when missing |
| AppImage tooling | `appimagetool` x86_64 | Supported | Uses `PATH` when present or bootstraps from the configured download URL |
| Toolchain bootstrap | `gnustep-cli-new` `v0.1.0-dev` release manifest | Supported for MSI and AppImage CI | Default hosted workflow paths bootstrap and smoke `gnustep-cli-new` before packaging |
| Linux host packages | `ca-certificates`, `curl`, `tar`, `gzip`, `squashfs-tools`, `desktop-file-utils` | Supported | Required for repo CI and recommended for local AppImage validation |
| Workflow | Caller-selected runner labels | Supported | Reusable workflow exposes `runs-on-msi` and `runs-on-appimage` |
| Workflow | Caller preflight hooks | Supported | Reusable workflow exposes `preflight-shell` and `preflight-command` |
| Workflow | Additive backend prerequisite packages | Supported | Reusable workflow exposes `msys2-packages` and `appimage-apt-packages` |
| Backend | MSI | Supported | Build, package, ZIP, and backend validation implemented |
| Backend | AppImage | Supported | AppDir transform, `AppRun`, artifact build, and backend validation implemented |
| Install scope | MSI perMachine | Supported | Packaging works; validation may require elevation |
| Install scope | MSI perUser | Supported | Used by sample fixture for local and CI validation |
| Diagnostics | MSI metadata and diagnostics sidecars | Supported | Package step emits `.metadata.json` and `.diagnostics.txt` next to the MSI |
| Diagnostics | AppImage metadata and diagnostics sidecars | Supported | Package step emits `.metadata.json` and `.diagnostics.txt` next to the `.AppImage` |
| Updates | Packaged updater runtime config | Supported | Emitted under `metadata/updates/` when manifest updates are enabled |
| Updates | MSI update-feed sidecar | Supported | Package step emits `.update-feed.json` next to the MSI when updates are enabled |
| Updates | AppImage update-feed and native update metadata | Supported | Package step emits `.update-feed.json` and passes native update info into `appimagetool` when updates are enabled |
| Compliance | MSI notice report generation | Supported | Built from `compliance.runtimeNotices` into the installed metadata tree |
| Compliance | AppImage notice report generation | Supported | Built from `compliance.runtimeNotices` into the AppDir metadata tree |
| Contracts | Semantic package contract assertions | Supported | `validation.packageContract` currently supports notice reports, updater config, default theme, metadata files, and updater helpers |
| Contracts | Installed or extracted result assertions | Supported | `validation.installedResult` runs on MSI install roots and extracted AppDir contents |
| Defaults | Declarative packaged default theme | Supported | `packagedDefaults.defaultTheme` realizes and validates both a `GSTheme` env fallback with `ifUnset` policy and a packaged first-launch `GSTheme` defaults seed on MSI and AppImage |
| Defaults | App-domain packaged defaults | Supported | `packagedDefaults.appDomain` seeds first-run app-domain defaults through the bundled defaults tool on Windows MSI and Linux AppImage; generic GNUstep global-domain writes are out of scope |

## Validation Scope

| Scenario | Status |
| --- | --- |
| Shared staged-layout validation | Supported |
| MSI package build on Windows | Supported |
| MSI install, launch, uninstall smoke path | Supported |
| AppImage package build on Linux | Supported |
| AppImage extractability and desktop-entry validation | Supported |
| AppImage smoke launch path | Supported | `launch-only`, `open-file`, `custom-arguments`, and `marker-file` modes |

## Consumer Boundary
The current support contract is intentionally narrow:

- Windows packaging expects MSYS2-style GNUstep runtime layout
- Linux AppImage packaging expects a self-contained staged Linux runtime tree
- launchers assume a private `runtime/` tree by default
- the example fixtures currently validate x64 Windows MSI and x64 Linux AppImage
- consumers are expected to stage any shipped notice files explicitly
- host dependency provisioning supports MSYS2 and Debian/Ubuntu-style apt paths only
- automatic host dependency inference is explicitly out of scope
- package contracts currently normalize a small supported semantic set; unusual
  packaged layouts should still use path-based escape hatches
