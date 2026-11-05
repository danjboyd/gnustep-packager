# Review: libs-back patch 5

**Item:** libs-back 0005, "x11, cairo: popover shadows for menus, when a theme asks"
**Commit:** `0c7dc1f0fc0bbdb53d029c8927c6201a227481fb`
**Base:** patch 4 (`fd50897`, branch `x11-window-shadows`) on patch 3 (`b94dc1b`) on libs-back master `23fbe39`
**Where:** branch `x11-popover-shadows` in the libs-back repository of `~/git/gnustep/libs-back-series`; patch file `Docs/upstream-patches/libs-back-standalone/0001-x11-cairo-popover-shadows-for-menus-when-a-theme-ask.patch`
**Files:** `Source/cairo/XGCairoModernSurface.m` (+55 −8), `Source/x11/XGServerWindow.m` (+46 −4), `Headers/x11/XGServerWindow.h` (+2), `ChangeLog` (+25), `Tests/x11/shadowmargin.m` (+41 −1), `Tests/x11/shadowdrawing.m` (+47 −1)

**It can only be sent after patches 3 and 4 are merged.** If either changes in review, this one is rebased, which is a new hash and goes back to review.

This is the version to sign off on. It is commit 5 of the series (`9160d53`) on top of the standalone patch 4. `git cherry-pick` applied it with no conflict; the lines it adds and removes are the same as the series commit's against its parent (compared on 2026-10-07). The commit message is the series commit's, word for word: every statement in it was checked (below), and none needed changing. Its hash changed from the first standalone build (`ab02789`) only because patch 4's message was corrected beneath it; the tree is the one tested.

Prepared under `Docs/UPSTREAM_POLICY.md`. Nothing has been sent.

## The problem

GNOME's menus are popovers: rounded, with a soft shadow of their own, fainter and shorter than a window's. With patch 3 a theme can round a menu's corners, but a borderless window has no margin to draw a shadow in.

## The fix, hunk by hunk

- **`XGServerWindow.m`, `-_windowGetsPopoverShadow:` (new).** A borderless window with `NSUtilityWindowMask` (which a borderless window has no other use for) is a popover when `GSBackPopoverShadows` is YES, on a window's terms: the gui draws decorations, the window manager knows `_GTK_FRAME_EXTENTS`, a compositing manager shows transparency.
- **`popoverMargin` and `marginFor()` (new).** A popover's margin is 14 points at the sides, 12 above and 16 below, instead of a window's 30/30/24/36. `-_updateShadowSizeOf:` and `-window::::` use `marginFor()`; the corner radius comes from `GSBackPopoverCornerRadius` for a popover.
- **No resize band** for a popover: presses land only in its visible part.
- **`XGServerWindow.h`**: the `shadow_popover` field.
- **`XGCairoModernSurface.m`.** `shadow_template()` takes a `popover` flag and draws libadwaita's popover box-shadow, "0 1px 5px 1px" black at 9% and "0 2px 14px 3px" black at 5%, as a CSS blur of the distance to the rounded outline, so it follows the corners. The template cache keeps two templates, one for windows and one for popovers (`caches[popover ? 1 : 0]`).

**What doesn't change:** nothing unless `GSBackPopoverShadows` is set and a window is marked; windows keep a window's margin.

## Who this affects

Nobody, unless a theme sets `GSBackPopoverShadows` and marks its menu windows with `NSUtilityWindowMask` (the Adwaita theme does both).

## The tests

Patch 4's two tests gain popover cases.

- **`shadowmargin.m`** (19 → 23 checks): a marked window has no margin without the default; with it, the popover's exact margin (`_GTK_FRAME_EXTENTS` 14 14 12 16), X window size and input shape (the visible part only); an unmarked borderless window gets none; a titled window keeps a window's margin.
- **`shadowdrawing.m`** (8 → 14 checks): a borderless `NSUtilityWindowMask` NSPanel, its pixels read back: contents opaque, corners rounded off, about 8% black beside it fading to nearly nothing at the margin's edge, stronger below than above.
- **Not covered:** a real menu (the tests make panels the way the theme marks them); popovers under a window manager without `_GTK_FRAME_EXTENTS` beyond the negative check.

