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
Status: implemented for the current Windows MSI and Linux AppImage scope.

The reusable workflow now supports backend-specific runner selection,
caller-provided host preflight hooks, and additive package inputs while still
driving packaging through the shared pipeline wrapper. Repo CI continues to
exercise both the Windows MSI and Linux AppImage reference paths.

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
Status: implemented for the current Windows MSI and Linux AppImage scope.

`Phase 6A` through `Phase 6F` are complete. The repo now carries both a
Windows MSI reference fixture and a Linux AppImage reference fixture, and
`scripts/test-repo.ps1` selects platform-appropriate regression coverage on
Windows and Linux hosts.

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
Status: implemented.

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
Status: implemented.

AppImage validation now supports launch-only, open-file, custom-arguments, and
marker-file smoke modes so real GUI apps do not have to adopt fixture-specific
marker behavior just to participate in backend validation.

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
Status: implemented for the current Windows MSI and Linux AppImage scope.

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
  - stable Linux AppImage backend
  Exit criteria:
  - repo can be tagged and presented as a reusable toolkit rather than an
    internal experiment

## Phase 10: Application Update Integration
Goal: add a simple, backend-aware update path that downstream GNUstep apps can
adopt without embedding packaging or installer logic into the app process.
Status: phase 10 implemented in the current repo baseline.

This phase introduces a companion updater integration path for apps that publish
signed MSI and AppImage artifacts to GitHub. The design should keep
`gnustep-packager` responsible for packaging-time metadata and release
conventions, while app-facing runtime behavior lives in a separate updater
library and helper.

- `Phase 10A`: Update architecture and trust model
  Deliverables:
  - documented split between packaging-time metadata generation, app-facing
    update API, and out-of-process update helper responsibilities
  - decision on the downstream integration surface, including an Objective-C
    API for GNUstep apps and a separate helper executable for applying updates
  - documented trust model for release discovery, signature verification,
    integrity checks, and channel handling
  Exit criteria:
  - the updater architecture is backend-neutral in shared concepts and does not
    collapse MSI and AppImage behavior into one platform-specific design
  - downstream apps can integrate update checks without owning installer
    semantics directly

- `Phase 10B`: Manifest and feed contract
  Deliverables:
  - manifest schema additions for update channels, release metadata, and
    backend-specific update configuration
  - a documented machine-readable feed contract for GitHub-hosted releases and
    channel selection
  - explicit rules for mapping the shared package version to update comparisons
    across MSI and AppImage outputs
  Exit criteria:
  - update discovery is driven by stable declarative inputs rather than release
    title parsing or backend-specific asset guessing
  - prerelease, stable, and future channel behavior is documented and testable

- `Phase 10C`: Packaging-time update metadata emission
  Deliverables:
  - shared pipeline support for generating and staging updater configuration
    consumed by downstream apps
  - AppImage backend support for standard embedded update information and
    `.zsync` sidecar publication inputs
  - MSI backend support for emitting release metadata suitable for full-package
    upgrade handoff while preserving existing signing and versioning rules
  Exit criteria:
  - a downstream release pipeline can publish updater-consumable metadata
    without custom per-app release scripting
  - package outputs contain or reference the metadata needed by the updater
    runtime for both supported backends

- `Phase 10D`: Objective-C updater core
  Deliverables:
  - a Foundation-level Objective-C library for update configuration, scheduled
    checks, version comparison, channel selection, and persisted user choices
  - a small downstream integration surface for startup checks and manual
    `Check for Updates` actions
  Exit criteria:
  - a GNUstep GUI app can adopt update discovery with minimal app-specific code
  - the core library stays free of backend packaging internals and GUI policy
    that belongs in higher layers

- `Phase 10E`: Optional standard update UI
  Deliverables:
  - an AppKit-oriented UI layer that can present update available, download
    progress, restart-to-update, and failure states
  - customization hooks so downstream apps can override strings, release-note
    presentation, and check timing without replacing the core update logic
  Exit criteria:
  - apps that want a default update UX can adopt one without writing their own
    dialogs from scratch
  - apps that want custom presentation can still use the same updater core

- `Phase 10F`: Update helper and backend application path
  Deliverables:
  - a separate helper executable that downloads, verifies, applies, and
    relaunches updates after the app exits
  - MSI handoff flow that uses signed installer upgrades rather than in-process
    binary replacement
  - AppImage flow that prefers standard tools such as `AppImageUpdate` when
    available and falls back cleanly when optional managers are absent
  Exit criteria:
  - update application does not require the running app to replace its own
    executable or own backend-specific install mechanics
  - Linux behavior plays well with AppImageLauncher, AppImageUpdate, and Gear
    without depending on them

- `Phase 10G`: Consumer documentation and examples
  Deliverables:
  - app-facing documentation for integrating the updater library and helper into
    a GNUstep app
  - release-publishing documentation for downstream repos that publish MSI and
    AppImage artifacts to GitHub
  - example manifests, staged config outputs, and minimal app code snippets for
    startup checks and manual update actions
  Exit criteria:
  - a downstream app can adopt the updater path without source spelunking or
    reverse-engineering repo tests
  - documentation covers local development, CI release publishing, runtime UX,
    and known platform-specific limitations

- `Phase 10H`: Validation and regression coverage
  Deliverables:
  - tests for manifest validation, feed rendering, version comparison, and
    helper decision logic
  - repo or fixture coverage that exercises both MSI and AppImage update
    metadata outputs
  - failure-path coverage for unsupported install locations, missing optional
    Linux update tools, and signature or integrity failures
  Exit criteria:
  - updater behavior is testable without requiring live GitHub release edits
  - release metadata regressions and unsafe update-handling changes are caught
    before downstream users discover them manually

## Phase 11: Manifest-Driven Host Dependency Provisioning
Goal: let downstream manifests declare app-specific host/build dependencies
once, then have `gnustep-packager` realize or validate them consistently across
local runs, reusable workflows, and remote packaging hosts.
Status: implemented.

This phase keeps host dependency declaration in the packaging manifest while
preserving the existing stage-first boundary. These dependencies are for host
tooling and build prerequisites such as MSYS2 or apt packages, not for staged
runtime payload contents.

- `Phase 11A`: Manifest schema and resolution model
  Deliverables:
  - manifest schema additions for host dependency declaration
  - defaults and profile-layering rules for shared dependency sets
  - a resolved internal model that stays backend-neutral in shared code while
    still supporting host-specific package managers
  Exit criteria:
  - a downstream manifest can declare additional Windows and Linux host
    dependencies without relying on workflow-only inputs
  - resolved manifest output is deterministic and testable

