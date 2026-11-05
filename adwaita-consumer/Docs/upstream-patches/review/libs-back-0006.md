# Review: libs-back 0006, WM_DELETE_WINDOW on closable windows the gui decorates

**Commit to approve:** `1ecd259c67e04f8bd174b4e43efecdf1bc7c6cf6`
**Branch:** `x11-wm-delete-window` on danjboyd/libs-back (pushed to the fork, not proposed upstream); worktree `~/git/gnustep/libs-back-wmdelete`
**Base:** libs-back master `36ac709` (still upstream master on 2026-10-15)
**Patch:** `../libs-back-standalone/0001-x11-list-WM_DELETE_WINDOW-on-closable-windows-the-gu.patch` (`git format-patch` of the commit)
**Files:** `Source/x11/XGServerWindow.m` (+10 −1), `ChangeLog` (+10), `Tests/x11/wmdeletewindow.m` (new, 156 lines)
**Written by:** the LinDirStat session, 2026-10-15; packet by the plugins-themes-adwaita session

## The bug

When the gui draws the decorations (`GSBackHandlesWindowDecorations` or
`GSX11HandlesWindowDecorations` NO, which the theme turns on), `-window::::`
creates the X window with a style stripped to `NSIconWindowMask` and
`NSMiniWindowMask`. `-_setSupportedWMProtocols:` took the closable bit from
that stripped style, so no window the gui decorates ever lists
`WM_DELETE_WINDOW` in `WM_PROTOCOLS`.

A window manager asked to close such a window (Alt+F4, its window menu, a
task bar) then has no way to ask the client. If it offers close at all,
Mutter falls back to `XKillClient`, and the whole application dies at once,
with nothing saved or asked.

Whether Mutter offers close depends on the Motif hints:
- **Stock libs-back:** the gui-decorated window allows no functions, so Alt+F4 does nothing.
- **libs-back#244** (our 0001, sent and still open, no reply) keeps the style's functions, close included. Then Alt+F4 kills the app.
- **The Adwaita theme:** it already sets those functions itself (see "The theme" below). So on any libs-back it kills the app today.

## The change, line by line

In `-_setSupportedWMProtocols:` (`XGServerWindow.m:1490`):

```objc
unsigned int closeStyle = window->win_attrs.window_style;
...
if (!handlesWindowDecorations && nswin != nil)
  {
    closeStyle = [nswin styleMask];
  }
if ((closeStyle & NSClosableWindowMask) != 0)
  window->protocols[window->numProtocols++] = generic.WM_DELETE_WINDOW_ATOM;
```

- **`handlesWindowDecorations`** is the file's static (line 83), NO when the gui draws the decorations. Windows the window manager decorates keep the old path exactly.
- **`nswin`** is `GSWindowWithNumber(window->number)`, already fetched at the top of the method for the `WM_TAKE_FOCUS` decision. It is nil while the window is being created (the calls at lines 1015 and 2222), so those keep the stripped style and list no `WM_DELETE_WINDOW`.
- **The call that matters** is the one in `-orderwindow:::` (line 3154), each time a window is ordered in. By then the NSWindow exists, and the method ends with `XSetWMProtocols` (line 1529), so the property is right before the window is mapped.
- **The request's path:** the window manager's `WM_DELETE_WINDOW` client message is turned into a `GSAppKitWindowClose` event (`XGServerEvent.m:715`). NSWindow answers that with `-performClose:` (libs-gui `NSWindow.m`, `GSAppKitWindowClose` case), the same path as the gui's own close button. So the delegate's `-windowShouldClose:` and the document's "save changes?" question both apply.

**Not covered:** a window that becomes closable through `-setStyleMask:` while it's on screen gets the protocol only the next time it's ordered in. Under gui-drawn decorations `-stylewindow::` isn't called at all (it asserts `handlesWindowDecorations`). That's rare, and the same limitation the rest of this path has; I'd mention it only if asked.

## The test: `Tests/x11/wmdeletewindow.m`

It sets `GSBackHandlesWindowDecorations NO` in the argument domain (this process only, as the other x11 tests do), orders in NSWindows of four styles and reads `WM_PROTOCOLS` back:

