# Linux AppImage Handoff

## Date
2026-03-30

## Scope Of This Checkpoint
This checkpoint started the remaining `Phase 6` Linux-readiness work but did
not complete `Phase 6F` or the `Phase 7` design-doc work.

## Landed In This Checkpoint
- roadmap expansion for Linux/AppImage preparation and implementation phases
- strict manifest schema enforcement in the shared CLI
- explicit backend-enabled checks when `-Backend` is requested
- backend host-support detection for `msi` and `appimage`
- Linux-safe MSI dry-run behavior
- a dry-run validation stub for the AppImage backend
- removal of the Windows-only runtime seed from the shared `gnustep-gui`
  profile, with the Windows sample manifest now owning its `defaults.exe` seed

## Files Changed In This Checkpoint
- `Roadmap.md`
- `schemas/gnustep-packager.schema.json`
- `scripts/lib/core.ps1`
- `scripts/gnustep-packager.ps1`
- `backends/msi/lib/msi.ps1`
- `backends/appimage/package.ps1`
- `backends/appimage/validate.ps1`
- `defaults/profiles/gnustep-gui.json`
- `examples/sample-gui/package.manifest.json`

## Verified Before Stopping
- `./scripts/gnustep-packager.ps1 -Command manifest-check -Manifest examples/sample-gui/package.manifest.json`
- schema validation now rejects unexpected top-level manifest keys
- `./scripts/run-packaging-pipeline.ps1 -Manifest examples/sample-gui/package.manifest.json -Backend msi -DryRun`
  now succeeds on Linux and reports `HostSupported = false` instead of failing
- `validate -Backend appimage -DryRun` now works when the backend is enabled in
  the manifest

## Not Done Yet
- add a Linux reference fixture under `examples/`
- refactor or split repo tests so Linux can run shared and AppImage-prep tests
- add Pester bootstrap or Linux test prerequisites to `scripts/test-repo.ps1`
- write the `Phase 7A` through `Phase 7D` AppImage preparation docs
- update README and AppImage docs to describe the Linux reference path
- update roadmap status text again after the above work is actually complete

## Recommended First Steps Tomorrow
1. Add a Linux reference fixture with build, stage, and manifest files.
2. Refactor `tests/` so Windows MSI tests and Linux/AppImage-prep tests are
   separate.
3. Make `scripts/test-repo.ps1` usable on Linux hosts.
4. Write the AppImage preparation docs for requirements, metadata mapping,
   AppDir design, and runtime policy.
5. Update README, compatibility docs, and backend AppImage docs.
