# Theme Demo Examples

Package a theme's demo app with the theme bundled, so a reviewer can run it
without installing either one.

## Adwaita (AppImage)

Copy `adwaita/` to `packaging/` in the plugins-themes-Adwaita repo. Add a
`packaging/ThemeDemo.png` icon; the theme repo doesn't have one. Then run this
from the repo root:

```sh
pwsh <gnustep-packager>/scripts/run-packaging-pipeline.ps1 \
  -Manifest packaging/package.manifest.json -Backend appimage -RunSmoke
```

Run the smoke step under `xvfb-run -a dbus-run-session` on a desktop machine, so
the app doesn't open on your screen.

How it fits together:

- `themeInputs` builds the theme from the checkout (`workspacePath: ".."`) and
  stages it in `runtime/System/Library/Themes`. It is the default theme input,
  so it also sets `packagedDefaults.defaultTheme`.
- The stage script removes the toolchain's own `Library/Themes`, so the only
  theme in the package is the one built from this checkout.
- A release should build a fixed theme version: replace `workspacePath` with
  `repo` and a tag or commit in `ref`.

Tested on Linux with `/usr/GNUstep`, on a clone at Adwaita 0.1.0-alpha21. The
AppImage passed package validation and the smoke run, and the running app had
the bundled `Adwaita.theme` loaded. `package-appimage.yml` hasn't been run yet.

### Loading the toolchain

The pipeline runs commands in a login shell, which resets `PATH`, so the
manifest's `bootstrapCommands` source `GNUstep.sh`. `GNUstep.sh` also unsets
`GNUSTEP_HOME`, which the packager uses to choose where the theme installs, so
the commands save the value and restore it. Without that, the install tries to
write to `/GNUstep`.
