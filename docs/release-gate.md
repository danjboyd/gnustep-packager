# Release Gate

## Version 1 Criteria
The repo is ready to present as a reusable GNUstep packaging toolkit when all
of the following are true:

- `scripts/test-repo.ps1` passes
- the Windows sample fixture passes the shared pipeline wrapper with MSI
  packaging and smoke validation
- the Linux sample fixture passes the shared pipeline wrapper with AppImage
  packaging and smoke validation
- package outputs include notice and provenance sidecars
- downstream onboarding docs and examples are current
- both supported backends have documented local and CI entry points
- hosted-runner MSI and AppImage workflow paths run the
  `gnustep-cli-new` bootstrap smoke before packaging
- release notes record the known-good `gnustep-cli-new` manifest URL

The Windows hosted-runner gate is fail-closed: release packaging from the
default hosted MSI path must not proceed when the `gnustep-cli-new` bootstrap
smoke is skipped or fails. Failed runs must retain the
`windows-gnustep-cli-new` or `<artifact-name>-gnustep-cli-new` diagnostic
artifact so the failure can be classified as a packager issue, an MSYS2 host
issue, a WiX issue, or an upstream `gnustep-cli-new` blocker.

Current `gnustep-cli-new` release baseline:

```text
https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json
```

## Windows Toolchain Baseline

Record this baseline in release notes whenever publishing a packager release
that claims hosted Windows MSI readiness:

- runner image: `windows-latest`
- MSYS2 mode: `CLANG64`
- bootstrap packages: `curl`, `tar`, `gzip`
- app-specific MSYS2 packages: declared under
  `hostDependencies.windows.msys2Packages`
- `gnustep-cli-new` manifest URL:
  `https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json`
- WiX source: hosted runner WiX installation or the documented local WiX
  baseline used by the MSI backend
- MSI smoke: shared pipeline `-Backend msi -RunSmoke` result
- diagnostics artifact: `windows-gnustep-cli-new` for repo validation or
  `<artifact-name>-gnustep-cli-new` for reusable workflow calls

Current Windows hosted status: blocked before MSI build by the upstream
`gnustep-cli-new` MSYS2 CLANG64 selector. The bootstrap classifies the hosted
MSYS2 shell as `os: unknown` and does not select the published
`windows-amd64-msys2-clang64` artifacts. Treat this as a release-blocking
upstream issue until a retest records a successful bootstrap smoke and MSI
package smoke on `windows-latest`.

Latest phase 14 gate evidence:

- run: `24738535673`
- commit: `83cfc8f`
- Linux/AppImage: passed bootstrap, Pester regression tests, and shared
  packaging pipeline
- Windows/MSI: failed closed at `Bootstrap And Smoke Test gnustep-cli-new`
  before packaging, with `windows-gnustep-cli-new` diagnostics uploaded

Release-note template:

```text
Windows MSI hosted baseline:
- runner: windows-latest
- MSYS2: CLANG64
- gnustep-cli-new manifest: <url>
- gnustep-cli-new smoke: <run URL and result>
- WiX baseline: <version/source>
- MSI package smoke: <run URL and result>
- known blockers: <none or upstream issue links>
```

## Windows MSI Checklist

1. Run `./scripts/test-repo.ps1`
2. Confirm the reusable Windows workflow path uploads the
   `gnustep-cli-new` diagnostic artifact, including
   `gnustep-cli-new-blocker-report.md`
3. Run:

```powershell
./scripts/run-packaging-pipeline.ps1 `
  -Manifest examples/sample-gui/package.manifest.json `
  -Backend msi `
  -RunSmoke
```

4. Confirm these outputs exist:
- MSI artifact
- portable ZIP artifact
- `<artifact-base>.metadata.json`
- `<artifact-base>.diagnostics.txt`
- `metadata/THIRD-PARTY-NOTICES.txt` inside the transformed install tree

## AppImage Requirement
Confirm the reusable Linux workflow path uploads the `gnustep-cli-new`
diagnostic artifact, including `gnustep-cli-new-blocker-report.md`.

Run:

```powershell
./scripts/run-packaging-pipeline.ps1 `
  -Manifest examples/sample-linux/package.manifest.json `
  -Backend appimage `
  -RunSmoke
```

Confirm these outputs exist:
- AppImage artifact
- `<artifact-base>.metadata.json`
- `<artifact-base>.diagnostics.txt`
- `usr/metadata/THIRD-PARTY-NOTICES.txt` inside the extracted AppDir

See [../backends/appimage/README.md](../backends/appimage/README.md).
