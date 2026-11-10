# AppImage Theme Metadata

An AppImage's themes live inside its squashfs, which is mounted at a different
`/tmp/.mount_*` path each time the app runs and isn't visible to other programs.
A tool that has to know which themes an AppImage app can load, and how its
`GSTheme` default is set, must not run or mount the AppImage to find out. A
standalone theme-settings configurator is one such tool. So the AppImage
backend writes that information out as data.

The format was agreed with the theme-settings framework (gnustep-themes).

## The Two Files

| File | Where | Written |
| ---- | ----- | ------- |
| `gnustep-packager-theme-report.json`, `formatVersion: 2` | the payload's metadata root (`usr/<payload.metadataRoot>/`), inside the AppImage | while the AppDir is prepared, before appimagetool |
| `<artifact-base>.themes.json`, `schema: 1` | beside the AppImage in `outputs.packageRoot`, for example `App-1.2.3-x86_64.themes.json` | after appimagetool, so it can carry the AppImage's sha256 |

Both are written only when the payload has at least one theme, or a theme
input that should be there.

- **Inside the AppImage:** the report keeps every field of the formatVersion 1
  report that `themeInputs` provisioning writes. The stage's own v1 copy, which
  the theme-reuse check reads, isn't changed.
- **Beside the AppImage:** the sidecar is what a configurator reads. It holds
  the report's discovery fields, bound to one AppImage file by name and sha256.
  `Test-GpAppImageThemeSidecarBinding` checks that binding.
- **Not uploaded:** the packager writes the sidecar next to the AppImage and
  publishes nothing. Whether a release uploads it is up to the app's own
  release step.

## Sidecar Fields

```jsonc
{
  "schema": 1,
  "generatedAt": "2026-11-10T17:00:00.0000000Z",
  "generator": { "name": "gnustep-packager", "version": null },
  "appimage": { "fileName": "App-1.2.3-x86_64.AppImage", "sizeBytes": 123, "sha256": "<hex>", "architecture": "x86_64" },
  "package": { "id": "org.example.App", "name": "App", "version": "1.2.3" },
  "app": {
    "executable": "App",
    "bundleIdentifier": "org.example.App",
    "runtimeDomainHint": "org.example.App",
    "runtimeDomainHintSource": "bundleIdentifier"
  },
  "defaults": {
    "seedDomain": "org.example.App",
    "seedDomainMatchesRuntimeHint": true,
    "seeds": [ { "key": "GSTheme", "value": "Adwaita", "policy": "each-launch-if-absent", "rank": 1 } ],
    "env": [ { "key": "GSTheme", "value": "Adwaita", "policy": "ifUnset", "rank": null, "effect": "not read by gnustep-base/gui; informational only" } ],
    "globalDefaultsTheme": { "value": "Adwaita", "desktops": ["GNOME"], "rank": 2 }
  },
  "search": { "gnustepConfig": true, "userLibrary": "~/GNUstep/Library", "order": ["user", "payload"] },
  "themes": [
    {
      "name": "Adwaita",
      "themeId": "org.example.adwaita",
      "bundleId": "org.gnustep.Adwaita",
      "version": "14",
      "shortVersion": "1.4.0",
      "installation": {
        "bundledPath": "usr/GNUstep/System/Library/Themes/Adwaita.theme",
        "executableSha256": "<hex>",
        "executableStatus": "ok",
        "infoPlistSha256": "<hex>"
      },
      "source": { "repo": "https://...", "commit": "<sha>" },
      "origin": "themeInputs",
      "settings": {
        "status": "inline",
        "schemaVersion": 1,
        "sha256": "<hex>",
        "sizeBytes": 812,
        "inline": { },
        "path": "usr/GNUstep/System/Library/Themes/Adwaita.theme/Resources/ThemeSettings.plist",
        "note": null
      }
    }
  ]
}
```

### Themes

- **Which themes:** every `<Name>.theme` directory whose parent is named
  `Themes`, anywhere in the payload. Linked directories aren't followed while
  searching.
- **Links inside a theme:** before any file is read or hashed (the Info plist,
  `ThemeSettings.plist`, the executable), every link along its path is
  resolved. It is read only when its real location is a file inside the
  payload. One that leads outside the payload, or loops, isn't read: its status
  is `unavailable` and its contents and hash are null. A link that stays inside
  the payload is read normally. The same applies to the app's own Info plist.
  - `origin: "themeInputs"`: the theme came from the manifest's `themeInputs`.
    Its `source` has the repository and resolved commit.
  - `origin: "stage"`: the app's own stage script put the theme there. Its
    `source` is null.
  - A theme input whose bundle is missing from the payload is listed with
    `infoStatus: "missing"` and a null `installation`.