## Results, each run on 2026-10-07

As for patch 4 (private Xvfb `:150`, the bundle under test shown by `LD_DEBUG=files`, libs-gui master `549f639`). Tested as `ab02789`, the same tree.

| Check | Patch 4 (`fd50897`, these tests copied in) | With the patch |
|---|---|---|
| `shadowmargin.m` | 22 of 23 pass; "with GSBackPopoverShadows a popover has a popover's margin" fails | 23 of 23 pass |
| `shadowdrawing.m` | 8 pass; "a popover has a 32-bit X window with a margin" fails and the popover checks after it don't run | 14 of 14 pass |
| Whole `Tests/x11` | 83 passed, 2 failed | 90 passed, 0 failed |
| Whole libs-back suite | 317 passed, 0 failed | 327 passed, 0 failed |
| `gcc-syntax-check.sh` on this branch | — | clean (canary rejected) |
| Build | 4 warnings | the same 4 |
| GNOME Shell 48.7, the theme's `make check-mutter-shadow` (with libs-gui `bd5a9830b`) | 18 of 19: "menu-shadow" fails | 19 of 19 pass |

## Statements in the commit message, checked

| Statement | How checked |
|---|---|
| Margin 14 at the sides, 12 above, 16 below | `popoverMargin`; the test's "14 14 12 16" |
| libadwaita's popover box-shadow "0 1px 5px 1px" at 0.09 and "0 2px 14px 3px" at 0.05 | the `popover > contents` rule in libadwaita 1.7.6's `base.css` (extracted from the installed library) reads `box-shadow: 0 1px 5px 1px RGB(0 0 0/9%), 0 2px 14px 3px RGB(0 0 0/5%)` |
| One template for windows and one for popovers | `caches[2]` in `XGCairoModernSurface.m`; read |
| No resize band, presses only in the visible part | the test's input-shape check |
| Values seen: 21 and 1 across the margin, 26 below, 16 above | the test's output above |
| About 8% black beside it | 21/255 = 8.2% |
| Without the change the margin check fails and the drawing checks can't run; with it 23 and 14 pass | run, above |

## Risks and open points

- **`NSUtilityWindowMask` as the marker.** A borderless window has no other use for it in GNUstep today, but it is an overloading of the style mask; a maintainer may prefer a window property or a theme method instead.
- **The code comment names the Adwaita theme** ("the Adwaita theme marks its menus"). True, but a maintainer may not want a third-party theme named in libs-back; easy to drop before sending, which would be a new hash.
- **Numbers from libadwaita.** Only the published CSS values are used; no code. The message says so.

## Questions to be able to answer

- Why a separate margin for popovers? *libadwaita's popover shadow is smaller and fainter than a window's; a window's 30-point margin would waste space and input area round every menu.*
- Why no resize band? *Menus aren't resized by the user; presses outside the visible menu should reach what is below (and close the menu).*

## To check it yourself

```
cd ~/git/gnustep/libs-back-series
git show 0c7dc1f                                    # the whole commit
git diff 129aefc 9160d53 -- Source Headers Tests    # the series commit's change: the same lines
```

## Sign-off

If you approve this exact version, say so in the chat ("I approve libs-back-0005") and Claude records it, or add this row to `Docs/UPSTREAM_SIGNOFF.md` yourself:

```
| <date> | libs-back 0005 | 0c7dc1f0fc0bbdb53d029c8927c6201a227481fb | | |
```

## The patch, as it would be sent

`Docs/upstream-patches/libs-back-standalone/0001-x11-cairo-popover-shadows-for-menus-when-a-theme-ask.patch` (from `git format-patch -1 0c7dc1f`; `git am` onto `fd50897` gives the same tree).
