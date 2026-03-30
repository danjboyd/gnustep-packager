# AppImage Extension Path

## Purpose
Phase 9D does not require a working AppImage backend yet, but it does require a
clear path from the shared model into a future AppImage implementation.

## Shared Model Reuse
The existing manifest already carries most of the AppImage inputs:

- `package.*` for identity, display metadata, license, and homepage
- `payload.*` for staged app, runtime, and metadata roots
- `launch.*` for entry path, working directory, startup arguments, PATH
  prefixes, and environment
- `integrations.*` for categories and file associations
- `compliance.runtimeNotices` for bundled notice traceability
- `backends.appimage.*` for AppImage-specific file naming

## Planned Mapping

### AppDir Layout
- `payload.appRoot` becomes the bundled application subtree in AppDir
- `payload.runtimeRoot` becomes the bundled GNUstep runtime subtree
- `payload.metadataRoot` carries icons, notices, and desktop-support files

### Launch
- `launch.entryRelativePath` maps into generated `AppRun`
- `launch.pathPrepend` and `launch.env` become AppRun environment setup
- `launch.resourceRoots` informs resource and icon lookup policy

### Desktop Metadata
- `package.name` and `package.displayName` feed desktop entry values
- `integrations.categories` maps to desktop categories
- `integrations.fileAssociations` maps to MIME or extension registration data
- `backends.appimage.desktopEntryName` controls the emitted `.desktop` filename
- `backends.appimage.iconRelativePath` points to the staged icon asset

### Diagnostics and Compliance
- artifact metadata sidecars should mirror the MSI provenance pattern
- bundled notice reports should continue to be generated from
  `compliance.runtimeNotices`

## Implementation Sequence
The expected next implementation steps still match the roadmap:

1. `Phase 7A`: supported Linux environment and portability target
2. `Phase 7B`: manifest-to-desktop metadata mapping
3. `Phase 7C`: AppDir transform and `AppRun` design
4. `Phase 7D`: Linux runtime policy
5. `Phase 8A` through `8D`: backend implementation and validation
