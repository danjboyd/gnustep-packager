# Sample GUI Reference Fixture

This example is the current reference consumer for the repo.

It exists to:

- exercise the manifest schema and defaults layering
- exercise built-in profile layering and compliance notice generation
- prove the MSI backend against a stable input
- give CI and local development one known-good fixture

## What It Includes

- `package.manifest.json`
  Reference manifest with MSI enabled, `gnustep-gui` profile usage, and
  compliance notice entries
- `src/SampleGNUstepApp.c`
  Tiny Windows GUI executable used as the inner app
- `scripts/build-fixture.ps1`
  Build step for the fixture
- `scripts/stage-fixture.ps1`
  Stage step that produces `app/`, `runtime/`, and `metadata/`

## Local Run

```powershell
./scripts/run-packaging-pipeline.ps1 `
  -Manifest examples/sample-gui/package.manifest.json `
  -Backend msi `
  -RunSmoke
```

The sample uses `perUser` MSI install scope so install and uninstall validation
can run without elevation on developer machines and CI runners.