- `Phase 11B`: Shared preflight and failure model
  Deliverables:
  - a shared preflight path that validates or installs declared host
    dependencies before build or package steps begin
  - explicit policy for install-versus-verify behavior on local and CI hosts
  - precise early failure messages for unresolved or disallowed dependencies
  Exit criteria:
  - missing host dependencies fail before compiler or backend-specific build
    work starts
  - runtime staging and host dependency provisioning remain separate concerns

- `Phase 11C`: Windows MSI host realization
  Deliverables:
  - Windows/MSYS2 realization for declared `msys2Packages`
  - support for both installation and verification-only modes on supported
    Windows packaging hosts
  - backend-aware diagnostics when declared packages cannot be installed or
    found
  Exit criteria:
  - a downstream Windows MSI packaging run can satisfy manifest-declared MSYS2
    package requirements without duplicating that list in repo-local wrapper
    scripts
  - failures point at the declared package requirement rather than surfacing
    later as missing headers or tools

- `Phase 11D`: Linux AppImage host realization
  Deliverables:
  - Linux host realization for declared apt-side dependencies used by AppImage
    packaging flows
  - support for both installation and verification-only modes on supported
    Linux hosts
  - backend-aware diagnostics for missing Linux host packages
  Exit criteria:
  - Linux packaging can use the same manifest-driven host dependency model as
    Windows
  - Linux-side host dependency behavior is documented and testable separately
    from bundled runtime policy

- `Phase 11E`: Reusable workflow and local parity
  Deliverables:
  - reusable workflow logic that reads manifest-declared host dependencies and
    realizes them automatically
  - local wrapper and repo entry-point updates so the same dependency
    declarations drive local packaging
  - a compatibility path for existing workflow inputs such as
    `msys2-packages` and `appimage-apt-packages`
  Exit criteria:
  - local and CI packaging use the same declared host dependency set by
    default
  - downstream workflow YAML no longer has to duplicate app-specific package
    lists just to match local runs

- `Phase 11F`: Remote and leased host parity
  Deliverables:
  - remote Windows host and leased-VM helpers that consume the same resolved
    host dependency model
  - plan execution updates so remote packaging environments can provision or
    verify declared dependencies before build begins
  Exit criteria:
  - remote packaging helpers do not need app-specific package lists copied into
    separate scripts
  - preflight behavior is consistent across local, CI, and remote-host paths

- `Phase 11G`: Consumer docs, examples, and regression coverage
  Deliverables:
  - consumer-facing documentation for declaring host/build dependencies in the
    manifest
  - updated examples showing a downstream app such as one using `cmark`
  - regression coverage for manifest resolution, preflight failure behavior,
    and workflow integration
  Exit criteria:
  - downstream users can adopt manifest-driven host dependency provisioning
    without source spelunking
  - repo tests catch drift between manifest declaration, workflow realization,
    and remote-host handling

## Phase 12: Packaging Contracts and Validation Maturity
Goal: harden the new host dependency model and extend manifest-driven packaging
contracts so staged content, packaged defaults, and installed or extracted
results stay maintainable, extensible, and verifiable under broader consumer
and CI scenarios.
Status: implemented.

Current handoff:
- last completed checkpoint: `Phase 12A` through `Phase 12J` implemented on
  `main`
- recommended next starting point: begin `Phase 13` by making
  `gnustep-cli-new` the standard GNUstep toolchain bootstrap path for local and
  CI packaging work
- first review target tomorrow:
  audit whether the current semantic contract set should stay intentionally
  narrow or grow only in response to repeated downstream runtime-layout needs
- guardrail for next work:
  keep the semantic contract set small and explicit unless a repeated consumer
  need justifies broadening it; prefer high-signal assertions over a large enum
  of barely-supported packaged asset kinds

Current status notes:
- `Phase 12A` landed as a shared internal provider abstraction for Windows
  MSYS2 and Linux apt host dependency verification and installation
- `Phase 12B` landed as clearer reusable-workflow host setup policy for hosted
  and self-hosted runs, including explicit verify-only behavior when
  `skip-default-host-setup: true`
- `Phase 12C` landed as stronger regression coverage around workflow host setup
  planning and provider-backed preflight behavior
- `Phase 12D` landed as reusable host dependency profile layering, starting
  with the built-in `gnustep-cmark` profile
- `Phase 12E` landed as updated consumer guidance, compatibility notes, and
  explicit support-boundary documentation for provisioning and contract usage
- `Phase 12F` landed as manifest-level semantic package contracts plus
  low-level packaged-path escape hatches
- `Phase 12G` landed as installed or extracted result assertions wired into MSI
  and AppImage backend validation
- `Phase 12H` landed as declarative packaged defaults, currently including
  `packagedDefaults.defaultTheme`, with contract-backed drift detection across
  stage, package, and installed or extracted results
- `Phase 12I` landed as a narrow semantic follow-on: `bundled-theme` now
  covers the common GNUstep `runtime/System/Library/Themes/<Theme>.theme`
  layout in addition to the existing `runtime/lib/GNUstep/Themes` and
  `runtime/share/GNUstep/Themes` checks
- `Phase 12J` landed as multi-layout regression coverage so semantic theme
  assertions no longer validate only one fixture-preferred runtime tree

This phase is follow-on work after the manifest-driven host dependency model is
in place. It focuses on stronger provider abstraction, better coverage of
self-hosted and manifest-only provisioning paths, richer packaged-content and
installed-result contracts, and improved end-to-end confidence.

- `Phase 12A`: Provider abstraction and package-manager extensibility
  Deliverables:
  - a clearer internal provider abstraction for host dependency verification and
    installation
  - reduced duplication between MSYS2 and apt provider implementations
  - extension points for future package-manager providers without reshaping the
    manifest contract again
  Exit criteria:
  - adding a new host package manager does not require rewriting the shared
    preflight model
  - current Windows and Linux providers share common execution and diagnostics
    patterns

- `Phase 12B`: Self-hosted and manifest-only workflow behavior
  Deliverables:
  - stronger workflow behavior when `skip-default-host-setup: true`
  - explicit policy and diagnostics for manifest-driven verification on
    pre-provisioned runners
  - reduced reliance on workflow-only additive package inputs in common
    downstream cases
  Exit criteria:
  - self-hosted runners can rely on manifest-declared host dependencies without
    ambiguous behavior
  - workflow logs make it clear whether dependencies were installed, verified,
    or intentionally left to the caller

