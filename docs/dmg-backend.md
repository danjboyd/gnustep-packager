# macOS DMG Backend

## Purpose
The `dmg` backend packages a staged macOS application bundle into a
compressed, read-only disk image: the familiar "drag the app onto
Applications" window. It follows the same stage-first pipeline as the MSI and
AppImage backends (`build -> stage -> package -> validate`) and only reads the
staged payload.

It is built entirely on Apple's own tools: `hdiutil`, `codesign`, `ditto`,
`plutil`, `lipo`, `spctl`, `osascript` (optional), and `xcrun notarytool` /
`xcrun stapler` (optional). It does not need `create-dmg`, Homebrew, or any
other third-party tool.

## Support Boundary And Design Tradeoffs
This backend is a deliberate expansion of the original GNUstep-on-Windows and
GNUstep-on-Linux scope (see [Roadmap.md](../Roadmap.md), phase 17):

- **It packages a native macOS `.app` bundle.** On macOS a GNUstep-derived
  application is usually built against Apple's AppKit (the GNUstep sources,
  compiled with Xcode's clang) rather than against a GNUstep runtime. Such a
  bundle carries its own launch behavior (`Info.plist`, `Contents/MacOS`,
  frameworks) and code signature.
- **The GNUstep launch contract is not rendered.** There is no generated
  launcher on macOS, so `launch.env`, `launch.pathPrepend`,
  `launch.resourceRoots`, `launch.arguments`, `packagedDefaults`,
  `themeInputs`, and `updates` are not applied. The backend lists every such
  setting it ignores as a `NOTE` in the package log and in the metadata
  sidecar (`ignoredSettings`) rather than failing, and the core model stays
  unchanged. Use `platformOverrides.macos` (below) to drop these settings from
  the macOS view of the manifest when they only make sense on Linux or
  Windows.
- **Bundling a GNUstep runtime inside a macOS bundle is out of scope** for
  now. A stage step may still do it, but the backend does not validate a
  runtime closure the way the AppImage backend does.
- **The staged signature is preserved by default.** Re-signing changes the
  app's identity for macOS privacy grants (Full Disk Access, Automation), so
  the backend keeps the signature the build produced unless
  `signing.resign` is `true`.
- **Finder layout uses AppleScript and is optional.** Writing a `.DS_Store`
  without Finder would need a third-party library. The backend asks Finder to
  lay out the one volume it just mounted; anywhere that is not possible (CI,
  SSH session, no Automation permission) the image falls back to Finder's
  default window. The resulting image is functionally the same.

The staged payload contract is unchanged: `app/<Name>.app`, `runtime/` (may be
empty for a native bundle), `metadata/`.

## Host Requirements
- macOS 13 or later (Apple Silicon or Intel); verified on macOS 26.5 with
  Xcode 26.4
- PowerShell 7+ (`pwsh`)
- Xcode or the Command Line Tools (for `lipo`, `codesign`, `xcrun`)
- For the Finder layout: a logged-in GUI (Aqua) session and permission for
  the terminal to control Finder (System Settings > Privacy & Security >
  Automation). The backend checks this permission without prompting.
- For notarization: a Developer ID Application certificate in the keychain and
  a `notarytool` keychain profile

## Manifest
Enable the backend under `backends.dmg`. All fields are optional except
`enabled`; the defaults live in
[defaults/backends/dmg/defaults.json](../defaults/backends/dmg/defaults.json).

```json
{
  "launch": {
    "entryRelativePath": "app/MyApp.app/Contents/MacOS/MyApp",
    "workingDirectory": "app"
  },
  "backends": {
    "dmg": {
      "enabled": true,
      "appBundleName": "{name}.app",
      "volumeName": "",
      "artifactNamePattern": "{name}-{version}-macos-{arch}.dmg",
      "filesystem": "APFS",
      "format": "UDZO",
      "applicationsLink": true,
      "backgroundImageRelativePath": "",
      "finderLayout": "auto",
      "window": {
        "x": 200, "y": 120, "width": 600, "height": 400,
        "iconSize": 128, "textSize": 12,
        "appIconPosition": { "x": 150, "y": 190 },
        "applicationsIconPosition": { "x": 450, "y": 190 },
        "noticeIconPosition": { "x": 300, "y": 330 }
      },
      "noticeReport": { "enabled": false, "fileName": "THIRD-PARTY-NOTICES.txt" },
      "signing": {
        "identity": "-",
        "resign": false,
        "deep": true,
        "hardenedRuntime": true,
        "entitlementsPath": "",
        "keychain": "",
        "signDmg": true,
        "additionalArguments": []
      },
      "notarization": {
        "enabled": false,
        "keychainProfileEnvVar": "GP_NOTARY_KEYCHAIN_PROFILE",
        "staple": true,
        "required": false
      },
      "validation": {
        "requireSignature": true,
        "requireGatekeeperAcceptance": false
      },
      "smoke": {
        "enabled": false,
        "startupSeconds": 5,
        "arguments": [],
        "environment": {}
      }
    }
  }
}
```

