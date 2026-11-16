# Theme Demo Examples

Package a theme's demo app with the theme bundled, so a reviewer can run it
without installing either one.

## Adwaita (AppImage)

Copy `adwaita/` to `packaging/` in the plugins-themes-Adwaita repo. Add a
`packaging/ThemeDemo.png` icon; the theme repo doesn't have one. Then run this
from the repo root:

```sh
xvfb-run -a dbus-run-session -- pwsh <gnustep-packager>/scripts/run-packaging-pipeline.ps1 \
  -Manifest packaging/package.manifest.json -Backend appimage
```

The manifest turns the launch smoke test on (`validation.smoke.enabled`), so it
runs without `-RunSmoke` and needs an X display. `xvfb-run` gives it a private
one, so the app doesn't open on your screen. Without a display, the AppImage is
still built, then validation fails with "Unable to connect to X Server".

How it fits together:

- `themeInputs` builds the theme from the checkout (`workspacePath: ".."`) and
  stages it in `runtime/System/Library/Themes`. It is the default theme input,
  so it also sets `packagedDefaults.defaultTheme`.
- The stage script removes the toolchain's own `Library/Themes`, so the only
  theme in the package is the one built from this checkout.
- A release should build a fixed theme version: replace `workspacePath` with
  `repo` and a tag or commit in `ref`.

Tested on Linux with `/usr/GNUstep`, on a clone at Adwaita 0.1.0-alpha21. The
AppImage passed package validation and the smoke run. On 2026-11-16, a dry run
from a clean clone at `240589f` found the app starting in the default GNUstep
theme: ThemeDemo has no `CFBundleIdentifier`, so it reads the defaults domain
`ThemeDemo`, and the packager seeded `GSTheme` into `package.id`'s domain.
Since that fix, the seed goes to `ThemeDemo` and the app starts in Adwaita
(the package log says which domain it used). `package-appimage.yml` hasn't
been run yet.

### Loading the toolchain

The pipeline runs commands in a login shell, which resets `PATH`, so the
manifest's `bootstrapCommands` source `GNUstep.sh`. `GNUstep.sh` also unsets
`GNUSTEP_HOME`, which the packager uses to choose where the theme installs, so
the commands save the value and restore it. Without that, the install tries to
write to `/GNUstep`.

## WinUITheme (MSI)

Copy `winuitheme/` to `packaging/` in the plugins-themes-winuitheme repo. It uses
`package-msi.yml` the same way. `upgradeCode` in the manifest belongs to this
example package, so keep it stable once you have shipped an MSI. The theme builds
from the checkout, as above; a release should use `repo` and `ref` instead.

Tested once on a `windows-latest` GitHub runner with the reusable workflow and
the `gnustep-cli-new` toolchain, from a copy of the theme repo at `48d21f0`. The
run built the MSI and portable ZIP, installed the MSI, and confirmed the installed
`WinUITheme.theme` and the default theme setting. Nobody has looked at the running
app, so its rendering is unchecked. `package-msi.yml` itself wasn't used: that
test called the workflow from this repo with the same settings.