- `Phase 12C`: End-to-end workflow and host provisioning integration tests
  Deliverables:
  - stronger regression coverage that exercises host dependency synthesis
    through realistic pipeline entry points
  - repo or fixture tests that cover workflow-driven package list resolution
    and preflight/install behavior more deeply than surface-string assertions
  - integration coverage for failure-path diagnostics when declared host
    dependencies are absent or unavailable
  Exit criteria:
  - regressions in manifest-to-workflow host dependency wiring are caught by
    behavior-focused tests, not only surface checks
  - host dependency failure messages stay stable and reviewable

- `Phase 12D`: Shared dependency sets and profile reuse
  Deliverables:
  - a deliberate way to share common host dependency sets across manifests,
    profiles, or reference consumer templates
  - guidance on when to use per-app declarations versus reusable dependency
    overlays
  Exit criteria:
  - downstream repos with multiple manifests can avoid copy-pasting identical
    host dependency declarations
  - reuse does not obscure which app-specific host prerequisites are actually
    required

- `Phase 12E`: Consumer guidance and support-boundary refinement
  Deliverables:
  - clearer guidance on supported host package-manager baselines, privilege
    expectations, and fallback behavior
  - refined compatibility-matrix and troubleshooting docs for host dependency
    provisioning
  - explicit non-goals around automatic dependency inference and unsupported
    host environments
  Exit criteria:
  - consumers can tell which host dependency scenarios are fully supported
    versus compatibility best-effort
  - support boundaries stay explicit as more provisioning paths are added

- `Phase 12F`: Packaged content contracts and semantic package assertions
  Deliverables:
  - manifest-level package contract sections for declaring required packaged
    content at a higher level than raw path lists
  - shared normalization rules that can map semantic declarations such as
    themes, updater helpers, updater UI/runtime libraries, metadata files, and
    other packaged support assets into concrete backend checks
  - compatibility rules that preserve existing low-level path-based escape
    hatches for unusual consumer cases
  Exit criteria:
  - downstream manifests can express common packaging intent without encoding
    packager internals directly in repo-local scripts
  - shared and backend validation can explain which declared packaged contract
    was expected and which concrete artifacts satisfy it

- `Phase 12G`: Installed-result assertions and backend validation hooks
  Deliverables:
  - backend-aware installed or extracted package assertion hooks for MSI and
    AppImage validation paths
  - manifest support for installed-result expectations such as required files,
    expected launcher/runtime outputs, and declared package defaults surviving
    packaging transforms
  - higher-signal diagnostics that identify the phase where declared content
    disappeared: stage, package transform, install, or extracted result
  Exit criteria:
  - a package that looks correct in stage but regresses during backend
    transform or install fails with a precise installed-result assertion
  - backend parity exists in principle for MSI install checks and AppImage
    extractability/assertion checks

- `Phase 12H`: Declarative packaged defaults and contract-backed drift detection
  Deliverables:
  - manifest support for semantic packaged defaults such as a default Windows
    theme, updater helper enablement, and other generated launch/runtime
    defaults that the packager is expected to carry through
  - validation helpers that confirm declared defaults are represented in the
    generated package and installed result
  - downstream fixture coverage for drift scenarios such as a declared theme or
    helper being present in one phase and missing in another
  Exit criteria:
  - consumers can declare packaging defaults once and rely on the packager to
    both realize and validate them
  - regressions such as omitted themes, dropped helpers, or lost packaged
    defaults are caught by repo-owned validation instead of downstream ad hoc
    checks

- `Phase 12I`: Bundled-theme root broadening for common GNUstep runtime trees
  Deliverables:
  - broaden `bundled-theme` candidate resolution to include common GNUstep
    runtime theme roots, at minimum
    `runtime/System/Library/Themes/<Theme>.theme`,
    `runtime/lib/GNUstep/Themes/<Theme>.theme`, and
    `runtime/share/GNUstep/Themes/<Theme>.theme`
  - preserve the current phase-aware semantic diagnostics, including the
    manifest assertion source and the concrete candidate paths checked
  - keep `requiredPaths` available as the low-level escape hatch for unusual
    consumer layouts
  Exit criteria:
  - downstream consumers staging private themes under
    `runtime/System/Library/Themes` can use `bundled-theme` without falling
    back to raw backend-specific path assertions
  - shared, packaged-result, and installed or extracted result checks all pass
    when any supported GNUstep theme root contains the declared theme

- `Phase 12J`: Multi-layout bundled-theme regression coverage
  Deliverables:
  - shared validation tests that prove `bundled-theme` succeeds across at least
    one GNUstep runtime tree layout under `runtime/System/Library/Themes` and
    one existing `runtime/lib/GNUstep/Themes` layout
  - backend regression coverage that confirms MSI and AppImage package or
    installed-result checks still pass with the broadened candidate set
  - fixture or manifest updates that avoid coupling semantic theme assertions
    to a single preferred staged runtime tree
  Exit criteria:
  - repo tests catch regressions where `bundled-theme` works only for one
    fixture-specific layout
  - downstream consumers can rely on semantic theme presence checks across
    common GNUstep runtime trees without reintroducing literal theme-bundle
    path assertions

## Phase 13: GNUstep CLI New Toolchain Integration
Goal: make `gnustep-cli-new` the default and required GNUstep toolchain
bootstrap path across supported local and CI packaging flows, treating
`gnustep-cli-new` failures as blockers to diagnose and report upstream rather
than falling back to legacy repo-local setup code.
Status: implemented.

This phase recognizes `gnustep-cli-new` as a sister project and a core part of
the packaging strategy. The packager should exercise it early, use it as the
normal source of GNUstep build environments, and produce concise upstream bug
reports whenever it prevents a supported packaging path from working.

Current status notes:
- `Phase 13A` landed as a documented policy update: `gnustep-cli-new` is now
  the default GNUstep bootstrap path for supported Linux/AppImage CI packaging
  flows, and supported bootstrap failures are tracked as blockers instead of
  being bypassed by legacy setup fallback.
- `Phase 13B` landed as workflow-level version and manifest selection inputs:
  `gnustep-cli-manifest-url`, `gnustep-cli-bootstrap-url`, and
  `gnustep-cli-root`.
