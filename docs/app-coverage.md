# App Coverage

What gnustep-packager builds today for each downstream app, by backend. This
is a snapshot taken on 2026-11-11 from each app's latest release assets and its
CI workflows. Re-check it before using it for release planning.

Legend:

- **packager**: built by a gnustep-packager backend, with a released artifact
  as evidence
- **app-script**: the app ships this format, but builds it with its own
  scripts rather than gnustep-packager
- **configured**: the manifest or workflow has it, but no released artifact
  exists yet
- **example**: `examples/downstream/` has a tested setup, but the app's repo
  doesn't use it yet
- **none**: no path today
- *(CI)*: the evidence comes from CI runs and release assets only; nobody ran
  it by hand on a local host (every DMG cell)

## Desktop apps

| App | AppImage | MSI | DMG | Packager pin | Linux provenance | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| ObjcMarkdown (MarkdownViewer) | packager (v0.2.7) | packager (v0.2.7, plus a portable ZIP) | app-script *(CI)*: `macos/Makefile` `dmg`, UDZO/HFS+ | reusable workflow `@v0.1.7` (AppImage), `@v0.1.4` (MSI) | not published | Also ships a Flatpak built outside gnustep-packager. The AppImage is built in the app's own CI image |
| ScreenshotTool | packager (v0.3.6) | packager (v0.3.6, plus a portable ZIP) | app-script *(CI)*: `scripts/package_macos_dmg.sh`, ULFO | reusable workflow `@v0.1.8` | packager `provenance.json`, with the app's own toolchain lock (`screenshottool`) | DMG script adds an "Opening an unsigned app" note, a `.sha256` file and a Sparkle appcast |
| LinDirStat | configured | configured | configured *(CI)*: DMG backend via `scripts/ci-release-macos.sh` | pinned checkout | n/a | No GitHub release yet. This is the only app wired to the DMG backend |
| PerformanceDashboard | packager (v0.1.5) | configured (manifest only) | none | pinned checkout (`v0.1.7`) | the app's own `provenance.json` format | Release gate uses `--require-backend appimage`. Builds libs-back itself, with two carried patches, over the gnustep-cli-new v0.1.3 toolchain |
| SpreadsheetApp | configured | configured (`release-msi.yml`) | none | reusable workflow `@main` (unpinned) | n/a | No release yet |
| Adwaita ThemeDemo | example (`theme-demos/adwaita`) | none | n/a | none | n/a | `Examples/ThemeDemo` in plugins-themes-Adwaita |
| WinUITheme ThemeDemo | n/a | example (`theme-demos/winuitheme`) | n/a | none | n/a | `Examples/ThemeDemo` in plugins-themes-winuitheme |
| Gorm | example (`gnustep-apps/gorm`) | none | none | none | n/a | Upstream GNUstep app, tag `gorm-1_5_0` |
| ProjectCenter | example (`gnustep-apps/projectcenter`) | none | none | none | n/a | Upstream GNUstep app, tag `projectcenter-0_7_0` |
| GWorkspace | example (`gnustep-apps/gworkspace`) | none | none | none | n/a | Upstream GNUstep app, tag `gworkspace-1_0_0` |
| SystemPreferences | example (`gnustep-apps/systempreferences`) | none | none | none | n/a | Upstream GNUstep app, tag `systempreferences-1_2_1` |
| Terminal | example (`gnustep-apps/terminal`) | none | none | none | n/a | GAP app, `gnustep/gap` commit `220860a` (the repo has no tags) |

## Command-arrow word moves (PR #83)

`gnustepConfig.keyBindings` with the `CommandWordMoves` preset belongs next to
the Ctrl=Command remap (`GSFirstCommandKey: "Control_L"`). These apps set the
remap on Linux and would turn it on once the libs-gui Command-modifier carry
lands:

| App | Where it sets the remap today | Change to turn it on |
| --- | --- | --- |
| ScreenshotTool | `backends.appimage.gnustepConfig.globalDefaults` | Add `keyBindings: [{ "preset": "CommandWordMoves" }]` |
| ObjcMarkdown | `packagedDefaults.appDomain` | Add `gnustepConfig.systemRoot` and `keyBindings` |
| LinDirStat | `scripts/package-stage.sh` (hand-written defaults) | Move the remap into `gnustepConfig`, then add `keyBindings` |
| PerformanceDashboard | `scripts/package-stage.sh` (hand-written defaults) | Same as LinDirStat |

No app sets the remap for MSI, so Windows is left out for now.

## Non-desktop consumers

| Consumer | Format today | Packager path | Notes |
| --- | --- | --- | --- |
| Arlen | `arlen-<ver>-windows-x64.zip` built by Arlen's own CI | none | Linux headless runtime delivery is proposed as Roadmap Phase 19 (PR #77), waiting on Dan |
| Swift apps (gnustep-swift) | none | none | Needs the `linux-amd64-clang-swift` flavor's runtime closure; hosting the toolchain archive is waiting on Dan's decision |

## Gaps, ranked

1. **The DMG backend has no released consumer.** Both apps that ship DMGs
   build them with their own scripts. The things they do that the backend
   doesn't:
   - Extra files at the volume root, such as ScreenshotTool's unsigned-app
     note. The backend writes only the app, the `Applications` link, the
     background and the notice report.
   - A `.sha256` sidecar file. The backend records the hash only in
     `.metadata.json`.
   - A Sparkle appcast for macOS updates. The update-feed contract accepts
     Sparkle keys, but the DMG backend emits no feed.
2. **PerformanceDashboard has no MSI.** This is on the app side: its Windows
   workflows build review and candidate artifacts, but no release has shipped
   an MSI, and its release gate requires only AppImage.
3. **The theme repos don't use the demo examples yet.** Both setups are tested
   in `examples/downstream/theme-demos`, and each theme repo still has to adopt
   its own.
4. **ObjcMarkdown publishes no Linux provenance.** Its packager pin writes
   `<artifact-base>.provenance.json` into the package root (it is on by
   default), but the release attaches only the AppImage, `.zsync`,
   `.metadata.json`, `.debug.tar.gz`, `.diagnostics.txt` and
   `.update-feed.json`. Nobody outside its CI can tell which libs-gui and
   libs-back a release shipped. Attaching the provenance file fixes it; no
   manifest change is needed.
5. **No app attaches the theme sidecar yet.** `<artifact-base>.themes.json`
   (`docs/appimage-theme-metadata.md`) is on `main` only, not in a tagged
   release, and the reusable workflow uploads it with the rest of the package
   root. Each app's release step decides whether to attach it.
6. **SpreadsheetApp tracks `@main`.** Any packager change can break its
   release. It should pin a tag.
5. **Arlen and the Swift apps** wait on decisions (PR #77, the archive
   hosting). They are not engineering gaps in this repo.

The DMG items in gap 1 are packager-side and small. The other gaps belong to
the app repos or are waiting on Dan's decisions.
