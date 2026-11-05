**Repository:** gnustep/libs-back (and a small part in libs-gui)

**Title:** Proposal: better support for GNUstep-drawn window decorations on X11

Draft, 2026-09-25, for Dan Boyd to send to the libs-back maintainers. Checked
against libs-back master 5db2ae7 (2026-09-11) and libs-gui master ff49ac8.

**Updated 2026-10-02: items 0, 2 and 4 have patches**, against those same
commits, with ChangeLog entries:
`Docs/upstream-patches/libs-back-csd.diff` (items 0 and 2) and
`Docs/upstream-patches/libs-gui-theme-decorations.diff` (item 4). They were
built and used with the Adwaita theme on GNOME (Mutter, X11 and Xwayland);
`make check-mutter-shadow` in the theme repository runs a GNOME Shell on a
private Xvfb against them and checks the shadow, corners, maximise and
restore, tiling, moves, the resize band and click-through. Each item below
says what its patch does where it differs from what was first proposed.

**Updated 2026-10-05: popover shadows for menus (item 2) and item 5
(window types) added** to
`Docs/upstream-patches/libs-back-csd.diff`, with its own ChangeLog entry and
test (`Tests/x11/windowtype.m`, 4 checks; 3 fail without the patch).

**Updated 2026-10-06: the patches are now a series** in
`Docs/upstream-patches/libs-back/` (five commits) and
`Docs/upstream-patches/libs-gui/` (one), against libs-back master 9731f15
and libs-gui master 549f63913, prepared to follow GNUstep's policy on
AI-generated content: one change per commit, each with its own ChangeLog
entry, its own test and a disclosure. They replace the two `.diff` files
above. `Docs/upstream-patches/README.md` lists them, how they meet the
policy, and what changed on the way (a libs-gui bug fix among them).

### Background

With `GSX11HandlesWindowDecorations NO`, GNUstep draws the title bar itself
(`GSStandardWindowDecorationView`), and a theme can replace it through
`-[GSTheme windowDecorator]`. The Adwaita theme
(plugins-themes-adwaita) uses this to draw libadwaita's header bar: title,
window buttons and the app's main menu button in one row, as GNOME apps
have.

The theme also hands moves, resizes, maximising and the window menu to the
window manager, as GTK does, by sending the EWMH and GTK messages itself
through `-[GSDisplayServer serverDevice]` and `-windowDevice:` with Xlib
(Source/Adapters/GnomeThemeWindowManager.m in the theme). Under Mutter that
gives GNUstep windows snapping, tiling, dragging off screen, Super-drag,
Mutter's maximise and its window menu. It needs one workaround for a
libs-back bug (item 0).

What still needs the backend:

- item 0, a bug: the Motif hints of windows GNUstep decorates forbid every
  window manager function;
- item 2, a shadow round the window and rounded top corners;
- item 4, letting a theme turn GNUstep-drawn decorations on.

Items 1 and 3 would still be worth having in libs-back, so that
`GSStandardWindowDecorationView` and other themes get the same behaviour
without Xlib code of their own; the theme's implementation can serve as the
reference. We can write the patches; we'd like to know first whether this
direction is welcome, and which API shapes you'd prefer.

### 0. Motif hints forbid all functions (bug)

