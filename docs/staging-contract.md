# Staging Contract

## Purpose
The staging contract defines the filesystem tree that all packaging backends
consume.

Backends should package only what is present under the stage root unless the
manifest explicitly permits additional generated files.

## Versioning
The staged payload format is versioned separately from backend implementations.

Current layout version:
- `1`

## Conceptual Layout

```text
<stage-root>/
  app/
  runtime/
  metadata/
  logs/
```

## Required Logical Areas
- `app/`
  The packaged application payload, such as a GNUstep app bundle or top-level
  application directory

- `runtime/`
  Runtime files needed on the target machine, such as GNUstep runtime DLLs,
  libraries, themes, bundles, fonts, or other support assets

- `metadata/`
  Optional metadata that may be reused by multiple backends, such as icons,
  desktop-entry templates, or generated notices

## Rules
- Paths in the manifest should be relative to the stage root unless documented
  otherwise.
- Backends may create temporary transformed layouts outside the stage root, but
  they should not mutate the original staged payload in place.
- Windows MSI currently transforms the stage root into a private install tree
  that mirrors `app/`, `runtime/`, and `metadata/` under `INSTALLDIR`.
- Generated backend artifacts such as WiX harvest output or AppDir trees belong
  under `dist/` or another backend-specific output location.
- A backend may require certain files under `runtime/` or `metadata/`, but that
  requirement must be declared through backend docs and manifest fields.
- Shared command logs, package outputs, temporary files, and validation outputs
  belong under the manifest's declared `outputs` roots rather than under ad hoc
  directories.

## Output Roots
The current shared output roots are:
- `outputs.root`
- `outputs.packageRoot`
- `outputs.logRoot`
- `outputs.tempRoot`
- `outputs.validationRoot`

These roots are resolved relative to the manifest directory unless they are
already absolute paths.

## Why This Matters
This contract is what keeps MSI-first work from becoming MSI-only work.

If the stage layout stays stable:
- MSI can map it to installer directories
- AppImage can map it to an AppDir
- validation can reason about one shared input shape
