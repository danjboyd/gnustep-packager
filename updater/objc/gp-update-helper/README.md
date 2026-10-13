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
  hands off to `msiexec` during apply. `certutil` (for the SHA-256) and
  `msiexec` are always taken from the Windows system directory, never from
  `Path` or the working directory. On Windows, `--mode apply` waits for the
  app to quit, writes `apply-msi.cmd` beside the state file, starts it with
  the system `cmd.exe` (no window, not waited for) and exits: the helper runs
  from the install folder, so Windows Installer's Restart Manager would close
  it partway through the install, before it records the result and starts
  the app again. The script runs `msiexec`, writes the final state and starts
  the app (through its launcher) after a successful install, unless Windows
  is already restarting (1641). The MSI and log paths
  are passed to `msiexec` with backslashes: Windows Installer drops the drive
  from a path written with `/` and fails with 1619.
  On Windows Server, an unset `DisableMsi` policy reads as 1, so the helper's
  non-elevated per-user install fails with 1625 ("forbidden by system
  policy"); the log shows `Machine policy value 'DisableMsi' is 1`. Windows
  10 and 11 read it as 0, and the update installs. On a server, set
  `DisableMsi` to 0 (Computer Configuration > Administrative Templates >
  Windows Components > Windows Installer > Turn off Windows Installer:
  Disabled) or install updates manually as an administrator
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
