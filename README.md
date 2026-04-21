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
- A Linux AppImage backend built on the same core packaging model
- Reusable local scripts and reusable GitHub Actions workflows
- Clean validation paths for package smoke testing
- A companion updater foundation for apps that publish MSI and AppImage
  releases to GitHub

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

## Supported Backends
### Windows MSI
Supported backend.

Expected stack:
- MSYS2 `CLANG64`
- GNUstep
- WiX
- GitHub Actions on Windows runners

### Linux AppImage
Supported backend.

Current shape:
- backend-specific AppDir transform
- generated `AppRun`
- desktop metadata, icon, and MIME handling
- Linux validation path in CI

## Repo Status
This repo includes the phase 1 through phase 4 implementation baseline:

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

This repo also includes the phase 5 and phase 6 foundation:

- a shared local/CI pipeline wrapper in `scripts/run-packaging-pipeline.ps1`
- package version override support for release automation
- a reusable GitHub Actions workflow for downstream repos
- optional signing hooks for release packaging
- platform-aware Pester regression tests for Windows MSI and Linux AppImage
- a Windows sample fixture and a Linux AppImage sample fixture
- a documented compatibility matrix and consumer setup path

This repo also includes the phase 7 through phase 9 AppImage completion and
hardening pass:

- manifest-level compliance notice entries plus generated runtime notice reports
- package-side artifact provenance and diagnostics sidecars
- built-in manifest profiles for common GNUstep GUI app shapes
- backend-specific runtime and transform docs for AppImage
- a real AppImage backend that emits AppDir-based `.AppImage` artifacts
- automated AppImage extractability, strict runtime-closure validation, desktop-entry validation, and configurable smoke validation
- backend-aware reusable GitHub Actions workflows for Windows and Linux with caller-selected runners, preflight hooks, and additive prerequisite inputs
- fail-by-default MSI runtime-closure enforcement with explicit `warn` and ignore overrides for known optional DLL imports
- launch-environment assignment policies so packaged defaults such as `GSTheme` can use `ifUnset` instead of always overriding the user
- MSI and AppImage release-gate documentation

This repo also includes the full phase 10 updater path:

- a documented update architecture and trust model
- manifest-level update feed and GitHub release settings
- packaging-time updater runtime config emission inside MSI and AppImage payloads
- package-side update-feed sidecars for downstream release publishing
- AppImage embedded update information and `.zsync` sidecar integration support
- a Foundation-only Objective-C updater core under `updater/`
- an optional AppKit updater UI layer
- a separate update helper executable contract and implementation
- consumer docs and downstream release-publishing examples
- dedicated updater contract and packaging regression coverage

This repo also includes the phase 11 host dependency model plus phase 12A
through phase 12D hardening:

- manifest-driven host dependency verification and installation for Windows
  MSYS2 and Linux apt providers
- a shared internal provider abstraction used by local preflight and reusable
  workflow setup planning
- clearer reusable-workflow behavior for self-hosted `skip-default-host-setup`
  runs, including explicit verify-only policy diagnostics
- reusable host dependency profiles such as `gnustep-cmark` for downstream
  manifest layering

This repo now also includes the phase 12E through phase 12H packaging-contract
and validation pass:

- documented support boundaries for host provisioning and packaging contracts
- manifest-level semantic package contracts and installed-result assertions
- declarative packaged defaults such as a default theme carried through
  generated launchers
- backend validation hooks that check packaged or extracted results for drift

This repo now also includes the phase 13 `gnustep-cli-new` integration:

- `gnustep-cli-new` is the default GNUstep bootstrap path for supported
  Windows/MSI and Linux/AppImage CI packaging flows
- the reusable workflow exposes `gnustep-cli-manifest-url`,
  `gnustep-cli-bootstrap-url`, and `gnustep-cli-root` for reproducible upstream
  manifest selection and validation
- hosted MSI and AppImage CI paths run a clean `gnustep-cli-new` bootstrap
  smoke before the shared packaging pipeline
- upstream bootstrap and artifact blockers are tracked as first-class packager
  blockers through generated diagnostic reports instead of being hidden by
  legacy setup fallback

Current sample verification covers:
- `build`
- `stage`
- `package -Backend msi`
- `validate -Backend msi -RunSmoke`
- `package -Backend appimage`
- `validate -Backend appimage -RunSmoke`
- `scripts/test-repo.ps1`

## Proposed Structure
- `AGENTS.md`
- `README.md`
- `Roadmap.md`
- `schemas/`
- `scripts/`
- `updater/`
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

## Backend Direction
MSI was the first concrete deliverable, but the repo now supports both MSI and
AppImage from the same staged payload model:
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
./scripts/gnustep-packager.ps1 -Command package -Backend appimage
./scripts/gnustep-packager.ps1 -Command validate -Backend appimage -RunSmoke
```

Backend design notes:
- [docs/msi-boundary.md](docs/msi-boundary.md)
- [docs/msi-runtime-policy.md](docs/msi-runtime-policy.md)
- [docs/msi-launcher-design.md](docs/msi-launcher-design.md)
- [docs/msi-wix-rendering.md](docs/msi-wix-rendering.md)
- [docs/appimage-requirements.md](docs/appimage-requirements.md)
- [docs/appimage-metadata-mapping.md](docs/appimage-metadata-mapping.md)
- [docs/appimage-appdir-design.md](docs/appimage-appdir-design.md)
- [docs/appimage-runtime-policy.md](docs/appimage-runtime-policy.md)

Release and consumer docs:
- [docs/local-ci-parity.md](docs/local-ci-parity.md)
- [docs/github-actions.md](docs/github-actions.md)
- [docs/versioning-release.md](docs/versioning-release.md)
- [docs/release-gate.md](docs/release-gate.md)
- [docs/signing.md](docs/signing.md)
- [docs/consumer-setup.md](docs/consumer-setup.md)
- [docs/compatibility-matrix.md](docs/compatibility-matrix.md)
- [docs/compliance-notices.md](docs/compliance-notices.md)
- [docs/objcmarkdown-upstream-requests.md](docs/objcmarkdown-upstream-requests.md)
- [docs/gnustep-cli-new-integration.md](docs/gnustep-cli-new-integration.md)
- [docs/gnustep-cli-new-upstream-requests.md](docs/gnustep-cli-new-upstream-requests.md)
- [docs/update-architecture.md](docs/update-architecture.md)
- [docs/update-feed-contract.md](docs/update-feed-contract.md)
- [docs/updater-consumer-guide.md](docs/updater-consumer-guide.md)
- [docs/updater-release-publishing.md](docs/updater-release-publishing.md)
- [docs/updater-helper-contract.md](docs/updater-helper-contract.md)
- [docs/windows-msi-triage.md](docs/windows-msi-triage.md)
- [backends/appimage/README.md](backends/appimage/README.md)
- [docs/appimage-extension-path.md](docs/appimage-extension-path.md)

See [Roadmap.md](Roadmap.md) for the implementation phases.
