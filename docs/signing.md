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
