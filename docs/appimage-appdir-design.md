# AppDir Transform Design

## Purpose
The AppImage backend transforms the staged payload into an AppDir without
mutating the original stage tree.

## Layout

```text
<AppDir>/
  AppRun
  <desktopEntryName>
  <icon-name>.png
  .DirIcon
  usr/
    app/
    runtime/
    metadata/
    share/
      applications/
        <desktopEntryName>
      icons/
        hicolor/256x256/apps/<icon-name>.png
      mime/
        packages/<normalized-package-id>.xml
```

## Transform Rules
- staged `app/` is copied to `AppDir/usr/app/`
- staged `runtime/` is copied to `AppDir/usr/runtime/`
- staged `metadata/` is copied to `AppDir/usr/metadata/`
- generated desktop, icon, MIME, and notice assets are added after the staged
  roots are copied
- the AppImage artifact is emitted from the AppDir into the configured package
  output root

## Working Directories
Temporary backend work lives under:

- `dist/tmp/appimage/<timestamp>/`

That working tree contains:
- the generated AppDir
- downloaded `appimagetool` payloads when bootstrapping is required
- extracted AppImage contents during validation