- `Phase 13C` landed as `scripts/ci/gnustep-cli-new-bootstrap-smoke.sh`, which
  runs setup, `gnustep --version`, `gnustep doctor --json`, `gnustep new`,
  `gnustep build`, and `gnustep run`, while preserving logs for upstream
  reports.
- `Phase 13D` landed for the Linux/AppImage CI path: the reusable AppImage
  workflow and repo validation now run the `gnustep-cli-new` bootstrap smoke
  before invoking the shared packaging pipeline and expose the selected
  toolchain root on `PATH`.
- `Phase 13E` landed for the Windows/MSI CI path: the reusable MSI workflow and
  repo validation now run the `gnustep-cli-new` bootstrap smoke from an MSYS2
  `CLANG64` bootstrap shell before invoking the shared packaging pipeline.
- `Phase 13F` landed as a generated `gnustep-cli-new-blocker-report.md` plus a
  dedicated workflow diagnostic artifact for bootstrap logs, doctor output,
  selected manifest data, and failed command output.
- `Phase 13G` landed as updated consumer setup guidance and downstream workflow
  examples that show the standard `gnustep-cli-new` manifest selection.
- `Phase 13H` landed as release-gate documentation and workflow regression
  coverage that require the `gnustep-cli-new` smoke and known-good manifest
  baseline before release packaging.
- next recommended starting point: define the next roadmap phase around
  hardening Windows `gnustep-cli-new` evidence from hosted runner results and
  any upstream fixes found by the new MSI bootstrap path.

- `Phase 13A`: Policy and support-boundary update
  Deliverables:
  - roadmap, README, and CI guidance updates that name `gnustep-cli-new` as the
    default GNUstep bootstrap mechanism for supported packaging workflows
  - explicit removal of legacy fallback expectations from the documented
    support path
  - a blocker policy that distinguishes packager bugs from actionable
    `gnustep-cli-new` upstream issues
  Exit criteria:
  - contributors can tell that `gnustep-cli-new` is the standard path before
    reading workflow internals
  - failures in `gnustep-cli-new` setup are tracked as blockers with enough
    context for upstream maintainers to act on them

- `Phase 13B`: Version and manifest selection contract
  Deliverables:
  - a documented way to select the `gnustep-cli-new` release, commit, or
    release manifest used by local tests and GitHub Actions
  - default inputs for reusable workflows that point at the supported
    `gnustep-cli-new` manifest while still allowing deliberate override for
    upstream validation
  - logging that records the selected manifest URL, resolved artifact IDs, and
    `gnustep --version`
  Exit criteria:
  - CI runs are reproducible enough to identify which `gnustep-cli-new`
    artifact set was tested
  - testing a newly published `gnustep-cli-new` manifest does not require
    editing backend implementation code

- `Phase 13C`: Ubuntu runner bootstrap smoke test
  Deliverables:
  - a clean Ubuntu runner or container smoke test that runs
    `gnustep-bootstrap.sh --json --yes setup`
  - validation steps for `gnustep --version`, `gnustep doctor --json`,
    `gnustep new`, `gnustep build`, and `gnustep run`
  - captured logs and JSON output suitable for upstream issue reports when the
    smoke path fails
  Exit criteria:
  - the supported Ubuntu GitHub Actions runner can install and use
    `gnustep-cli-new` without hand-installed GNUstep prerequisites
  - failure output identifies the missing artifact, missing package,
    incompatible library, or command failure precisely enough to file upstream

- `Phase 13D`: Linux AppImage workflow integration
  Deliverables:
  - AppImage build and stage workflows updated to bootstrap GNUstep through
    `gnustep-cli-new`
  - fixture coverage proving a small GNUstep app can be built, staged, packaged
    as an AppImage, and smoke-validated from the same toolchain path
  - removal or quarantine of repo-local Linux GNUstep setup code from the
    supported default path
  Exit criteria:
  - the AppImage CI path uses `gnustep-cli-new` for GNUstep setup by default
  - AppImage validation failures clearly separate packager staging or packaging
    bugs from upstream toolchain/bootstrap blockers

- `Phase 13E`: Windows MSI workflow integration
  Deliverables:
  - Windows reusable workflows updated to use the `gnustep-cli-new` Windows or
    MSYS2 bootstrap path when producing MSI fixtures
  - logging of the resolved MSYS2/GNUstep environment, selected target, and
    package versions used for MSI builds
  - verification that existing MSI staging, WiX generation, install, and smoke
    validation still operate from the `gnustep-cli-new` provisioned toolchain
  Exit criteria:
  - the MSI CI path uses `gnustep-cli-new` for supported GNUstep setup by
    default
  - Windows failures produce enough detail to decide whether the fix belongs in
    `gnustep-packager`, `gnustep-cli-new`, MSYS2 packaging, or WiX integration

- `Phase 13F`: Blocker evidence and upstream bug-report workflow
  Deliverables:
  - a repo-owned bug-report template or generated diagnostic bundle for
    `gnustep-cli-new` blockers
  - CI artifact collection for bootstrap logs, selected manifest data,
    `gnustep doctor --json`, host OS details, and failed command output
  - documentation for when to stop packager work and file or update an
    upstream `gnustep-cli-new` issue
  Exit criteria:
  - failed `gnustep-cli-new` setup runs produce a ready-to-copy upstream report
    without manual log archaeology
  - the packager does not silently bypass `gnustep-cli-new` when the supported
    bootstrap path fails

- `Phase 13G`: Consumer docs and migration examples
  Deliverables:
  - consumer-facing documentation showing local and GitHub Actions setup with
    `gnustep-cli-new`
  - updated reference workflow snippets for projects that need both Windows MSI
    and Linux AppImage artifacts
  - migration notes for removing legacy GNUstep setup steps from downstream
    workflows
  Exit criteria:
  - a downstream GNUstep project can adopt the standard MSI plus AppImage
    workflow without inventing its own build boxes or bootstrap scripts
  - consumer docs make clear that `gnustep-cli-new` issues should be reported
    upstream with the generated evidence

- `Phase 13H`: Release gating and regression coverage
  Deliverables:
  - CI gates that require the `gnustep-cli-new` bootstrap smoke test before
    packaging release artifacts
  - regression coverage for manifest selection, workflow inputs, and
    blocker-report artifact generation
  - release-readiness notes that record the known-good `gnustep-cli-new`
    manifest or commit for each packager release
  Exit criteria:
  - packager releases cannot accidentally publish from an unvalidated legacy
    GNUstep setup path
  - release notes identify the `gnustep-cli-new` baseline that downstream
    projects should use or compare against

