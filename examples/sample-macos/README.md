# Sample macOS Fixture

This fixture is the reference input for the DMG backend.

- `build` compiles a tiny universal (arm64 + x86_64) C program into
  `out/build/SampleMacApp.app` and ad-hoc signs it with the hardened runtime,
  the way a native macOS build would.
- `stage` copies the bundle into `dist/stage/app/SampleMacApp.app` with
  `ditto`, adds a license notice and a background image under `metadata/`,
  and leaves `runtime/` empty (a native bundle carries its own runtime).
- `package -Backend dmg` builds `dist/packages/SampleMacApp-0.1.0-macos-universal.dmg`.
- `validate -Backend dmg -RunSmoke` verifies, mounts and smoke-launches it.

The program is faceless (`LSBackgroundOnly`), prints one line and waits to be
terminated, so packaging tests never open a window. `finderLayout` is `off`
to keep test runs from driving Finder; notarization is enabled with an unset
`GP_SAMPLE_NOTARY_PROFILE` to exercise the "skipped, no credentials" path.

```powershell
./scripts/gnustep-packager.ps1 -Command build -Manifest examples/sample-macos/package.manifest.json
./scripts/gnustep-packager.ps1 -Command stage -Manifest examples/sample-macos/package.manifest.json
./scripts/gnustep-packager.ps1 -Command validate -Manifest examples/sample-macos/package.manifest.json
./scripts/gnustep-packager.ps1 -Command package -Manifest examples/sample-macos/package.manifest.json -Backend dmg
./scripts/gnustep-packager.ps1 -Command validate -Manifest examples/sample-macos/package.manifest.json -Backend dmg -RunSmoke
```