| Field | Meaning |
| --- | --- |
| `appBundleName` | Bundle under `payload.appRoot`; tokens `{name}`, `{version}`, `{packageId}` |
| `volumeName` | Mounted volume name; empty uses `package.displayName` (or `package.name`) |
| `artifactNamePattern` | Tokens `{name}`, `{version}`, `{packageId}`, `{backend}`, `{arch}`. `{arch}` is `universal` when the main executable has arm64 and x86_64 slices (`lipo -archs`), else the single slice name |
| `filesystem` | `APFS` (default) or `HFS+` (for images that must mount on macOS 10.12 or older) |
| `format` | `UDZO` (zlib level 9, default, mounts everywhere) or `ULFO` (lzfse, smaller, macOS 10.11+) |
| `applicationsLink` | Adds the `Applications -> /Applications` symlink |
| `backgroundImageRelativePath` | Stage-relative PNG/TIFF copied to `.background/` and used as the window background (needs the Finder layout) |
| `finderLayout` | `auto`: lay out the window when a GUI session and Finder automation permission are available, else skip with a log line. `applescript`: always try, fail packaging if it fails. `off`: never. `GP_DMG_FINDER_LAYOUT` overrides it per run |
| `window.*` | Window bounds, icon and text size, and icon positions (app on the left, Applications on the right by default) |
| `noticeReport` | When enabled, writes a `THIRD-PARTY-NOTICES.txt` at the volume root from `compliance.runtimeNotices`, with the staged license texts inline |
| `signing.identity` | `codesign` identity; `-` is ad-hoc. Any other string (e.g. `Developer ID Application: Name (TEAMID)`) is passed through |
| `signing.resign` | `false` keeps the staged app's signature (after verifying it). `true` signs the volume copy with `--force`, `--deep` (`deep`), `--options runtime` (`hardenedRuntime`), `--entitlements` (`entitlementsPath`), `--timestamp` (real identities) or `--timestamp=none` (ad-hoc), `--keychain`, and any `additionalArguments` |
| `signing.entitlementsPath` | Entitlements plist, relative to the manifest directory |
| `signing.signDmg` | Sign the final image too when the identity is not ad-hoc |
| `notarization.enabled` | Submit the image with `xcrun notarytool submit --wait`, then `xcrun stapler staple` (`staple`) |
| `notarization.keychainProfileEnvVar` | Name of the environment variable that holds the `notarytool` keychain profile name. Never put the profile, an Apple ID or a password in the manifest |
| `notarization.required` | Fail packaging when notarization cannot run (no credentials or ad-hoc identity). Default `false`: skip with a log line |
| `validation.requireSignature` | Fail when `codesign --verify --deep --strict` fails |
| `validation.requireGatekeeperAcceptance` | Fail when `spctl --assess` rejects the app. Leave `false` until a Developer ID and notarization are in place |
| `smoke.*` | Launch smoke settings. Runs with `-RunSmoke` or when `smoke.enabled` is `true` |

Schema: [schemas/gnustep-packager.schema.json](../schemas/gnustep-packager.schema.json)
(`backends.dmg`). Semantic checks are in `Test-GpManifest`.

### Sharing one manifest with Linux and Windows
A GNUstep app that ships an AppImage on Linux and a native bundle on macOS
keeps one manifest and adds a `platformOverrides.macos` overlay for the
pipeline, payload and validation differences:

```json
{
  "platformOverrides": {
    "macos": {
      "profiles": [],
      "pipeline": {
        "build": { "command": "make -C macos" },
        "stage": { "command": "./scripts/package-stage-macos.sh dist/stage", "outputRoot": "dist/stage" }
      },
      "launch": {
        "entryRelativePath": "app/MyApp.app/Contents/MacOS/MyApp",
        "workingDirectory": "app",
        "env": null
      },
      "validation": {
        "smoke": { "requiredPaths": ["app/MyApp.app/Contents/Info.plist"] },
        "packageContract": null,
        "installedResult": { "requiredContent": [{ "kind": "notice-report" }], "requiredPaths": [] }
      },
      "compliance": { "runtimeNotices": [ { "name": "MyApp", "license": "MIT", "stageRelativePath": "metadata/licenses/MyApp.txt" } ] }
    }
  }
}
```

