# Signing

## Purpose
Phase 5D adds release-ready signing hooks without requiring signing for normal
development or CI validation.

## Runtime Contract
The MSI backend signs artifacts only when explicitly enabled.

Supported environment variables:

- `GP_SIGN_ENABLED`
- `GP_SIGNTOOL_PATH`
- `GP_SIGN_TIMESTAMP_URL`
- `GP_SIGN_CERT_SHA1`
- `GP_SIGN_PFX_PATH`
- `GP_SIGN_PFX_PASSWORD`
- `GP_SIGN_DESCRIPTION`

## What Gets Signed
When signing is enabled, the backend signs:

- the generated Windows launcher EXE before MSI assembly
- the final MSI after WiX linking

## CI Secret Handling
Recommended pattern:

1. store a PFX as a base64 secret
2. decode it to a temporary file inside the reusable workflow
3. pass only the temporary file path and password through environment variables
4. avoid committing certificate paths or passwords into manifests

## Non-Goals
The toolkit does not try to manage certificate enrollment or trust setup.
Signing remains an optional integration point owned by the consumer's release
environment.

## macOS DMG
The DMG backend uses `codesign` and `xcrun notarytool` instead of the
environment variables above, and it is configured in
`backends.dmg.signing` and `backends.dmg.notarization`:

- `signing.identity` defaults to `-` (ad-hoc). Any other value is passed to
  `codesign --sign`, e.g. `Developer ID Application: Name (TEAMID)`.
- By default the app keeps the signature the build gave it. With
  `signing.resign`, the backend signs its copy (`--deep`, hardened runtime,
  optional entitlements relative to the manifest, `--timestamp` for real
  identities).
- A non-ad-hoc identity also signs the DMG (`signing.signDmg`).
- Notarization runs only when `notarization.enabled` is true, the identity is
  not ad-hoc, and the environment variable named by
  `notarization.keychainProfileEnvVar` holds a `notarytool` keychain profile
  name. Otherwise it is skipped with a log line, or fails when
  `notarization.required` is true.

In CI, import the certificate into a temporary keychain and run
`xcrun notarytool store-credentials` from secrets, then export the profile
name; [examples/downstream/package-dmg.yml](../examples/downstream/package-dmg.yml)
shows the steps. Details: [dmg-backend.md](dmg-backend.md#signing-and-notarization).
