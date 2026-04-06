# Architecture

## Core Rule
The core model in `gnustep-packager` describes a packaged GNUstep application.
It does not describe an MSI, an AppDir, or any other backend-specific format.

Backend-specific formats are render targets built from:
- a manifest
- a staged payload
- a launch contract

## Shared Concepts
The shared model is built around these concepts:

- `package`
  Human and machine identity for the application

- `pipeline`
  Consumer-repo commands that build and stage the application payload

- `payload`
  The staged filesystem contract that packaging backends consume

- `launch`
  The environment and executable information needed to start the packaged app

- `outputs`
  Shared locations for package artifacts, logs, temporary files, and validation
  output

- `validation`
  Backend-neutral smoke validation for the staged payload and launch contract

- `updates`
  Shared release-discovery and update-feed settings that downstream apps can
  consume through a runtime updater library without embedding backend-specific
  installer behavior in the app process

- `integrations`
  Logical desktop integration requests such as shortcuts, categories, and file
  associations

- `backends`
  Backend-specific configuration that should not leak into shared code

## Staged Payload Rule
Backends must package from the staged payload, not from arbitrary build output
discovery.

That rule keeps:
- backend behavior predictable
- local and CI flows aligned
- MSI and AppImage on the same input contract

## Backend Responsibilities
Each backend is responsible for:
- mapping the staged payload into its own filesystem layout
- rendering launch behavior into backend-native startup mechanics
- applying backend-specific metadata and integration rules
- emitting artifacts and logs
- running backend-specific validation

Each backend is not responsible for:
- inventing new package identity fields
- bypassing the staged payload contract
- reaching back into raw build output without a declared reason

## Launch Contract
GNUstep apps often need launch-time environment setup such as:
- runtime search paths
- GNUstep path prefix variables
- fontconfig or resource roots
- default theme selection that should often apply only when unset

Those requirements must be represented once in the shared launch contract and
then rendered by each backend:
- Windows MSI can generate a bootstrap launcher
- Linux AppImage can generate `AppRun`

## CI Model
The intended pipeline shape is:

1. Load and validate a manifest.
2. Run the consumer repo's build command.
3. Run the consumer repo's stage command.
4. Package the staged payload through the selected backend.
5. Run backend validation.
6. Publish artifacts and logs.

## Configuration Layering
Shared behavior is driven by layered configuration:
- core defaults
- backend defaults
- app overrides

This keeps the manifest concise while avoiding hidden backend-specific behavior
in shared code.

## Early Directory Layout
- `schemas/`
  Manifest schemas and future validation assets

- `scripts/`
  Shared entry points and helper libraries

- `updater/`
  Runtime updater libraries and related helper code

- `backends/msi/`
  Windows MSI backend

- `backends/appimage/`
  Linux AppImage backend

## MSI References
The Windows backend design details live in:
- [msi-boundary.md](msi-boundary.md)
- [msi-runtime-policy.md](msi-runtime-policy.md)
- [msi-launcher-design.md](msi-launcher-design.md)
- [msi-wix-rendering.md](msi-wix-rendering.md)

- `examples/`
  Reference manifests and fixture setups

- `docs/`
  Architecture notes, contracts, and usage docs
