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
- `updates`
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

`launch.env` entries may be either:
- a plain string, which means `policy: override`
- an object with `value` plus optional `policy`

Current launch environment policies:
- `override`
  Always set the variable in the generated launcher.
- `ifUnset`
  Set the variable only when the user has not already defined it.

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

Current shared smoke behavior only covers staged-layout validation. Backend
artifact smoke strategies stay under backend-specific configuration.

## `updates`
Declares shared release-discovery settings for packaged apps.

Important fields:
- `enabled`
- `provider`
- `channel`
- `feedUrl`
- `minimumCheckIntervalHours`
- `startupDelaySeconds`
- `github.owner`
- `github.repo`
- `github.tagPattern`
- `github.releaseNotesUrlPattern`

Current provider value:
- `github-release-feed`

When `updates.enabled` is `true`, each enabled backend must resolve a feed URL
either from `updates.feedUrl` or from its backend-specific override.

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
- `unresolvedDependencyPolicy`
- `ignoredRuntimeDependencies`
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
- `updates.feedUrl`

### `backends.appimage`
Important fields:
- `appDirName`
- `desktopEntryName`
- `iconRelativePath`
- `updates.feedUrl`
- `updates.embedUpdateInformation`
- `updates.updateInformation`
- `updates.releaseSelector`
- `updates.zsyncArtifactNamePattern`
- `artifactNamePattern`
- `toolRoot`
- `downloadUrl`
- `skipAppStreamValidation`
- `validation.runtimeClosure`
- `validation.allowedSystemLibraries`
- `validation.allowedExternalRunpaths`
- `smoke.mode`
- `smoke.arguments`
- `smoke.environment`
- `smoke.documentStageRelativePath`
- `smoke.startupSeconds`

When `backends.appimage.enabled` is `true`, `iconRelativePath` must point to a
staged `.png` asset.

Supported AppImage smoke modes:

- `launch-only`
  Launch the packaged app and treat a clean exit or a still-running process
  after the startup window as success.
- `open-file`
  Launch the packaged app with a staged sample document path appended after any
  configured smoke arguments.
- `custom-arguments`
  Launch the packaged app with manifest-defined smoke arguments.
- `marker-file`
  Launch the packaged app with a marker-file compatibility argument and the
  same path exported as `GP_APPIMAGE_SMOKE_MARKER_PATH`.

AppImage update settings:

- `embedUpdateInformation`
  When `true`, the backend emits standard AppImage update metadata into the
  generated `.AppImage`.
- `updateInformation`
  Optional explicit update-information string override.
- `releaseSelector`
  Selector segment used when deriving `gh-releases-zsync` metadata.
- `zsyncArtifactNamePattern`
  Pattern for the generated `.zsync` sidecar artifact name.

AppImage runtime-closure validation modes:

- `strict`
  Extract the packaged AppImage, scan bundled ELF files, reject host-escaping
  `RUNPATH` or `RPATH` entries, and fail on unresolved dependencies under the
  packaged library search path. If `validation.allowedSystemLibraries` is set,
  host-resolved libraries outside the AppDir must appear in that allowlist.
- `off`
  Skip backend ELF closure checks.

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
- [update-architecture.md](update-architecture.md)
- [update-feed-contract.md](update-feed-contract.md)
