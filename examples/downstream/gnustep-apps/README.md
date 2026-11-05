# GNUstep App Examples

AppImage setups for five GNUstep apps that have no packaging of their own. The
source comes from a fixed upstream tag or commit, so nothing changes in the
upstream repo.

| App | Upstream tag or commit | License |
| --- | --- | --- |
| Gorm | `gorm-1_5_0` | GPL-3.0-or-later |
| ProjectCenter | `projectcenter-0_7_0` | GPL-2.0-or-later |
| GWorkspace | `gworkspace-1_0_0` | GPL-2.0-or-later |
| SystemPreferences | `systempreferences-1_2_1` | GPL-2.0-or-later |
| Terminal | `gnustep/gap` at `220860a`, `system-apps/Terminal` | GPL-2.0-only |

## Setting one up

Make a repo with `build-app.sh`, `stage-app.sh`, `package-appimage.yml` (under
`.github/workflows/`) and the app's `package.manifest.json` at its root. Then run
this from the repo root:

```sh
pwsh <gnustep-packager>/scripts/run-packaging-pipeline.ps1 \
  -Manifest package.manifest.json -Backend appimage -RunSmoke
```

To try the result by hand, use `scripts/run-gui-isolated.sh`. A GNUstep app given
only a private `HOME` still rewrites your real preferences.

`build-app.sh` takes the repo URL, a tag or full commit SHA, and optionally the
app's subdirectory, for repos such as `gnustep/gap` that hold many apps. The
app's `COPYING` becomes its license in the package.

To package another GNUstep app the same way, copy a manifest and change the
`package` block, the two commands under `pipeline`, and the app name in the
`launch` and `compliance` blocks.

## What was tested

Built with `/usr/GNUstep`. All five passed package validation and the smoke run
from a fresh clone through `build-app.sh`, with the pipeline run under
`scripts/run-gui-isolated.sh`. Gorm, ProjectCenter and GWorkspace also passed
from a local checkout at the tag above. Each opened its main window from the
package in the sandbox, System Preferences loaded all eight of its panes, and
Terminal opened a shell prompt.

Known limits of Terminal (and of GWorkspace when it launches other programs),
both from how `AppRun` starts every app:

- The shell starts in the app's directory inside the mounted AppImage, not in
  your home, because `AppRun` changes into `launch.workingDirectory`.
- Programs started from it inherit the `LD_LIBRARY_PATH` that puts the bundled
  libraries first, so a host program can load a bundled library instead of its
  own.

Not tested yet:

- `package-appimage.yml`, so nothing has built these on a `gnustep-cli-new`
  toolchain
- The apps' features beyond starting up

A system-wide `/usr/GNUstep` can change what gets staged. These setups copy the
whole system `Library` except headers, makefiles, themes and documentation, so
the AppImages are about 83 MB.
