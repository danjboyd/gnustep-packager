# Updater Release Publishing

## Goal
Publish signed MSI and AppImage artifacts to GitHub in a way that the packaged
updater can consume with stable feed URLs.

The runtime updater does not query GitHub directly. It reads the packaged feed
URL, and that feed URL should always point at a current JSON document for the
selected channel.

## Package Outputs To Publish
For each release build, keep:

- the distributable package itself
  - `.msi`
  - `.AppImage`
- package diagnostics sidecars when useful
  - `.metadata.json`
  - `.diagnostics.txt`
- updater sidecars
  - `.update-feed.json`
  - `.AppImage.zsync` for AppImage releases

The generated feed sidecar already contains:

- package identity
- resolved release tag
- release notes URL
- asset download URL
- asset SHA-256
- backend-specific metadata such as `msiVersion` or AppImage `updateInformation`

## Recommended Publishing Model
Use two publication surfaces:

- GitHub Releases
  host the signed MSI and AppImage artifacts that users actually download
- GitHub Pages
  host the stable feed URLs consumed by the app at runtime

Example stable feed layout:

```text
https://example-org.github.io/my-gnustep-app/updates/windows/stable.json
https://example-org.github.io/my-gnustep-app/updates/linux/stable.json
```

The feed contents can still point back at GitHub Release asset URLs.

## Channel Rules
Keep channels separate on disk and in the manifest:

- `stable`
- `beta`
- `nightly`

Do not publish one mixed feed and expect the app to infer prerelease semantics
from tag names.

## AppImage Requirements
When `backends.appimage.updates.embedUpdateInformation` is enabled:

- publish the `.AppImage`
- publish the matching `.AppImage.zsync`
- keep the release asset names stable

That lets AppImage-native tools resolve the same release without app-specific
logic.

## GitHub Actions Shape
The recommended downstream flow is:

1. package Windows MSI with the reusable workflow
2. package Linux AppImage with the reusable workflow
3. download the uploaded package artifacts
4. publish the release assets to GitHub Releases
5. copy the generated `.update-feed.json` files to your stable feed URLs
6. deploy those feed URLs to GitHub Pages

An end-to-end example lives at:

- `examples/downstream/package-release-with-updates.yml`

## Publishing Example
The reusable workflow uploads three artifact groups:

- `<artifact-name>-packages`
- `<artifact-name>-logs`
- `<artifact-name>-validation`

The release job should download the `-packages` artifacts, then stage:

- `site/updates/windows/stable.json`
- `site/updates/linux/stable.json`
- release assets such as `.msi`, `.AppImage`, and `.zsync`

## Release Checklist
- The manifest `package.version` or release override matches the Git tag.
- MSI artifacts are signed before release publication.
- AppImage `.zsync` sidecars are published together with the `.AppImage`.
- The stable feed URLs point at the newest channel document.
- The feed URLs configured in the manifest match the actual published Pages
  URLs.

Related docs:

- [github-actions.md](github-actions.md)
- [versioning-release.md](versioning-release.md)
- [update-feed-contract.md](update-feed-contract.md)
