# Changelog

## Unreleased

### Added
- `examples/downstream/gnustep-apps`: SystemPreferences and Terminal AppImage
  setups. Terminal comes from `gnustep/gap` at a fixed commit, since that repo
  has no tags: `build-app.sh` now takes a tag or a commit, and optionally the
  app's subdirectory.

## v0.1.8

### Changed
- The docs and `examples/downstream/` workflows pin `@v0.1.8`, and the
  downstream example manifests point `$schema` at the v0.1.8 schema.
- AppImage backend: the smoke launch refuses to run if `smoke.environment` points
  `GNUSTEP_HOME` at the real home or clears it.

### Added
- `scripts/run-gui-isolated.sh` runs a GUI app with a private display and
  session bus and a scratch directory bound over the real home.
- `examples/downstream/theme-demos`: examples that package the theme demo apps
  with the theme bundled through `themeInputs`: Adwaita as an AppImage and
  WinUITheme as an MSI.
- `examples/downstream/gnustep-apps`: example AppImage setups for Gorm,
  ProjectCenter and GWorkspace, built from upstream tags.
- The test suite now validates every manifest under `examples/` against the
  schema and the validator.

### Fixed
- Theme inputs: the default install command now names its install root in full.
  A manifest whose `bootstrapCommands` source `GNUstep.sh`, which unsets
  `GNUSTEP_HOME`, no longer sends the theme install to `/GNUstep`.
- Updater: automatic checks could stop west of UTC. gnustep-base reads a plist
  date back shifted by the zone's offset, so the stored last check time moved on
  every read and write of the defaults, into the future, where no check was due
  until real time passed it. It's now stored as seconds since 1970, under
  `lastCheckTime`, and a time in the future counts as due. The old
  `lastCheckDate` is ignored and removed, so one automatic check runs after
  updating.
- Updater: a second, identical update offer could appear over the download after
  a check by hand and Install Update. The pending launch check fired when the
  alert closed. Any check now cancels it.

## v0.1.7

### Changed
- The docs and `examples/downstream/` workflows pin `@v0.1.7`.

### Added
- AppImage backend: the launch-environment token `{@userRuntimeDir}` expands
  to a directory of the app's own for the user,
  `${XDG_RUNTIME_DIR:-/tmp}/gp-<package id>-<uid>`, which `AppRun` creates with
  mode 0700 and reuses at every launch (a symlink, or a directory the user
  doesn't own, gets a fresh `mktemp -d` one; a relaunch through `AppRun`
  keeps it). Setting `TMP` and `TEMP` to it under
  `platformOverrides.linux.launch.env` gives a GNUstep app message ports of
  its own, so it starts its bundled `gpbs` and `gdnc` instead of using a
  distribution GNUstep's. If no directory can be made, values that use the
  token are left unset. AppImage only: other backends leave it as written.
- DMG backend: `backends.dmg.extraVolumeFiles` copies stage-relative files or
  folders to the volume root next to the app, such as a note on opening an
  unsigned app. Reserved names (the app bundle, `Applications`, `.background`,
  `.DS_Store`) and duplicates are rejected, and validation checks that each
  file is on the mounted volume.
- DMG backend: `backends.dmg.checksumSidecar` writes `<artifact>.dmg.sha256`
  in `shasum -a 256 -c` format after signing and stapling. Validation checks
  that it matches the image.
- DMG backend: `backends.dmg.updates.appcast` writes a Sparkle appcast
  (`<artifact-base>.appcast.xml`) for the release. It signs the final image
  with Sparkle's `sign_update`, feeding the EdDSA key from an environment
  variable over stdin. Packaging skips the appcast, or fails when it is
  `required`, if there is no key or no `sign_update`. Validation checks the
  enclosure length against the image.
- AppImage backend: `backends.appimage.gnustepConfig.keyBindings` bundles key
  binding files under `<systemRoot>/Library/KeyBindings` and loads them after
  libs-gui's `DefaultKeyBindings` through `GSKeyBindingsFiles` in
  `GlobalDefaults.plist`. The new `CommandWordMoves` preset
  (`templates/keybindings/`) puts word and document moves on Command-arrow for
  apps that remap Ctrl to Command. It needs a libs-gui that handles the
  Command modifier in key bindings.

## v0.1.6

### Changed
- The docs and `examples/downstream/` workflows pin `@v0.1.6`.
- The reusable workflow, repo validation and the bootstrap smoke script default
  to the `gnustep-cli-new` v0.1.3 release: the manifest moves off the
  `v0.1.0-dev` pre-release, and the bootstrap script comes from the v0.1.3
  release assets instead of the `master` branch. The docs and
  `examples/downstream/` workflows name the same release.
- The bootstrap smoke no longer puts `C:\Windows\System32` first on `PATH`
  for the Windows bootstrap; the v0.1.3 `gnustep-bootstrap.ps1` picks the
  Windows `tar.exe` itself. A caller that overrides `gnustep-cli-bootstrap-url`
  with an older bootstrap should also pin the matching older packager release.

### Added
- The reusable workflow and the bootstrap smoke check the downloaded
  `gnustep-cli-new` bootstrap script against a SHA-256 digest before running
  it: `gnustep-cli-bootstrap-sha256` (`gnustep-bootstrap.sh`, AppImage) and
  `gnustep-cli-bootstrap-ps1-sha256` (`gnustep-bootstrap.ps1`, MSI), which
  default to the v0.1.3 scripts. A caller that overrides
  `gnustep-cli-bootstrap-url` must set the matching digests, or empty strings
  to skip the check.

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
