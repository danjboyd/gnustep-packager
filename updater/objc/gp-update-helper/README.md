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
  Prefers `AppImageUpdate` when it is present and the app is running from an
  AppImage; otherwise downloads and verifies the new AppImage and either
  replaces the current file or leaves a manual-download result when the current
  location is not writable

Supported command-line shape:

```text
gp-update-helper --mode prepare --plan <plan.json> --state-file <state.json>
gp-update-helper --mode apply --plan <plan.json> --state-file <state.json> --wait-pid <pid>
gp-update-helper --dry-run --mode prepare --plan <plan.json> --state-file <state.json>
```

The helper is intentionally not packaged as part of `gnustep-packager` core.
