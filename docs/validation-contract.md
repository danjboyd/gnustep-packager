# Validation Contract

## Purpose
The shared validation contract defines what can be checked before backend
install-time validation exists.

Validation now spans three layers:
- shared staged payload and launch-contract checks
- packaged-content contract checks during backend transforms
- installed or extracted result assertions during backend validation

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

`validation.smoke.requiredPaths` accepts both literal stage-relative paths and
glob patterns. Glob entries currently use PowerShell wildcard semantics.

Glob behavior:
- a literal entry succeeds when the exact resolved path exists
- a glob entry succeeds when at least one staged path matches
- a glob entry fails when no staged path matches
- validation logs preserve the original pattern and list the matched concrete
  paths

Example:

```json
{
  "validation": {
    "smoke": {
      "requiredPaths": [
        "runtime/lib/GNUstep/Bundles/libgnustep-back-*.bundle/libgnustep-back-*.dll",
        "runtime/lib/GNUstep/Themes/*.theme/*.dll"
      ]
    }
  }
}
```

Backend-specific packaged-artifact smoke behavior remains backend-owned. For
example, AppImage launch strategies are configured under
`backends.appimage.smoke.*` rather than expanding the shared staged-layout
contract with AppImage-only semantics.

## Packaged Content Contracts
`validation.packageContract` lets manifests declare higher-level packaged
expectations that the packager normalizes into backend-specific checks.

Current semantic kinds:
- `notice-report`
  Confirms the generated `THIRD-PARTY-NOTICES.txt` exists in the packaged
  metadata tree.
- `update-runtime-config`
  Confirms the generated updater runtime config exists in the packaged metadata
  tree.
- `default-theme`
  Confirms the declared theme default survives into the generated launcher
  artifact, such as MSI `.launcher.ini` or AppImage `AppRun`.
- `bundled-theme`
  Confirms a named GNUstep theme payload exists under the packaged runtime
  theme roots without forcing the manifest to spell out backend-specific theme
  paths.
- `metadata-file`
  Confirms a staged metadata file survives packaging.
- `updater-helper`
  Confirms a helper binary still exists near the packaged app entrypoint.

`validation.packageContract.requiredPaths` remains available as a low-level
escape hatch for backend-specific packaged layouts that are easier to assert as
literal paths.

## Installed Or Extracted Result Assertions
`validation.installedResult` applies the same contract idea to backend
validation:
- MSI checks run against the installed payload root after install.
- AppImage checks run against the extracted AppDir root during validation.

This is what lets validation distinguish between:
- content missing in stage
- content lost during package transform
- content lost after install or extraction

For bundled GNUstep themes, this keeps two separate invariants explicit:
- `packagedDefaults.defaultTheme`
  What launcher behavior should default to.
- `bundled-theme`
  Whether the actual theme payload is still present.

Example:

```json
{
  "packagedDefaults": {
    "defaultTheme": "WinUXTheme"
  },
  "validation": {
    "packageContract": {
      "requiredContent": [
        { "kind": "notice-report" },
        { "kind": "metadata-file", "path": "metadata/icons/app.png" }
      ]
    },
    "installedResult": {
      "requiredContent": [
        { "kind": "notice-report" }
      ],
      "requiredPaths": [
        "metadata/icons/app.png"
      ]
    }
  }
}
```

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
