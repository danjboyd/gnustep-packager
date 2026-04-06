# Update Architecture

## Goal
Add app-facing update support without turning `gnustep-packager` into a runtime
framework or forcing GNUstep GUI apps to own backend-specific install logic.

The update path is split deliberately:

- `gnustep-packager`
  Owns manifest schema, packaging-time metadata, generated runtime config, and
  release-feed sidecars.
- `GPUpdaterCore`
  Owns packaged-config loading, feed parsing, version comparison, channel
  selection, and persisted user choices.
- `GPUpdaterUI`
  Owns the default AppKit dialogs, helper-plan emission, prepare progress
  polling, and restart-to-update flow.
- `gp-update-helper`
  Owns download, verification, backend-specific apply mechanics, and relaunch.

## Core Rule
The app process may discover updates, but it should not be responsible for
replacing its own executable or reimplementing MSI/AppImage install semantics.

That keeps the shared model backend-neutral while still allowing a simple
Objective-C integration surface in GNUstep applications.

## Trust Model
The update path trusts a machine-readable feed contract, not GitHub release
titles or asset-name guessing at runtime.

Current trust anchors:

- the packaged app version remains `package.version`
- the packaged runtime config embeds the expected update channel and feed URL
- the generated feed includes release tags, release-note URLs, asset hashes, and
  backend-specific metadata
- MSI artifacts continue to rely on existing signing and major-upgrade rules
- AppImage artifacts can embed standard update information and produce `.zsync`
  sidecars for AppImage-native tools

The current repo baseline keeps the trust boundary clear:
discovery happens in the app, application happens elsewhere.

## GitHub Role
GitHub is treated as a release host, not as an in-app policy engine.

The packager generates feed and asset metadata that downstream release workflows
can publish from GitHub. The runtime updater consumes the feed URL declared in
the packaged config. This avoids teaching each app to scrape release pages or
hardcode GitHub API response handling.

## Backend Behavior
Shared update concepts:

- update enabled or disabled
- channel
- feed URL
- release tag mapping
- release notes URL
- package-version comparison

Backend-specific behavior stays backend-specific:

- MSI emits a release-feed entry for the signed `.msi` and preserves existing
  MSI version normalization and upgrade semantics
- AppImage can embed native update information and emit a `.zsync` sidecar so
  AppImageLauncher, AppImageUpdate, and Gear can participate without being
  required

## Runtime Config
When updates are enabled, packaging now generates a bundled runtime config at:

- `metadata/updates/gnustep-packager-update.json`

MSI places that file under the installed metadata tree.

AppImage places that file under `usr/metadata/updates/` inside the AppDir.

`GPUpdaterCore` resolves that file relative to the running executable so apps do
not have to hardcode repo-specific URLs or backend logic.

## Phase 10 Scope
Implemented in the current repo baseline:

- documented update architecture and trust model
- manifest and feed contract
- packaging-time runtime config and update-feed emission
- Foundation-only Objective-C updater core
- default AppKit update UI layer
- out-of-process update helper
- end-to-end release workflow docs and examples
- dedicated updater regression coverage
