# Moving an App to v0.1.9 or Later (Signed Updates)

v0.1.9 makes update signing mandatory. An app with `updates.enabled: true`
can't be packaged until it has a key, and its feed must carry two signatures
per asset. This note is the checklist for each app's move. The rules
themselves are in `docs/update-feed-contract.md`, and CHANGELOG v0.1.9 has
"Upgrading".

Status as of 2026-11-06, from each repo's default branch.

## What every app does, in one release

1. **Key.** An Ed25519 key pair for the app's updates. The private seed is a
   secret of the release job only. Never put it in a checkout, a log or an
   artifact.
2. **`updates.publicEDKey`**: the base64 public key, in every manifest with
   updates on (AppImage and MSI). Validation fails without it, and refuses the
   test key from the docs.
3. **Signer.** In the release job, after packaging and before the feed is
   published, every asset gets:
   - `edSignature`: Ed25519 over the asset file's bytes (Sparkle's
     `sign_update` makes the same signature).
   - `versionSignature`: Ed25519 over the six-line message
     `gnustep-packager-update-v1`, package id, version, channel, platform, and
     lowercase sha256, joined with `\n` and with no trailing newline.

   Check the signer against the test vector in `docs/update-feed-contract.md`
   ("Test vector") before using it on a real key.
4. **Pins.** Move every `package-gnustep-app.yml@vX` or
   `release-inputs.json` packager pin to the new tag in the same change, so
   every platform's feed is signed the same way.
5. **Mixed feeds.** If the feed carries several architectures, merge them with
   `scripts/merge-update-feeds.ps1`, which keeps x64 first.

**What users see.** Copies built with v0.1.8 or earlier ignore the new fields
and take the first asset for their backend. So the first signed release still
reaches them through the old updater, as long as the x64 asset is first. From
then on, copies refuse an update that is unsigned, wrongly signed, not newer,
or not built for the machine.

**macOS DMG.** These updates go through Sparkle's appcast and Sparkle's own
signature, not this feed. None of the above applies to them.

## Per app

| App | Packager pin now | Updates | Key in manifest | Signer | versionSignature |
| --- | --- | --- | --- | --- | --- |
| ObjcMarkdown | AppImage `@v0.1.7`; MSI `@v0.1.4` (open PR #355 moves it to v0.1.7) | AppImage, MSI | yes (both manifests) | `packaging/ci/sign-update-feed.py` | **no** |
| LinDirStat | `release-inputs.json` v0.1.7 | AppImage (DMG via Sparkle) | yes | `scripts/sign-update-feed.py` | **no** |
| PerformanceDashboard | `release-inputs.json` v0.1.7 | AppImage | yes | `scripts/sign-update-feed.py`, with `Tests/update-signing-checks.py` and `docs/update-signing-keys.md` | **no** |
| ScreenshotTool | `@v0.1.7` (4 uses) | AppImage, MSI (macOS via Sparkle) | **no** | none for this feed | n/a |

"versionSignature" means the signer writes it today. None does, so every app
needs step 3. The steps left for each:

- **ObjcMarkdown:**
  1. Add `versionSignature` to `sign-update-feed.py` and check it against the
     test vector.
  2. Move both pins to the new tag together. The MSI pin is the furthest
     behind.
  3. It already has the key and edSignature.
- **LinDirStat:**
  1. Add `versionSignature` to its own `scripts/sign-update-feed.py`, the same
     change as ObjcMarkdown's.
  2. Move the `release-inputs.json` pin (tag and peeled revision).
- **PerformanceDashboard:**
  1. Add `versionSignature` to `scripts/sign-update-feed.py`, and cover it in
     `Tests/update-signing-checks.py` with the test vector.
  2. Move the pin.
  3. Its arm64 AppImage (#112, v0.1.10) puts a `linux-arm64` asset in the feed.
     Merge it with `merge-update-feeds.ps1`, x64 first.
- **ScreenshotTool:**
  1. Dan makes a key.
  2. Put the public key in `packaging/package.manifest.json`.
  3. Add a signer to the release job, writing both signatures, for the AppImage
     and MSI feeds.
  4. Move all four pins together.
  5. Its macOS appcast stays on Sparkle.
- **SpreadsheetApp:** updates are off, so no key is needed. It still tracks
  `@main`; pin it to a tag.

## Checking a release before it ships

- `scripts/gnustep-packager.ps1 -Command manifest-check -Manifest <manifest>`
  catches a missing key, or the test key.
- Run the signer on the packaged assets, then check the feed with a copy built
  by the new packager:
  - Point `GP_UPDATER_FEED_URL` at the signed feed (`file://` works) and check
    for updates. It should offer the release.
  - Change one byte in an asset and check again. It should refuse it, and the
    error should say why.
