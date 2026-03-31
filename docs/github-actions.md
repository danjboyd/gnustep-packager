# GitHub Actions

## Reusable Workflow
The repo now exposes a reusable workflow:

- `.github/workflows/package-gnustep-app.yml`

Downstream repos can call it without copying packaging logic.

The workflow is backend-aware:
- `backend: msi` runs on `windows-latest`
- `backend: appimage` runs on `ubuntu-latest`
- Linux prerequisite packages are installed automatically for AppImage jobs

## Inputs
Primary inputs:

- `manifest-path`
- `backend`
- `package-version`
- `run-validation`
- `run-smoke`
- `upload-artifacts`
- `artifact-name`
- `artifact-retention-days`
- `sign-artifacts`
- `sign-timestamp-url`

## Secrets
Optional signing secrets:

- `sign_pfx_base64`
- `sign_pfx_password`
- `sign_cert_sha1`

## Example

```yaml
jobs:
  package-windows:
    uses: <owner>/gnustep-packager/.github/workflows/package-gnustep-app.yml@main
    with:
      manifest-path: packaging/package.manifest.json
      backend: msi
      run-validation: true
      run-smoke: true
      artifact-name: my-app-windows
    secrets:
      sign_pfx_base64: ${{ secrets.WINDOWS_SIGN_PFX_BASE64 }}
      sign_pfx_password: ${{ secrets.WINDOWS_SIGN_PFX_PASSWORD }}

  package-linux:
    uses: <owner>/gnustep-packager/.github/workflows/package-gnustep-app.yml@main
    with:
      manifest-path: packaging/package.manifest.json
      backend: appimage
      run-validation: true
      run-smoke: true
      artifact-name: my-app-linux
```

## Implementation Note
The reusable workflow checks out:

- the caller repository as the consumer repo
- this repo as the packager toolchain

That means the consumer manifest and build outputs stay in the caller repo while
the packaging logic stays centralized here.
