# App Coverage

What gnustep-packager builds today for each downstream app, by backend. This
is a snapshot taken on 2026-11-03 from each app's latest release assets and its
CI workflows. Re-check it before using it for release planning.

Legend:

- **packager**: built by a gnustep-packager backend, with a released artifact
  as evidence
- **app-script**: the app ships this format, but builds it with its own
  scripts rather than gnustep-packager
- **configured**: the manifest or workflow has it, but no released artifact
  exists yet
- **example**: `examples/downstream/` has a tested setup, but no repo uses it
  yet
- **none**: no path today
- *(CI)*: the evidence comes from CI runs and release assets only; nobody ran
  it by hand on a local host (every DMG cell)

## Desktop apps

| App | AppImage | MSI | DMG | Packager pin | Notes |
| --- | --- | --- | --- | --- | --- |
| ObjcMarkdown (MarkdownViewer) | packager (v0.2.6-rc4) | packager (v0.2.6-rc3; the rc4 run was still in progress) | app-script *(CI)*: `macos/Makefile` `dmg`, UDZO/HFS+ | reusable workflow at a commit SHA | Also ships a Flatpak built outside gnustep-packager |
| ScreenshotTool | packager (v0.3.3) | packager (v0.3.3, plus a portable ZIP) | app-script *(CI)*: `scripts/package_macos_dmg.sh`, ULFO | reusable workflow `@v0.1.4` | DMG script adds an "Opening an unsigned app" note, a `.sha256` file and a Sparkle appcast |
| LinDirStat | configured | configured | configured *(CI)*: DMG backend via `scripts/ci-release-macos.sh` | pinned checkout | No GitHub release yet. This is the only app wired to the DMG backend |
| PerformanceDashboard | packager (v0.1.3) | configured (manifest only) | none | pinned checkout | Release gate uses `--require-backend appimage`; the Windows CI job is skipped because the Linux job fails on `main` |
| SpreadsheetApp | configured | configured (`release-msi.yml`) | none | reusable workflow `@main` (unpinned) | No release yet |
| Adwaita ThemeDemo | none | none | n/a | none | `Examples/ThemeDemo` in plugins-themes-Adwaita |
| WinUITheme ThemeDemo | n/a | none | n/a | none | `Examples/ThemeDemo` in plugins-themes-winuitheme |
| Gorm | example (`gnustep-apps/gorm`) | none | none | none | Upstream GNUstep app, tag `gorm-1_5_0` |
| ProjectCenter | example (`gnustep-apps/projectcenter`) | none | none | none | Upstream GNUstep app, tag `projectcenter-0_7_0` |
| GWorkspace | example (`gnustep-apps/gworkspace`) | none | none | none | Upstream GNUstep app, tag `gworkspace-1_0_0` |

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
2. **PerformanceDashboard has no MSI.** This is on the app side: its Linux CI
   is red, so the Windows job never runs, and its release gate requires only
   AppImage.
3. **The theme demos have no packaging.** `packagedDefaults.defaultTheme`
   exists, but there is no example manifest that ships a theme bundle
   alongside a demo app.
4. **SpreadsheetApp tracks `@main`.** Any packager change can break its
   release. It should pin a tag.
5. **Arlen and the Swift apps** wait on decisions (PR #77, the archive
   hosting). They are not engineering gaps in this repo.

The DMG items in gap 1 are packager-side and small. The other gaps belong to
the app repos or are waiting on Dan's decisions.
