# Updater Components

The updater companion path is split into small layers so downstream GNUstep apps
can adopt update checks without taking ownership of installer mechanics.

Current components:

- `objc/GPUpdaterCore`
  Foundation-only runtime layer for packaged config loading, feed parsing,
  version comparison, and persisted user choices
- `objc/GPUpdaterUI`
  Optional AppKit layer that presents a default update UX on top of
  `GPUpdaterCore`
- `objc/gp-update-helper`
  Separate executable that downloads, verifies, applies, and relaunches updates
  after the app exits

The packager emits the runtime config and feed sidecars those components expect.
Downstream apps do not need to call the GitHub releases API directly.
