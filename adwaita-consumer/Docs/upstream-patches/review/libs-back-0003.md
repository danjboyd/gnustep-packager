# Review: libs-back patch 3

**Item:** libs-back 0003, "x11: an alpha channel for borderless windows, when a theme asks"
**Commit:** `b94dc1b79bb56ac9cde6b0dbffa289e4ff8c56c3`
**Base:** libs-back master `23fbe39` (current on 2026-10-07)
**Where:** branch `x11-borderless-alpha` in the libs-back repository of `~/git/gnustep/libs-back-series`; patch file `Docs/upstream-patches/libs-back-standalone/0001-x11-an-alpha-channel-for-borderless-windows-when-a-t.patch`
**Files:** `Source/x11/XGServerWindow.m` (+144 −11), `ChangeLog` (+13), `Tests/x11/FakeCompositor.h` (new, 104 lines), `Tests/x11/borderlessalpha.m` (new, 152 lines)

This is the version to sign off on. It is commit 3 of the series (`8589356`) made to stand on its own on current master, as patch 2 was: it goes as its own pull request, and patches 1 and 2 aren't merged. `git cherry-pick` applied the code and the tests unchanged; only the ChangeLog needed resolving, because the series' entry sat on top of patches 1 and 2. The lines it adds and removes in `Source` and `Tests` are the same as the series commit's against its parent (compared on 2026-10-07). The commit message is the series commit's, word for word: every statement in it was checked (below), and none needed changing.

Patches 4 and 5 build on this one; they can only go after it is merged.

Prepared under `Docs/UPSTREAM_POLICY.md`. Nothing has been sent.

## The problem

The backend creates every window with the screen's default visual, which has no alpha channel. A theme that draws menus and tool tips with rounded corners, as GNOME's are, leaves the corners transparent, but with no alpha channel they show black or the window's background colour instead of what is behind the window.

## The fix, hunk by hunk

All in `Source/x11/XGServerWindow.m`.

1. **Includes.** `AppKit/NSPanel.h` (for `NSDocModalWindowMask`) and, when the backend is built with XRender, `X11/extensions/Xrender.h`.
2. **`argb_visual()` (new).** Finds a 32-bit TrueColor visual whose XRender format has an alpha mask, and makes a colormap for it. It looks once per screen (up to 8) and keeps the answer for the life of the process. Without XRender it finds none.
3. **`-_compositorRuns` (new).** Whether some client owns the `_NET_WM_CM_S<n>` selection, which is how a compositing manager announces itself.
4. **`-_compositorShowsAlpha` (new).** A compositing manager runs and the screen has the 32-bit visual. Without a compositing manager, transparent pixels show black.
5. **`-_windowGetsAlpha:` (new).** Only a borderless window (no title, close, miniaturize, resize, doc-modal, icon or mini-window bit), only when the `GSBackBorderlessWindowAlpha` default is YES, and only when `-_compositorShowsAlpha` says so.
6. **`-window::::`.** When `-_windowGetsAlpha:` says yes, the window is created with the 32-bit visual, its colormap, border pixel 0 and background pixel 0 (it starts transparent), and `window->depth` set to 32. Otherwise the original `XCreateWindow` call runs unchanged (re-indented into an `else`).

**What doesn't change:** nothing unless the default is set. Windows with a style keep the default visual even when it is.

**Why drawing works without further changes:** `XGCairoModernSurface` (master) makes its cairo surface with the visual the X window actually has (`XGetWindowAttributes`), so a 32-bit window gets a 32-bit surface. Read in the code on 2026-10-07; this patch's test doesn't look at drawn pixels (see below).

## Who this affects

Nobody, unless a theme or user sets `GSBackBorderlessWindowAlpha`. A theme sets it in the `GSThemeDomain` of its Info.plist: `-[GSTheme activate]` puts that domain in the defaults search list, and the backend reads the default when each window is created, after the theme is active (libs-gui master, `Source/GSTheme.m`, read on 2026-10-07). The Adwaita theme sets it.

## The test: `Tests/x11/borderlessalpha.m`

