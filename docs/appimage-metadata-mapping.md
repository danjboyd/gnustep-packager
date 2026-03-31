# AppImage Metadata Mapping

## Purpose
This document maps the shared manifest model onto the AppImage-specific
metadata emitted by the backend.

## Desktop Entry
The generated desktop entry maps:

- `package.displayName` to `Name`
- `package.summary` or `package.description` to `Comment`
- `package.homepage` to `X-AppImage-Homepage`
- `package.name` to `X-AppImage-Name`
- `package.version` to `X-AppImage-Version`
- `integrations.categories` to `Categories`
- generated MIME types to `MimeType`
- `backends.appimage.desktopEntryName` to the emitted `.desktop` filename

The backend writes the desktop file to both:
- `AppDir/usr/share/applications/<desktopEntryName>`
- `AppDir/<desktopEntryName>`

## Icons
`backends.appimage.iconRelativePath` points to the staged `.png` icon. The
backend copies it to:

- `AppDir/usr/share/icons/hicolor/256x256/apps/<icon-name>.png`
- `AppDir/<icon-name>.png`
- `AppDir/.DirIcon`

`<icon-name>` is derived from the desktop entry base name.

## MIME Associations
Extension associations in `integrations.fileAssociations` become generated MIME
types of the form:

- `application/x-<package-name>-<extension>`

The backend emits a shared-mime-info package under:

- `AppDir/usr/share/mime/packages/<normalized-package-id>.xml`

Those generated MIME types are also added to the desktop entry.

## Compliance and Diagnostics
Shared compliance entries map to:

- bundled notice validation against staged notice files
- `AppDir/usr/<metadataRoot>/THIRD-PARTY-NOTICES.txt`

Package outputs also include:

- `<artifact-base>.metadata.json`
- `<artifact-base>.diagnostics.txt`