- **Identity:** these are kept apart, since two forks can share a theme id and
  version:
  - `themeId` is `ThemeIdentifier` from `ThemeSettings.plist`;
  - `bundleId`, `version` and `shortVersion` are `CFBundleIdentifier`,
    `CFBundleVersion` and `CFBundleShortVersionString` from the theme's Info
    plist;
  - `installation` holds the bundle's path and the sha256 of its executable
    and Info plist.
  - Any of these is null when its source is absent or unreadable.
  - `infoStatus` is `ok`, `absent`, `unavailable`, `tooLarge` or
    `malformed`, and `installation.executableStatus` is `ok`, `absent` or
    `unavailable`.
- **Settings:** the first of `Resources/ThemeSettings.plist`,
  `Contents/Resources/ThemeSettings.plist` and `ThemeSettings.plist` at the
  bundle root, the same order the theme-settings loader uses.
  - `status: "inline"`: the file is at most 256 KiB and parsed. `inline` holds
    its contents.
  - `status: "notInlined"`: the file is larger, and wasn't parsed or copied.
    Its theme id, schema version and settings are unavailable without reading
    the AppImage; `note` says so. A configurator must not present such a theme
    as fully described.
  - `status: "malformed"`: the file couldn't be parsed. `note` gives the
    reason.
  - `status: "unavailable"`: a link leads outside the payload or loops, so the
    file wasn't read. Its contents and hash are unavailable.
  - `settings` is null when the theme has no settings file.

### Domains

- **`seedDomain`:** exactly the domain AppRun writes `GSTheme` to:
  `packagedDefaults.appDomain.domain`, else `package.id`. It's null when the
  package seeds no theme.
- **`runtimeDomainHint`:** the domain the running app reads. gnustep-base uses
  the main bundle's `CFBundleIdentifier`, and the process name when there is
  none.
  - The hint is the app Info plist's `CFBundleIdentifier`, else the launch
    entry's file name. `runtimeDomainHintSource` says which.
  - If the app bundle's Info plist can't be read (malformed, too large, or
    behind a link that leaves the payload), the hint is null with source
    `unknown`, rather than a guess.
- **`seedDomainMatchesRuntimeHint`:** null when either side is unknown. When
  it's false, a configurator should warn: the packaged default isn't in the
  domain the app reads.

### GSTheme Sources

- **`seeds`** (rank 1): AppRun runs `defaults read <domain> GSTheme` on every
  launch, and writes the packaged value only when the key is absent.
  - A value the user set stays.
  - A key the user removes comes back at the next launch.
  - So "remove" isn't a meaningful action for a seeded theme; choosing another
    theme is.
- **`globalDefaultsTheme`** (rank 2): `GlobalDefaults.plist` next to the
  AppImage's own `GNUstep.conf`, from `backends.appimage.gnustepConfig.defaultTheme`.
  gnustep-base reads it below the user's own defaults.
- **`env`** (no rank): AppRun exports `GSTheme` (from `launch.env` or
  `packagedDefaults.defaultTheme`), but nothing in GNUstep reads it:
  - gnustep-gui picks the theme from `NSUserDefaults` alone;
  - the defaults search list has no environment domain (checked against
    libs-base 6479d4483 and libs-gui 9bd1123a1);
  - AppRun doesn't turn the variable into a `-GSTheme` argument.
  A `-GSTheme` argument given at launch outranks all of these, and isn't
  recorded.

### Search

- **`gnustepConfig: true`:** the AppImage's own `GNUstep.conf` maps the system,
  local and network domains into the payload. The user's Library stays
  `~/GNUstep/Library`, or the app-specific path the manifest sets. The user's
  themes come first and can shadow bundled ones.
- **`gnustepConfig: false`:** the app reads the configuration its gnustep-base
  was built with, so the host's domains apply (`host-configured`).

## Treat It as Data

Everything copied from a theme (names, versions, settings) is untrusted text.
Consumers should display it, never execute it or load a theme's code into
another process. A theme's executable is built against the GNUstep libraries
inside its own AppImage.
