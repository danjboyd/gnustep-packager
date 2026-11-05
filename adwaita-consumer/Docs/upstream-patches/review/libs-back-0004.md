# Review: libs-back patch 4

**Item:** libs-back 0004, "x11, cairo: window shadows and rounded corners for windows the gui decorates"
**Commit:** `fd508976ce0a3dace81dbd9f7542e14b721bdcf9`
**Base:** patch 3 (`b94dc1b`, branch `x11-borderless-alpha`) on libs-back master `23fbe39`
**Where:** branch `x11-window-shadows` in the libs-back repository of `~/git/gnustep/libs-back-series`; patch file `Docs/upstream-patches/libs-back-standalone/0001-x11-cairo-window-shadows-and-rounded-corners-for-win.patch`
**Files:** `Source/x11/XGServerWindow.m` (+309 −13), `Source/x11/XGServerEvent.m` (+158 −1), `Source/cairo/XGCairoModernSurface.m` (+293 −2), `Source/x11/XGServer.m` (+26), `Source/x11/XGGLContext.m` (+20 −8), four headers (+39 −1), `ChangeLog` (+78), tests: `Tests/x11/FakeCSDWindowManager.h` (new, 145 lines), `Tests/x11/shadowmargin.m` (new, 404), `Tests/x11/shadowdrawing.m` (new, 229)

**It can only be sent after patch 3 is merged**: it uses patch 3's 32-bit visual and its test helper. If patch 3 changes in review, this one is rebased onto the merged version, which is a new hash and goes back to review.

This is the version to sign off on. It is commit 4 of the series (`129aefc`) on top of the standalone patch 3 instead of patches 1–3. `git cherry-pick` applied it with one conflict, in the list of private method declarations at the top of `XGServerWindow.m`, where the series had patch 2's `-_setWindowType:` next to this patch's `-_checkWMSupports:`; the resolution keeps only this patch's line. The lines it adds and removes in `Source`, `Headers` and `Tests` are the same as the series commit's against its parent (compared on 2026-10-07).

