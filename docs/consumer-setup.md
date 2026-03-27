# Consumer Setup

## Minimal Consumer Shape
A downstream app repo needs:

- a `package.manifest.json`
- a `build` command that produces app output
- a `stage` command that produces the normalized stage layout

## Expected Stage Layout

```text
<stage-root>/
  app/
  runtime/
  metadata/
```

## Windows MSI Onboarding
For the current MSI backend, the consumer should:

1. build with MSYS2 `CLANG64`
2. stage a self-contained GNUstep payload under `runtime/`
3. enable `backends.msi`
4. provide a stable `upgradeCode`
5. run the shared pipeline wrapper locally before wiring CI

## Recommended First Run

```powershell
./scripts/run-packaging-pipeline.ps1 `
  -Manifest packaging/package.manifest.json `
  -Backend msi `
  -RunSmoke
```

## GitHub Actions
Once the local run works, call the reusable workflow documented in
[github-actions.md](github-actions.md).
