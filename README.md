# gnustep-packager

`gnustep-packager` is a packaging toolkit for GNUstep desktop applications.

The repo is intended to separate packaging concerns from individual app repos.
Instead of every GNUstep app carrying its own ad hoc installer scripts, this
repo will provide a shared packaging model, backend implementations, and CI
entry points that downstream apps can reuse.

## Why This Exists
The immediate driver is to generalize the Windows MSI packaging method currently
used for a GNUstep app built with MSYS2 `CLANG64`.

The broader goal is to build that work on a backend-neutral foundation so the
same app can later target additional distribution formats such as Linux
AppImage without rewriting the entire packaging system.

## Intended Outcomes
- A backend-neutral package manifest and staged payload contract
- A Windows MSI backend suitable for MSYS2 `CLANG64` GNUstep apps
- A future Linux AppImage backend built on the same core packaging model
- Reusable local scripts and reusable GitHub Actions workflows
- Clean validation paths for package smoke testing

## Design Principles
- Stage first. Packaging starts from a self-contained staged payload.
- Keep the core model neutral. MSI and AppImage are backends, not the model.
- Prefer declarative configuration over app-specific hard-coded paths.
- Keep local and CI workflows aligned.
- Keep generated packaging artifacts out of source control.

## Planned Packaging Lifecycle
1. Build the app with its native toolchain.
2. Stage a self-contained payload tree plus manifest.
3. Transform that staged payload into a backend-specific layout.
4. Produce the distributable artifact.
5. Validate the artifact in an automated smoke path.

## Planned Backends
### Windows MSI
Initial backend target.

Expected stack:
- MSYS2 `CLANG64`
- GNUstep
- WiX
- GitHub Actions on Windows runners

### Linux AppImage
Planned second backend.

Expected shape:
- backend-specific AppDir transform
- generated `AppRun`
- desktop metadata and icon handling
- Linux validation path in CI

## Repo Status
This repo now includes the phase 1 through phase 4 implementation baseline:

- layered manifest resolution
- shared CLI entry points
- shared path and shell abstractions
- a normalized launch contract
- shared staged-payload validation
- an executable reference fixture for local and CI checks
- MSI backend docs for backend boundary, runtime policy, launcher design, and
  WiX rendering
- a manifest-driven Windows launcher plus generated `.launcher.ini`
- support for embedding a staged `.ico` into the MSI launcher
- a real MSI backend that transforms the staged payload into an install tree,
  harvests it with WiX, and emits both MSI and ZIP artifacts
- backend MSI validation for install, launch, and uninstall smoke testing

This repo now also includes the phase 5 and phase 6 foundation:

- a shared local/CI pipeline wrapper in `scripts/run-packaging-pipeline.ps1`
- package version override support for release automation
- a reusable GitHub Actions workflow for downstream repos
- optional signing hooks for release packaging
- Pester regression tests for manifest, versioning, and MSI transform behavior
- a documented compatibility matrix and consumer setup path

This repo now also includes the phase 9 Windows hardening pass:

- manifest-level compliance notice entries plus generated runtime notice reports
- package-side artifact provenance and diagnostics sidecars
- built-in manifest profiles for common GNUstep GUI app shapes
- MSI failure triage guidance and release-gate documentation
- a documented AppImage extension path for the future Linux backend

Current sample verification covers:
- `build`
- `stage`
- `package -Backend msi`
- `validate -Backend msi -RunSmoke`
- `scripts/test-repo.ps1`

## Proposed Structure
- `AGENTS.md`
- `README.md`
- `Roadmap.md`
- `schemas/`
- `scripts/`
- `backends/msi/`
- `backends/appimage/`
- `examples/`
- `docs/`
- `.github/workflows/`

## What This Repo Will Not Try To Do Early
- Support every GNUstep toolchain at once
- Support every Linux package format before AppImage is working
- Hide all packaging details behind opaque automation
- Treat generated backend output as hand-maintained source

## Near-Term Direction
MSI is the first concrete deliverable, but implementation choices should always
be reviewed through a future AppImage lens:
- no MSI-only assumptions in shared code
- launch behavior modeled as a contract, not a Windows bootstrap special case
- runtime inclusion rules expressed declaratively
- metadata modeled once and rendered differently per backend

## Shared Commands
Examples:

```powershell
./scripts/gnustep-packager.ps1 -Command resolve-manifest
./scripts/gnustep-packager.ps1 -Command build
./scripts/gnustep-packager.ps1 -Command stage
./scripts/gnustep-packager.ps1 -Command validate
./scripts/gnustep-packager.ps1 -Command package -Backend msi
./scripts/gnustep-packager.ps1 -Command validate -Backend msi -RunSmoke
```

MSI-specific design notes:
- [docs/msi-boundary.md](docs/msi-boundary.md)
- [docs/msi-runtime-policy.md](docs/msi-runtime-policy.md)
- [docs/msi-launcher-design.md](docs/msi-launcher-design.md)
- [docs/msi-wix-rendering.md](docs/msi-wix-rendering.md)

Release and consumer docs:
- [docs/local-ci-parity.md](docs/local-ci-parity.md)
- [docs/github-actions.md](docs/github-actions.md)
- [docs/versioning-release.md](docs/versioning-release.md)
- [docs/release-gate.md](docs/release-gate.md)
- [docs/signing.md](docs/signing.md)
- [docs/consumer-setup.md](docs/consumer-setup.md)
- [docs/compatibility-matrix.md](docs/compatibility-matrix.md)
- [docs/compliance-notices.md](docs/compliance-notices.md)
- [docs/windows-msi-triage.md](docs/windows-msi-triage.md)
- [docs/appimage-extension-path.md](docs/appimage-extension-path.md)

See [Roadmap.md](Roadmap.md) for the implementation phases.
