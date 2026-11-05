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
  Base64 Ed25519 public key (32 bytes), required when `updates.enabled` is true.
  Copied into the runtime config. The helper refuses any payload whose feed asset
  lacks a valid `edSignature` or `versionSignature`, or whose version isn't newer
  than the installed one, and refuses every update if the config has no key.
  A Sparkle key pair works as is (Sparkle's `SUPublicEDKey`)
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

Each asset must have `edSignature`: the base64 Ed25519 signature of the asset
file's bytes, made with the private half of `updates.publicEDKey` (Sparkle's
`sign_update` makes the same signature). gnustep-packager doesn't sign: the
downstream release job adds it before publishing the feed, so the private key
stays a secret of that job. `sha256` is checked as well, but it comes from the
same feed, so it doesn't replace the signature.

Each asset must also have `versionSignature`. `edSignature` shows who published
the file, but not which version it is, so a feed could offer the publisher's
genuine older release as a newer one. `versionSignature` is the base64 Ed25519
signature, made with the same key, of this UTF-8 message: six lines joined by
`\n`, with no trailing newline.

```text
gnustep-packager-update-v1
<package.id>
<release version>
<channel>
<asset platform>
<asset sha256, lowercase hex>
```

`package.id` is the manifest's package id, the release version is the
`releases[].version` the asset belongs to, and the channel is the feed's
`channel` (`stable` when the manifest sets no `updates.channel`), and the
platform is the asset's `platform`, such as `linux-x64` or `windows-x64`. No part
may be empty or contain a line break.

Before downloading, the helper rebuilds this message from the update plan. It
refuses the update unless the message verifies against `updates.publicEDKey`,
and unless the release version is newer than the installed version, compared
the same way the updater picks the newest release. After the download, the
file must match `sha256`, which ties it to the signed message, and `edSignature`.
That refuses each of these cases:

- a signed older file offered as a newer version
- the installed file relabelled with a newer version
- a correctly signed older release offered again
- a release signed for another channel, such as `beta` offered on `stable`
- one platform's file labelled as another's, such as an x64 AppImage offered
  to arm64 machines

### Test vector

Signers can check their output against this. The key is a test key: its
32-byte Ed25519 seed is the ASCII string `gnustep-packager test key, never`
(hex `676e75737465702d7061636b616765722074657374206b65792c206e65766572`).
Manifest validation refuses its public key, so never use it for an app.

- Public key (base64): `Ll6BcPIwCiJWeu8fUhAG52rU62luKpZdTNsdJBfgxIs=`
- Asset bytes: the 23 ASCII bytes `not really an installer`
- `sha256`: `110499c3d4d34a94a1ea70ae7e7353d32708e043bc0ccee13ec9fbdb7a9d20b1`
- `edSignature`: `OontQOUseqhwI8bs9WutMZpDP8CsAJ7VAmIO0CC3B40C29NAXAk7mHaLJVtbDOQxK+tUxuneXomb1b8VAoQ7Bw==`
- Message for package `com.example.MyGNUstepApp`, version `1.2.3`, channel
  `stable`, platform `windows-x64`:
  `gnustep-packager-update-v1\ncom.example.MyGNUstepApp\n1.2.3\nstable\nwindows-x64\n110499c3d4d34a94a1ea70ae7e7353d32708e043bc0ccee13ec9fbdb7a9d20b1`
  (141 bytes)
- `versionSignature`: `OznddanxdN2fuBl7/hJlwqj+rFthQ+ItcaDcH25RKtjymCuDudMpn+23Ynocc+6d8im05LYjMhCWnaGyK39+BA==`

With OpenSSL 3, `openssl pkeyutl -sign -inkey key.pem -rawin -in message.bin`
signs a message, as `sign-update-feed.py` style scripts do for `edSignature`.
`tests/shared/UpdaterHelperRuntime.Tests.ps1` uses these values.

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
