# Updater Helper Contract

## Purpose
`gp-update-helper` is launched by the app-facing updater UI through two JSON
contracts:

- a helper plan written by the app
- a helper state file updated by the helper

The helper plan is intentionally runtime-oriented. It is not emitted by the
packager directly.

## Helper Plan
Example document:

```json
{
  "formatVersion": 1,
  "package": {
    "id": "com.example.MyGNUstepApp",
    "name": "MyGNUstepApp",
    "displayName": "My GNUstep App",
    "currentVersion": "1.2.2",
    "backend": "appimage",
    "channel": "stable"
  },
  "release": {
    "version": "1.2.3",
    "tag": "v1.2.3",
    "releaseNotesUrl": "https://github.com/example-org/my-gnustep-app/releases/tag/v1.2.3"
  },
  "asset": {
    "backend": "appimage",
    "platform": "linux-x64",
    "kind": "appimage",
    "name": "MyGNUstepApp-1.2.3-x86_64.AppImage",
    "url": "https://github.com/example-org/my-gnustep-app/releases/download/v1.2.3/MyGNUstepApp-1.2.3-x86_64.AppImage",
    "sha256": "abc123...",
    "sizeBytes": 12345678,
    "updateInformation": "gh-releases-zsync|example-org|my-gnustep-app|latest|MyGNUstepApp-*x86_64.AppImage.zsync",
    "zsync": {
      "url": "https://github.com/example-org/my-gnustep-app/releases/download/v1.2.3/MyGNUstepApp-1.2.3-x86_64.AppImage.zsync"
    }
  },
  "currentExecutablePath": "/home/user/Applications/MyGNUstepApp.AppImage",
  "execution": {
    "stateFile": "/tmp/gnustep-packager-updater/com.example.MyGNUstepApp/update-state.json",
    "workingRoot": "/tmp/gnustep-packager-updater/com.example.MyGNUstepApp",
    "relaunchExecutablePath": "/home/user/Applications/MyGNUstepApp.AppImage",
    "linux": {
      "currentAppImagePath": "/home/user/Applications/MyGNUstepApp.AppImage"
    }
  }
}
```

Reference fixture:

- `updater/contracts/helper-plan.example.json`

## State File
Example document:

```json
{
  "formatVersion": 1,
  "status": "readyToApply",
  "message": "Restart to finish applying the new AppImage.",
  "updatedAt": "2026-04-06T18:45:00Z",
  "downloadedPath": "/tmp/gnustep-packager-updater/com.example.MyGNUstepApp/downloads/MyGNUstepApp-1.2.3-x86_64.AppImage",
  "apply": {
    "mode": "appimage-replace",
    "currentAppImagePath": "/home/user/Applications/MyGNUstepApp.AppImage"
  },
  "progress": {
    "fractionCompleted": 1.0,
    "bytesReceived": 12345678,
    "bytesExpected": 12345678
  }
}
```

Reference fixture:

- `updater/contracts/helper-state.example.json`

## Supported Status Values
- `preparing`
- `downloading`
- `readyToApply`
- `applying`
- `completed`
- `manualActionRequired`
- `failed`

## Supported Apply Modes
- `msi-install`
- `appimage-update`
- `appimage-replace`
- `manual-download`

## Invocation Shape
Prepare phase:

```text
gp-update-helper --mode prepare --plan <plan.json> --state-file <state.json>
```

Apply phase:

```text
gp-update-helper --mode apply --plan <plan.json> --state-file <state.json> --wait-pid <pid>
```

Dry-run support:

```text
gp-update-helper --dry-run --mode prepare --plan <plan.json> --state-file <state.json>
```

## Behavioral Rules
- The helper owns download, verification, and apply steps.
- The app owns user prompts and decides when to request apply.
- MSI upgrades are handed off to `msiexec`, not applied by replacing binaries in
  place.
- AppImage replacement only happens when the currently running AppImage path is
  writable.
- If AppImage replacement is not safe, the helper reports
  `manualActionRequired` and leaves the downloaded file in a stable location.
