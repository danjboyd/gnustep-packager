# Roadmap

## Objective
Build `gnustep-packager` into a reusable packaging toolkit for GNUstep desktop
applications with:

- a backend-neutral core package model
- a production-ready Windows MSI backend
- a clear extension path to Linux AppImage
- reusable CI entry points and validation flows

## Planning Rules
- Main phases use numbers: `Phase 1`, `Phase 2`, and so on.
- Subphases use letters: `Phase 1A`, `Phase 1B`, `Phase 1C`, and so on.
- A phase is complete only when its deliverables are documented and testable.

## Phase 1: Foundation
Goal: establish the repo shape, terminology, and backend-neutral architecture.
Status: implemented in the current repo foundation.

- `Phase 1A`: Repo scaffolding and baseline docs
  Deliverables:
  - `AGENTS.md`, `README.md`, and `Roadmap.md`
  - initial repo layout decisions
  - common terminology for build, stage, package, and validate
  Exit criteria:
  - repo purpose and boundaries are documented
  - future contributors can tell what belongs in core versus a backend

- `Phase 1B`: Core package model
  Deliverables:
  - initial package domain model
  - list of backend-neutral concepts such as app identity, runtime payload,
    launch contract, integrations, and validation steps
  Exit criteria:
  - shared logic can be described without referring to WiX, MSI registry keys,
    AppDir paths, or AppImage-only concepts

- `Phase 1C`: Manifest schema design
  Deliverables:
  - first manifest schema
  - configuration layering rules for defaults, backend overrides, and app
    overrides
  Exit criteria:
  - an app can declare metadata, payload inputs, launch requirements, and
    backend options without editing code

- `Phase 1D`: Staged payload contract
  Deliverables:
  - documented staging layout
  - rules for artifact naming and output directories
  - distinction between source inputs and generated packaging outputs
  Exit criteria:
  - every backend can consume the same staged payload contract

## Phase 2: Shared Tooling
Goal: implement common orchestration and validation primitives before the first
backend is finalized.
Status: implemented in the current repo foundation.

- `Phase 2A`: Shared CLI entry points
  Deliverables:
  - common top-level scripts for `build`, `stage`, `package`, and `validate`
  - consistent argument naming and logging
  Exit criteria:
  - shared commands can dispatch to backend-specific handlers cleanly

- `Phase 2B`: Path and environment abstraction
  Deliverables:
  - repo-relative path handling
  - backend-aware path resolution
  - host environment bootstrap helpers
  Exit criteria:
  - shared logic does not depend on Windows-only or Linux-only path semantics

- `Phase 2C`: Launch contract abstraction
  Deliverables:
  - shared representation of runtime search paths, resource roots, and startup
    environment variables
  Exit criteria:
  - Windows bootstrap EXE and future Linux `AppRun` can both be generated from
    the same logical launch contract

- `Phase 2D`: Common validation model
  Deliverables:
  - smoke-test contract
  - log collection conventions
  - artifact naming conventions for validation outputs
  Exit criteria:
  - backends can plug into the same validation shape even if mechanics differ

## Phase 3: Windows MSI Backend Architecture
Goal: extract a reusable MSI backend design from the current app-specific
approach without locking the repo into MSI assumptions.
Status: implemented in the current repo baseline.

- `Phase 3A`: MSI backend boundary
  Deliverables:
  - list of MSI-specific inputs and outputs
  - separation of shared model from backend rendering
  Exit criteria:
  - MSI-specific concepts live under backend scope only

- `Phase 3B`: Windows runtime policy
  Deliverables:
  - documented policy for staged runtime contents
  - strategy for app-private binaries versus toolchain runtime binaries
  - inclusion and exclusion rules for staged resources
  Exit criteria:
  - runtime staging is predictable and not dependent on one app's hard-coded
    names

- `Phase 3C`: Windows launcher design
  Deliverables:
  - generic Windows GUI launcher template
  - manifest-driven launcher generation inputs
  Exit criteria:
  - launcher behavior can be configured without source edits per app

- `Phase 3D`: WiX rendering plan
  Deliverables:
  - small version-controlled product template
  - generated fragment strategy
  - upgrade/versioning policy for MSI artifacts
  Exit criteria:
  - no hand-maintained generated WiX harvest output is required

## Phase 4: Windows MSI Backend Implementation
Goal: deliver the first usable backend.
Status: implemented in the current repo baseline.

- `Phase 4A`: Shared-to-MSI transform
  Deliverables:
  - implementation that converts staged payload data into the MSI backend layout
  Exit criteria:
  - an app manifest can drive packaging without app-specific script forks

