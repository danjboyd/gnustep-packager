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
4. app manifest, with its `platformOverrides.<platform>` entry merged over it
   first

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

## Platform Overrides
`platformOverrides.windows`, `platformOverrides.linux` and
`platformOverrides.macos` hold partial manifests. The entry for the target
platform is merged over the app manifest before defaults and profiles are
applied, so it can also change `profiles`. Rules:

- objects merge recursively, arrays and scalars replace (as above)
- a `null` value removes the key, for example `"launch": { "env": null }` or
  `"packagedDefaults": null`
- `schemaVersion`, `package` and `platformOverrides` itself cannot be
  overridden: identity stays the same on every platform

Target platform: `-Platform` when given, otherwise the platform of the
requested `-Backend` (`msi` -> `windows`, `appimage` -> `linux`, `dmg` ->
`macos`), otherwise the host. `build` and `stage` therefore use the host's
overlay, and `package`/`validate` use the backend's.

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
