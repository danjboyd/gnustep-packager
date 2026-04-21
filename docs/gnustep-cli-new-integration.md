# GNUstep CLI New Integration

`gnustep-cli-new` is the default GNUstep toolchain bootstrap path for supported
Windows/MSI and Linux/AppImage CI packaging flows.

The packager remains responsible for manifest resolution, staging validation,
backend transforms, AppImage generation, package validation, release sidecars,
and diagnostics. `gnustep-cli-new` is responsible for provisioning and checking
the GNUstep build toolchain that downstream build and stage commands use before
the staged payload is packaged.

## Default Baseline

The supported default release manifest is:

```text
https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json
```

The supported default bootstrap script is:

```text
https://raw.githubusercontent.com/danjboyd/gnustep-cli-new/master/scripts/bootstrap/gnustep-bootstrap.sh
```

The reusable workflow records both values in the `gnustep-cli-new` logs so a
failed run identifies which upstream artifact set was tested.

## Local Smoke Test

Use the repo-owned smoke script to validate a clean Linux host or container:

```sh
GP_GNUSTEP_CLI_ROOT=/tmp/gnustep-cli-new \
GP_GNUSTEP_CLI_LOG_ROOT=dist/logs/gnustep-cli-new \
./scripts/ci/gnustep-cli-new-bootstrap-smoke.sh
```

The smoke path downloads the bootstrap script, runs:

```sh
gnustep-bootstrap.sh --json --yes setup
```

Then it checks:

- `gnustep --version`
- `gnustep doctor --json`
- `gnustep new cli-tool HelloPackager --json`
- `gnustep build --json`
- `gnustep run --json`

The hosted Windows MSI path currently runs the built `HelloPackager.exe`
directly after `gnustep build --json`. This keeps the hosted packager gate
blocked on managed toolchain build/run viability without depending on older
published `gnustep-cli-new` artifacts that still resolve tool runs to the
POSIX-style `./obj/<target>` path.

The script writes selection, setup, doctor, build, run, and blocker-report logs
under `GP_GNUSTEP_CLI_LOG_ROOT`.

## Workflow Inputs

`.github/workflows/package-gnustep-app.yml` exposes:

- `gnustep-cli-manifest-url`
- `gnustep-cli-bootstrap-url`
- `gnustep-cli-root`

Use these inputs to test a newly published upstream manifest or bootstrap
change without editing packager backend code.

When `skip-default-host-setup: false`, the workflow runs the bootstrap smoke
before packaging for both supported backends.

For `backend: appimage`, the workflow:

1. installs the Linux host baseline, including `ca-certificates`, `curl`,
   `tar`, `gzip`, `squashfs-tools`, and `desktop-file-utils`
2. runs the `gnustep-cli-new` bootstrap smoke
3. adds the selected `gnustep-cli-new` root to `PATH`
4. runs the normal shared packaging pipeline

For `backend: msi`, the workflow:

1. starts an MSYS2 `CLANG64` shell as the Windows bootstrap host
2. installs only bootstrap shell prerequisites plus manifest-declared MSYS2
   host packages
3. runs the `gnustep-cli-new` bootstrap smoke from that shell
4. adds the selected `gnustep-cli-new` root to `PATH`
5. runs the normal shared packaging pipeline

When `skip-default-host-setup: true`, the caller owns provisioning. The
workflow still runs the shared package pipeline, but it does not install or
smoke-test `gnustep-cli-new`.

## Blocker Policy

Failures in the supported `gnustep-cli-new` bootstrap path are blockers for MSI
and AppImage CI unless they are clearly caused by downstream app commands or
packager staging/package logic.

Record upstream bootstrap or artifact failures in
[gnustep-cli-new-upstream-requests.md](gnustep-cli-new-upstream-requests.md)
with:

- host OS and runner/container details
- selected manifest URL
- selected bootstrap URL
- resolved artifact IDs when available
- `gnustep --version` and `gnustep doctor --json` output when they run
- failing command output

Do not silently fall back to legacy repo-local GNUstep setup on the supported
default path.

The smoke script writes `gnustep-cli-new-blocker-report.md` into the log root
on both success and failure. On failure, that file is the ready-to-copy upstream
report body. The reusable workflow uploads the `gnustep-cli-new` log directory
as a dedicated diagnostic artifact even when later packaging steps fail.

See [windows-gnustep-cli-new-hardening.md](windows-gnustep-cli-new-hardening.md)
for the Windows/MSYS2 hosted-runner evidence contract and failure
classification guidance.

## Migration Notes

Downstream projects should remove workflow-local GNUstep installation steps
from default hosted-runner packaging jobs. The reusable workflow owns the
standard bootstrap path when `skip-default-host-setup` is `false`.

Keep app-specific build prerequisites in the package manifest:

- `hostDependencies.windows.msys2Packages`
- `hostDependencies.linux.aptPackages`
- reusable profiles such as `gnustep-cmark`

Use workflow package inputs only as temporary overrides while default host setup
is enabled. For self-hosted runners with `skip-default-host-setup: true`, make
the caller preflight run `gnustep --version` and `gnustep doctor --json` against
the expected toolchain before packaging.

## Release Baseline

Release notes should identify the known-good `gnustep-cli-new` release manifest
used by the packager release. The current baseline is:

```text
https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json
```
