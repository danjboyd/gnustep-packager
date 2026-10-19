# Changelog

## v0.1.1

### Changed
- The reusable workflow `package-gnustep-app.yml` now checks out its own
  commit (`job.workflow_repository` at `job.workflow_sha`) when
  `packager-repository` and `packager-ref` are left empty. Callers no longer
  need to pass them; they remain optional overrides for testing packager
  changes from another repository or ref, and are still required on GitHub
  Enterprise Server. (#57)
- The docs and `examples/downstream/` workflows pin `@v0.1.1` and no longer
  pass the two packager inputs.

### Fixed
- GPUpdaterUI: the "Installing Update" progress label is no longer bezeled,
  which drew it inside a faint text-field outline under WinUITheme. (#58,
  fixes #45)
- AppImage smoke validation no longer fails with "You cannot call a method on
  a null-valued expression" when a GNUstep alert panel is already on screen
  before the launch. (#59)

### Added
- AppImage packaging logs a warning when the AppDir bundles `libgnustep-gui`
  but `<gnustepConfig.systemRoot>/Tools` lacks `gdnc`, `gpbs` or
  `make_services`, which gnustep-gui starts on demand. (#60, closes #25)

### Upgrading
Change `@v0.1.0` to `@v0.1.1` in your `uses:` line. You can then drop
`packager-repository` and `packager-ref`. Callers that stay on `@v0.1.0` must
keep passing both.

## v0.1.0

First tagged release: Windows MSI, Linux AppImage and macOS DMG backends, the
reusable `package-gnustep-app.yml` workflow, release sidecars, and the
Objective-C updater.
