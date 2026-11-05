# Update Feed Contract

## Purpose
The update contract gives downstream apps one stable runtime input:

- a packaged updater runtime config inside the app payload
- a machine-readable release feed published by the downstream repo

The app should not infer release state from GitHub page HTML or free-form
release titles.

## Manifest Shape

### Shared `updates`

- `updates.enabled`
  Enables update metadata generation and runtime config emission.
- `updates.provider`
  Current value: `github-release-feed`
- `updates.channel`
  Logical channel such as `stable` or `beta`
- `updates.feedUrl`
  Optional shared fallback feed URL for enabled backends
- `updates.minimumCheckIntervalHours`
  Minimum time between automatic checks
- `updates.startupDelaySeconds`
  Delay before a startup-triggered automatic check
- `updates.publicEDKey`
  Optional base64 Ed25519 public key (32 bytes). Copied into the runtime
  config; when set, the helper refuses any payload whose feed asset lacks a
  valid `edSignature`. A Sparkle key pair works as is (Sparkle's
  `SUPublicEDKey`)
- `updates.github.owner`
- `updates.github.repo`
- `updates.github.tagPattern`
  Pattern for the release tag, for example `v{version}`
- `updates.github.releaseNotesUrlPattern`

### Backend overrides

- `backends.msi.updates.feedUrl`
  Windows-specific feed URL override
- `backends.appimage.updates.feedUrl`
  Linux-specific feed URL override
- `backends.appimage.updates.embedUpdateInformation`
  Enables native AppImage update metadata
- `backends.appimage.updates.updateInformation`
  Explicit AppImage update-information string override
- `backends.appimage.updates.releaseSelector`
  Selector segment used in generated `gh-releases-zsync` metadata
- `backends.appimage.updates.zsyncArtifactNamePattern`
- `backends.dmg.updates.appcast.*`
  Sparkle appcast for macOS, which uses Sparkle rather than the packaged
  updater runtime config. See [dmg-backend.md](dmg-backend.md#sparkle-appcast)

## Example Manifest Snippet

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
      "repo": "sample-app",
      "tagPattern": "v{version}",
      "releaseNotesUrlPattern": "https://github.com/{owner}/{repo}/releases/tag/{tag}"
    }
  },
  "backends": {
    "msi": {
      "enabled": true,
      "updates": {
        "feedUrl": "https://example.invalid/updates/windows/stable.json"
      }
    },
    "appimage": {
      "enabled": true,
      "updates": {
        "feedUrl": "https://example.invalid/updates/linux/stable.json",
        "embedUpdateInformation": true,
        "releaseSelector": "latest"
      }
    }
  }
}
```

## Packaged Runtime Config
When updates are enabled, packaging emits:

- `metadata/updates/gnustep-packager-update.json`

Document shape:

```json
{
  "formatVersion": 1,
  "package": {
    "id": "com.example.SampleApp",
    "name": "SampleApp",
    "displayName": "Sample App",
    "version": "1.2.3",
    "manufacturer": "Example Org",
    "backend": "msi",
    "platform": "windows-x64"
  },
  "updates": {
    "enabled": true,
    "provider": "github-release-feed",
    "channel": "stable",
    "feedUrl": "https://example.invalid/updates/windows/stable.json",
    "minimumCheckIntervalHours": 24,
    "startupDelaySeconds": 15,
    "releaseNotesUrl": "https://github.com/example-org/sample-app/releases/tag/v1.2.3",
    "github": {
      "owner": "example-org",
      "repo": "sample-app",
      "tag": "v1.2.3"
    }
  }
}
```

## Feed Document
Package steps also emit an update-feed sidecar next to the backend artifact:

- `<artifact-base>.update-feed.json`

Current format:

```json
{
  "formatVersion": 1,
  "provider": "github-release-feed",
  "generatedAt": "2026-04-06T12:34:56.0000000Z",
  "channel": "stable",
  "feedUrl": "https://example.invalid/updates/windows/stable.json",
  "package": {
    "id": "com.example.SampleApp",
    "name": "SampleApp",
    "displayName": "Sample App",
    "version": "1.2.3",
    "manufacturer": "Example Org"
  },
  "source": {
    "github": {
      "owner": "example-org",
      "repo": "sample-app"
    }
  },
  "releases": [
    {
      "version": "1.2.3",
      "tag": "v1.2.3",
      "releaseNotesUrl": "https://github.com/example-org/sample-app/releases/tag/v1.2.3",
      "assets": [
        {
          "backend": "msi",
          "platform": "windows-x64",
          "kind": "msi",
          "name": "SampleApp-1.2.3-win64.msi",
          "url": "https://github.com/example-org/sample-app/releases/download/v1.2.3/SampleApp-1.2.3-win64.msi",
          "sha256": "abc123...",
          "sizeBytes": 12345678,
          "installScope": "perUser",
          "msiVersion": "1.2.3.0"
        }
      ]
    }
  ]
}
```

Signed feeds add `edSignature` to each asset: the base64 Ed25519 signature
of the asset file's bytes, made with the private half of `updates.publicEDKey`
(Sparkle's `sign_update` makes the same signature). gnustep-packager doesn't
sign: the downstream release job adds it before publishing the feed, so the
private key stays a secret of that job. Without a public key in the runtime
config the helper checks `sha256` only.

AppImage feeds add AppImage-native fields:

- `updateInformation`
- nested `zsync`

### Platforms

Each asset's `platform` names the machines it runs on: `linux-x64`,
`linux-arm64`, `windows-x64`, `windows-arm64`, or `macos` for DMG. The
packager sets it from the architecture the backend builds for. Both the
AppImage and MSI backends build x64 only so far.

The updater takes the asset whose backend and platform match the running
machine exactly, wherever it is in the release. An asset with no `platform`,
as feeds before v0.1.9 had, counts as x64 only, so an arm64 machine never
installs it. If the newest release has no asset for the machine, the check
fails with "Version X is available, but has no download for this computer
(platform)" instead of reporting the app as up to date. An older release that
does have one is still offered.

To publish one feed for several architectures, merge the per-artifact feeds:

```sh
pwsh scripts/merge-update-feeds.ps1 -Output stable.json \
  x64/MyApp-1.2.3-x86_64.update-feed.json arm64/MyApp-1.2.3-aarch64.update-feed.json
```

It combines releases with the same version, puts x64 assets first, and
refuses duplicate backend and platform pairs, or feeds for another package or
channel. Keep x64 first in a feed you assemble yourself, too: updaters before
v0.1.9 install the first asset whose backend matches, whatever its platform.

## Current Publishing Model
The downstream repo is expected to publish the generated feed file at the
configured feed URL.

The recommended default path is now documented:

- publish distributables to GitHub Releases
- publish stable feed URLs through GitHub Pages
- keep separate channel documents per backend

See:

- [updater-release-publishing.md](updater-release-publishing.md)
- [updater-consumer-guide.md](updater-consumer-guide.md)
