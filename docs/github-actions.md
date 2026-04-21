# GitHub Actions

## Reusable Workflow
The repo now exposes a reusable workflow:

- `.github/workflows/package-gnustep-app.yml`

Downstream repos can call it without copying packaging logic. The reusable
workflow still delegates packaging to `scripts/run-packaging-pipeline.ps1`, but
it now lets callers control runner selection, host setup, and app-specific
prerequisites.

For Windows/MSI and Linux/AppImage jobs with default host setup enabled, the
workflow uses `gnustep-cli-new` as the standard GNUstep toolchain bootstrap path
before it starts the shared packaging pipeline.

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

Default MSI MSYS2 bootstrap baseline:

- `curl`
- `tar`
- `gzip`

Manifest-declared Windows host packages under
`hostDependencies.windows.msys2Packages` are installed into the bootstrap shell
automatically. The reusable workflow then runs `gnustep-cli-new` setup and smoke
validation before MSI packaging. The `msys2-packages` input remains available as
an additive override or temporary escape hatch while default host setup is
enabled.

Default AppImage host packages:

- `ca-certificates`
- `curl`
- `tar`
- `gzip`
- `squashfs-tools`
- `desktop-file-utils`

Manifest-declared Linux host packages under `hostDependencies.linux.aptPackages`
are added automatically. Override or extend that list through
`appimage-apt-packages`, or set
`skip-default-host-setup: true` on a pre-provisioned self-hosted runner.

After installing backend host prerequisites, the default MSI and AppImage paths
run the repo-owned `scripts/ci/gnustep-cli-new-bootstrap-smoke.sh` script. That
smoke downloads the selected bootstrap script, runs `gnustep-bootstrap.sh
--json --yes setup`, records `gnustep --version`, runs `gnustep doctor --json`,
generates a small `HelloPackager` CLI project, builds it, and runs it. The
workflow adds the selected `gnustep-cli-new` root to `PATH` for the downstream
build and stage commands.

When `skip-default-host-setup` is `true`, the workflow does not apply
`msys2-packages` or `appimage-apt-packages`. In that mode, app-specific host
packages should come from the manifest or from the caller's preflight logic so
the later shared verification step sees the same declared contract.

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
- `gnustep-cli-manifest-url`
- `gnustep-cli-bootstrap-url`
- `gnustep-cli-root`
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
The workflow also uploads a dedicated `<artifact-name>-gnustep-cli-new`
diagnostic artifact containing the selected manifest, setup logs, doctor output,
and `gnustep-cli-new-blocker-report.md`.

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
      gnustep-cli-manifest-url: https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json
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
      gnustep-cli-manifest-url: https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json
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
automatically. The workflow now emits a host-setup policy summary during
manifest resolution so the logs state whether the run is in install-and-verify
or verify-only mode.

The `gnustep-cli-manifest-url`, `gnustep-cli-bootstrap-url`, and
`gnustep-cli-root` inputs exist so CI can test a new upstream manifest or
bootstrap commit without editing packager implementation files. The selected
values are recorded under the workflow log root in `gnustep-cli-new` logs. If
that supported bootstrap path fails, treat it as an upstream blocker unless the
failure is clearly in downstream app build/stage commands or packager
transform/validation code. The generated `gnustep-cli-new-blocker-report.md`
file is intended to be copied into the upstream issue body.

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
