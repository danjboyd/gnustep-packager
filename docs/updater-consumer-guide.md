# Updater Consumer Guide

## Goal
Add update discovery and application to a GNUstep GUI app without teaching the
app to scrape GitHub releases or replace its own executable in process.

The intended split is:

- `GPUpdaterCore`
  load packaged config, read the published feed, compare versions, and persist
  user choices
- `GPUpdaterUI`
  optional default AppKit experience for `Check for Updates...`, prepare
  progress, restart-to-update, and failure states
- `gp-update-helper`
  separate executable that downloads, verifies, applies, and relaunches updates

## What The App Ships
An app that adopts the default path should ship:

- `libGPUpdaterCore.a`
- optionally `libGPUpdaterUI.a`
- `gp-update-helper` beside the main executable or under `Helpers/`
- the packaged runtime config emitted by `gnustep-packager`

Expected helper locations:

- `<app-executable-dir>/gp-update-helper`
- `<app-executable-dir>/Helpers/gp-update-helper`
- `<app-executable-dir>/gp-update-helper.exe`
- `<app-executable-dir>/Helpers/gp-update-helper.exe`

If the helper lives elsewhere, set `GPStandardUpdaterController.helperPath` or
implement the delegate override.

## Manifest Requirements
Enable updater metadata in the manifest and give each enabled backend a stable
feed URL.

Example:

```json
{
  "updates": {
    "enabled": true,
    "provider": "github-release-feed",
    "channel": "stable",
    "minimumCheckIntervalHours": 24,
    "startupDelaySeconds": 15,
    "github": {
      "owner": "example-org",
      "repo": "my-gnustep-app",
      "tagPattern": "v{version}",
      "releaseNotesUrlPattern": "https://github.com/{owner}/{repo}/releases/tag/{tag}"
    }
  },
  "backends": {
    "msi": {
      "enabled": true,
      "updates": {
        "feedUrl": "https://example-org.github.io/my-gnustep-app/updates/windows/stable.json"
      }
    },
    "appimage": {
      "enabled": true,
      "updates": {
        "feedUrl": "https://example-org.github.io/my-gnustep-app/updates/linux/stable.json",
        "embedUpdateInformation": true,
        "releaseSelector": "latest"
      }
    }
  }
}
```

The package step will then emit:

- bundled runtime config: `metadata/updates/gnustep-packager-update.json`
- package-side feed sidecar: `<artifact>.update-feed.json`
- AppImage-native update info and `.zsync` output when enabled

## Minimal App Integration
With the standard UI layer, the app only needs to create a controller, start
it on launch, and wire one menu action.

```objc
#import <GPUpdater.h>
#import <GPStandardUpdaterController.h>

@interface AppDelegate () <GPStandardUpdaterControllerDelegate> {
  GPStandardUpdaterController *_updaterController;
}
@end

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSError *error = nil;
  _updaterController = [[GPStandardUpdaterController alloc] initWithPackagedConfiguration:&error];
  if (_updaterController == nil) {
    NSLog(@"Updater disabled: %@", [error localizedDescription]);
    return;
  }

  [_updaterController setDelegate:self];
  [_updaterController start];
}

- (IBAction)checkForUpdates:(id)sender {
  [_updaterController checkForUpdates:sender];
}
```

See the downstream code snippet in
`examples/downstream/objc/AppDelegate+Updates.m`.

## Default UX
The standard UI layer behaves as follows:

- automatic checks stay quiet when the app is already current
- manual checks show an explicit up-to-date or failure dialog
- update-available prompts offer `Install Update`, `Later`, `Skip This Version`,
  and release-note viewing
- install preparation happens through `gp-update-helper`
- once preparation finishes, the UI shows `Restart and Install`
- AppImage installs fall back to a manual-download path when the current file
  cannot be replaced safely

## Customization Hooks
`GPStandardUpdaterControllerDelegate` can override:

- whether a result should be shown
- alert titles and message text
- release-note presentation
- helper path resolution

Check timing stays in the packaged config generated from the manifest:

- `updates.minimumCheckIntervalHours`
- `updates.startupDelaySeconds`

## Linux Notes
The AppImage path is intentionally ecosystem-friendly:

- if `AppImageUpdate` is available and the app is running from an AppImage, the
  helper prefers it
- if not, the helper downloads the replacement AppImage itself
- if the current location is not writable, the helper reports a manual-download
  result instead of moving files behind the user's back

That lets AppImageLauncher, AppImageUpdate, and Gear participate without
becoming hard requirements.

## Known Limits
- The Objective-C updater components are committed here, but this host did not
  have GNUstep development headers installed, so the ObjC layers were not
  build-verified in this environment.
- The helper's download progress is machine-readable, but the default helper
  implementation currently reports phase transitions plus completion rather than
  streaming byte-by-byte progress.

Related docs:

- [update-architecture.md](update-architecture.md)
- [update-feed-contract.md](update-feed-contract.md)
- [updater-helper-contract.md](updater-helper-contract.md)
- [updater-release-publishing.md](updater-release-publishing.md)
