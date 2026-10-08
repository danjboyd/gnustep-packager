# gp-update-helper

`gp-update-helper` is the out-of-process update worker used by
`GPUpdaterUI`.

Responsibilities:

- read a JSON helper plan emitted by the app
- emit a JSON state file while work progresses
- download and verify update payloads during a prepare phase
- apply the prepared payload after the app exits
- relaunch the app when backend semantics allow it

Current backend behavior:

- `msi`
  Downloads the target MSI, verifies the configured SHA-256 when available, and
  hands off to `msiexec` during apply
- `appimage`
  Prefers `appimageupdatetool` when it is present and the app is running from
  an AppImage; otherwise downloads and verifies the new AppImage. When the
  AppImage's directory isn't writable it leaves a manual-download result.
  Otherwise it writes `apply-appimage.sh` into the working root, and the app
  runs that with `/bin/sh` on restart instead of `--mode apply`: the helper and
  its libraries are inside the AppImage, whose mount goes when the app quits.
  The script waits for the app (two minutes at most), swaps the new AppImage in
  by renaming within its directory (or runs `appimageupdatetool -O`), and
  starts the AppImage at its path again
- Inside a Flatpak (`FLATPAK_ID` set or `/.flatpak-info` present) the updater
  is off: Flatpak updates the app

Supported command-line shape:

```text
gp-update-helper --mode prepare --plan <plan.json> --state-file <state.json>
gp-update-helper --mode apply --plan <plan.json> --state-file <state.json> --wait-pid <pid>
gp-update-helper --dry-run --mode prepare --plan <plan.json> --state-file <state.json>
```

The helper is intentionally not packaged as part of `gnustep-packager` core.
