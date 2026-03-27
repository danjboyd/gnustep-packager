# Compatibility Matrix

## Current Support Status

| Area | Baseline | Status | Notes |
| --- | --- | --- | --- |
| Host OS | Windows x64 | Supported | Primary target for MSI backend work |
| PowerShell | PowerShell 7+ | Supported | Shared scripts and tests use `pwsh` |
| Toolchain | MSYS2 `CLANG64` x64 | Supported | Current runtime discovery and launcher assumptions target this layout |
| WiX | WiX 3.11.x | Supported | Bootstrapped automatically when missing |
| Backend | MSI | Supported | Build, package, ZIP, and backend validation implemented |
| Backend | AppImage | Planned | Shared architecture exists, backend not implemented yet |
| Install scope | MSI perMachine | Supported | Packaging works; validation may require elevation |
| Install scope | MSI perUser | Supported | Used by sample fixture for local and CI validation |

## Validation Scope

| Scenario | Status |
| --- | --- |
| Shared staged-layout validation | Supported |
| MSI package build on Windows | Supported |
| MSI install, launch, uninstall smoke path | Supported |
| Linux AppImage validation | Planned |

## Consumer Boundary
The current support contract is intentionally narrow:

- Windows packaging expects MSYS2-style GNUstep runtime layout
- the launcher assumes a private `runtime/` tree by default
- the example fixture validates x64 Windows packaging only
