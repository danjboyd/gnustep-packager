# MSI WiX Rendering

## Purpose
This document defines how the backend renders MSI output without requiring
hand-maintained harvested WiX source.

## Source Strategy
Version-controlled inputs:

- one generic product template
- one generic launcher source file
- backend PowerShell scripts

Generated inputs:

- harvested file fragment for the transformed install tree
- rendered product `.wxs`
- `.wixobj` files
- linker output under temporary directories

## Harvest Strategy
The backend harvests one transformed install tree rooted at `INSTALLDIR`.

That keeps the WiX model simple:

- one app-private install root
- no separate hard-coded `clang64` directory tree
- one file component group for installed payload

## Version Policy
MSI uses a normalized numeric version. The backend maps package versions to an
MSI-safe version with at most four numeric fields.

Non-numeric prerelease metadata is ignored for MSI upgrade semantics and should
instead live in artifact naming or release metadata.

## Upgrade Policy
The backend uses:

- a stable app-specific `UpgradeCode`
- `Product Id="*"` for new package codes
- `MajorUpgrade` semantics by default

This gives deterministic replacement behavior for newer package versions.

## Tool Bootstrap
If `heat.exe`, `candle.exe`, or `light.exe` are not found on `PATH`, the
backend may bootstrap WiX into `backends.msi.wix.toolRoot` by downloading the
configured WiX archive.

## Artifact Policy
The backend emits:

- an MSI named by `backends.msi.artifactNamePattern`
- a ZIP named by `backends.msi.portableArtifactNamePattern`

Both artifacts are produced from the same transformed install tree.
