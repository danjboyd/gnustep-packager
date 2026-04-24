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
- `packagedDefaults`
- `themeInputs`
- `outputs`
- `hostDependencies`
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
- `gnustep-cmark`

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

## `packagedDefaults`
Declares semantic defaults that the packager should realize into generated
launch/runtime artifacts and later validate against packaged results.

Current fields:
- `defaultTheme`
- `appDomain`

`packagedDefaults.defaultTheme` currently realizes a `GSTheme` launch default
with `policy: ifUnset` when the manifest does not already declare one. On
Windows MSI and Linux AppImage, it also seeds `GSTheme` into the packaged app's
defaults domain on first launch so the requested theme becomes an effective
user default without requiring a generic global-domain write. If the manifest
also sets `launch.env.GSTheme`, the values must match.

`packagedDefaults.appDomain` declares first-run app-domain defaults for the
packaged app. Current shape:

- `domain`
  Optional explicit defaults domain. When omitted, the packager uses
  `package.id`.
- `values`
  Required object of scalar defaults to seed only when the key is absent.
  Supported value types are string, boolean, integer, and number.

Current boundary:
- generic app-domain seeding is currently implemented for Windows MSI and Linux
  AppImage
- generic GNUstep global-domain seeding is not supported
- `GSTheme` is still a narrow semantic under `packagedDefaults.defaultTheme`,
  not a generic `appDomain.values` key

## `themeInputs`
Declares packaging-time GNUstep theme sources that the packager should
provision into the staged runtime before validation and backend packaging.

Important fields:
- `name`
  GNUstep theme name, such as `WinUITheme`.
- `repo`
  Git URL for the theme source. Either `repo` or `workspacePath` is required.
- `ref`
  Branch, tag, or commit to check out. Release builds should use a tag or
  commit and record the resolved commit in package logs.
- `platforms`
  Platform or backend filter. Current values are `windows`, `linux`, `msi`,
  and `appimage`.
- `required`
  When `true`, provisioning failures stop packaging. Optional themes warn and
  continue.
- `default`
  Marks the preferred packaged default theme. If exactly one default theme
  input is declared and `packagedDefaults.defaultTheme` is absent, the packager
  derives `packagedDefaults.defaultTheme` from it. If both are present, they
  must match.
- `workspacePath`
  Optional local checkout override for developer workflows.
- `build`
  Optional command, install command, and environment overrides for advanced
  theme builds.

Example:

```json
{
  "themeInputs": [
    {
      "name": "WinUITheme",
      "repo": "https://github.com/danjboyd/plugins-themes-winuitheme.git",
      "ref": "v0.1.0",
      "platforms": ["windows"],
      "required": true,
      "default": true
    }
  ],
  "packagedDefaults": {
    "defaultTheme": "WinUITheme"
  }
}
```

The first realization path targets Windows/MSYS2 `CLANG64` plus the managed
`gnustep-cli-new` toolchain. Theme provisioning runs after the app's stage
command and before shared validation and backend packaging. Generated source
checkouts, temporary install roots, and logs belong under declared `outputs`
roots. Successful provisioning writes
`metadata/gnustep-packager-theme-report.json` into the staged payload with
source/ref, resolved commit when available, staged path, executable, info plist,
and resource inventory details.

## `hostDependencies`
Declares app-specific host/build prerequisites that the shared tooling may
verify or install before build and packaging steps begin.

Important fields:
- `windows.msys2Packages`
- `linux.aptPackages`

These declarations are for host-side package managers and build prerequisites,
not for staged runtime payload contents under `app/`, `runtime/`, or
`metadata/`.

Shared dependency sets may also come from manifest `profiles`. For example,
`gnustep-cmark` layers in the common cmark host packages for both the Windows
MSYS2 and Linux apt provider paths without changing the `hostDependencies`
shape.

## `validation`
Declares shared smoke validation behavior that is backend-neutral.

Important fields:
- `smoke.enabled`
- `smoke.kind`
- `smoke.requiredPaths`
- `smoke.timeoutSeconds`
- `logs.retainOnSuccess`
- `packageContract.requiredContent`
- `packageContract.requiredPaths`
- `installedResult.requiredContent`
- `installedResult.requiredPaths`

Shared validation still centers on staged-layout checks, but the manifest can
now also declare semantic package contracts and installed-result assertions.

Current semantic contract kinds:
- `notice-report`
- `update-runtime-config`
- `default-theme`
- `bundled-theme`
- `theme-resource`
- `metadata-file`
- `updater-helper`

`requiredPaths` remains the low-level escape hatch for backend-specific or
unusual packaged results that are easier to assert as concrete paths.

`default-theme` and `bundled-theme` intentionally cover different invariants:
- `default-theme`
  Confirms the generated launcher preserves the declared default theme
  behavior.
- `bundled-theme`
  Confirms the named GNUstep theme payload is actually present in stage,
  packaged output, and installed or extracted results across the supported
  runtime theme roots:
  `runtime/System/Library/Themes/<Theme>.theme`,
  `runtime/lib/GNUstep/Themes/<Theme>.theme`, and
  `runtime/share/GNUstep/Themes/<Theme>.theme`.
- `theme-resource`
  Confirms a named file inside a bundled theme exists. This is an optional
  app-specific assertion; ordinary theme resources are covered by structural
  bundled-theme validation and do not need to be listed one by one.

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
