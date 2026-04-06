# MSI Backend

## Purpose
The MSI backend packages a staged GNUstep application into a Windows MSI.

## Initial Target
- MSYS2 `CLANG64`
- GNUstep desktop applications
- WiX-based package generation

## Shared Inputs
- package manifest
- staged payload
- launch contract

## Backend Responsibilities
- map the staged payload into an MSI install layout
- render Windows launcher behavior
- apply MSI versioning and upgrade rules
- emit MSI artifacts and related logs

## Design Constraint
This backend must consume the shared model. It must not redefine the core
package contract around MSI-only concepts.

## Current State
The backend now implements:
- staged payload to install-tree transform
- generic Windows launcher compilation and config generation
- optional launcher icon embedding from a staged `.ico`
- best-effort runtime DLL closure from configured search roots
- WiX bootstrap, harvest, compile, and link steps
- MSI plus portable ZIP artifact emission
- package metadata and diagnostics sidecar outputs
- optional updater runtime config and update-feed sidecar outputs when updates
  are enabled
- bundled third-party notice report generation from manifest compliance entries
- backend validation for install, launch, and uninstall smoke paths

Key backend assets:
- `assets/GpWindowsLauncher.c`
- `assets/Product.wxs.template`
- `lib/msi.ps1`

Related docs:
- `../../docs/compliance-notices.md`
- `../../docs/windows-msi-triage.md`