- **What it does:** it forks a stand-in compositing manager that only owns `_NET_WM_CM_S0` (`Tests/x11/FakeCompositor.h`, used again by patches 4 and 5's tests), creates windows through the display server, and reads back the depth of their X windows. Four checks:

  | Case | Expected |
  |---|---|
  | default off, borderless window | 24-bit |
  | default on, compositing manager running, borderless window | 32-bit |
  | default on, titled window | 24-bit |
  | default on, compositing manager gone, borderless window | 24-bit |

- **Why that is enough:** the X window's depth decides whether transparency can show at all. The negative cases guard against alpha where it would show black (no compositing manager) or where it isn't asked for.
- **What it needs:** a display with no compositing manager of its own (a private Xvfb); it skips otherwise.
- **Not covered:** the pixels the gui draws into such a window. The shadow-drawing test of patch 4 reads drawn pixels back from a 32-bit window.

## Results, each run on 2026-10-07

On a private Xvfb (`:150`), each build loaded through a GNUstep.conf copy (mode 600) whose user Library holds only that build's bundle, with empty user defaults; `LD_DEBUG=files` on `borderlessalpha` showed the bundle under test loaded. libs-gui master `549f639` (uninstalled, `LD_LIBRARY_PATH`) and libs-base 1.31.1.

| Check | Master `23fbe39` (the test copied in) | With the patch (`b94dc1b`) |
|---|---|---|
| `Tests/x11/borderlessalpha.m` | 1 of 4 fails ("with GSBackBorderlessWindowAlpha and a compositing manager a borderless window has an alpha channel") | 4 of 4 pass |
| Whole `Tests/x11` | 52 passed, 1 failed (the above) | 53 passed, 0 failed |
| Whole libs-back suite | 286 passed, 0 failed | 290 passed, 0 failed |
| `gcc-syntax-check.sh` on this branch | — | clean (canary rejected): `XGServerWindow.m`, `borderlessalpha.m` |
| Build (`./configure && make`) | builds, 4 warnings | builds, the same 4 warnings |

The 4 extra passes are the new test. Against the installed gui (a Debian snapshot older than libs-gui's `8a092cfa7`), `Tests/cairo/pdfps.m` aborts on both builds with `-[GSCInlineString copy]` sent to a deallocated instance: libs-gui's font-roles bug, fixed on gui master (`Docs/upstream-issues/12-libs-gui-font-role-names-fixed-on-master.md`). With gui master it doesn't, which is why the suite was run against it.

## Statements in the commit message, checked

| Statement | How checked |
|---|---|
| Every window gets the default visual, which has no alpha | master `-window::::` passes `context->visual`; read |
| A 32-bit visual, starting transparent | the new branch sets background pixel 0; read |
| Only with a compositing manager (`_NET_WM_CM_S<n>`) and such a visual | `-_compositorShowsAlpha`; read, and the test's no-compositor case |
| Windows with a style are left alone | the test's titled-window case |
| A theme can set it in its GSThemeDomain | libs-gui's `-activate` and the backend's per-window read; read |
| Without the change "has an alpha channel" fails, with it all four pass | run, above |
| The test skips with a compositing manager of its own | `borderlessalpha.m` line 90; read |

## Risks and open points

- **Black corners if the compositing manager dies while a menu is open.** The check is made when the window is created. Patch 4 adds XFixes notifications for this, for windows with a margin only.
- **Matching on the style mask.** Any borderless window gets the 32-bit visual when the default is on, including ones an app made for its own purposes. They start transparent, so an app that relied on an X background colour showing would see the desktop instead until it draws.
- **One colormap per screen, never freed.** It lives as long as the process.

## Questions to be able to answer

- Why not give every window an alpha channel? *A 32-bit window costs more to composite and shows black without a compositing manager. Only the windows a theme rounds need it.*
- Why a default rather than an API? *The theme decides how menus look; a default in its `GSThemeDomain` needs no new libs-gui API and changes nothing for other themes.*
- Why does the test not draw? *The depth is what this patch changes. Drawing into 32-bit windows is exercised by patch 4's `shadowdrawing.m`.*

## To check it yourself

```
cd ~/git/gnustep/libs-back-series
git show b94dc1b                                   # the whole commit
git diff 8589356~1 8589356 -- Source Tests         # the series commit's change: the same lines
```

The results came from `run.sh <bundle tree> <display> <tests dir>` in the session's scratch directory. Ask Claude to run it with you watching.

## Sign-off

If you approve this exact version, say so in the chat ("I approve libs-back-0003") and Claude records it, or add this row to `Docs/UPSTREAM_SIGNOFF.md` yourself:

```
| <date> | libs-back 0003 | b94dc1b79bb56ac9cde6b0dbffa289e4ff8c56c3 | | |
```

## The patch, as it would be sent

`Docs/upstream-patches/libs-back-standalone/0001-x11-an-alpha-channel-for-borderless-windows-when-a-t.patch` (from `git format-patch -1 b94dc1b`; `git am` onto `23fbe39` gives the same tree).