- `Phase 4B`: Launcher generation and runtime staging
  Deliverables:
  - generic Windows launcher output
  - runtime staging helpers
  - dependency closure implementation
  Exit criteria:
  - packaged apps run on clean Windows machines through the top-level launcher

- `Phase 4C`: WiX compilation and artifact emission
  Deliverables:
  - MSI build script
  - artifact naming policy
  - portable ZIP option from the same staged payload
  Exit criteria:
  - MSI and ZIP outputs are reproducible from one stage directory

- `Phase 4D`: MSI validation path
  Deliverables:
  - install, launch, and uninstall smoke path
  - log capture
  Exit criteria:
  - backend has an automated validation flow, not only a manual install story

## Phase 5: CI and Release Workflow
Goal: make the backend usable in app repos and CI systems.
Status: implemented for the current Windows MSI scope.

The reusable workflow and repo validation jobs currently target Windows runners.
Linux/AppImage CI extension is tracked under `Phase 8E`.

- `Phase 5A`: Local and CI parity
  Deliverables:
  - documented local entry points
  - matching CI entry points
  Exit criteria:
  - CI is not the only supported way to package or validate

- `Phase 5B`: Reusable GitHub Actions workflow
  Deliverables:
  - workflow interface for downstream repos
  - clear inputs for backend, manifest path, version, artifact names, and
    validation settings
  Exit criteria:
  - a downstream repo can call the workflow without copying packaging logic

- `Phase 5C`: Versioning and release policy
  Deliverables:
  - artifact naming conventions
  - semantic version to backend version mapping rules
  - release tagging expectations
  Exit criteria:
  - version behavior is deterministic across local and CI builds

- `Phase 5D`: Signing and secret-handling plan
  Deliverables:
  - optional signing hooks
  - CI secret usage guidance
  Exit criteria:
  - backend can support release-quality signing later without redesign

## Phase 6: Reference Consumer and Test Coverage
Goal: keep the repo grounded in a real consumer shape and prevent regression.
Status: implemented for the current Windows MSI scope.

`Phase 6A` through `Phase 6D` are complete for the Windows sample fixture and
Windows-oriented regression coverage. `Phase 6E` and `Phase 6F` extend this
phase so Linux/AppImage work can proceed on Linux hosts without regressing the
shared model.

- `Phase 6A`: Reference fixture app
  Deliverables:
  - one small GNUstep reference application or reference manifest fixture
  Exit criteria:
  - backend behavior can be tested against a stable input

- `Phase 6B`: Backend regression tests
  Deliverables:
  - tests for manifest handling
  - tests for transform logic
  - tests for artifact naming and expected outputs
  Exit criteria:
  - backend regressions can be caught before clean-machine validation

- `Phase 6C`: Docs and examples
  Deliverables:
  - minimal consumer setup docs
  - example manifests
  - example CI configuration
  Exit criteria:
  - downstream users have enough material to try the toolkit without source
    spelunking

- `Phase 6D`: Compatibility matrix
  Deliverables:
  - explicit support table for toolchain versions, host OS, and backend status
  Exit criteria:
  - support boundaries are documented and discoverable

- `Phase 6E`: Linux host readiness for shared tooling
  Deliverables:
  - strict manifest validation that enforces the documented schema contract
  - backend dry-run behavior that does not assume a Windows host
  - explicit host guards and clearer backend-not-available failures
  - an AppImage backend validation stub for dry-run and early CLI integration
  Exit criteria:
  - shared CLI commands and backend dry-runs are predictable on Linux hosts
  - Windows-only backend behavior fails clearly instead of leaking through
    shared code paths

- `Phase 6F`: Linux reference fixture and regression path
  Deliverables:
  - a Linux reference fixture app or manifest fixture
  - repo tests that can exercise shared logic and Linux/AppImage backend paths
    on Linux hosts
  - documented local prerequisites for Linux repo validation
  Exit criteria:
  - a Linux host can run a stable reference build, stage, package, and validate
    path for AppImage work
  - Linux regressions are caught before distro-portability testing starts

## Phase 7: Linux AppImage Preparation
Goal: prepare the architecture so AppImage is an extension, not a rewrite.
Status: AppImage extension path is documented, but `Phase 7A` through
`Phase 7D` remain.

- `Phase 7A`: Linux backend requirements study
  Deliverables:
  - list of Linux-specific packaging requirements for the targeted GNUstep setup
  - decision on supported Linux build environment for portability
  - decision on AppImage build tooling, including `appimagetool` bootstrap and
    the role of optional helpers such as `linuxdeploy`
  Exit criteria:
  - Linux backend assumptions are documented before implementation starts

