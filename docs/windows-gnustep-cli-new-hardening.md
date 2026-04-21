# Windows gnustep-cli-new Hardening

This note tracks the hosted Windows hardening contract for the
`gnustep-cli-new` MSI bootstrap path.

The supported hosted Windows MSI path is:

1. start on `windows-latest`
2. provision an MSYS2 `CLANG64` bootstrap shell
3. run `scripts/ci/gnustep-cli-new-bootstrap-smoke.sh` from that shell
4. add the selected `gnustep-cli-new` root to `PATH`
5. run the shared build, stage, package, and validation pipeline

Direct hosted-runner installation of the GNUstep MSYS2 package baseline is not
the default path. App-specific MSYS2 packages still belong in
`hostDependencies.windows.msys2Packages` or the reusable workflow's temporary
`msys2-packages` input while default host setup is enabled.

## Evidence Collected

The smoke script writes these logs under `dist/logs/gnustep-cli-new` or the
workflow-resolved log root:

- `gnustep-cli-new-host-context.log`
- `gnustep-cli-new-path-context.log`
- `gnustep-cli-new-selection.log`
- `gnustep-cli-new-bootstrap-download.log`
- `gnustep-cli-new-setup.log`
- `gnustep-cli-new-version.log`
- `gnustep-cli-new-doctor.json`
- `gnustep-cli-new-new.json`
- `gnustep-cli-new-build.json`
- `gnustep-cli-new-run.json`
- `gnustep-cli-new-blocker-report.md`

The reusable workflow uploads that directory as the
`<artifact-name>-gnustep-cli-new` artifact. The repo validation workflow uploads
the same directory as `windows-gnustep-cli-new` or `linux-gnustep-cli-new`.

## Windows-Specific Diagnostics

The host and path context logs include:

- hosted runner metadata such as workflow, run ID, and ref when available
- `MSYSTEM`, `MSYS2_LOCATION`, and the declared `host_kind`
- POSIX and Windows forms of the install, log, and smoke roots
- PATH entries as seen by the smoke script
- `command -v` results for `gnustep`, bootstrap tools, shell tools, and
  compiler entry points
- `cmd.exe /c where gnustep` when running from a Windows-capable MSYS2 shell

These fields are intended to expose path conversion mistakes before they look
like toolchain or WiX problems.

## Failure Classification

Use this split when reading the generated blocker report:

- `gnustep-cli-new` blocker: setup cannot select, download, extract, start, or
  validate the declared managed toolchain artifact.
- MSYS2/bootstrap host blocker: the bootstrap shell cannot provide required
  basics such as `curl`, `tar`, `gzip`, POSIX shell behavior, or path
  conversion.
- Packager workflow bug: the selected toolchain works, but the workflow fails to
  expose it to build, stage, package, or validation steps.
- MSI backend bug: build and stage succeed, but WiX generation, installer
  output, install validation, launch smoke, or uninstall validation fails.

Confirmed upstream issues should be copied into
[gnustep-cli-new-upstream-requests.md](gnustep-cli-new-upstream-requests.md)
with the generated blocker report attached or summarized.

## Current Phase 14A-D Status

Phase 14A-D are implemented as repo-owned evidence collection and diagnostics.
Hosted validation run `24736846989` confirmed that the current public
`gnustep-cli-new` bootstrap classifies the MSYS2 `CLANG64` shell as
`os: unknown`, then fails to select the published Windows artifacts:

```text
No matching release artifacts were found for this host.
```

The uploaded `windows-gnustep-cli-new` artifact contains the blocker report,
setup log, host context, and bootstrap download log for upstream reproduction.
Phase 14E should retest this hosted path after the upstream selector can detect
MSYS2/Windows and install the published `windows-amd64-msys2-clang64`
artifacts.
