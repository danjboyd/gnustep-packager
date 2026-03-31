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
| Linux host packages | `squashfs-tools`, `desktop-file-utils` | Supported | Required for repo CI and recommended for local AppImage validation |
| Workflow | Caller-selected runner labels | Supported | Reusable workflow exposes `runs-on-msi` and `runs-on-appimage` |
| Workflow | Caller preflight hooks | Supported | Reusable workflow exposes `preflight-shell` and `preflight-command` |
| Workflow | Additive backend prerequisite packages | Supported | Reusable workflow exposes `msys2-packages` and `appimage-apt-packages` |
| Backend | MSI | Supported | Build, package, ZIP, and backend validation implemented |
| Backend | AppImage | Supported | AppDir transform, `AppRun`, artifact build, and backend validation implemented |
| Install scope | MSI perMachine | Supported | Packaging works; validation may require elevation |
| Install scope | MSI perUser | Supported | Used by sample fixture for local and CI validation |
| Diagnostics | MSI metadata and diagnostics sidecars | Supported | Package step emits `.metadata.json` and `.diagnostics.txt` next to the MSI |
| Diagnostics | AppImage metadata and diagnostics sidecars | Supported | Package step emits `.metadata.json` and `.diagnostics.txt` next to the `.AppImage` |
| Compliance | MSI notice report generation | Supported | Built from `compliance.runtimeNotices` into the installed metadata tree |
| Compliance | AppImage notice report generation | Supported | Built from `compliance.runtimeNotices` into the AppDir metadata tree |

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