## Phase 14: Hosted Windows Toolchain Hardening
Goal: turn the `gnustep-cli-new` Windows/MSI bootstrap path from workflow
integration into a proven, diagnosable, release-ready hosted-runner path.
Status: complete. Phase 14A through phase 14H are implemented, with hosted
Windows release readiness blocked by the upstream `gnustep-cli-new` MSYS2
CLANG64 selector issue recorded below.

This phase focuses on hosted Windows evidence, path normalization across
PowerShell, MSYS2, and Windows command contexts, and upstream-quality blocker
reports. The MSI workflow should continue to package from the staged payload;
this phase hardens how that staged payload is built and diagnosed on the
standard hosted Windows runner path.

Current status notes:
- `Phase 14A` landed as hosted Windows evidence capture in the shared
  `gnustep-cli-new` smoke path, including host kind, runner metadata, selected
  manifest, setup logs, doctor output, and command logs suitable for CI
  artifacts.
- `Phase 14B` landed as Windows path-context logging for MSYS2 and Windows path
  forms, including `cygpath` output, PATH entries, command lookup, and
  `cmd.exe where gnustep` when available.
- `Phase 14C` landed as workflow enforcement that the MSI hosted path runs the
  `gnustep-cli-new` smoke before the packaging pipeline, keeping the sample MSI
  build, stage, package, install, smoke validation, and uninstall path tied to
  the provisioned toolchain.
- `Phase 14D` landed as richer blocker-report content for Windows-specific
  failures, including selected host kind, context logs, and exact command logs
  with preserved exit status.
- hosted validation run `24736846989` confirmed that the current public
  `gnustep-cli-new` bootstrap classifies the MSYS2 `CLANG64` shell as
  `os: unknown`, then fails to select the published
  `windows-amd64-msys2-clang64` artifacts. The generated
  `windows-gnustep-cli-new` artifact contains the blocker report and command
  logs.
- hosted validation run `24738535673` confirmed the completed phase 14 gate
  behavior: Linux validation passed through bootstrap, Pester, and the shared
  AppImage pipeline; Windows failed closed at `Bootstrap And Smoke Test
  gnustep-cli-new` with exit code 4 before manifest, Pester, or MSI packaging
  steps ran, and uploaded `windows-gnustep-cli-new` diagnostics.
- `Phase 14E` landed as a hosted-runner regression gate contract: the default
  Windows MSI path runs the `gnustep-cli-new` bootstrap smoke before packaging,
  fails closed when that smoke fails or is skipped, and preserves diagnostics
  for release triage.
- `Phase 14F` landed as the upstream feedback loop in
  `docs/gnustep-cli-new-upstream-requests.md`, including a minimal Windows
  MSYS2 CLANG64 reproduction and packager impact statement.
- `Phase 14G` landed as downstream migration guidance in the consumer and
  GitHub Actions docs, covering hosted and self-hosted Windows runners and
  manifest-owned app-specific MSYS2 packages.
- `Phase 14H` landed as the release readiness baseline in
  `docs/release-gate.md`, including the runner image, manifest URL, MSYS2
  bootstrap baseline, WiX baseline, MSI smoke expectation, and release-note
  guidance.
- next recommended starting point: retest the hosted Windows gate after the
  upstream bootstrap selector can detect MSYS2/Windows and install the
  published `windows-amd64-msys2-clang64` artifacts.

- `Phase 14A`: Hosted Windows bootstrap evidence pass
  Deliverables:
  - hosted Windows/MSYS2 evidence capture for the `gnustep-cli-new` setup smoke
  - logs for setup, `gnustep --version`, `gnustep doctor --json`,
    `gnustep new`, `gnustep build`, and `gnustep run`
  - clear separation between packager workflow failures and upstream
    `gnustep-cli-new` blockers
  Exit criteria:
  - Windows runs upload enough evidence to determine where a bootstrap failure
    belongs
  - hosted-runner evidence does not require manual log archaeology

- `Phase 14B`: Windows bootstrap path normalization
  Deliverables:
  - normalized treatment of `GP_GNUSTEP_CLI_ROOT`, `GITHUB_PATH`,
    `MSYS2_LOCATION`, and runner temp paths across PowerShell, MSYS2, and
    Windows command contexts
  - diagnostics for POSIX and Windows path forms
  - command lookup logs for `gnustep` and bootstrap tools
  Exit criteria:
  - spaces, Windows separators, and MSYS2 path conversion failures are visible
    in diagnostics
  - workflow changes do not hide which path form was used by each shell

- `Phase 14C`: MSI fixture build from provisioned toolchain
  Deliverables:
  - MSI workflow ordering that runs `gnustep-cli-new` before build and stage
  - regression coverage that prevents direct hosted-runner GNUstep package
    installation from re-entering the default MSI path
  - validation that the existing MSI pipeline still runs through build, stage,
    package, install, smoke, and uninstall from the provisioned environment
  Exit criteria:
  - hosted MSI packaging depends on the `gnustep-cli-new` provisioned
    toolchain path, not legacy direct GNUstep setup
  - workflow-surface tests catch regressions in that ordering

- `Phase 14D`: Windows failure classification and upstream report quality
  Deliverables:
  - Windows-specific blocker-report fields such as host kind, MSYS2 location,
    path conversion output, command lookup, and failed command logs
  - artifact layout that keeps `gnustep-cli-new` evidence separate from generic
    package logs
  - upstream-request documentation guidance for filing or updating Windows
    blockers
  Exit criteria:
  - a failed Windows bootstrap smoke produces a ready-to-copy upstream report
  - the report is precise enough to decide whether the fix belongs in
    `gnustep-packager`, `gnustep-cli-new`, MSYS2 packaging, or WiX integration

- `Phase 14E`: Windows hosted-runner regression gate
  Deliverables:
  - hosted Windows CI status checks that make the `gnustep-cli-new` smoke a
    required release-packaging gate
  - uploaded diagnostics retained for failed hosted Windows runs
  - documentation for interpreting the hosted-runner result
  Exit criteria:
  - release packaging cannot proceed from a Windows hosted runner that skipped
    or failed the supported bootstrap smoke

