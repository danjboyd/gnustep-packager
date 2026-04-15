# Configuration Layering

## Goal
Configuration layering keeps the shared package model stable while still
letting:
- the toolkit define safe defaults
- backends add backend-specific defaults
- consumer manifests override what they actually need

## Merge Order
The current merge order is:

1. core defaults
2. backend defaults
3. selected manifest profiles
4. app manifest

In practical terms:
- `defaults/core/defaults.json` applies first
- `defaults/backends/<backend>/defaults.json` overlays next
- `defaults/profiles/<profile>.json` overlays next, in manifest order
- the consumer manifest wins last

Release automation may then apply runtime overrides such as a package version
override after normal configuration layering has completed.

## Merge Rules
- objects merge recursively
- arrays replace, they do not concatenate
- scalar values replace previous values

## Why This Order
This keeps the core package shape stable without making consumers repeat common
settings, while still letting backend defaults fill in backend-specific values
such as artifact naming patterns and letting profiles contribute reusable app or
host-dependency overlays.

## Current Default Sources
- [defaults/core/defaults.json](/C:/Users/Support/git/gnustep-packager/defaults/core/defaults.json)
- [defaults/backends/msi/defaults.json](/C:/Users/Support/git/gnustep-packager/defaults/backends/msi/defaults.json)
- [defaults/backends/appimage/defaults.json](/C:/Users/Support/git/gnustep-packager/defaults/backends/appimage/defaults.json)
- `defaults/profiles/*.json` selected by the manifest `profiles` list