Two statements in the message were corrected (this commit's tree is the same as before the correction):

1. "with libs-gui 0.32 the test process aborts … which windowtype.m also works around": the abort comes from libs-gui snapshots older than `8a092cfa7` (libs-gui#816, the font roles keeping the backend's default font names unretained), not the 0.32 release, which can't load a libs-back built from master at all; and `windowtype.m` is patch 2's test, not in this branch. Now: "with a libs-gui older than 8a092cfa7 (libs-gui#816), the test process aborts before its first check (… the font roles kept the backend's default font names unretained)". The series commit has the same correction (`46dc8b2`, which keeps the `windowtype.m` mention: it is true there).
2. The paragraph on the theme's GNOME Shell check said it ran "against this series" and passed "among its 16 checks". It was rerun against exactly this branch (below), where 18 of its 19 checks pass and the 19th, a menu's shadow, is patch 5's. The paragraph now says that, and that the KWin, Xfwm4 and Openbox runs were with the rest of the series.

Prepared under `Docs/UPSTREAM_POLICY.md`. Nothing has been sent.

## The problem

With `GSBackHandlesWindowDecorations` (or `GSX11HandlesWindowDecorations`) NO the gui draws the title bar and the window manager draws no frame, so the window has no shadow. GTK's client-side decorated windows draw their own shadow in a transparent margin round the window, tell the window manager where the window is inside that margin (`_GTK_FRAME_EXTENTS`), and round their top corners. GNUstep windows look flat and square next to them.

## The fix, hunk by hunk

The ChangeLog entry lists every function; in short:

- **`XGServerWindow.m`, which windows get a margin** (`-_windowGetsShadow:`): styled, buffered windows the gui decorates, when `GSBackWindowShadows` is YES, the window manager lists `_GTK_FRAME_EXTENTS` in `_NET_SUPPORTED` (else it would place and tile by the margin's edge) and a compositing manager shows transparency (patch 3). `-window::::` creates them with patch 3's 32-bit visual and the margin: 30 points at the sides, 24 above, 36 below, measured from libadwaita windows under Mutter, scaled by `GSScaleFactor` (`shadowScale`, `shadowScaled`).
- **Coordinates** (`-_offsets::::for:`): the offset between the frame the gui sees and the X window is the window manager's decorations when it draws them, otherwise minus the margin. It replaces `-styleoffsets:::::` in the frame, rectangle and point conversions, `-setWindowdevice:forContext:`, `-flushwindowrect::`, event locations (`XGServerEvent.m`) and an OpenGL view's placement (`XGGLContext.m`). The window manager hint conversions keep `-styleoffsets` (hints use the X window's own origin).
- **What the window manager is told** (`-_updateShadowOf:`): `_GTK_FRAME_EXTENTS` and an input shape of the visible part plus a 12-point band round a resizable window, where the gui resizes from; presses further out in the margin go to what is below.
- **When the margin goes** (`-_updateShadowSizeOf:`): while the window is maximized or fullscreen (`_NET_WM_STATE`), tiled (`_GTK_EDGE_CONSTRAINTS`) or no compositing manager runs. The min and max size hints include the margin and move with it; a growing margin is published before the larger hints and a shrinking one after the smaller ones, so the window manager never holds the window at the other margin's minimum.
- **Compositor start and stop** (`XGServer.m`, `-_compositorChanged`): XFixes selection events on `_NET_WM_CM_S<n>`, when the backend is built with XFixes (`HAVE_XFIXES`, already in master's configure).
- **Settling** (`XGServerEvent.m`, `-_shadowSizeChangedFor:`, `-_settleShadowOf:`, `-_shadowSettled:`): after the margin changes, the frame sent to the gui is held until ConfigureNotify events stop (50 ms with none, 300 ms at most), so a maximize is one resize for the gui rather than three. Expose copies the margin from the backing store; ConfigureNotify reshapes the input region.
- **Drawing** (`XGCairoModernSurface.m`): `shadow_template()` computes the shadow once (black, about 19% beside the window, fading over the margin, weaker above and stronger below) as corners and edges, `create_shadow()` puts it together in the X server for each window size, and `-handleExposeRect:` copies contents and shadow as rectangles, with only the four corners through a rounded clip (`GSBackWindowCornerRadius`).
- **Headers**: the new `gswindow_device_t` fields, method declarations, `xfixesEventBase`, `_shadowSurface`, and the `_GTK_FRAME_EXTENTS` and `_GTK_EDGE_CONSTRAINTS` atoms.

**What doesn't change:** nothing unless `GSBackWindowShadows` is set; without a margin, `-_offsets::::for:` returns what `-styleoffsets:::::` did.

## Who this affects

Nobody, unless a theme or user sets `GSBackWindowShadows` (the Adwaita theme sets it in its `GSThemeDomain`), and then only for windows the gui decorates, under a window manager that knows `_GTK_FRAME_EXTENTS`, with a compositing manager running.

In practice it also wants patch 1: without it the Motif hints forbid the window manager to move or resize a window the gui decorates. The Adwaita theme sets those hints itself, which is why the GNOME Shell check below passes without patch 1; a theme that doesn't would need patch 1.

## The tests

Both fork a stand-in window manager that knows `_GTK_FRAME_EXTENTS` (`FakeCSDWindowManager.h`, which grants every configure request and sets no state itself) and patch 3's stand-in compositing manager, need a display with neither (a private Xvfb) and skip otherwise, and set their defaults in the argument domain.

- **`Tests/x11/shadowmargin.m`** (19 checks) works with the display server alone and reads back what the window manager is told, as exact values: `_GTK_FRAME_EXTENTS`, the X window's depth and size, its input shape. It plays a maximize and a restore through `_NET_WM_STATE` (checking, with a minimum size set, that the hints change before the margin on the maximize and after it on the restore), stops and restarts the compositing manager, makes a program resize, and repeats with `GSScaleFactor` 2. Its negative cases: no default, a non-retained window, a borderless window, a window made with no compositing manager, a window manager without `_GTK_FRAME_EXTENTS`.
- **`Tests/x11/shadowdrawing.m`** (8 checks) makes a real NSWindow and reads its X window's alpha back: contents opaque, top corners rounded off, about 19% black beside the window fading to nearly nothing at the margin's edge, stronger below than above.
- **Why that is enough:** the exact values catch any change in what the window manager is told; the drawing check's bounds are loose enough for rounding but catch a missing shadow, square corners or a shadow over the window.
- **Not covered:** the settling of the frame, the tiled (`_GTK_EDGE_CONSTRAINTS`) case and the OpenGL view's placement in libs-back's own tests; tiling is covered by the theme's GNOME Shell check below.

## Results, each run on 2026-10-07

Private Xvfb `:150`; each build loaded through a GNUstep.conf copy (mode 600) with only that bundle and empty defaults, `LD_DEBUG=files` on `shadowmargin` showing the bundle under test; libs-gui master `549f639` (uninstalled), libs-base 1.31.1. The patch was tested as `5d724d4`, which has this commit's tree (only the message changed since).

| Check | Patch 3 (`b94dc1b`, the tests copied in) | With the patch |
|---|---|---|
| `shadowmargin.m` | 14 of 19 fail (all the positive ones), 5 pass | 19 of 19 pass |
| `shadowdrawing.m` | its first check fails ("a 32-bit X window with a margin round its frame"); the rest don't run | 8 of 8 pass |
| Whole `Tests/x11` | 58 passed, 15 failed | 80 passed, 0 failed |
| Whole libs-back suite | 290 passed, 0 failed | 317 passed, 0 failed |
| `gcc-syntax-check.sh` on this branch | — | clean (canary rejected): the five sources and three tests |
| Build | 4 warnings | the same 4 warnings (`-Wunused-result`, as on master) |

The 27 extra passes are the two new tests. Also run:

- **The order of hints and margin** (the KWin fix, 2026-10-07): with the series' earlier 0004 (`4ed1272`), which set the hints first, this `shadowmargin.m` fails only "on a restore the margin comes back before the larger minimum" (18 of 19 pass), as the message says.
- **The values `shadowdrawing.m` reports**: 46, 19 and 3 across the margin, 51 below and 22 above, the numbers in the message.
- **GNOME Shell 48.7 (X11)**, the Adwaita theme's `make check-mutter-shadow` on a private Xvfb, against this branch's backend and libs-gui master with the theme-defaults patch (`bd5a9830b`): 18 of 19 pass. Among them: Mutter allows move, maximize and close; a 32-bit window with frame extents 30 30 24 36, a shadow and rounded corners; maximize with no margin and square corners, one resize on maximize and two on restore; tiling to the left half with no margin and back; Mutter's window menu; moving past the screen edge; resizing from the band; a press 12 pixels out resizes, 13 out reaches the window behind; an attached alert. The failing one, "menu-shadow" (a menu with frame extents none), is patch 5's.
- The message's KWin 6.3.6, Xfwm4 4.20.0 and Openbox 3.6.1 + picom 12.5 results are from the theme's `make check-wms` against the whole series on 2026-10-07 (plugins-themes-Adwaita#14), not rerun against this branch alone.

## Risks and open points

- **Size.** About 1,700 lines with tests, 840 in the sources. A maintainer may ask for it split (margin and hints; drawing; settling).
- **The settling timers** (50 ms / 300 ms) are tuned on Mutter, KWin, Xfwm4 and Openbox; another window manager might configure more slowly, and the gui would then see an extra resize.
- **Measured numbers.** The margin and the shadow's strength are measured from libadwaita 1.7 windows under Mutter; no code was taken. The message says so.
- **A window made while no compositing manager runs never gets a margin** (it has the 24-bit visual; `shadow_eligible` is decided once, in `-window::::`, and the test checks it). Only windows made with one lose the margin when it stops and get it back when it starts, which needs XFixes.

## Questions to be able to answer

- Why only when the window manager knows `_GTK_FRAME_EXTENTS`? *Otherwise it treats the margin as part of the window: it places, snaps and tiles by the shadow's edge, and the window ends up 30 pixels off.*
- Why do the size hints include the margin? *They are for the X window, which includes it; GTK does the same. And why the order matters: KWin restored a maximized window 20 pixels larger each way when the hints came first.*
- Why hold the frame back after a margin change? *The window manager usually configures the window for the old margin first; without the hold, the gui lays out three times for one maximize.*

## To check it yourself

```
cd ~/git/gnustep/libs-back-series
git show fd50897                                    # the whole commit
git diff 8589356 129aefc -- Source Headers Tests    # the series commit's change: the same lines
```

## Sign-off

If you approve this exact version, say so in the chat ("I approve libs-back-0004") and Claude records it, or add this row to `Docs/UPSTREAM_SIGNOFF.md` yourself:

```
| <date> | libs-back 0004 | fd508976ce0a3dace81dbd9f7542e14b721bdcf9 | | |
```

## The patch, as it would be sent

`Docs/upstream-patches/libs-back-standalone/0001-x11-cairo-window-shadows-and-rounded-corners-for-win.patch` (from `git format-patch -1 fd50897`; `git am` onto `b94dc1b` gives the same tree).
