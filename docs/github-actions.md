# GitHub Actions

## Reusable Workflow
The repo now exposes a reusable workflow:

- `.github/workflows/package-gnustep-app.yml`

Downstream repos can call it without copying packaging logic. The reusable
workflow still delegates packaging to `scripts/run-packaging-pipeline.ps1`, but
it now lets callers control runner selection, host setup, and app-specific
prerequisites.

## Runner Selection
Default runner JSON arrays:

- `runs-on-msi`: `["windows-latest"]`
- `runs-on-appimage`: `["ubuntu-latest"]`

Callers may override either input with a different JSON array, for example:

- `["self-hosted","linux","gnustep-clang"]`

## Default Host Setup
When `skip-default-host-setup` is `false`, the workflow provisions a documented
baseline per backend before resolving the manifest.

Default MSI MSYS2 baseline:

- `make`
- `mingw-w64-clang-x86_64-gnustep-make`
- `mingw-w64-clang-x86_64-gnustep-base`
- `mingw-w64-clang-x86_64-gnustep-gui`
- `mingw-w64-clang-x86_64-gnustep-back`
- `mingw-w64-clang-x86_64-libdispatch`
- `mingw-w64-clang-x86_64-libobjc2`
- `mingw-w64-clang-x86_64-toolchain`

Add app-specific MSYS2 packages through `msys2-packages`, for example
`mingw-w64-clang-x86_64-cmark`.

Default AppImage host packages:

- `squashfs-tools`
- `desktop-file-utils`

Override that list through `appimage-apt-packages`, or set
`skip-default-host-setup: true` on a pre-provisioned self-hosted runner.

## Caller Preflight
The reusable workflow can run caller-owned host/bootstrap logic after checkout
and before manifest resolution through:

- `preflight-shell`
- `preflight-command`

Typical uses:

- clone or prepare extra packaging inputs
- run org-specific bootstrap commands
- verify a self-hosted GNUstep environment before packaging

## Inputs
Primary inputs:

- `manifest-path`
- `backend`
- `package-version`
- `runs-on-msi`
- `runs-on-appimage`
- `skip-default-host-setup`
- `msys2-packages`
- `appimage-apt-packages`
- `preflight-shell`
- `preflight-command`
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
      msys2-packages: >-
        mingw-w64-clang-x86_64-cmark
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

Advanced self-hosted AppImage example:

```yaml
jobs:
  package-linux:
    uses: <owner>/gnustep-packager/.github/workflows/package-gnustep-app.yml@main
    with:
      manifest-path: packaging/package.manifest.json
      backend: appimage
      runs-on-appimage: '["self-hosted","linux","gnustep-clang"]'
      skip-default-host-setup: true
      preflight-shell: bash
      preflight-command: ./packaging/ci/preflight-appimage.sh
      run-validation: true
      run-smoke: true
      artifact-name: my-app-linux
```

## Implementation Note
The reusable workflow checks out:

- the caller repository as the consumer repo
- this repo as the packager toolchain

That means the consumer manifest and build outputs stay in the caller repo while
the packaging logic stays centralized here. Caller preflight commands run in
that checked-out workspace before the workflow resolves outputs or invokes the
shared packaging pipeline.
