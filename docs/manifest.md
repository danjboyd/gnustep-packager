# Manifest

## Purpose
The package manifest tells `gnustep-packager`:
- what the app is
- how the consumer repo builds and stages it
- what staged layout the backend should expect
- how the app should be launched
- which backends are enabled

## Top-Level Sections
- `schemaVersion`
- `profiles`
- `package`
- `pipeline`
- `payload`
- `launch`
- `outputs`
- `validation`
- `integrations`
- `compliance`
- `backends`

## `profiles`
Optional built-in defaults layers for common consumer shapes.

Current built-in profiles:
- `gnustep-gui`
- `gnustep-document-viewer`

## `package`
Shared identity and display metadata.

Important fields:
- `id`
- `name`
- `version`
- `manufacturer`

## `pipeline`
Commands that run in the consumer repo.

Important fields:
- `workingDirectory`
- `shell.kind`
- `shell.bootstrapCommands`
- `shell.environment`
- `build.command`
- `stage.command`
- `stage.outputRoot`

Current `shell.kind` values used by the reference fixtures:
- `pwsh`
- `bash`

## `payload`
Describes the staged layout.

Important fields:
- `layoutVersion`
- `stageRoot`
- `appRoot`
- `runtimeRoot`

## `launch`
Describes how the packaged app starts from the staged payload.

Important fields:
- `entryRelativePath`
- `workingDirectory`
- `pathPrepend`
- `resourceRoots`
- `env`

## `outputs`
Declares shared output roots for logs, packages, temporary files, and validation
artifacts.

Important fields:
- `root`
- `packageRoot`
- `logRoot`
- `tempRoot`
- `validationRoot`

## `validation`
Declares shared smoke validation behavior that is backend-neutral.

Important fields:
- `smoke.enabled`
- `smoke.kind`
- `smoke.requiredPaths`
- `smoke.timeoutSeconds`
- `logs.retainOnSuccess`

## `integrations`
Logical desktop integrations that backends may map differently.

Examples:
- shortcut names
- menu categories
- file associations

## `compliance`
Optional runtime notice metadata for packaged payload contents.

Important fields:
- `runtimeNotices[].name`
- `runtimeNotices[].version`
- `runtimeNotices[].license`
- `runtimeNotices[].source`
- `runtimeNotices[].homepage`
- `runtimeNotices[].stageRelativePath`

## `backends`
Backend-specific toggles and settings.

Current planned backends:
- `msi`
- `appimage`

### `backends.msi`
Important fields:
- `upgradeCode`
- `installScope`
- `productName`
- `shortcutName`
- `installDirectoryName`
- `launcherFileName`
- `iconRelativePath`
- `artifactNamePattern`
- `portableArtifactNamePattern`
- `fallbackRuntimeRoot`
- `runtimeSearchRoots`
- `wix.version`
- `wix.downloadUrl`
- `wix.toolRoot`
- `wix.skipValidation`
- `wix.suppressedIces`
- `signing.enabled`
- `signing.toolPath`
- `signing.timestampUrl`
- `signing.certificateSha1`
- `signing.description`
- `signing.additionalArguments`

### `backends.appimage`
Important fields:
- `appDirName`
- `desktopEntryName`
- `iconRelativePath`
- `artifactNamePattern`
- `toolRoot`
- `downloadUrl`
- `skipAppStreamValidation`

When `backends.appimage.enabled` is `true`, `iconRelativePath` must point to a
staged `.png` asset.

## Resolution
The CLI resolves manifests through layered defaults before validation and
execution:

1. core defaults
2. backend defaults
3. app manifest

At execution time, the resolved manifest may also receive a package-version
override from:

- `-PackageVersion`
- `GP_PACKAGE_VERSION_OVERRIDE`

See [configuration-layering.md](configuration-layering.md).

See also:
- [consumer-setup.md](consumer-setup.md)
- [compliance-notices.md](compliance-notices.md)
