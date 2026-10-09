# DMG Backend

## Purpose
The DMG backend packages a staged macOS `.app` bundle into a compressed,
read-only disk image with an `Applications` link, using only Apple's tools.

Full documentation: [../../docs/dmg-backend.md](../../docs/dmg-backend.md).

## Supported Target
- native macOS app bundles (universal, arm64 or x86_64)
- macOS hosts with PowerShell 7+ and Xcode or the Command Line Tools

## Shared Inputs
- package manifest (`backends.dmg`, optionally `platformOverrides.macos`)
- staged payload: `<appRoot>/<Name>.app`

## Backend Responsibilities
- copy the staged bundle (never mutate the stage) and keep or re-sign its
  signature
- lay out the volume: `Applications` link, optional background, optional
  notice report, optional Finder window layout
- build `UDZO` or `ULFO` images on `APFS` or `HFS+`
- sign, notarize and staple when configured and credentials are present
- emit `.metadata.json` and `.diagnostics.txt` sidecars
- validate: `hdiutil verify`, read-only `-nobrowse` attach, bundle and link
  checks, `codesign --verify --deep --strict`, `spctl --assess` (recorded),
  installed-result contract, optional launch smoke, guaranteed detach

## Commands

```powershell
./scripts/gnustep-packager.ps1 -Command package -Manifest examples/sample-macos/package.manifest.json -Backend dmg
./scripts/gnustep-packager.ps1 -Command validate -Manifest examples/sample-macos/package.manifest.json -Backend dmg -RunSmoke
./scripts/run-packaging-pipeline.ps1 -Manifest examples/sample-macos/package.manifest.json -Backend dmg -RunSmoke
```

## Files
- `package.ps1`, `validate.ps1`: entry points called by `scripts/gnustep-packager.ps1`
- `lib/dmg.ps1`: implementation
- `assets/finder-layout.applescript`: Finder window layout for the mounted volume
- `assets/finder-automation-check.swift`: checks Finder automation permission without prompting
