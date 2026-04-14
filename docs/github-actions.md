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
baseline per backend, resolves the manifest, and then merges manifest-declared
host dependency packages with any additive workflow inputs.

Default MSI MSYS2 baseline:

- `make`
- `mingw-w64-clang-x86_64-gnustep-make`
- `mingw-w64-clang-x86_64-gnustep-base`
- `mingw-w64-clang-x86_64-gnustep-gui`
- `mingw-w64-clang-x86_64-gnustep-back`
- `mingw-w64-clang-x86_64-libdispatch`
- `mingw-w64-clang-x86_64-libobjc2`
- `mingw-w64-clang-x86_64-toolchain`

Manifest-declared Windows host packages under
`hostDependencies.windows.msys2Packages` are installed automatically. The
`msys2-packages` input remains available as an additive override or temporary
escape hatch.

Default AppImage host packages:

- `squashfs-tools`
- `desktop-file-utils`

Manifest-declared Linux host packages under `hostDependencies.linux.aptPackages`
are added automatically. Override or extend that list through
`appimage-apt-packages`, or set
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

The reusable workflow uploads package outputs exactly as the backend produced
them. When updates are enabled, that includes the generated `.update-feed.json`
sidecars and any AppImage `.zsync` outputs under the `-packages` artifact.

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

When default host setup is enabled, the workflow also passes
`-InstallHostDependencies` into the shared pipeline wrapper so manifest-driven
host preflight can repair missing app-specific packages before build starts.
On self-hosted runs with `skip-default-host-setup: true`, manifest-driven host
preflight still runs, but it verifies dependencies instead of installing them
automatically.

## Release Publishing Follow-On
The reusable workflow stops at packaging, validation, and artifact upload.

For updater-enabled apps, add a downstream release job that:

1. downloads the `-packages` artifacts
2. publishes `.msi`, `.AppImage`, and `.zsync` outputs to GitHub Releases
3. copies the generated `.update-feed.json` files to stable feed URLs such as
   `updates/windows/stable.json` and `updates/linux/stable.json`
4. deploys those feed URLs through GitHub Pages or another static host

See:

- [updater-release-publishing.md](updater-release-publishing.md)
- `examples/downstream/package-release-with-updates.yml`