- `Phase 14F`: Upstream feedback loop
  Deliverables:
  - confirmed Windows blockers recorded in
    `docs/gnustep-cli-new-upstream-requests.md`
  - minimal reproductions extracted from hosted-runner diagnostics
  - retest notes when upstream manifests or artifacts change
  Exit criteria:
  - every confirmed upstream Windows blocker has a concise reproduction and a
    packager impact statement

- `Phase 14G`: Consumer-facing Windows migration notes
  Deliverables:
  - docs for moving downstream Windows workflows away from direct GNUstep MSYS2
    setup and toward the reusable `gnustep-cli-new` bootstrap path
  - guidance for keeping app-specific host packages under
    `hostDependencies.windows.msys2Packages`
  - examples for hosted and self-hosted Windows runners
  Exit criteria:
  - downstream maintainers can migrate Windows packaging without reading
    workflow internals

- `Phase 14H`: Release readiness baseline
  Deliverables:
  - release-gate notes for the known-good Windows runner image,
    `gnustep-cli-new` manifest, MSYS2 bootstrap baseline, WiX baseline, and MSI
    smoke result
  - regression coverage for baseline documentation and workflow inputs
  - release-note guidance for future baseline changes
  Exit criteria:
  - a packager release records the Windows toolchain baseline that downstream
    projects should use or compare against

## Phase 15: App-Domain Packaged Defaults
Goal: add a generic packaged-defaults mechanism that seeds app-domain defaults
on first launch without turning the packager into a global GNUstep preference
writer.
Status: complete. Phase 15A through 15G are implemented.

This phase follows the current semantic `packagedDefaults.defaultTheme` work and
turns packaged defaults into a more general, backend-neutral launch/runtime
contract. The generic mechanism should remain scoped to the packaged app's own
defaults domain. GNUstep global-domain writes such as generic `NSGlobalDomain`
or `GNUstep`-wide seeding are explicitly out of scope for this phase.

Guardrails:
- keep the core contract backend-neutral while allowing backend-specific launch
  helpers to realize first-run defaults
- only seed app-domain defaults when a key is absent; never overwrite later
  user changes
- do not expose a generic manifest surface for cross-app or machine-wide
  preference writes
- if `defaultTheme` cannot be implemented as an app-domain default, keep it as
  a narrow packager-owned semantic instead of broadening the generic contract

Current status notes:
- `Phase 15A` landed as a schema-backed `packagedDefaults.appDomain` manifest
  shape with scalar value validation and app-domain-only documentation.
- `Phase 15B` landed as shared normalization in `scripts/lib/core.ps1`,
  including typed packaged-default entries, default-domain resolution to
  `package.id`, and validation that rejects unsupported value types or
  `GSTheme` under generic app-domain defaults.
- `Phase 15C` landed as a backend-facing MSI launcher contract with
  `appDefaultsDomain` plus serialized `appDefault` entries and explicit docs
  that `defaultTheme` remains a narrow semantic rather than a generic
  app-domain key.
- `Phase 15D` landed as Windows launcher seeding through the bundled
  `runtime/bin/defaults.exe`, plus MSI transform regression coverage for
  packaged app-domain defaults and prerequisite diagnostics when `defaults.exe`
  is missing.
- `Phase 15E` landed as Linux/AppImage parity through generated `AppRun`
  seeding logic backed by a bundled defaults tool under
  `runtime/bin/defaults` or `runtime/bin/defaults.exe`.
- `Phase 15F` landed as behavioral fixture coverage that verifies first-launch
  defaults are actually seeded and that later user overrides survive later
  launches rather than being overwritten.
- `Phase 15G` landed as consumer guidance, template updates, and migration
  notes for downstream repos moving packaged first-run preferences out of
  repo-local fallback code and into `packagedDefaults.appDomain`.

- `Phase 15A`: Manifest shape and schema contract
  Deliverables:
  - a schema-backed manifest shape for generic packaged app-domain defaults
    under `packagedDefaults`
  - validation rules for supported value types and key naming
  - explicit documentation that generic seeding is app-domain only
  Exit criteria:
  - consumers can declare stable first-run app defaults without inventing
    backend-specific config files
  - schema and docs make clear that generic GNUstep global-domain seeding is
    not supported

- `Phase 15B`: Core normalization and merge semantics
  Deliverables:
  - shared core helpers that normalize packaged app-domain defaults into a
    backend-neutral internal contract
  - layering and conflict rules between semantic defaults such as
    `defaultTheme`, explicit `launch.env`, and generic app-domain defaults
  - manifest validation that rejects ambiguous or contradictory declarations
  Exit criteria:
  - one resolved packaged-defaults contract feeds all backends
  - conflicting defaults fail early with precise diagnostics

- `Phase 15C`: Backend realization contract
  Deliverables:
  - a backend-facing contract for "seed once if absent" behavior at packaged
    app launch time
  - MSI and AppImage design notes describing where first-run seeding logic
    lives and how it avoids persistent cross-app side effects
  - a decision on whether `defaultTheme` remains semantic-only or can map into
    the new contract cleanly
  Exit criteria:
  - both backends have a clear realization strategy without introducing
    backend-specific concepts into shared manifest fields
  - theme handling is explicitly documented rather than left implicit

- `Phase 15D`: Windows MSI implementation
  Deliverables:
  - Windows packaged-launch behavior that seeds declared app-domain defaults on
    first launch only when the target key is absent
  - regression coverage around install, first launch, and preserved user
    overrides on later launches
  - diagnostics that distinguish launcher failure, seeding failure, and app
    startup failure
  Exit criteria:
  - a fresh MSI install applies declared app-domain defaults for the packaged
    app on first launch
  - later user preference changes survive subsequent launches

- `Phase 15E`: Linux AppImage implementation
  Deliverables:
  - AppRun or equivalent launch-time logic that realizes the same app-domain
    first-run defaults contract on Linux
  - parity coverage showing the same manifest semantics work across MSI and
    AppImage
  - documentation of any platform-specific limitations that remain
  Exit criteria:
  - AppImage honors the shared app-domain defaults contract without diverging
    manifest semantics
  - backend differences are implementation details, not consumer-visible
    contract drift

- `Phase 15F`: Behavioral validation and fixtures
  Deliverables:
  - reference fixtures that exercise packaged app-domain defaults in a small
    GNUstep app
  - validation paths that confirm behavioral first-launch results instead of
    only checking generated config text
  - installed or extracted result assertions that detect drift between declared
    defaults and actual runtime behavior
  Exit criteria:
  - repo-owned validation catches "launcher config looks right but first launch
    still behaves wrong" regressions
  - downstream repos do not need ad hoc checks for packaged first-run defaults

