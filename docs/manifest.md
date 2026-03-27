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
- `package`
- `pipeline`
- `payload`
- `launch`
- `outputs`
- `validation`
- `integrations`
- `backends`

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
- `artifactNamePattern`
- `portableArtifactNamePattern`
- `fallbackRuntimeRoot`
- `runtimeSearchRoots`
- `wix.version`
- `wix.downloadUrl`
- `wix.toolRoot`
- `signing.enabled`
- `signing.toolPath`
- `signing.timestampUrl`
- `signing.certificateSha1`
- `signing.description`
- `signing.additionalArguments`

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
