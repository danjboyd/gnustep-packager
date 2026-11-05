# Review: libs-back patch 2

**Item:** libs-back 0002, "x11: type menus, tool tips, drag images and modal panels as GTK does"
**Commit:** `25affcd98513fd08554fa8cd931348f236143909`
**Base:** libs-back master `23fbe39` (2026-10-06, current on 2026-10-07)
**Where:** branch `x11-window-types` in the libs-back repository of `~/git/gnustep/libs-back-series` (a branch of its own, not in the series worktree's checkout); patch file `Docs/upstream-patches/libs-back-standalone/0001-x11-type-menus-tool-tips-drag-images-and-modal-panel.patch`
**Files:** `Source/x11/XGServerWindow.m` (+107 −64), `ChangeLog` (+18), `Tests/x11/windowtype.m` (new, 307 lines)

This is the version to sign off on. It is commit 2 of the series (`2a7e6cb`) made to stand on its own: it goes as its own pull request, and libs-back#244 (patch 1) isn't merged, so it is based on current master instead of on patch 1. `git cherry-pick` applied the code and the test unchanged; only the ChangeLog needed resolving, because the series' entry sat on top of patch 1's. Two corrections were made to the series commit's wording, both because a run disproved it. First, the Mutter focus sentence in the message (see "Under a real window manager"). Second, the code comment, the ChangeLog and the message about Openbox. They said Openbox knows none of the new types, but Openbox 3.6.1's `libobt` interns `_POPUP_MENU` (it doesn't intern `_TOOLTIP` or `_DND`). They now say that. `git diff 2a7e6cb 25affcd -- Source Tests` shows patch 1's lines (which this commit doesn't contain) and that comment, nothing else. The series commit has the same fixes since 2026-10-07 (`7ac2405`).

Prepared under `Docs/UPSTREAM_POLICY.md`. Nothing has been sent.

## The problem

X11 window managers read `_NET_WM_WINDOW_TYPE` to decide how to treat a window: whether to focus it, whether to animate it, whether to keep its parent drawn as active, what shadow a compositor gives it. libs-back sets the type in `-setwindowlevel::`, from the window's level alone:

- Every window at `NSPopUpMenuWindowLevel` that isn't a tool tip was typed `_DIALOG`. That covers context menus, pop-up buttons' menus and drag images. The code already had `_POPUP_MENU` written there, commented out.
- Tool tips were meant to be `_TOOLTIP`, and the code checks for `GSTTPanel`. But libs-gui sets a tool tip's level while its window is still deferred, before the backend has registered the `NSWindow` for it. So `GSWindowWithNumber()` returns nil, the class check fails, and tool tips were typed `_DIALOG` too. This is the registration-order problem of libs-gui#965.
- Modal panels (`NSModalPanelWindowLevel`) were typed `_NORMAL`.

GTK types the same windows `_POPUP_MENU`, `_TOOLTIP`, `_DND` and `_DIALOG`.

## The fix, hunk by hunk

All in `Source/x11/XGServerWindow.m`.

1. **A declaration (line 454).** `-_setWindowType:` joins the private methods declared at the top of the file, so the call in `-orderwindow:::`, which comes before the definition, has a declared return type. This is the GCC point from the policy.
2. **The new method `-_setWindowType:` (line 3580).** The typing code moves out of `-setwindowlevel::` into this method, unchanged except for:
   - modal panel level: `_DIALOG` instead of `_NORMAL`;
   - pop-up menu level: `GSTTPanel` gives `_TOOLTIP`, `NSMenuPanel` gives `_POPUP_MENU`, `XGRawWindow` or `GSRawWindow` (drag images) give `_DND`, each followed by `_DIALOG` as a second entry (len 2); anything else at that level stays `_DIALOG` alone.

   It returns early if the window manager isn't EWMH or the window has no level yet (`GSWindowLevelAttr`). The XChangeProperty call and its "X-bug" comment are moved as they were.
3. **`-setwindowlevel::` (line 3711).** The old block becomes a call to the new method. The `skipTaskbar` flag, which the old branches set one by one, is now one expression over the same nine levels. The code after it, which sets `_NET_WM_STATE`, is unchanged.
4. **`-orderwindow:::` (line 3104).** Just before a window is mapped, after `setNormalHints()` and `XSetWMHints()` (where the existing comment says some window managers only read properties at map time), a window at the pop-up menu level is typed again. By then its `NSWindow` is registered, so a tool tip's class is known.

**Why the second entry.** The EWMH spec lists the types in order of preference, and a window manager uses the first one it knows. With `_DIALOG` second, a window manager that doesn't know `_TOOLTIP` or `_DND` treats those windows exactly as before. Openbox 3.6.1 is one: its `libobt` interns `_POPUP_MENU` but neither of those two (`strings` on the library, 2026-10-07). So under Openbox a context menu does change type, from `_DIALOG` to `_POPUP_MENU`. `make check-wms` passed under Openbox on 2026-10-06 with the installed backend, which carries this change, but nothing checked Openbox's handling of that one type specifically.

**As GTK types them.** A run on 2026-10-07 with GTK 3.24 on Xvfb gave `_POPUP_MENU` for a `GtkMenu` and `_DIALOG` for a modal `GtkDialog`. GTK's own tool tip and drag icon windows weren't run; GDK's `TOOLTIP` and `DND` type hints give `_TOOLTIP` and `_DND` (the tool tip hint was checked in the same run).

**What doesn't change:**
- Windows at every other level get the type they had.
- A theme that sets a finer type after the level keeps it. The re-typing at map time only touches pop-up-level windows, and the Adwaita theme's `_DROPDOWN_MENU` goes on submenu-level windows.

## Who this affects

Every GNUstep app on an EWMH window manager, whatever theme it uses: context menus, pop-up button menus, tool tips, drag images and modal panels change type. The modal panel change is the broadest. Alerts and run-modal panels go from `_NORMAL` to `_DIALOG` under every window manager.

## The test: `Tests/x11/windowtype.m`

- **What it does:** it forks a minimal window manager that claims EWMH support on the root window (`_NET_SUPPORTING_WM_CHECK`) and maps whatever asks to be mapped. That makes libs-back take its EWMH path without a real window manager. It then creates the windows libs-gui creates, the way libs-gui creates them, orders them in, and reads back the whole `_NET_WM_WINDOW_TYPE` list for each:

  | Window | Expected list |
  |---|---|
  | `GSTTPanel`, deferred, level set before it has an X window (as `GSToolTips` does) | `_TOOLTIP _DIALOG` |
  | `NSMenuPanel` at the pop-up menu level | `_POPUP_MENU _DIALOG` |
  | a panel at the modal panel level | `_DIALOG` |
  | a plain `NSWindow` at the pop-up menu level | `_DIALOG` |
  | a drag image window | `_DND _DIALOG` |

- **Why that is enough:** comparing the whole list checks the fallback entry as well as the new one. The tool tip case reproduces the order that hid its class. The plain-window case guards against typing windows by level alone.
- **What it needs:** a display with no window manager of its own (a private Xvfb). It skips otherwise.
- **Not covered:** how any real window manager acts on the types (see the next section); the levels whose typing didn't change; windows whose level changes after they are mapped.

## Results, each run on 2026-10-07

On a private Xvfb, each build loaded through a GNUstep.conf copy whose user Library holds only that build's bundle, with empty user defaults. libs-gui and libs-base were the installed packages: gui snapshot 7892137bd, base 1.31.1.

| Check | Master `23fbe39` (the test copied in) | With the patch (`25affcd`) |
|---|---|---|
| `Tests/x11/windowtype.m` | 4 of 5 fail: tool tip, context menu, modal panel, drag image. "Another window at the pop-up menu level stays a dialog" passes | 5 of 5 pass |
| Whole `Tests/x11` | 50 passed, 4 failed (the above) | 54 passed, 0 failed |
| Whole libs-back suite | 284 passed; `pdfps.m` aborted | 289 passed; `pdfps.m` aborted |
| `gcc-syntax-check.sh` on this commit | — | clean (canary rejected): `XGServerWindow.m`, `windowtype.m` |
| This commit alone: `./configure && make` | builds | builds |

The 5 extra passes are the new test. `pdfps.m` aborts the same way on both (`-[GSCInlineString copy]: message sent to deallocated instance`). That is libs-gui's font-roles bug in the installed gui snapshot, fixed on gui master by 8a092cfa7 (libs-gui#816; `Docs/upstream-issues/12-…`). It has nothing to do with this patch.

**A trap met on the way:** gnustep-make ignores a `GNUstep.conf` that others can write to ("writable by someone other than its owner … Ignoring it"). The first runs did that silently and loaded the installed backend, which already carries this change, so master passed. The runs above had the config at 0644, and the log has no such message.

## Under a real window manager

Run on 2026-10-07 under GNOME Shell 48.7 (`--x11`) as the window manager of a private Xvfb. It compared master `23fbe39` with this change, both built from the same tree as this commit. The app ran with GNUstep's own theme, empty defaults and libs-gui master `549f639` (the installed gui snapshot crashes at start with a master libs-back; see `pdfps.m` above), and `/proc/<pid>/maps` confirmed which backend loaded. It used real clicks on that display only: a pop-up button, a right-button context menu, and a hover over a button with a tool tip.

| Window, shown for real | Master | With the patch |
|---|---|---|
| Pop-up button's menu | `_DIALOG` | `_POPUP_MENU, _DIALOG` |
| Context menu | `_DIALOG` | `_POPUP_MENU, _DIALOG` |
| Tool tip | `_DIALOG` | `_TOOLTIP, _DIALOG` |

**Focus did not change, with either build.** `_NET_ACTIVE_WINDOW`, the X input focus and `_NET_WM_STATE_FOCUSED` stayed on the main window while each menu and the tool tip was open, and the app saw no change of key or main window.

The series commit's message said the opposite ("Mutter focuses a dialog, so opening a context menu or a pop-up button's menu drew the window under it as unfocused"). That came from an earlier session and doesn't hold on this setup, so this version's message drops it. It now says only that window managers and compositors read the type, and it gives the GNOME Shell types above as a result. This is the only change from `db25bb5`; the tree is identical. `25affcd` then rewrapped one line of the message that the Openbox fix had left over 80 characters (2026-10-07); nothing else changed, and the tree is still identical, so every result here applies to it.

**Not covered:** GNOME on Wayland (through Xwayland), the Adwaita theme's own title bar, and Mutter focus settings other than the default. If the unfocused parent was ever real, it came from one of those. With the GNUstep-drawn decorations, only the context menu and the tool tip were checked.

## Risks and open points

- **Modal panels become dialogs everywhere.** Mutter, KWin and Xfwm4 may place dialogs differently (centred on their parent when they have `WM_TRANSIENT_FOR`) and treat them differently in the window list. Nobody has checked an alert under another window manager with only this patch. GTK types its dialogs this way, so the behaviour is the one users of those window managers already know.
- **Matching on class names.** Exact class-name matches (`isEqual:` on `-className`) don't catch subclasses. A subclass of `NSMenuPanel` stays `_DIALOG`, as it was before. The existing tool-tip check worked the same way.
- **The map-time re-type writes the property again** each time a pop-up-level window is ordered in: one `XChangeProperty` per menu or tool tip shown.

## Questions to be able to answer

- Why type again at map time instead of fixing the order in libs-gui? *The backend can't see the class until the window is registered, and libs-gui#965 (the order) is a separate change in another repository. Typing again at map time fixes it whatever libs-gui does, and window managers read the type at map time anyway.*
- Why `_DIALOG` second, not `_NORMAL`? *It was the type these windows had. A window manager that knows none of the new types sees no change.*
- Does anything change for menus that a menu bar opens, or for torn-off menus? *No: they are at the submenu and torn-off levels, which keep `_MENU`.*

## To check it yourself

```
cd ~/git/gnustep/libs-back-series
git show 25affcd                       # the whole commit
git diff 7ac2405 25affcd -- Source Tests   # differs from the series commit only by patch 1
```

The packet's results came from `run-back-tests.sh <tree> <display> [dir]` in the session's scratch directory. Ask Claude to run it with you watching.

## Sign-off

If you approve this exact version, say so in the chat ("I approve libs-back-0002") and Claude records it, or add this row to `Docs/UPSTREAM_SIGNOFF.md` yourself:

```
| <date> | libs-back 0002 | 25affcd98513fd08554fa8cd931348f236143909 | | |
```

## The patch, as it would be sent

See `Docs/upstream-patches/libs-back-standalone/0001-x11-type-menus-tool-tips-drag-images-and-modal-panel.patch` (from `git format-patch -1 25affcd`; `git am` onto `23fbe39` gives the same tree).
