# AppImage Extension Path

## Purpose
This document captured the Phase 9 extension-path baseline before the AppImage
backend landed. The backend is now implemented; this file remains as a compact
overview of how the shared model maps into AppImage concerns.

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

## Implemented Follow-Through
The detailed implementation docs now live here:

- [appimage-requirements.md](appimage-requirements.md)
- [appimage-metadata-mapping.md](appimage-metadata-mapping.md)
- [appimage-appdir-design.md](appimage-appdir-design.md)
- [appimage-runtime-policy.md](appimage-runtime-policy.md)
- [../backends/appimage/README.md](../backends/appimage/README.md)