See [manifest.md](manifest.md#platformoverrides) for the merge rules. The
target platform is `-Platform` when given, otherwise the requested backend's
platform (`dmg` -> `macos`), otherwise the host, so `build` and `stage` on a
Mac pick up the macOS commands automatically.

## Commands

```powershell
./scripts/gnustep-packager.ps1 -Command build -Manifest <manifest>
./scripts/gnustep-packager.ps1 -Command stage -Manifest <manifest>
./scripts/gnustep-packager.ps1 -Command validate -Manifest <manifest>
./scripts/gnustep-packager.ps1 -Command package -Manifest <manifest> -Backend dmg
./scripts/gnustep-packager.ps1 -Command validate -Manifest <manifest> -Backend dmg -RunSmoke

# or all of it
./scripts/run-packaging-pipeline.ps1 -Manifest <manifest> -Backend dmg -RunSmoke
```

Reference fixture:
[examples/sample-macos](../examples/sample-macos/README.md).

## What `package` Does
1. Checks that `<stage>/<appRoot>/<appBundleName>` has `Contents/Info.plist`
   and the `CFBundleExecutable`, reads the version, and detects the
   architectures with `lipo`. A `CFBundleShortVersionString` that differs from
   `package.version` is a warning.
2. Copies the bundle into a work folder (`dist/tmp/dmg/<timestamp>/volume`)
   with `ditto`, which keeps symlinks, extended attributes and the signature.
   The stage is never modified.
3. Re-signs the copy when `signing.resign` is `true`; otherwise verifies the
   existing signature (`codesign --verify --deep --strict`).
4. Adds the `Applications` symlink, the optional background under
   `.background/`, and the optional notice report.
5. `hdiutil create -srcfolder ... -format UDRW` builds a read-write image of
   the folder (20% plus 32 MB of headroom).
6. Finder layout (when not skipped): the image is attached read-write, Finder
   lays out that volume's window through
   [backends/dmg/assets/finder-layout.applescript](../backends/dmg/assets/finder-layout.applescript)
   (with a timeout), the backend waits for `.DS_Store`, removes `.fseventsd`,
   and detaches.
7. `hdiutil convert` writes the compressed read-only image.
8. Signs the image (non-ad-hoc identities with `signDmg`), then notarizes and
   staples it when enabled and credentials are present.
9. Writes the `.metadata.json` and `.diagnostics.txt` sidecars, deletes the
   read-write image and the volume folder, and detaches anything it attached,
   also on failure.

## What `validate` Does
1. `hdiutil verify` (checksum) and `hdiutil imageinfo` (format matches the
   manifest).
2. Records the image's signature and whether a notarization ticket is stapled.
3. Attaches the image read-only, `-nobrowse`, at a temporary mount point under
   the validation log directory (invisible to Finder).
4. Checks the app bundle, its executable, the `Applications` link, the
   background, and whether a `.DS_Store` layout is present.
5. `codesign --verify --deep --strict` on the mounted app, plus the signature
   details (ad-hoc or authorities, team, hardened runtime).
6. `spctl --assess --type execute` on the mounted app. A rejection is recorded
   as `info` (an ad-hoc signature is always rejected) unless
   `validation.requireGatekeeperAcceptance` is `true`.
7. `validation.installedResult` assertions against the volume root. The
   `notice-report` kind checks `<volume>/<noticeReport.fileName>`.
8. Launch smoke (with `-RunSmoke` or `smoke.enabled`): runs
   `Contents/MacOS/<executable>` directly with `smoke.arguments` and
   `smoke.environment`. Still running at the end of `startupSeconds`, or a
   clean exit, passes; it is then killed. A non-zero exit fails. The app's
   window does appear during the smoke run on a desktop session.
9. Detaches the image and removes the mount point, including after a failure,
   and writes `validation-summary.json`.

Each check is printed as `PASS`, `FAIL`, `WARN`, `INFO` or `SKIP`.

## Artifact Layout

```text
dist/packages/
  <name>-<version>-macos-<arch>.dmg
  <name>-<version>-macos-<arch>.metadata.json
  <name>-<version>-macos-<arch>.diagnostics.txt
dist/logs/package-dmg/<timestamp>.log
dist/logs/validate-dmg/<timestamp>.log
dist/logs/validate-dmg/validation-summary.json
dist/logs/validate-dmg/smoke.log
dist/tmp/dmg/<timestamp>/finder-layout.log
```

Volume contents:

```text
<Name>.app
Applications -> /Applications
THIRD-PARTY-NOTICES.txt     (noticeReport.enabled)
.background/<image>         (backgroundImageRelativePath)
.DS_Store                   (Finder layout applied)
```

The metadata sidecar records the artifact hash and size, format, filesystem,
volume name, bundle identifier, versions, architectures, Finder layout result,
signing identity and the app's signature details, the notarization status
(`disabled`, `skipped-no-credentials`, `skipped-ad-hoc`, `accepted`), ignored
manifest settings, warnings, tool paths and host details.

## Signing And Notarization
Without an Apple Developer account the useful configuration is the default:
ad-hoc identity (`-`), keep the build's signature, notarization disabled.
Such an image runs on the Mac that built it; on another Mac Gatekeeper blocks
the first launch of a downloaded copy until the user allows it (System
Settings > Privacy & Security > Open Anyway) or removes the quarantine flag.

With a Developer ID later:

1. Set `signing.identity` to the Developer ID Application identity, and
   `signing.resign` to `true` if the build does not sign with it already
   (keep `hardenedRuntime` on; notarization requires it). Point
   `entitlementsPath` at the app's entitlements.
2. Store notary credentials once per machine or runner:
   `xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team> --password <app-specific password>`
   (or `--key`/`--key-id`/`--issuer` for an App Store Connect API key).
3. Set `notarization.enabled` to `true` and `keychainProfileEnvVar` to a
   variable name such as `MYAPP_NOTARY_PROFILE`; export
   `MYAPP_NOTARY_PROFILE=<profile>` where packaging runs.
4. Optionally set `notarization.required` and
   `validation.requireGatekeeperAcceptance` to `true` for release builds so
   they fail closed.

The backend notarizes the DMG (which covers the app inside it) and staples the
ticket to the DMG. If `notarytool` reports anything other than `Accepted`, the
backend fetches `notarytool log <id>` into the package log and fails. When the
environment variable is unset, or the identity is ad-hoc, notarization is
skipped with a log line such as:

```text
Notarization skipped: environment variable LINDIRSTAT_NOTARY_PROFILE is not set, and the signing identity is ad-hoc ('-'). Store credentials with 'xcrun notarytool store-credentials <profile>' and export LINDIRSTAT_NOTARY_PROFILE=<profile>.
```

See also [signing.md](signing.md).

## CI Usage
GitHub-hosted `macos-latest` runners have everything the backend needs.
`validate-repo.yml` runs the macOS fixture (`macos-validation` job): Pester
tests, then the shared pipeline with `-Backend dmg -RunSmoke`. The `CI`
environment variable makes `finderLayout: auto` skip the Finder layout, so the
runner never needs Automation permission.

The reusable `package-gnustep-app.yml` workflow does not have a `dmg` path
yet. Downstream repos can use
[examples/downstream/package-dmg.yml](../examples/downstream/package-dmg.yml),
which checks out the packager, optionally imports a Developer ID certificate
and stores a notary profile from secrets into a temporary keychain, exports the
profile name in the variable the manifest names, and runs
`run-packaging-pipeline.ps1 -Backend dmg -RunSmoke`.

## Troubleshooting
- **"Staged app bundle not found"**: run `stage`, and check
  `payload.appRoot` and `backends.dmg.appBundleName`.
- **"code signature does not verify"**: the build changed the bundle after
  signing (or did not sign it). Fix the build, or set `signing.resign`.
- **Finder layout skipped or failed**: see the package log and
  `dist/tmp/dmg/<timestamp>/finder-layout.log`. Allow the terminal to control
  Finder, or set `finderLayout` to `off`. The image is still valid.
- **Leftover mounts**: `hdiutil info` lists attached images; the backend
  detaches by device (retrying with `-force`) and logs any image it could not
  detach.
- **Gatekeeper `rejected`**: expected for ad-hoc signatures; see Signing.

## Known Limitations
- No Developer ID has been available while building this backend, so the
  `notarytool` and `stapler` path and Developer ID signing of the image are
  implemented but have not been run against Apple's service.
- The Finder layout needs a GUI session and Finder automation permission; on
  CI or over SSH the image uses Finder's default window.
- No custom volume icon (`.VolumeIcon.icns`) yet; it would need `SetFile`,
  which Apple has deprecated.
- No license agreement shown on mount (Apple removed the `hdiutil udifrez`
  route for that).
- The updater runtime config and update-feed sidecars are not emitted for DMG
  artifacts.
- The reusable GitHub workflow does not cover `dmg` yet (see CI Usage).
- One app bundle per image.
