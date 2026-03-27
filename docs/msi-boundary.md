# MSI Backend Boundary

## Purpose
This document defines what belongs to the Windows MSI backend and what must stay
in the shared `gnustep-packager` model.

## Shared Inputs
The MSI backend consumes only shared inputs plus backend configuration:

- manifest metadata from `package`
- stage layout from `payload`
- startup behavior from `launch`
- output roots from `outputs`
- smoke expectations from `validation`
- logical integrations from `integrations`
- MSI-only options from `backends.msi`

## MSI-Specific Inputs
The backend-specific inputs are:

- `backends.msi.upgradeCode`
- `backends.msi.installScope`
- `backends.msi.productName`
- `backends.msi.shortcutName`
- `backends.msi.installDirectoryName`
- `backends.msi.launcherFileName`
- `backends.msi.artifactNamePattern`
- `backends.msi.portableArtifactNamePattern`
- `backends.msi.fallbackRuntimeRoot`
- `backends.msi.runtimeSearchRoots`
- `backends.msi.wix.*`

## Backend Outputs
The backend emits:

- a transformed install tree under `outputs.tempRoot`
- generated launcher assets
- generated WiX sources and object files
- an MSI under `outputs.packageRoot`
- a portable ZIP built from the same install tree
- backend validation logs under `outputs.validationRoot`

## Separation Rule
The shared model must not know about:

- WiX `Directory` IDs
- MSI `UpgradeCode`
- `ProgramFilesFolder`
- registry-backed shortcut key paths
- Windows-only installer UI or logging switches

Those concepts exist only under `backends/msi/`.

## Transform Rule
The MSI backend packages a transformed install tree, not the raw stage root.

That transform may:

- copy `app/`, `runtime/`, and `metadata/` into an install layout
- add generated launcher files
- add generated WiX sources
- normalize version and naming values for MSI constraints

It must not mutate the original staged payload in place.
