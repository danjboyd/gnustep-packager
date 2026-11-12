# Bundling a Theme and Its Fonts

Can a manifest put a GNUstep theme, and the fonts it asks for, into an app's
installers and make it the theme the app starts with? This note answers that
for the MSI and AppImage backends. The example is Gumdrop
(`danjboyd/gnustep-funthemes`, `Themes/Gumdrop`). Its `GSThemeDomain` sets
`NSFont = DejaVuSans` and `NSBoldFont = DejaVuSans-Bold`. Windows has no
DejaVu, and some Linux distributions don't either.

Status: findings from 2026-11-11. Gap 1, fonts for the MSI, is now
`backends.msi.fonts.bundle` (2026-11-12).

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

## A Manifest Sketch (AppImage, Works Today)

```json
{
  "themeInputs": [
    {
      "name": "Gumdrop",
      "repo": "https://github.com/danjboyd/gnustep-funthemes.git",
      "ref": "<tag or commit>",
      "platforms": ["linux"],
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
            "licenseFile": "/usr/share/doc/fonts-dejavu-core/copyright"
          }
        ]
      }
    }
  }
}
```

The build shell's environment sets `GNUSTEP_HOME` to the theme's install
root (`Get-GpThemeBuildShellConfig`), and the command passes it to
`make install` explicitly because gnustep-make otherwise uses `$(HOME)`. The
default command writes the path literally because `GNUstep.sh` unsets
`GNUSTEP_HOME`. If the manifest's `bootstrapCommands` source it, write the
path literally too. The same `themeInputs`
entry with `"platforms": ["windows"]` covers the MSI, with the same font entry
under `backends.msi.fonts.bundle` (Windows paths to the TTFs and license).
