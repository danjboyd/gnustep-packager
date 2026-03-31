# Sample Linux Fixture

This fixture provides a small Linux-oriented reference input for the AppImage
backend.

It is intentionally simple:

- `build` produces a tiny executable shell-script payload
- `stage` lays it out under the shared `app/`, `runtime/`, and `metadata/`
  roots
- `package -Backend appimage` transforms that staged payload into an AppDir and
  emits an AppImage
- `validate -Backend appimage -RunSmoke` launches the packaged fixture through
  the configured AppImage smoke mode

Local commands:

```powershell
./scripts/gnustep-packager.ps1 -Command build -Manifest examples/sample-linux/package.manifest.json
./scripts/gnustep-packager.ps1 -Command stage -Manifest examples/sample-linux/package.manifest.json
./scripts/gnustep-packager.ps1 -Command package -Manifest examples/sample-linux/package.manifest.json -Backend appimage
./scripts/gnustep-packager.ps1 -Command validate -Manifest examples/sample-linux/package.manifest.json -Backend appimage -RunSmoke
```

The fixture manifest currently demonstrates `backends.appimage.smoke.mode:
launch-only`. The backend also supports explicit `open-file`,
`custom-arguments`, and `marker-file` smoke modes.