- `Phase 15G`: Consumer guidance and migration
  Deliverables:
  - manifest documentation and examples for app-domain packaged defaults
  - migration guidance for downstream apps currently using repo-local fallback
    preference seeding
  - explicit notes about when to use generic app-domain defaults versus narrow
    semantic fields such as `defaultTheme`
  Exit criteria:
  - downstream maintainers can adopt packaged first-run defaults without
    guessing at backend behavior
  - docs keep the support boundary clear: app-domain seeding is supported,
    generic global-domain preference writing is not

## Phase 16: First-Class GNUstep Theme Inputs
Goal: let downstream GNUstep applications declare required packaged themes while
`gnustep-packager` owns theme source resolution, build, staging, structural
validation, default-theme consistency, diagnostics, and consumer migration.
Status: complete. Phase 16A through 16M are implemented.

This phase moves generic GNUstep theme packaging concerns out of downstream app
repos. The staged payload remains the single source of truth for MSI and
AppImage backends, but the packager becomes responsible for composing declared
theme inputs into that staged payload before shared validation and backend
packaging run.

Guardrails:
- keep `themeInputs` backend-neutral even though the first implementation
  targets Windows/MSYS2 `CLANG64` plus `gnustep-cli-new`
- keep `packagedDefaults.defaultTheme` as the single effective default-theme
  contract; `themeInputs[].default` may derive it but must not contradict it
- preserve complete `.theme` bundles, including arbitrary future resources,
  instead of copying only the theme executable
- keep app-specific theme assertions optional; normal GNUstep theme structure
  should be validated generically

Current status notes:
- `Phase 16A` landed as a schema-backed `themeInputs` manifest contract with
  source selection, platform filters, required/default flags, workspace
  overrides, and limited build overrides.
- `Phase 16B` landed as default-theme normalization, conflict validation, and
  automatic bundled-theme contract declarations for required or default theme
  inputs.
- `Phase 16C` landed as a shared `provision` pipeline step that runs after app
  staging and before validation/package in the shared wrapper, while backend
  package commands also invoke theme provisioning before packaging.
- `Phase 16D` landed as the first Windows/MSYS2 realization path: theme
  sources can be cloned or reused, checked out at the requested ref, built
  through the managed GNUstep shell environment, installed into a temporary
  GNUstep user root, and copied as complete `.theme` bundles into stage.
- `Phase 16E` landed as complete bundle copy behavior that preserves arbitrary
  files under the installed `.theme` directory and stages under the stable
  `runtime/lib/GNUstep/Themes` root.
- `Phase 16F` landed as structural `bundled-theme` validation for known
  backend executable conventions plus `Resources/Info-gnustep.plist` and
  `GSThemeImages` resource references when theme resources are present.
- `Phase 16G` landed as an optional `theme-resource` semantic assertion for
  downstream app-specific files inside bundled themes.
- `Phase 16H` landed as a staged
  `metadata/gnustep-packager-theme-report.json` payload report with source,
  ref, resolved commit, staged path, executable, info plist, and resource
  inventory details.
- `Phase 16I` landed as downstream template and documentation updates showing
  `WinUITheme` as a required Windows default theme input, plus regression
  coverage that keeps the template valid and checks the migration guidance.
- downstream ObjcMarkdown review confirmed the Windows/MSI migration path is a
  strong first pass, but the feature should not be closed until DLL-only theme
  bundles fail structural validation, duplicate provisioning is avoided, the
  backend-aware validation behavior is explicit, and AppImage provisioning is
  either implemented or cleanly scoped as unsupported.
- `Phase 16J` landed as strict incomplete-theme rejection for required,
  default, or packager-provisioned themes, so a DLL-only Windows theme bundle
  no longer satisfies the semantic theme contract.
- `Phase 16K` landed as staged report-based provisioning idempotence so a
  current theme payload is reused instead of rebuilt by a later package step.
- `Phase 16L` landed as explicit CLI and docs guidance that shared validation
  checks the current staged layout, while backend-aware theme behavior requires
  backend-scoped provision, package, or validation commands.
- `Phase 16M` landed as an explicit AppImage support boundary: required
  AppImage theme inputs fail early with a deliberate unsupported-backend
  diagnostic until Linux provisioning is implemented in a later phase.

- `Phase 16A`: Theme input manifest contract
  Deliverables:
  - schema-backed `themeInputs` manifest section with fields for `name`,
    `repo`, `ref`, `platforms`, `required`, `default`, `workspacePath`, and
    limited build overrides
  - validation rules for required fields, platform applicability, one default
    theme per active platform, and `repo` versus `workspacePath` source
    selection
  - release-build guidance for recording exact resolved commits instead of
    relying only on branch names
  Exit criteria:
  - a downstream manifest can declare required and optional GNUstep themes
    without repo-local theme provisioning scripts
  - invalid or contradictory theme declarations fail before build or package
    work starts

- `Phase 16B`: Default-theme integration and automatic contracts
  Deliverables:
  - normalization rules that connect `themeInputs[].default` with
    `packagedDefaults.defaultTheme`
  - early failure when `packagedDefaults.defaultTheme` names a theme that is
    neither declared in active `themeInputs` nor already present in a supported
    staged runtime theme root
  - automatic semantic package and installed-result assertions for required
    and default bundled themes
  Exit criteria:
  - the packaged default theme has one effective source of truth
  - downstream manifests do not need to repeat normal required-theme assertions
    under `validation.packageContract.requiredContent`

- `Phase 16C`: Shared theme provisioning pipeline step
  Deliverables:
  - a packager-owned stage augmentation step that runs after app staging and
    before shared validation and backend packaging
  - source checkout or reuse logic for `repo`, `ref`, and `workspacePath`
    inputs, with required-theme failures and optional-theme warnings
  - output discipline that keeps source checkouts, build roots, install roots,
    temporary manifests, and logs under declared `dist/` output roots
  Exit criteria:
  - downstream app stage commands can produce only the app payload while the
    packager composes declared theme inputs into the same staged payload
  - local and CI packaging use the same theme provisioning path

