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

## CI Usage
The reusable GitHub Actions workflow calls the same wrapper rather than
re-encoding packaging logic in YAML.

That keeps:

- local reproduction straightforward
- workflow behavior easier to reason about
- release changes concentrated in PowerShell and manifest logic
- backend-specific host setup constrained to a small workflow preflight step

## Version Overrides
Both local and CI flows can override the package version with:

- `-PackageVersion <value>`
- or `GP_PACKAGE_VERSION_OVERRIDE`

## Why This Matters
Without a single shared entry point, CI and local runs drift quickly:

- one path forgets a validation step
- one path uses different version rules
- one path uploads artifacts the other never produced
