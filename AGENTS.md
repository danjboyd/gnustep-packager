# AGENTS.md

## Project
`gnustep-packager` is a packaging toolkit for GNUstep applications.

The initial target is Windows packaging for applications built with the MSYS2
`CLANG64` GNUstep toolchain. The long-term goal is a backend-neutral system
that can package the same staged application payload into multiple output
formats, starting with:

- Windows MSI
- Linux AppImage

## Core Goals
- Keep the core package model backend-neutral.
- Use a stage-first pipeline: `build -> stage -> package -> validate`.
- Make the staged payload the single source of truth for all package formats.
- Keep local and CI execution paths aligned.
- Avoid checking generated packaging artifacts into source control.

## Scope
In scope:
- Packaging GNUstep apps that use the supported toolchain contracts
- Runtime staging and dependency closure
- Package backend generation
- Validation and release-oriented CI workflows
- Reusable templates, schemas, and example consumer setups

Out of scope for the MVP:
- Supporting arbitrary non-GNUstep desktop apps
- Supporting arbitrary Windows or Linux toolchains
- Adding package-manager-specific backends before the core model is stable

## Initial Support Boundary
- Windows backend: MSYS2 `CLANG64` + GNUstep + WiX
- Linux backend target: clang-based GNUstep builds packaged as AppImage

Any expansion beyond those boundaries should be treated as a deliberate roadmap
item, not an incidental convenience change.

## Architecture Rules
- The core model must not depend on MSI concepts such as registry keys,
  `Program Files`, WiX directory IDs, or installer-only metadata.
- Backend-specific logic belongs under backend-specific directories and entry
  points.
- Launch behavior must be expressed as a logical contract and rendered into
  backend-specific launchers such as a Windows bootstrap EXE or Linux `AppRun`.
- Runtime inclusion rules must be declarative. Do not hard-code app names,
  bundle names, DLL names, or install paths into shared core logic.
- Generated files such as harvested WiX fragments, AppDir trees, and temporary
  manifests belong under `dist/` or another build output directory, not under
  version-controlled source paths.

## Expected Structure
- `schemas/` package manifest schemas and related validation assets
- `scripts/` orchestration entry points and shared helpers
- `backends/msi/` Windows MSI backend
- `backends/appimage/` Linux AppImage backend
- `examples/` reference applications or reference manifests
- `docs/` design notes, backend docs, and CI guidance
- `.github/workflows/` reusable workflows and validation jobs

## Conventions
- Keep source files ASCII unless there is a clear reason not to.
- Prefer readable PowerShell for Windows orchestration and POSIX shell for
  backend-local Linux tasks.
- Favor explicit manifests over magic path discovery.
- Keep filenames and artifact names stable and predictable.
- Use consistent terminology:
  - `build`: compile the app
  - `stage`: produce a self-contained payload tree
  - `package`: emit backend-specific distributables
  - `validate`: smoke-test the result

## Process
- Update `README.md` whenever the public shape of the repo changes.
- Update `Roadmap.md` when priorities, backend order, or phase boundaries move.
- If a design choice makes MSI easier but AppImage harder, stop and document the
  tradeoff before proceeding.
- Before asking a user to validate a new backend manually, make sure the local
  package build and the relevant automated checks have been run successfully.
- Prefer a small working reference app fixture for backend tests over purely
  synthetic unit coverage.

## Quality Gates
Do not consider a backend ready until it can:
- Build from a documented local entry point
- Run from a documented CI entry point
- Package from a staged payload without hand edits
- Pass at least one clean-environment smoke validation path
- Produce predictable artifact names and logs

## Documentation Requirements
Every backend should eventually document:
- supported toolchain and host requirements
- build, stage, package, and validate commands
- artifact layout
- known limitations
- CI usage

