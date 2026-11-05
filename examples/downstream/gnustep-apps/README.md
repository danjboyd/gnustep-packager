# GNUstep App Examples

AppImage setups for four GNUstep apps that have no packaging of their own. The
source comes from an upstream tag, so nothing changes in the upstream repo.

| App | Upstream tag | License |
| --- | --- | --- |
| Gorm | `gorm-1_5_0` | GPL-3.0-or-later |
| ProjectCenter | `projectcenter-0_7_0` | GPL-2.0-or-later |
| GWorkspace | `gworkspace-1_0_0` | GPL-2.0-or-later |
| SystemPreferences | `systempreferences-1_2_1` | GPL-2.0-or-later |

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

To package another GNUstep app the same way, copy a manifest and change the
`package` block, the two commands under `pipeline`, and the app name in the
`launch` and `compliance` blocks.

## What was tested

Built with `/usr/GNUstep`. All four passed package validation and the smoke run
from a fresh clone through `build-app.sh`, with the pipeline run under
`scripts/run-gui-isolated.sh`. Gorm, ProjectCenter and GWorkspace also passed
from a local checkout at the tag above. Each opened its main window from the
package in the sandbox, and System Preferences loaded all eight of its panes.

Not tested yet:

- `package-appimage.yml`, so nothing has built these on a `gnustep-cli-new`
  toolchain
- The apps' features beyond starting up

A system-wide `/usr/GNUstep` can change what gets staged. These setups copy the
whole system `Library` except headers, makefiles, themes and documentation, so
the AppImages are about 83 MB.
