# Changelog

## Unreleased

### Changed
- The reusable workflow, repo validation and the bootstrap smoke script default
  to the `gnustep-cli-new` v0.1.3 release: the manifest moves off the
  `v0.1.0-dev` pre-release, and the bootstrap script comes from the v0.1.3
  release assets instead of the `master` branch. The docs and
  `examples/downstream/` workflows name the same release.
- The bootstrap smoke no longer puts `C:\Windows\System32` first on `PATH`
  for the Windows bootstrap; the v0.1.3 `gnustep-bootstrap.ps1` picks the
  Windows `tar.exe` itself. A caller that overrides `gnustep-cli-bootstrap-url`
  with an older bootstrap should also pin the matching older packager release.

## v0.1.5

### Changed
- The docs and `examples/downstream/` workflows pin `@v0.1.5`.

### Fixed
- AppImage: the desktop entry has `StartupWMClass`, so GNOME's dash,
  dash-to-dock and other docks match the running window to it and show the
  app's icon instead of a generic one. Integrators such as Gear Lever install
  the entry under a name of their own (`markdown_viewer.desktop`), which
  never matched the window class. It defaults to the launch entry's file
  name, a GNUstep app's window class; `backends.appimage.startupWMClass`
  overrides it.

## v0.1.4

### Changed
- The docs and `examples/downstream/` workflows pin `@v0.1.4`.

### Fixed
- Updater: the install-failed alert no longer ends with a doubled period, as in
  "...could not be copied next to the current one..". The failure reasons are
  already sentences, so the alert adds a period only when one is missing.

## v0.1.3

### Changed
- The reusable workflow's `runs-on-appimage` default is now `["ubuntu-24.04"]`
  instead of `["ubuntu-latest"]`. The build image sets an AppImage's glibc floor
  and must be one `gnustep-cli-new` publishes for, so GitHub moving
  `ubuntu-latest` to a new Ubuntu release no longer changes your AppImages
  silently. To build on a newer image, pass `runs-on-appimage` explicitly; see
  "AppImage Runner Image" in `docs/github-actions.md`. Repo CI's Linux job uses
  the same pinned image.
- The docs and `examples/downstream/` workflows pin `@v0.1.3`.

### Fixed
- AppImage and MSI launchers: the value after a single-dash option, such as the
  `YES` in GNUstep's `-NSDebugLog YES`, is no longer made absolute just because
  a file of that name exists in the caller's directory. It's still resolved
  when it contains a path separator (`-GSLogFile logs/run.txt`). `--long`
  options don't protect their value.

## v0.1.2

### Fixed
- AppImage: a relative path on the command line, such as
  `./MyApp.AppImage Pictures/x.png` run from `~`, now resolves against the
  caller's directory. Previously `AppRun` changed into `launch.workingDirectory`
  first, so the app looked for the file inside the bundle. Options, URLs and
  absolute paths pass through unchanged, and the app still runs in
  `launch.workingDirectory`. (fixes #63)
- MSI: the same fix for the Windows launcher. `MyApp.exe docs\notes.md` from a
  prompt now opens the caller's `docs\notes.md` instead of looking inside the
  install folder. Arguments starting with `-` or `/`, URLs, and rooted or drive
  paths pass through unchanged. (#63)

### Changed
- `docs/release-gate.md`: the hosted Windows MSI gate is now recorded as
  passing. The `gnustep-cli-new` MSYS2 CLANG64 selector blocker no longer
  reproduces, and the gate stays fail-closed. (#62)
- The docs and `examples/downstream/` workflows pin `@v0.1.2`.

### Upgrading
Change `@v0.1.1` to `@v0.1.2` in your `uses:` line. Nothing else changes for
callers. Command-line launches with relative paths now open the caller's file;
launches from file managers, Explorer, Open with and shortcuts behave as
before.

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
