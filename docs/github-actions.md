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
- `runs-on-appimage`: `["ubuntu-24.04"]`
- `runs-on-dmg`: `["macos-latest"]`

Callers may override either input with a different JSON array, for example:

- `["self-hosted","linux","gnustep-clang"]`

### AppImage Runner Image
`runs-on-appimage` defaults to a pinned image, `ubuntu-24.04`, not
`ubuntu-latest`. This matters for two reasons:

- An AppImage only runs on hosts whose glibc is at least as new as the one it
  was built against. Building on a newer image raises that floor and drops
  older distributions.
- The default host setup bootstraps the toolchain from `gnustep-cli-new`, whose
  Linux artifacts are published for specific Ubuntu releases.

So when GitHub moves `ubuntu-latest` to a new release, your AppImages don't
change. To build on a newer image, opt in explicitly:

```yaml
    with:
      runs-on-appimage: '["ubuntu-latest"]'   # follow GitHub's current image
```

or name a specific newer hosted image label the same way.

Before switching, confirm that `gnustep-cli-new` supports that release (or
use `container-appimage` / `skip-default-host-setup` with your own toolchain),
and check that the resulting glibc floor is acceptable for the distributions
you support. A job that builds inside `container-appimage` takes its glibc
from the container image, not from the runner.

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

Hosted Windows release packaging should use this default path as the required
regression gate. Do not add separate hosted-runner steps that install
`mingw-w64-clang-x86_64-gnustep-*` packages directly; those bypass the
supported `gnustep-cli-new` evidence path. If the bootstrap smoke fails, the job
must stop before build, stage, package, signing, or upload.

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

Instead of a pre-provisioned runner, the AppImage job can run in a container
image that already holds the GNUstep toolchain: pass it as
`container-appimage` (for example `ghcr.io/owner/app-ci@sha256:...`, pinned
by digest) together with `skip-default-host-setup: true`. The image must
provide PowerShell (`pwsh`), `git`, and the AppImage tools
(`squashfs-tools`, `desktop-file-utils`, `file`, `zsync`); `appimagetool`
is bootstrapped and run with `APPIMAGE_EXTRACT_AND_RUN`, so FUSE isn't
needed. A GHCR image gets the workflow's token as its registry login, so a
private package of the calling repository can be pulled; images from other
registries must be public. A smoke test that opens a window needs a display:
start Xvfb in `preflight-command` and export `DISPLAY` through
`$GITHUB_ENV`.

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
- `packager-repository` (optional override; see Implementation Note)
- `packager-ref` (optional override; see Implementation Note)
- `runs-on-msi`
- `runs-on-appimage`
- `runs-on-dmg`
- `container-appimage`
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

For hosted Windows MSI runs, keep that diagnostic artifact with release
candidate evidence. It is the handoff point for upstream issues because it
records `windows-msys2-clang64`, `MSYSTEM=CLANG64`, path conversion output,
command lookup, and the exact failed bootstrap command logs.

## Secrets
Optional MSI signing secrets:

- `sign_pfx_base64`
- `sign_pfx_password`
- `sign_cert_sha1`

Optional DMG signing and notarization secrets, used with `backend: dmg` and
`sign-artifacts: true`:

- `macos_certificate_p12`: a Developer ID Application certificate, base64 `.p12`
- `macos_certificate_password`
- `notary_apple_id`, `notary_team_id`, `notary_app_password`: when all three
  are set, a `notarytool` keychain profile is stored and its name exported in
  the variable `backends.dmg.notarization.keychainProfileEnvVar` names

The manifest's `backends.dmg.signing.identity` and `notarization` settings
still decide how the DMG is signed and whether it is notarized; see
[dmg-backend.md](dmg-backend.md).

## Example

```yaml
jobs:
  package-windows:
    uses: danjboyd/gnustep-packager/.github/workflows/package-gnustep-app.yml@v0.1.5
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
    uses: danjboyd/gnustep-packager/.github/workflows/package-gnustep-app.yml@v0.1.5
    with:
      manifest-path: packaging/package.manifest.json
      backend: appimage
      gnustep-cli-manifest-url: https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json
      run-validation: true
      run-smoke: true
      artifact-name: my-app-linux

  package-macos:
    uses: danjboyd/gnustep-packager/.github/workflows/package-gnustep-app.yml@v0.1.5
    with:
      manifest-path: packaging/package.manifest.json
      backend: dmg
      run-validation: true
      run-smoke: true
      sign-artifacts: true
      artifact-name: my-app-macos
    secrets:
      macos_certificate_p12: ${{ secrets.MACOS_CERTIFICATE_P12 }}
      macos_certificate_password: ${{ secrets.MACOS_CERTIFICATE_PASSWORD }}
      notary_apple_id: ${{ secrets.NOTARY_APPLE_ID }}
      notary_team_id: ${{ secrets.NOTARY_TEAM_ID }}
      notary_app_password: ${{ secrets.NOTARY_APP_PASSWORD }}
```

Advanced self-hosted AppImage example:

```yaml
jobs:
  package-linux:
    uses: danjboyd/gnustep-packager/.github/workflows/package-gnustep-app.yml@v0.1.5
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

Advanced self-hosted Windows example:

```yaml
jobs:
  package-windows:
    uses: danjboyd/gnustep-packager/.github/workflows/package-gnustep-app.yml@v0.1.5
    with:
      manifest-path: packaging/package.manifest.json
      backend: msi
      runs-on-msi: '["self-hosted","windows","msys2-clang64"]'
      skip-default-host-setup: true
      preflight-shell: pwsh
      preflight-command: ./packaging/ci/preflight-msys2-clang64.ps1
      run-validation: true
      run-smoke: true
      artifact-name: my-app-windows
```

Self-hosted Windows preflight should verify that `gnustep` resolves to the
intended toolchain and that any app-specific MSYS2 packages are present. Keep
those packages in `hostDependencies.windows.msys2Packages` so local preflight,
remote validation, and CI describe the same requirement.

## Implementation Note
The reusable workflow checks out:

- the caller repository as the consumer repo
- this repo as the packager toolchain

When `packager-repository` and `packager-ref` are both left empty, the workflow
checks out the exact packager commit that the caller's `uses:` line resolved to,
using `job.workflow_repository` and `job.workflow_sha`. It does not use
`github.workflow_ref`, which names the caller's workflow inside a
reusable-workflow call. Set both inputs only to test packager scripts from a
different repository or ref, or on GitHub Enterprise Server, where the
`job.workflow_*` properties are not available.

This fallback ships in `v0.1.1`. Callers pinned to `@v0.1.0`, which predates
it, must still pass both inputs.

Keeping the two checkouts separate means the consumer manifest and build
outputs stay in the caller repo while the packaging logic stays centralized
here. Caller preflight commands run in
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
