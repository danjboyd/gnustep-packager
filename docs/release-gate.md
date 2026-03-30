# Release Gate

## Version 1 Criteria
The repo is ready to present as a reusable Windows packaging toolkit when all
of the following are true:

- `scripts/test-repo.ps1` passes
- the sample fixture passes the shared pipeline wrapper with MSI packaging and
  smoke validation
- package outputs include notice and provenance sidecars
- downstream onboarding docs and examples are current
- the AppImage extension path is documented, even if the backend is still
  pending

## Windows MSI Checklist

1. Run `./scripts/test-repo.ps1`
2. Run:

```powershell
./scripts/run-packaging-pipeline.ps1 `
  -Manifest examples/sample-gui/package.manifest.json `
  -Backend msi `
  -RunSmoke
```

3. Confirm these outputs exist:
- MSI artifact
- portable ZIP artifact
- `<artifact-base>.metadata.json`
- `<artifact-base>.diagnostics.txt`
- `metadata/THIRD-PARTY-NOTICES.txt` inside the transformed install tree

## AppImage Requirement
Until Phase 8 is complete, the AppImage requirement for a v1 Windows release is
documentation, not a stub pretending to be complete.

See [appimage-extension-path.md](appimage-extension-path.md).