- `Phase 7B`: AppImage metadata mapping
  Deliverables:
  - mapping from shared package metadata to desktop file, icon, MIME, and other
    AppImage-relevant outputs
  - mapping for root AppDir entries such as `.desktop`, icon symlink, and
    `.DirIcon`
  Exit criteria:
  - no AppImage metadata requirement is left to ad hoc per-app scripting

- `Phase 7C`: AppDir transform design
  Deliverables:
  - transform rules from staged payload to AppDir layout
  - `AppRun` generation plan
  - placement rules for staged `app/`, `runtime/`, and `metadata/` content
    under the AppDir
  Exit criteria:
  - AppImage backend shape is concrete and compatible with the shared model

- `Phase 7D`: Linux runtime policy
  Deliverables:
  - strategy for bundled GNUstep runtime, resource roots, launch environment,
    and ELF dependency closure
  Exit criteria:
  - Linux bundling rules are explicit rather than copied from Windows

## Phase 8: Linux AppImage Backend Implementation
Goal: ship the second backend using the same shared model.
Status: not started.

- `Phase 8A`: Shared-to-AppDir transform
  Deliverables:
  - backend implementation that emits AppDir from the staged payload without
    mutating the original stage tree
  Exit criteria:
  - AppDir generation works from the shared manifest and stage contract

- `Phase 8B`: `AppRun` and launch environment
  Deliverables:
  - generated `AppRun`
  - launch environment setup for the packaged GNUstep app
  - runtime token expansion rendered from the shared launch contract
  Exit criteria:
  - packaged AppImage launches through generated startup logic, not hand-written
    per-app scripts

- `Phase 8C`: AppImage artifact generation
  Deliverables:
  - AppImage build path
  - artifact naming and output handling
  - AppImage-side artifact metadata and diagnostics sidecars
  Exit criteria:
  - AppImage can be emitted from the same shared pipeline stages as MSI

- `Phase 8D`: Linux validation path
  Deliverables:
  - automated AppImage smoke validation
  - structural validation such as desktop-entry checks and extractability
  - log capture and failure diagnostics
  Exit criteria:
  - AppImage backend has an automated validation flow equivalent in spirit to
    the MSI backend

- `Phase 8E`: Linux CI integration
  Deliverables:
  - backend-aware runner selection in the reusable workflow
  - Linux AppImage packaging and validation jobs in repo CI
  - artifact upload and log handling for Linux backend runs
  Exit criteria:
  - AppImage can run from a documented CI entry point as well as a local one

- `Phase 8F`: Linux consumer docs and examples
  Deliverables:
  - AppImage backend usage docs and backend README updates
  - compatibility matrix and consumer setup updates for Linux/AppImage
  - example downstream manifest and CI usage for the Linux backend
  Exit criteria:
  - downstream users can adopt the AppImage backend without source spelunking

## Phase 9: Hardening and Release Readiness
Goal: make the repo suitable for sustained reuse.
Status: implemented for the current Windows MSI scope, with the AppImage
extension path documented for later phases.

- `Phase 9A`: Licensing and notices
  Deliverables:
  - third-party notice strategy
  - runtime license documentation
  Exit criteria:
  - packaged runtime contents are traceable and documented

- `Phase 9B`: Artifact provenance and diagnostics
  Deliverables:
  - improved logs
  - artifact metadata outputs
  - failure triage guidance
  Exit criteria:
  - downstream users can diagnose packaging failures without digging through
    backend internals

- `Phase 9C`: Consumer polish
  Deliverables:
  - stronger examples
  - defaults for common GNUstep app shapes
  - clearer onboarding docs
  Exit criteria:
  - basic downstream adoption does not require custom engineering up front

- `Phase 9D`: Version 1 release gate
  Deliverables:
  - stable Windows MSI backend
  - documented AppImage extension path, or working AppImage backend if Phase 8
    is complete
  Exit criteria:
  - repo can be tagged and presented as a reusable toolkit rather than an
    internal experiment

## Suggested Early Execution Order
Prioritize these subphases first:

1. `Phase 1B`
2. `Phase 1C`
3. `Phase 1D`
4. `Phase 2A`
5. `Phase 3A`
6. `Phase 3B`
7. `Phase 4A`
8. `Phase 4B`

That order gets the core model, stage contract, and first backend boundary
right before more detailed backend-specific automation accumulates.