- `Phase 16D`: Windows/MSYS2 GNUstep theme build and install realization
  Deliverables:
  - Windows `CLANG64` theme build/install implementation using the managed
    `gnustep-cli-new` GNUstep toolchain environment
  - handling for MSYS2 path conversion, `GNUSTEP_MAKEFILES`, compiler
    overrides such as `CC`, `OBJC_CC`, `CXX`, and `OBJCXX`, and known
    GNUstep/MSYS2 compatibility flags when required
  - collection of the installed `.theme` bundle from the user GNUstep theme
    root into the staged runtime theme root
  Exit criteria:
  - a hosted Windows MSI build can fetch or reuse `WinUITheme`, build it with
    the managed toolchain, install it, and stage the complete theme bundle
    without downstream repo-local scripts
  - failures identify the theme input, source ref, command, and toolchain
    context involved

- `Phase 16E`: Complete theme bundle staging
  Deliverables:
  - staging logic that preserves complete `.theme` directories, including
    executable files, `Resources/Info-gnustep.plist`, image directories, tiles,
    localization files, metadata, and future theme resources
  - stable supported runtime theme root selection for staged theme bundles
  - regression coverage proving resource directories survive stage
    augmentation and backend transforms
  Exit criteria:
  - packaged output cannot appear to ship a theme by including only
    `<Theme>.dll` while omitting resources required for correct rendering
  - arbitrary files inside the installed `.theme` bundle survive into the
    packaged runtime

- `Phase 16F`: Structural bundled-theme validation
  Deliverables:
  - stronger `bundled-theme` validation that checks the theme directory,
    platform executable, `Resources/Info-gnustep.plist` when expected, and
    coherent principal-class or executable metadata when available
  - validation that `GSThemeImages` resource references resolve to packaged
    files
  - phase-aware checks across stage, package transform, and installed or
    extracted result roots
  Exit criteria:
  - missing theme resources fail validation before release artifacts are
    accepted
  - diagnostics distinguish content missing from stage, lost during backend
    transform, or lost after install or extraction

- `Phase 16G`: Theme-specific assertion escape hatch
  Deliverables:
  - optional `theme-resource` semantic assertion for downstream app-specific
    requirements such as a named image under a declared theme bundle
  - manifest validation for `theme`, `path`, and applicable assertion fields
  - backend-neutral resolution against supported runtime theme roots
  Exit criteria:
  - downstream apps can assert important theme-specific files without listing
    every normal theme resource
  - generic theme validation remains sufficient for ordinary complete bundle
    checks

- `Phase 16H`: Theme payload diagnostics and metadata report
  Deliverables:
  - generated theme payload report in logs and/or staged metadata listing
    bundled themes, source repo or workspace path, requested ref, resolved
    commit, required/default flags, staged path, executable, and resource
    inventory
  - backend package logs that summarize theme provisioning and validation
    results
  - diagnostic retention in CI artifacts for failed theme provisioning or
    validation runs
  Exit criteria:
  - UAT and release triage can classify missing theme asset issues from
    package logs without manually unpacking the MSI or AppImage
  - release artifacts can be traced back to the exact theme source commit used

- `Phase 16I`: Consumer migration, examples, and regression coverage
  Deliverables:
  - updated manifest docs, consumer setup guidance, and downstream examples
    showing `WinUITheme` as a required Windows theme and packaged default
  - migration notes for removing ObjcMarkdown-style repo-local theme scripts
  - regression coverage for manifest validation, theme provisioning dry-runs,
    Windows theme staging, structural validation failures, and final
    installed-result assertions
  Exit criteria:
  - a downstream app can declare `WinUITheme` as a required Windows default
    theme without custom fetch/build/install/copy scripts
  - repo-owned tests catch incomplete theme bundles and default-theme drift
    before downstream release pipelines encounter them

- `Phase 16J`: Strict incomplete-theme rejection
  Deliverables:
  - update structural `bundled-theme` validation so required/default or
    packager-provisioned themes fail when a `.theme` bundle contains only the
    backend executable and omits `Resources/Info-gnustep.plist`
  - regression coverage proving a DLL-only Windows theme bundle fails package
    and installed-result validation with a precise diagnostic
  - clear policy for compatibility fixtures or legacy manually-staged themes
    that intentionally lack a GNUstep resources directory
  Exit criteria:
  - a package cannot satisfy a required/default bundled-theme contract by
    shipping only `<Theme>.dll`
  - missing `Resources/Info-gnustep.plist` is reported as an incomplete theme
    bundle before release artifacts are accepted

- `Phase 16K`: Provisioning idempotence and duplicate-build avoidance
  Deliverables:
  - pipeline behavior that avoids rebuilding the same active theme inputs twice
    when `run-packaging-pipeline.ps1` runs `provision` and the backend
    `package` command is invoked afterward
  - a durable per-stage provisioning marker or report check that records the
    theme input name, source, requested ref, resolved commit, and staged bundle
    path used to determine whether provisioning is already current
  - command-line policy for direct `package` invocations, including when they
    auto-provision and when callers may explicitly skip or force provisioning
  Exit criteria:
  - the normal shared pipeline builds each active theme input at most once
    before packaging
  - direct backend package commands remain safe for users who skip the wrapper
  - stale or changed theme inputs trigger reprovisioning instead of silently
    reusing old staged bundles

- `Phase 16L`: Backend-aware validation behavior and documentation
  Deliverables:
  - explicit documentation that shared `validate` without `-Backend` checks the
    current staged layout and does not imply backend/platform-specific theme
    provisioning
  - CLI or validation diagnostics that point users toward `provision -Backend
    msi`, `package -Backend msi`, or `validate -Backend msi` when active theme
    inputs are platform-filtered
  - regression coverage for Windows-only theme inputs showing the difference
    between shared validation and backend-aware validation paths
  Exit criteria:
  - downstream users can predict when theme provisioning and structural
    backend checks run
  - validation failures do not imply that a platform-filtered theme was ignored
    silently

- `Phase 16M`: AppImage theme provisioning support boundary
  Deliverables:
  - either implement Linux/AppImage theme input provisioning using the managed
    GNUstep toolchain path or document AppImage theme provisioning as an
    explicit unsupported follow-up with clear required-theme failure behavior
  - if implemented, Linux source resolution, build/install, staged bundle
    collection, structural validation, and payload-report parity with the MSI
    path
  - AppImage fixture or integration coverage for at least one declared Linux
    theme input, including final extracted-result validation
  Exit criteria:
  - the cross-backend support boundary for `themeInputs` is explicit and
    test-backed
  - a required AppImage theme input either provisions successfully through the
    documented Linux path or fails early with a deliberate unsupported-backend
    diagnostic

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
