# Compliance and Notices

## Purpose
Phase 9A adds a simple rule: packaged runtime contents should be traceable
without opening backend internals or reverse-engineering the staged payload.

The manifest supports this through `compliance.runtimeNotices`.

## Manifest Shape
Each `runtimeNotices` entry may declare:

- `name`
- `version`
- `license`
- `source`
- `homepage`
- `stageRelativePath`

`stageRelativePath` should point to a staged notice or license file that will be
bundled into the package payload, typically under `metadata/licenses/`.

## MSI Outputs
The MSI backend now emits:

- an installed notice report at `<install-root>/<metadataRoot>/THIRD-PARTY-NOTICES.txt`
- an artifact sidecar at `<artifact-base>.metadata.json` listing declared notice
  entries and bundled file paths

## Example

```json
{
  "compliance": {
    "runtimeNotices": [
      {
        "name": "GNUstep Base",
        "version": "1.31.0",
        "license": "LGPL-2.1-or-later",
        "source": "MSYS2 clang64 runtime payload",
        "homepage": "https://gnustep.org/",
        "stageRelativePath": "metadata/licenses/gnustep-base.txt"
      }
    ]
  }
}
```

## Consumer Guidance
- Stage real license or notice files alongside the payload, not only URLs.
- Keep notice entries aligned with the actual bundled runtime contents.
- Prefer stable relative paths under `metadata/licenses/` so downstream review
  stays predictable across backends.
