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

Current `gnustep-cli-new` release baseline:

```text
https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json
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
