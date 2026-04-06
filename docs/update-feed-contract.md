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

AppImage feeds add AppImage-native fields:

- `updateInformation`
- nested `zsync`

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