With `GSX11HandlesWindowDecorations NO`, `setWindowHintsForStyle()`
(XGServerWindow.m around line 312) sets `_MOTIF_WM_HINTS` with
`MWM_HINTS_FUNCTIONS` and `functions = 0` for every window, not only
borderless ones. That asks for no decorations, which is right, but also
tells the window manager that the window may not be moved, resized,
minimised, maximised or closed. Mutter follows it: `_NET_WM_ALLOWED_ACTIONS`
lists no move, maximise, minimise or close, so `_NET_WM_MOVERESIZE`,
`_NET_WM_STATE` maximise requests, Super-drag and the window menu's
entries all do nothing. (GNUstep's own title bar moves the window with
`XMoveWindow`, which the hints don't restrict, so this went unnoticed.)

GTK sets only `MWM_HINTS_DECORATIONS` with no decorations. Suggested fix:
for a styled window that GNUstep decorates, keep `decorations = 0` and set
the functions from the style mask as the decorated branch already does
(move; close, minimise, resize and maximise as the style allows). The
theme does this after the window is created
(`GnomeThemeWindowManagerAllowFunctions`).

**Patch:** exactly that, in `setWindowHintsForStyle()`; borderless windows
keep functions 0. Note that this changes behaviour for everyone who uses
GNUstep-drawn decorations today: every styled window, sheets and utility
panels included, now lets the window manager move it (and resize, minimise,
maximise or close it as its style allows), where before it allowed
nothing.

### 1. Window-manager-driven move and resize (`_NET_WM_MOVERESIZE`) (done in the theme)

libs-back sends no `_NET_WM_MOVERESIZE`. A decoration view that gets a press
on its title bar or an edge could hand the drag to the window manager:

```objc
/* GSDisplayServer: ask the window manager to move (edge 8) or resize
   (edges 0-7, EWMH order) the window, starting at a screen point, for the
   given mouse button. Returns NO when the window manager doesn't support
   it, and the caller keeps its own loop. */
- (BOOL) beginMoveResizeWindow: (int)win
                          edge: (int)edge
                       atPoint: (NSPoint)screenPoint
                        button: (int)button;
```

The X11 implementation ungrabs the pointer and sends the EWMH client message
to the root window when `_NET_SUPPORTED` lists `_NET_WM_MOVERESIZE`. The
Wayland backend already does the equivalent (`xdg_toplevel_move` and
`xdg_toplevel_resize` in WaylandServer+Cursor.m); this would give X11 the
same and make it available to decoration views.
`GSStandardWindowDecorationView` would try it first in
`-moveWindowStartingWithEvent:` and `-resizeWindowStartingWithEvent:`, so
every theme benefits.

### 2. A shadow margin (`_GTK_FRAME_EXTENTS`)

A shadow needs a transparent margin outside the window's visible edge, drawn
into, and the window manager told where the visible window is, so that it
snaps and tiles the visible part and passes input through the margin. GTK
does this with an ARGB visual and `_GTK_FRAME_EXTENTS` (left, right, top,
bottom, CARDINAL[4]); Mutter and KWin both honour it.

libs-back creates windows with the default visual and has no
`_GTK_FRAME_EXTENTS`. The existing offset mechanism (frame offsets for
window-manager borders) already separates `NSWindow`'s frame from the X
window's geometry; a margin is the same idea turned outwards. A possible
shape:

- When GNUstep draws the decorations and the screen has a compositing
  manager (`_NET_WM_CM_S<n>` is owned), create top-level windows with a
  32-bit ARGB visual and a margin of N pixels on each side (a user default,
  0 to turn it off).
- Keep `NSWindow`'s frame the visible window; the X window is the frame plus
  the margin, and the backend converts, as it does for the offsets today.
- Set `_GTK_FRAME_EXTENTS` to the margin, and clear it (margin 0) while
  maximised, tiled or fullscreen (item 3).
- Who draws the shadow: either the backend (a blurred rectangle in the
  margin, simplest, no gui change) or the decoration view, if the drawable
  covers the margin. We'd start with the backend drawing it and a theme
  hook for its size and colour.

This is the largest of the four and touches every drawing path, so we'd like
your view on it before starting.

**Patch:** the backend draws the shadow, so the gui needs no change beyond
item 4.

- *When:* a styled, buffered window the gui decorates, `GSBackWindowShadows`
  YES (the theme sets it in its `GSThemeDomain`), a window manager that
  lists `_GTK_FRAME_EXTENTS` in `_NET_SUPPORTED` (one that doesn't would
  treat the margin as part of the window), a compositing manager owning
  `_NET_WM_CM_S<n>`, and a 32-bit visual. Such windows get a visual and
  colormap of their own; other windows are unchanged. The backend watches
  the compositing manager with XFixes: while none runs, windows have no
  margin (it would show black), and get it back when one starts. A window
  created while none runs keeps the default visual and never gets one.
- *Margin:* 30, 30, 24, 36 pixels (left, right, top, bottom), measured from
  libadwaita 1.7 under Mutter; `GSBackWindowCornerRadius` (the theme: 15)
  rounds the corners. `-_offsets::::for:` returns minus the margin where
  `-styleoffsets` was used for the frame and point conversions, so
  `NSWindow`'s frame stays the visible window.
- *Window manager:* `_GTK_FRAME_EXTENTS` is the margin, 0 while
  `_NET_WM_STATE` is maximised or fullscreen or `_GTK_EDGE_CONSTRAINTS`
  says tiled (read on PropertyNotify, which also sends the window its new
  frame; so item 3's reading of states is partly here). The size hints
  move with the margin: with stale ones Mutter restored a maximised window
  20 pixels too big.
- *Input:* an input shape of the visible part, plus a 12 pixel band round a
  resizable window's edge, where GTK 4 windows resize from under Mutter; a
  press further out in the shadow goes to the window behind. The Adwaita
  theme's decoration view resizes from that band.
- *Drawing:* the shadow (libadwaita's, measured: 0.19 opacity at the edge,
  falling off over 30 pixels, weaker above and stronger below) is made
  from corners and edges computed once per margin and radius and kept in
  the X server; the expose copy takes the window's contents and the
  shadow as rectangles and only the four corner squares through the
  rounded clip. A 40-step resize drag under Mutter: every step reaches the
  window and its first copy follows the configure within about 6 ms,
  the same as without a shadow.
- *Borderless windows:* with `GSBackBorderlessWindowAlpha` (the theme sets
  it too) and a compositing manager, borderless windows such as menus and
  tool tips get the 32-bit visual, so a theme can round their corners, as
  libadwaita's popovers and tool tips are. No margin or shadow for them.
  This covers every borderless window, an application's own included:
  what it leaves transparent shows what's behind it.
- *Tests:* `Tests/x11/shadowmargin.m` forks a window manager that lists
  `_GTK_FRAME_EXTENTS` and a compositing manager that only owns the
  selection, and checks the visual, the extents, the window size, the input
  shape (also after a resize the program makes), the maximized state, the
  compositing manager stopping and starting, the scale factor,
  non-retained and borderless windows, a window manager without
  `_GTK_FRAME_EXTENTS`, and the Motif hints (19 checks; 14 fail without
  the patch).
- *Scale factor:* the margin, the corner radius and the resize band are
  in points, multiplied by the gui's scale factor (`GSScaleFactor`), as
  GTK's grow with its scale; the shadow's fall-off scales with them. At 2×
  under Mutter: extents 60 60 48 72, the band 24 pixels, the shadow and
  corners as at 1× (checked by hand; `shadowmargin.m` checks the extents,
  the band and the margin after a maximise).
- *Frame changes:* when the margin changes the window manager re-fits
  the window, usually configuring it for the old margin first. libs-back
  holds the frame from the gui until those ConfigureNotify events stop
  (50 ms with none, 300 ms at most; a ConfigureNotify also looks for a
  new state, which Mutter may configure before the PropertyNotify for it
  arrives) and sends it once, then exposes the
  whole window from the new buffers: a maximize is one resize, not
  three, at 1× and 2×. A restore is two, since Mutter configures the restored size
  before it changes the state, while the window still has no margin
  (`make check-mutter-shadow` in the theme counts them, and checks the
  shadow is drawn again).
- *Popovers (2026-10-05):* libadwaita's menus are popovers with a smaller
  shadow (box-shadow `0 1px 5px 1px` at 9% and `0 2px 14px 3px` at 5%
  black) and 15px corners. Mutter draws no shadow for a 32-bit window (it
  can't tell its shape), so, as GTK 4 does, the menu draws its own in a
  margin, computed (as a browser does) from the distance to the rounded
  outline, so it follows the corners. A borderless window marked with
  `NSUtilityWindowMask` (a theme
  marks its menus' windows; a borderless window has no other use for the
  bit) gets a popover's margin (14, 14, 12, 16) when `GSBackPopoverShadows`
  is YES, on a window's terms, and `GSBackPopoverCornerRadius` rounds it;
  presses reach only its visible part. The marker is the weak point: the
  backend creates the X window before libs-gui registers the NSWindow, so
  it can't ask the window's class (as with libs-gui#965). A cleaner
  upstream form would be a style bit or a `GSDisplayServer` call from
  libs-gui for popovers.
- *Popover arrows (2026-10-09, theme #74):* a popover whose window also
  holds an arrow (an app's panel conforming to `GSThemePopoverPanel`)
  tells libs-back where its body is, with
  `-setPopoverBodyInsetLeft:right:top:bottom::` in points. The shadow and
  the rounded corners then follow the body. The inset, where the theme
  draws the arrow, is laid over the shadow, so what it leaves clear shows
  the shadow, as GTK 4 draws it. A change of inset rebuilds the shadow and
  exposes the whole window. A popover with an inset composites its expose
  rather than copying rectangles; popovers are small. Windows without an
  inset are drawn as before.
- *Known limitations:* tried under Mutter, KWin and Xfwm4 (the margin, shadow
  and rounded corners) and Openbox (no `_GTK_FRAME_EXTENTS`: no margin);
  the art and xlib graphics backends don't define XRENDER and never make
  32-bit windows.

### 3. Window states (`_NET_WM_STATE`) (maximise done in the theme)

libs-back sets `_NET_WM_STATE` for skip-taskbar, sticky and modal, but
doesn't read the maximised, tiled or fullscreen states, and `-zoom:` resizes
the window itself instead of asking the window manager (which then doesn't
know the window is maximised: no restore on drag, no tiling interplay).

- Ask the window manager to maximise and restore with
  `_NET_WM_STATE_MAXIMIZED_VERT`/`_HORZ` client messages (a
  `GSDisplayServer` call used by `-[NSWindow zoom:]` when the window manager
  supports it).
- Read `_NET_WM_STATE` on PropertyNotify and pass maximised, fullscreen and
  the tiled edges (`_NET_WM_STATE_TILED` where supported, Mutter's
  `_GTK_EDGE_CONSTRAINTS` otherwise) to the window, for example as an
  `NSAppKitDefined` event that the decoration view receives.

### 4. Letting a theme ask for GNUstep-drawn decorations

The backend reads `GSBackHandlesWindowDecorations` /
`GSX11HandlesWindowDecorations` in `-[XGServer _setupRootWindow]`
(XGServerWindow.m around line 1582) into a file-static `BOOL`. The theme is
loaded later: its `+initialize` runs from inside the backend's own start-up
(seen in a backtrace), after that read. So a theme that draws its own
decorations can't turn them on; each user or app has to set the flag, and
then gets the theme's decorations only while that theme is in use.

Proposal: a key in the theme bundle's Info.plist, for example
`GSThemeWindowDecorations = client`, that libs-gui reads from the theme named
by the `GSTheme` default before it creates the display server
(`-[NSApplication _init]`, before `+[GSDisplayServer serverWithAttributes:]`)
and passes on (a volatile defaults domain, or a server attribute). An
explicit user default still wins.

**Patch:** no new key. The theme sets `GSBackHandlesWindowDecorations = NO`
in its Info.plist `GSThemeDomain`, which `-activate` already installs as a
volatile domain; `GSThemeInstallBackendDefaults()` in GSTheme.m installs
that one value early, from the bundle's Info.plist without loading the
theme, unless the user set `GSBackHandlesWindowDecorations` or
`GSX11HandlesWindowDecorations`. `-[NSApplication _init]` calls it just
before creating the display server. The theme path lookup moves out of
`+loadThemeNamed:` into `GSThemePathForFileName()` for it.

### 5. Window types (`_NET_WM_WINDOW_TYPE`)

`-setwindowlevel::` types a window from its level alone. A context menu or
a pop-up button's menu (`NSPopUpMenuWindowLevel`) becomes `_DIALOG` (the
`_POPUP_MENU` line is there, commented out), so Mutter focuses it and the
window it belongs to is drawn unfocused while it's open. A modal panel is
`_NORMAL`. A tool tip is meant to be `_TOOLTIP`, but libs-gui sets its level
before the window is registered, so `GSWindowWithNumber()` finds nothing and
it becomes `_DIALOG` too (libs-gui#965).

GTK types its menus `_DROPDOWN_MENU` (from a menu bar), `_POPUP_MENU`
(context menus, submenus) or `_COMBO`, its tool tips `_TOOLTIP`, its drag
icons `_DND` and its dialogs `_DIALOG`. Mutter neither focuses nor animates
the menu and tool tip types, stacks them above other windows and keeps their
parent drawn as focused (`src/core/window.c`, 48.7); it accepts them on
managed windows, which is what GNUstep's menus are. Compositors such as
picom key their shadow, opacity and fade rules on the type.

**Patch:** `-_setWindowType:`, split out of `-setwindowlevel::`, which calls
it. At the pop-up menu level a `GSTTPanel` is `_TOOLTIP`, an `NSMenuPanel`
`_POPUP_MENU` and the drag window (`XGRawWindow`) `_DND`; anything else there
stays `_DIALOG`. The new types are followed by `_DIALOG`, what these
windows were before: EWMH lists types in order of preference, and Openbox,
which knows none of the menu or tool tip types, then treats them as it did.
A modal panel is `_DIALOG`. Other levels keep their types.
`-orderwindow:::` calls it again just before mapping a window at the pop-up
menu level, when its class is known, which fixes the tool tip.

Not in the patch: a menu bar's menus stay `_MENU` (the type for torn-off
menus), because in GNUstep's own menu style (`NSNextStepInterfaceStyle`)
submenus are windows that stay open. A theme with an in-window menu bar can
set `_DROPDOWN_MENU` after the level, as the Adwaita theme does.

### Wayland

The Wayland backend always leaves the decorations to GNUstep
(`-handlesWindowDecorations` returns NO) and already uses `xdg_toplevel_move`,
`xdg_toplevel_resize` and `xdg_surface_set_window_geometry`. This proposal is
about X11, where GNUstep apps run on GNOME today (Xwayland); items 2 and 3
would map to the window geometry and the toplevel's configure states on
Wayland.

### Contact

Dan Boyd (plugins-themes-adwaita). A test program for each item can follow;
the theme's `make check-quirks` already exercises the decoration view with
`-GSX11HandlesWindowDecorations NO`.
