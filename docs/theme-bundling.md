# Bundling a Theme and Its Fonts

Can a manifest put a GNUstep theme, and the fonts it asks for, into an app's
installers and make it the theme the app starts with? This note answers that
for the MSI and AppImage backends. The example is Gumdrop
(`danjboyd/gnustep-funthemes`, `Themes/Gumdrop`). Its `GSThemeDomain` sets
`NSFont = DejaVuSans` and `NSBoldFont = DejaVuSans-Bold`. Windows has no
DejaVu, and some Linux distributions don't either.

Status: findings from 2026-11-11. Gap 1, fonts for the MSI, is now
`backends.msi.fonts.bundle` (2026-11-12), and Windows CI tests it end to end
(2026-11-13). For the steps an app author follows, see
[How To](#how-to-a-theme-and-its-fonts-in-both-installers).

## Summary

| Step | AppImage | MSI |
| --- | --- | --- |
| Build the theme from its repository | yes: `themeInputs` | yes: `themeInputs`, the first path it was built for |
| Put it where the app finds it | yes: `<gnustepConfig.systemRoot>/Library/Themes` or `runtime/lib/GNUstep/Themes` | yes: the staged runtime's themes directory |
| Start the app with it | yes: `packagedDefaults.defaultTheme` seeds `GSTheme` in the app's domain on every launch if absent | yes: the launcher seeds `GSTheme` with the bundled `defaults.exe` on first launch, plus a `GSTheme` environment fallback |
| Ship the fonts it names | yes: `backends.appimage.fonts.bundle` | yes: `backends.msi.fonts.bundle` (was gap 1) |
| Tools can see the bundled themes | yes: `<artifact-base>.themes.json` | no sidecar (gap 4) |

So Gumdrop is a manifest-only change on both an AppImage and an MSI.

## How Windows Finds Fonts

The managed toolchain's Windows `gnustep-back` is MSYS2's
`mingw-w64-clang-x86_64-gnustep-back` 0.32.0-6, the version gnustep-cli-new
v0.1.5's Windows input manifest pins. Its
`libgnustep-back-032.dll` imports `libcairo-2.dll`, `libfontconfig-1.dll` and
`libfreetype-6.dll`, so it is the cairo backend. It finds fonts through
fontconfig, not GDI. libs-back's own default on MinGW is `winlib`, which uses
GDI, so another toolchain could differ.

It follows that a font only has to be in a directory that the app's
`fonts.conf` lists. Nothing is installed into Windows. The MSI launcher
already sets `FONTCONFIG_FILE` and `FONTCONFIG_PATH` when
`runtime\etc\fonts\fonts.conf` exists (`docs/msi-launcher-design.md`).
`examples/sample-gui` copies MSYS2's `clang64\etc\fonts\fonts.conf` into the
stage. That file lists `WINDOWSFONTDIR`, which has no DejaVu.

## Gaps

1. **Fonts for the MSI: done.** `backends.msi.fonts.bundle` takes the
   AppImage's entries. It copies the TTFs under `runtime\share\fonts\<name>\`
   and the licenses into the notice report. It writes a `runtime\etc\fonts\fonts.conf`
   that includes a staged one (kept as `fonts.app.conf`) or lists
   `WINDOWSFONTDIR`, adds the bundled directory as
   `<dir prefix="relative">../../share/fonts</dir>`, and caches under
   `LOCAL_APPDATA_FONTCONFIG_CACHE`. It covers the cairo backend only. A
   `winlib` build finds fonts through GDI and would need them registered with
   `AddFontResourceEx`, which nothing does today. On 2026-11-12 winuitheme's
   check of Gumdrop on Windows saw DejaVuSans missing and a fall back to Tahoma.
   That matches the fontconfig enumerator's fallback order
   (`FCFontEnumerator -defaultSystemFontName`: DejaVuSans, then Bitstream
   Vera, FreeSans, Tahoma).
2. **A repository with several themes needs `build.command`.**
   funthemes has no top-level makefile; Gumdrop builds from `Themes/Gumdrop`
   and uses `../../Shared`. The default build command, `make clean; make;
   make install ...`, runs at the checkout's root. A manifest can set
   `build.command`, for example
   as in the sketch below, but it then has to pass the install path that the
   default command fills in. A
   `themeInputs[].sourceSubdirectory` field would remove that.
3. **Gumdrop's look on Windows is untested.** Its README and checks cover X11:
   client-decorated windows, `GSBackBorderlessWindowAlpha` and popover
   shadows. The win32 server ignores those X11 defaults, so Gumdrop may draw
   differently on Windows even with the right fonts. Gumdrop has no tag yet
   either, and `themeInputs` should pin a tag or commit for releases. These
   are theme-side, for the fun-themes owner.
4. **The MSI has no theme sidecar.** `<artifact-base>.themes.json`
   (`docs/appimage-theme-metadata.md`) is AppImage-only. The in-payload
   `metadata/gnustep-packager-theme-report.json` is written for both.
5. **DMG:** `themeInputs` for macOS aren't provisioned into a native app
   bundle. The backend notes that and ignores them.

## How To: A Theme and Its Fonts in Both Installers

Three parts of the manifest are involved, and none of them needs packager
code of your own:

1. `themeInputs` builds the theme and puts it in the staged runtime. One
   entry with `"platforms": ["linux", "windows"]` covers both installers;
   use one entry per platform if they need different builds.
2. `"default": true` on that entry makes it the theme the app starts with on
   each of its platforms. You can also name it in
   `packagedDefaults.defaultTheme`. The user's own `GSTheme` setting still
   wins.
3. `fonts.bundle` ships the fonts the theme names. It is set per backend:
   `backends.appimage.fonts.bundle` and `backends.msi.fonts.bundle` take the
   same entries. Each one gives a `name`, the font `files`, and a required
   `licenseFile`, plus an optional `license` and `homepage` for the notice
   report.

### Where the font files come from

Paths in `fonts.bundle` are relative to the manifest, or absolute. The build
host has to have the files:

- **Linux (AppImage):** the distribution's package, for example
  `fonts-dejavu-core` on Debian and Ubuntu:
  `/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf`, license
  `/usr/share/doc/fonts-dejavu-core/copyright`.
- **Windows (MSI):** MSYS2's `mingw-w64-clang-x86_64-ttf-dejavu`, which puts
  the fonts in `clang64\share\fonts\TTF\` and the license under
  `clang64\share\licenses\`. MSYS2's location differs between hosts, so
  have the stage script copy them to a folder next to the manifest and point
  `fonts.bundle` there. `examples/sample-gui/scripts/stage-fixture.ps1` does
  this, copying them into `dist/fixture-fonts`.

A font can also live in the app's own repository, with its license beside
it. That needs no host package at all.

### Example (Gumdrop)

```json
{
  "themeInputs": [
    {
      "name": "Gumdrop",
      "repo": "https://github.com/danjboyd/gnustep-funthemes.git",
      "ref": "<tag or commit>",
      "platforms": ["linux", "windows"],
      "required": true,
      "default": true,
      "build": { "command": "cd Themes/Gumdrop && make clean && make && make install GNUSTEP_INSTALLATION_DOMAIN=USER GNUSTEP_HOME=\"$GNUSTEP_HOME\"" }
    }
  ],
  "backends": {
    "appimage": {
      "fonts": {
        "bundle": [
          {
            "name": "DejaVu",
            "files": ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
            "licenseFile": "/usr/share/doc/fonts-dejavu-core/copyright",
            "license": "Bitstream-Vera AND LicenseRef-DejaVu-Public-Domain"
          }
        ]
      }
    },
    "msi": {
      "fonts": {
        "bundle": [
          {
            "name": "DejaVu",
            "files": ["dist/fonts/DejaVuSans.ttf", "dist/fonts/DejaVuSans-Bold.ttf"],
            "licenseFile": "dist/fonts/LICENSE",
            "license": "Bitstream-Vera AND LicenseRef-DejaVu-Public-Domain"
          }
        ]
      }
    }
  }
}
```

The AppImage entry names the system paths directly. The MSI entry names a
folder the stage script fills from MSYS2. Adwaita works the same way: see
`examples/downstream/theme-demos/adwaita`, which bundles DejaVu in its
AppImage.

### Checking the result

- Add the font and its license to `validation.installedResult.requiredPaths`,
  so the installed package's validation fails if they're missing:
  `runtime/share/fonts/dejavu/DejaVuSans.ttf`, `runtime/etc/fonts/fonts.conf`
  and `metadata/licenses/fonts/dejavu.txt`. The paths are relative to the
  payload, so the same entries work for the MSI and the AppImage (the
  AppImage's `usr/`).
- `THIRD-PARTY-NOTICES.txt` lists the font as `DejaVu (font)`.
- The tested example is `examples/sample-gui`. It bundles MSYS2's DejaVu and
  WinUXTheme as its default theme. On every run, `validate-repo.yml`'s
  Windows job runs `fc-list` with the same `FONTCONFIG_FILE` and
  `FONTCONFIG_PATH` the launcher sets, and it must list DejaVu Sans from the
  MSI's own `runtime\share\fonts\dejavu`.

### Limits

- Windows: the MSI's fonts reach a `gnustep-back` that is built with cairo
  and fontconfig, as MSYS2's (the managed toolchain's) is. A `winlib` (GDI)
  backend doesn't read fontconfig (gap 1).
- The theme's own look on each platform is the theme's business. Gumdrop's
  X11 defaults don't apply on Windows (gap 3).
- `themeInputs` don't reach a DMG (gap 5).

### Theme build commands

The build shell's environment sets `GNUSTEP_HOME` to the theme's install
root (`Get-GpThemeBuildShellConfig`), and the command passes it to
`make install` explicitly because gnustep-make otherwise uses `$(HOME)`. The
default command writes the path literally because `GNUstep.sh` unsets
`GNUSTEP_HOME`. If the manifest's `bootstrapCommands` source it, write the
path literally too. For the MSI the
same command runs in the MSYS2 shell. Building Gumdrop there hasn't been
tried yet (gap 3).
