# Validation Contract

## Purpose
The shared validation contract defines what can be checked before backend
install-time validation exists.

For phases 1 and 2, validation focuses on the staged payload and shared launch
model rather than on installer-specific behavior.

## Current Shared Validation
The current shared validation mode is:
- `staged-layout`

That mode verifies:
- the stage root exists
- the declared app root exists
- the declared runtime root exists
- the launch entry exists
- declared path-prepend entries exist
- declared resource roots exist
- any extra required smoke paths exist

Backend-specific packaged-artifact smoke behavior remains backend-owned. For
example, AppImage launch strategies are configured under
`backends.appimage.smoke.*` rather than expanding the shared staged-layout
contract with AppImage-only semantics.

## Logs
Shared validation logs belong under:
- `outputs.validationRoot`
- `outputs.logRoot`

## Artifact Naming Conventions
Shared output roots are declared through:
- `outputs.root`
- `outputs.packageRoot`
- `outputs.logRoot`
- `outputs.tempRoot`
- `outputs.validationRoot`

Backends may define their own artifact name patterns, but they should render
those names through shared token replacement instead of inventing ad hoc rules.