| Window | Expects `WM_DELETE_WINDOW` |
|---|---|
| titled, closable, miniaturizable, resizable | yes |
| titled, closable | yes |
| titled, resizable (not closable) | no |
| borderless | no |

Plus a check that the backend really isn't handling decorations, so the
test can't pass vacuously. Without the change the two "yes" checks fail
(3 of 5 pass); with it, 5 of 5. The whole libs-back suite: 291 passed, none
failed, against 286 on master. It reads only the property, so it needs a
display (a private Xvfb) but no window manager.

The commit message also reports a manual run under GNOME Shell 48.7 (X11, private Xvfb), pressing Alt+F4 in a small program:

| libs-back | Alt+F4 |
|---|---|
| master, with or without this change | nothing (Mutter doesn't offer close) |
| #244 alone | the client is killed |
| #244 and this change | the panel, then the window, close through `-performClose:` and the program keeps running |

## Checks done for this packet (2026-10-15)

- **GCC:** `Tests/Scripts/gcc-syntax-check.sh ~/git/gnustep/libs-back-wmdelete 36ac709 1ecd259` passes. The canary was rejected as it should be; `XGServerWindow.m` and `wmdeletewindow.m` are clean.
- **The exported patch** is byte-identical to `git format-patch -1 1ecd259`, apart from the `From` line.
- **Against #244 and the CSD series:** the code merges cleanly onto #244 (`dbfbe53`, offset 12 lines) and onto the CSD series tip (`fd6e241`, offset 433). **The ChangeLog conflicts** in both cases, because both add an entry at the top. That takes a trivial hand merge (keep both entries, newest first), not just an offset as first reported.
- **No overlap with #244's code:** #244 changes `setWindowHintsForStyle` (the Motif hints) and this changes `-_setSupportedWMProtocols:` (the protocols). Each fixes its own property.

## Ordering with #244, and how to tell upstream

#244 on its own turns "Alt+F4 does nothing" into "Alt+F4 kills the app" under Mutter, so this must land before #244 or with it. #244 has had no reply since 2026-10-06. The options:

1. **A separate pull request, plus a comment on #244** (recommended):
   - The PR is small and stands alone, and it fixes a real problem for any app that sets the Motif hints itself, ours included.
   - The comment says #244 should be merged only together with or after it, and links it. The maintainers can then take them in order, and neither PR changes what was already reviewed or sent.
2. **Add this commit to #244's branch**, making one PR. That keeps them together, but it changes a PR Dan signed off at `dbfbe53`. That would need a new sign-off on the combined branch and new PR text, and the history of #244's review gets muddier.

Either way the PR text and the #244 comment need their own drafts and sign-offs; neither is written yet.

## The theme: its own Motif hints, now and after both land

`GnomeThemeWindowManagerAllowFunctions` (`Source/Adapters/GnomeThemeWindowManager.m:159`) is the theme's stand-in for #244. It was added on 2026-09-25 (3ebf9f1) and is called from the header bar's `-setWindowNumber:`. It writes `_MOTIF_WM_HINTS` with move plus the style's functions, close included.

- **Today, on every libs-back:** libs-back writes the Motif hints only when it creates a window, and in `-stylewindow::`, which doesn't run under gui decorations. So the theme's hints stick, Mutter offers close, and the window lists no `WM_DELETE_WINDOW`. **Alt+F4, or Close in the window menu, kills any app running the theme under GNOME.** That covers every release since 2026-09-25, alpha10 included, with stock libs-back or one built with the patches in `Docs/upstream-patches/`. It needs a theme-side fix of its own, independent of upstream (to be decided separately).
- **Once #244 and this fix are both in a release:** the theme's function writes duplicate what libs-back does, from the same style mask, so `GnomeThemeWindowManagerAllowFunctions` can go for that libs-back and later. It is one of the workarounds tracked in #28. Until then, keep it for older libs-back: without it Mutter won't move, resize or maximize the window through the header bar.
- **With only this fix (not #244):** the theme's hints plus the protocol give the right behaviour. Alt+F4 goes through `-performClose:`.

## Approve with

"I approve libs-back-0006 1ecd259". Approving is not sending: sending needs "send libs-back-0006", and the PR text (and the #244 comment, if option 1) need their own approval.
