# Local and CI Parity

## Purpose
Phase 5A is centered on one rule: CI should call the same packaging entry point
that a developer can run locally.

## Shared Entry Point
The shared wrapper is:

- `scripts/run-packaging-pipeline.ps1`

It drives the same sequence in both local and CI contexts:

1. `build`
2. `stage`
3. shared staged-layout `validate`
4. backend `package`
5. backend `validate`

## Local Usage

```powershell
./scripts/run-packaging-pipeline.ps1 `
  -Manifest examples/sample-gui/package.manifest.json `
  -Backend msi `
  -RunSmoke
```

```powershell
./scripts/run-packaging-pipeline.ps1 `
  -Manifest examples/sample-linux/package.manifest.json `
  -Backend appimage `
  -RunSmoke
```

## Running GUI Apps By Hand
Don't launch a GNUstep app with only a private `HOME`. gnustep-base takes the
home directory from the passwd database, so the app still reads and rewrites the
real `~/GNUstep/Defaults`, and it opens whatever the user's saved state points
to. `xvfb-run` hides the windows but not those writes.

Use the sandbox, which binds a scratch directory over the real home:

```sh
scripts/run-gui-isolated.sh --seconds 15 --screenshot /tmp/app.png -- ./App.AppImage
```

The program and the screenshot path must be outside the home directory. The
packaging pipeline's own smoke launch sets a private `GNUSTEP_HOME` and refuses
to run with the real one.

## CI Usage
The reusable GitHub Actions workflow calls the same wrapper rather than
re-encoding packaging logic in YAML.

`validate-repo.yml` also calls the reusable workflow itself once per backend,
so each one builds an installer through the entry point consumers use:
`linux-reusable-workflow` (AppImage, `examples/sample-linux`, plus a launch in
a clean `ubuntu:24.04` container), `windows-reusable-workflow` (MSI,
`examples/sample-gui`) and `macos-reusable-workflow` (DMG,
`examples/sample-macos`).

That keeps:

- local reproduction straightforward
- workflow behavior easier to reason about
- release changes concentrated in PowerShell and manifest logic
- backend-specific host setup constrained to a small, caller-extensible workflow
  preflight step

## Version Overrides
Both local and CI flows can override the package version with:

- `-PackageVersion <value>`
- or `GP_PACKAGE_VERSION_OVERRIDE`

The build and stage commands see the effective version as `GP_PACKAGE_VERSION`
and the override as `GP_PACKAGE_VERSION_OVERRIDE`; see
[manifest.md](manifest.md#pipeline).

## Why This Matters
Without a single shared entry point, CI and local runs drift quickly:

- one path forgets a validation step
- one path uses different version rules
- one path uploads artifacts the other never produced
