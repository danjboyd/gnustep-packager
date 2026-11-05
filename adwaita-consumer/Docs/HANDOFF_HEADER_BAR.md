# Handoff: an Adwaita header bar drawn by GNUstep

Written 2026-09-25 for whoever picks this up in a new session. It covers the
goal, what's already in place, verified facts about GNUstep's window
decorations (with file and line references), a proposed plan, and the open
questions. Start with "Before you start" and "Testing".

## Goal

GNOME apps have no separate title bar: the window's top row is a header bar
holding the title, the app's main controls, the main menu button (☰) and the
window buttons, with rounded top corners and a shadow. GNUstep apps under
this theme get Mutter's title bar (server-side decorations, drawn by the
window manager), with the app's toolbar or ☰ bar as a second row under it.

Build a header bar that GNUstep draws itself (client-side decorations, CSD):

- one row: centred bold title, window buttons (minimise, maximise, close)
  on the right as GNOME draws them, and ☰ just left of them when the app uses
  the primary menu (`GnomeThemeMenuStyle = primary`);
- later, the window's toolbar items in the same row, as a GNOME header bar
  holds its buttons;
- moving, resizing, double-click to maximise, and window snapping still
  working as well as they do with Mutter's title bar.

The user (Dan) asked for this as the next piece of work. It was discussed as
"option 3" when the primary menu was designed; options 1 and 2 (☰ in the
toolbar, or a slim bar) are built.

## Before you start

- Repo: `~/git/gnustep/plugins-themes-adwaita` (branch `main`, commits up to
  `ad13364` at the time of writing, nothing pushed). Read `README.md` and
  `Docs/IMPROVEMENTS.md` first: the Fixed table records every change and
  why.
- Sibling checkouts used for reading GNUstep's source: `~/git/gnustep/libs-gui`,
  `~/git/gnustep/libs-back`, `~/git/gnustep/apps-gorm`. The installed GNUstep
  is gui 0.32.0 / base 1.31.1 under `/usr/GNUstep`.
- Commit style: code, QuirkProbe and docs as separate commits, messages in
  plain present tense, ending with the Co-Authored-By line. Commit only when
  Dan asks. Install the theme for his apps with
  `make install GNUSTEP_INSTALLATION_DOMAIN=USER`.
- Docs style: short plain sentences, measured facts, no marketing words.
  Code comments explain *why*, as the existing ones do.

## What's already in place

- `Source/Rendering/GnomeThemePrimaryMenu.m`: the primary menu. A
  `GnomeThemePrimaryMenuButton` view draws ☰ as a flat header bar button
  (34px, 6px margins, hover 7% / pressed 16% of the text colour, 6px
  corners) and, when clicked, shows a copy of the main menu right-aligned
  under itself (`GnomeThemeCopyPrimaryMenu`). It is placed in the toolbar
  (narrowed via `-[GSToolbarView setFrame:]`) or in a slim bar that
  replaces the menu bar (`-menuHeightForWindow:`, `-setMenu:forWindow:`).
  A header bar should reuse this button and the copy/show logic.
- `Source/GnomeTheme.m`: `GnomeThemeDrawApplicationMenuIcon()` draws ☰;
  `GnomeThemeUsesPrimaryMenu()` reads the setting (user default, then the
  app's Info.plist).
- Toolbar styling (flat buttons with hover, light bottom edge, icon-only
  default) is in `Source/Rendering/GnomeThemeControls.m`, search for
  `GSToolbarButton`.
- Settings: `Source/Settings/GnomeThemeSettings.m` reads GNOME's GSettings
  (`org.gnome.desktop.interface`) with GIO. The header bar will also want
  `org.gnome.desktop.wm.preferences` (`button-layout`, `titlebar-font`,
  `action-double-click-titlebar`).
- Theme method overrides use GSTheme's `_override<Class>Method_<selector>`
  convention; call the original through `GnomeThemeOriginalMethod()`
  (`Source/GnomeTheme.h`), which also works for subclasses. Overriding an
  inherited method only affects the named class (GSTheme adds the method to
  that class).

## Verified facts about GNUstep's decorations

- Who draws the frame is the backend's choice:
  `-[GSDisplayServer handlesWindowDecorations]`. The X11 backend reads the
  user defaults `GSBackHandlesWindowDecorations`, then
  `GSX11HandlesWindowDecorations` (`libs-back/Source/x11/XGServerWindow.m`,
  around line 1487), when the display server is created at application
  start. Default: the window manager decorates.
- With `-GSX11HandlesWindowDecorations NO`, GNUstep draws its own title bar
  today, in the NeXT style (black bar, round miniaturise and close buttons):
  `Docs/Screenshots/headerbar-baseline.png`, ThemeDemo on a private Xvfb
  display with this theme. The theme doesn't style it yet.
- The decoration view class comes from the theme:
  `-[GSTheme windowDecorator]` (`libs-gui/Source/GSThemeWindow.m:91`)
  returns `GSBackendWindowDecorationView` when the backend decorates and
  `GSStandardWindowDecorationView` otherwise. A theme can override it to
  return its own subclass, e.g. `GnomeThemeHeaderBarDecorationView`.
- `GSStandardWindowDecorationView` (header installed:
  `GNUstepGUI/GSWindowDecorationView.h`, source
  `libs-gui/Source/GSStandardWindowDecorationView.m`) has a title bar rect,
  a *bottom* resize bar only (`resizeModeForPoint:` knows bottom, bottom-left
  and bottom-right), close and miniaturise buttons (no maximise), and moves
  and resizes the window itself in an event loop (`moveWindowStartingWithEvent:`
  calls `setFrameOrigin:` per drag event).
- Its drawing and sizes go through GSTheme: `titlebarHeight`,
  `resizebarHeight`, `titlebarButtonSize`, `titlebarPadding{Left,Right,Top}`,
  `drawTitleBarRect:forStyleMask:state:andTitle:`, `drawWindowBorder:…`
  (`libs-gui/Source/GSThemeDrawing.m` from line 1776),
  `standardWindowButton:forStyleMask:` (`GSThemeWindow.m:39`).
- The menu bar (Win95 style) and toolbar are subviews of the decoration
  view, laid out in `-[GSWindowDecorationView layout]`,
  `addMenuView:`/`removeMenuView`, `addToolbarView:`
  (`libs-gui/Source/GSWindowDecorationView.m`, from line 277 and 460). The
  primary-menu code already hooks these.
- The X11 backend has no support for `_NET_WM_MOVERESIZE` (window-manager
  driven moves and resizes, which give Mutter's snapping, tiling and edge
  resizing), `_GTK_FRAME_EXTENTS` (tells Mutter where the shadow margin is),
  or ARGB (translucent) top-level windows. It does set `_MOTIF_WM_HINTS`
  (`XGServerWindow.m` around line 311) to ask for no WM decorations.
  Everything in this bullet was checked by searching `XGServerWindow.m`.

## Proposed plan

### Phase 1: theme only

1. The opt-in is the backend flag alone (Dan, 2026-09-25): whenever
   GNUstep draws the decorations (`GSX11HandlesWindowDecorations NO`), this
   theme draws the header bar. There is no separate theme setting.

   Checked 2026-09-25: the theme can't set the backend flag itself. The
   theme is loaded (`+[GSTheme initialize]`, then `-[GnomeTheme activate]`)
   from inside the X11 backend's start-up, after the backend has copied the
   default into a file-static `BOOL` (`XGServerWindow.m:79`, read at 1485).
   With `GSX11HandlesWindowDecorations = NO` in the theme's runtime defaults
   domain, ThemeDemo on Xvfb had no title bar (the backend still left
   decorations to the window manager); with `-GSX11HandlesWindowDecorations
   NO` on the command line, GNUstep drew its own. Overriding
   `-[XGServer handlesWindowDecorations]` doesn't help either: the backend
   reads the static directly (lines 224, 341, 1618, 1906 and others), so
   the WM would still decorate. Loading code earlier through
   `GSAppKitUserBundles` would work but needs a second bundle per user.
   Until libs-back changes (phase 2 can add a way for the theme to ask for
   client-side decorations), the user or app sets the backend flag.
2. `-windowDecorator` returns `GnomeThemeHeaderBarDecorationView`, a
   subclass of `GSStandardWindowDecorationView`:
   - height 47 (libadwaita's header bar, measured in the reference renders
     used for the tab work), window background colour, a light
     bottom edge like the toolbar's, bold centred title in the title font
     (`titlebar-font`), dimmed when the window isn't key;
   - window buttons as libadwaita draws them (round, with symbolic icons
     and a grey circle on hover; about 24px circles with 16px icons, from
     memory, so measure them against a libadwaita render), in `button-layout`
     order (GNOME's default `appmenu:close`; Dan's desktop shows
     minimise, maximise, close). Maximise needs its own button (the
     standard view has none) and `-[NSWindow zoom:]`;
   - ☰ in the header bar when the primary menu is on (reuse
     `GnomeThemePrimaryMenuButton`), and then no ☰ bar or toolbar ☰;
   - resizing from every edge and corner, not only the bottom bar: a few
     pixels inside each edge (there's no shadow margin to put them in until
     phase 2), with the matching cursors (the frame-resize cursor images are
     already in `Resources/ThemeImages`);
   - double-click on the title: `action-double-click-titlebar` (default
     toggle-maximise).
3. Check panels, sheets (`GSAlertSheet` is borderless and must stay so),
   utility windows, alerts (the AdwAlertDialog layout in
   `GnomeThemeAlerts.m`), windows without a title, and fullscreen.

### Phase 2: libs-back, for Mutter integration

Upstream changes to `libs-back` (discuss with its maintainers first):

- send `_NET_WM_MOVERESIZE` when the header bar is dragged or an edge is
  pressed, so Mutter moves and resizes (snapping to edges, tiling, the
  resize cursor feedback, Super-drag);
- an ARGB visual for decorated-by-GNUstep windows, a transparent margin with
  a drawn shadow, and `_GTK_FRAME_EXTENTS` so Mutter treats the margin as
  shadow (input goes through it, snapping uses the visible edge); this also
  allows libadwaita's rounded top corners;
- `_NET_WM_STATE` for maximised and tiled states, so the header bar can drop
  the shadow and corners, and the maximise button can show "restore".

### Phase 3: toolbar in the header bar (done 2026-10-02)

Move the window's toolbar items into the header bar row (start items on
the left, trailing ones on the right, ☰ last), leaving no separate toolbar
row. NSToolbar has no notion of start and end groups; flexible spaces could
mark the split. Opt-in per app (see Decisions).

Built (2026-10-02): `GnomeThemeHeaderBarToolbar` (user default, then the
app's Info.plist) puts a titled window's visible toolbar in the bar. The
toolbar view lies between the buttons at the bar's start and those at its
end (☰ included), 6pt from them; the header bar decoration view overrides
`-addToolbarView:`, `-removeToolbarView:`, `-adjustToolbarView:`,
`-contentRectForFrameRect:styleMask:` and `-frameRectForContentRect:...`
and clears `hasToolbar` around `-[GSWindowDecorationView layout]`, so no
toolbar row is reserved and the window keeps its size. The title goes in
the widest flexible space (after the items without one). GSToolbarView
draws no background there, isn't opaque, and its empty parts and spaces
hit-test through to the bar (moves, double-click, window menu). Items show
icons alone, an item without an icon its label as a text button
(vertically centred: libs-gui draws a label at the top of its frame).
QuirkProbe `header-bar-toolbar`; tried with ScreenshotTool under GNOME
Shell.

Finished (2026-10-02): right to left, the toolbar is mirrored after every
`-[GSToolbarView _reload]` (libs-gui lays it out left to right): the items
within the clip view, the clip view to the right end and the » of the
items that don't fit to the left, as GTK mirrors its header bar (an app's
arrow icons stay as they are). A toolbar too wide for the bar keeps
libs-gui's overflow: the items that don't fit go into the » menu, which
opens and runs them; the title is shortened first. In the bar the toolbar
has no border mask (libs-gui kept a point for the bottom line, putting the
items 1pt high and » 1pt taller). QuirkProbe `header-bar-toolbar-overflow`
and `header-bar-toolbar-rtl`. A first click on an item of a window that
isn't active only activates it, as anywhere in GNUstep (GTK passes it
through); left as it is.

## Decisions (Dan, 2026-09-25)

- The header bar becomes the default once it's solid. Until then it stays
  opt-in behind the setting.
- Phases 1 and 2 ship together: build the whole thing before shipping.
  Phase 1 alone (no Mutter snapping, square corners, no shadow) is not a
  release.
- Phase 3 (toolbar items in the header bar row) is opt-in per app.

## Progress (2026-09-25)

Phase 1 is built: `Source/Rendering/GnomeThemeHeaderBar.m`, the ☰ hand-over
in `GnomeThemePrimaryMenu.m`, `button-layout` and
`action-double-click-titlebar` in `GnomeThemeSettings`, nine `header-bar-*`
QuirkProbe checks plus `primary-menu-escape`. `make check-quirks` runs four
configurations (38, 42, 46 and 50 checks, all passing). Dan tried the demo
by hand on GNOME Wayland (menu bar and primary menu) and was happy with it.

Measured and settled (from `Reference/HeaderBar/headerbar_reference.py`,
libadwaita 1.7.6):

- The bar is 46px *including* the 1px border GTK draws round a window
  without a compositor shadow: the border covers the bar's outer pixels, and
  the buttons' 6px margins count from the window's edge. (The "47" above was
  46 plus that border counted twice.)
- libadwaita's bar is flat: the window background, no bottom line.
- Window buttons: 34px, 3px apart, a 24px circle at 10% of the text colour
  (15% hover, 30% pressed) round a 16px icon; icons drawn from Adwaita's
  `window-*-symbolic.svg` paths (restore is one 6px square outline).
- Title: the bold interface font (libadwaita ignores `titlebar-font`),
  centred with its ascent and descent box centred in the bar.
- Not focused (GTK's backdrop state follows keyboard focus, not main-window
  status): text at 60% of the text colour over the background.

Window kinds: panels and utility panels get the bar with a close button; a
window with buttons and no title gets the bar without one; resizable-only
windows keep a border; borderless and `NSFullScreenWindowMask` windows get
neither. Alerts (GSAlertPanel, alone or as a sheet) have no bar, as
AdwAlertDialog: in header bar mode they are created with
`NSDocModalWindowMask` instead of `NSTitledWindowMask` (NSPanel can become
key without a title bar).

GNUstep facts found on the way:

- `-[NSWindow zoom:]` maximises but only goes back through an autosave
  name; the header bar keeps the frame to restore itself.
- `GSWindowDecorationView -layout` puts a menu bar 1pt above the content
  area; the header bar trims it so the bar keeps its 46px.
- NSButton is flipped (the icons turn over for it).
- GNUstep has no `-setStyleMask:` and no `-toggleFullScreen:`.
- In gui 0.32.0 any mouse up ends menu tracking, so a click closed ☰
  straight away; fixed on master (upstream item 8). ☰ opens on the release
  and tracks from a fresh press; Escape closes it.
- QuirkProbe renders come from the window's backing store: call
  `displayIfNeeded` after a state change before rendering. Cursor rects
  post `NSCursorUpdate` events: deliver them before reading
  `[NSCursor currentCursor]`.

Smaller gaps closed afterwards (2026-09-25): the scale factor (offsets in
device pixels; the content origin GNUstep leaves unscaled is corrected),
right-to-left mirroring (matched to a GTK `--rtl` render), GNOME's right,
middle and double-click title bar actions with a window menu, and
libadwaita's high contrast ring and border. `make check-quirks` runs six
configurations (38, 42, 48, 52, then 9 and 9 header bar checks in dark and
high contrast). Left as is: the title and icon colour is the theme's text
colour (#1f1f1f), where libadwaita uses 80% black (#323236); that is a
palette-wide choice.

Phase 2a (2026-09-25), the window manager's part done in the theme on X11:
`Source/Adapters/GnomeThemeWindowManager.m` sends `_NET_WM_MOVERESIZE`
(moves after GTK's 8px drag threshold; resizes on the press),
`_NET_WM_STATE` maximise toggles and `_GTK_SHOW_WINDOW_MENU`, and reads
`_NET_WM_STATE` for the restore icon, all through Xlib on
`-[GSDisplayServer serverDevice]`/`-windowDevice:`. Each call checks the
backend is X11 and the message is in `_NET_SUPPORTED`, else the header bar
does it itself. The decisive fix: libs-back's `_MOTIF_WM_HINTS` for windows
it doesn't decorate allow no functions, so Mutter refused everything; the
header bar rewrites them in `-setWindowNumber:`.

Verified under Mutter (`make check-mutter`, GNOME Shell 48 on a private
Xvfb): allowed actions, maximise and restore by double-click, a move
handed to Mutter taking the window past the screen's edge, a resize from
the right edge; Mutter's window menu on right-click by eye. The request
names the button the X server reports held (`XQueryPointer`), not
`-[NSEvent buttonNumber]`: libs-back 0.32 returns the X number there (left
is 1) and master since b037ebf AppKit's (left is 0), and Mutter declines a
move whose button isn't down. (That mismatch first looked like xdotool not
reaching Mutter on Xvfb; it wasn't.) Drag to the top to maximise didn't
trigger with xdotool; try it by hand.

Warning for test sessions: a GNOME Shell session started for testing runs
gvfs, which mounts plugged-in devices (Dan's phone is always plugged in: it
is the network) under the session's runtime directory. Start such sessions
with `GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 GIO_USE_VOLUME_MONITOR=unix` and
never delete their directories across file systems (the check script's
cleanup shows how).

## Phase 2b (started 2026-09-25; done 2026-10-02, patches not yet sent upstream)

Work in two new git worktrees, on local branches, **nothing committed or
pushed**, nothing installed system-wide:

- `~/git/gnustep/libs-gui-csd` (branch `csd-theme-decorations`, from
  origin/master ff49ac830), built: `Source/obj/libgnustep-gui.so.0.32.0`
  (built with `make ADDITIONAL_OBJCFLAGS=-Wno-error=format-security`).
  Proposal item 4: `GSThemeInstallBackendDefaults()` in GSTheme.m (the
  theme path lookup factored out of `+loadThemeNamed:` into
  `GSThemePathForFileName()`), declared in GSThemePrivate.h, called in
  `-[NSApplication _init]` just before the display server is created. It
  reads `GSBackHandlesWindowDecorations` from the named theme's
  `GSThemeDomain` without loading the theme, and installs it in the
  GSThemeDomain volatile domain unless the user set
  GSBackHandlesWindowDecorations or GSX11HandlesWindowDecorations.
  Verified: with no user setting (isolated defaults, below), ThemeDemo gets
  the header bar from the theme alone with this libs-gui, and none with the
  installed one.
- `~/git/gnustep/libs-back-csd` (branch `csd-header-bar`, from origin/master
  5db2ae7), built: `Source/libgnustep-back-032.bundle`.
  - Item 0: `setWindowHintsForStyle()` keeps the functions for windows the
    gui decorates (decorations 0, functions from the style, plus move).
  - Item 2, the shadow margin: `gswindow_device_t` gains `shadow[4]`
    (left, right, top, bottom), `corner_radius`, `shadow_eligible`. A
    styled window gets a margin of 30/30/24/36 px (measured from
    libadwaita under Mutter) when the gui decorates, `GSBackWindowShadows`
    is YES and a compositing manager owns `_NET_WM_CM_Sn`. Such windows
    get a 32-bit ARGB visual of their own (`argb_visual()`; master's
    `xlibimage.c` RCreateContext always uses the default 24-bit visual, so
    nothing else has alpha). `-_offsets::::for:` returns minus the margin
    when the gui decorates (else `-styleoffsets`), and is used by the
    frame, window-rect and point conversions, `-setWindowdevice:forContext:`
    and `-flushwindowrect::`; the WM hint conversions keep `-styleoffsets`
    (hints use the X window's own origin). `-_updateShadowOf:` sets
    `_GTK_FRAME_EXTENTS` and an XShape input region of the visible part
    plus a 12px resize band for resizable windows (`shadow_resizable`;
    clicks further out in the margin go through). `-_updateShadowSizeOf:` drops the
    margin while `_NET_WM_STATE` is maximised (both) or fullscreen, or
    `_GTK_EDGE_CONSTRAINTS` has a tiled bit, and moves the min and max
    size hints (X window sizes, margin included) by the change, as GTK
    does; PropertyNotify on those calls it and sends the gui the new
    frame; ConfigureNotify reshapes the input region; Expose copies the
    margin from the backing store.
  - XGCairoModernSurface keeps a separate shadow image
    (`create_shadow()`: 0.19·e^(−d/10) at the sides, weaker above, a little
    stronger below, following the corner radius) and `-handleExposeRect:`
    copies the backing store through a rounded clip of the visible part
    (`visible_path()`) and the shadow everywhere else, so nothing the gui
    draws can un-round the corners.
- Theme (this repo, committed in 6926fb0): `Resources/Info-gnustep.plist`
  GSThemeDomain sets `GSBackHandlesWindowDecorations = NO`,
  `GSBackWindowShadows = YES`, `GSBackWindowCornerRadius = 15`;
  `GnomeThemeWindowManagerHasShadow()` is YES when `_GTK_FRAME_EXTENTS`
  exists (also while it is 0, maximised or tiled), and the header bar then
  paints its 1px border in the window background (the shadow's outline is
  the edge, as in libadwaita; maximised, libadwaita has no border at all).
  `make check-quirks` passes.

Verified under Mutter (GNOME Shell on a private Xvfb, `:63`): the X window
is 32-bit, `_GTK_FRAME_EXTENTS` = 30, 30, 24, 36, the visible window sits
where the frame says, the shadow is there (about 18% at the edge, like
libadwaita's) and all four corners are rounded with the shadow following
them.

Step 1 done (2026-10-02, GNOME Shell on a private Xvfb, 1280x800 and
1920x1080, against libadwaita 1.7 in the same session): maximise by
double-click, by the button and by Super+Up, restore by double-click, by
the button and by dragging the bar down, tile with Super+Left and
Super+Right and untile with Super+Down. Maximised and tiled, the extents
are 0, the window fills the work area (or its half) with square corners
and no border, and the button shows the restore icon (6px; 8px
otherwise). Restored and untiled, the screen is pixel for pixel what it
was before (shadow, corners, frame). The free edge of a tiled window
resizes. Two fixes on the way:

- libs-back: the min/max size hints kept the margin while it was 0, so
  Mutter restored a maximised window to the stale minimum (the window came
  back 20px wider and taller); `-_updateShadowSizeOf:` now moves them with
  the margin.
- Theme: maximised, `_GTK_FRAME_EXTENTS` is 0 and the header bar drew the
  grey border of a window without a compositor; libadwaita has none.

Differences from libadwaita left as they are: tiled, GTK keeps a 20px
margin (extents 20, 20, 20, 20) with no shadow but a faint 1px outline
outside the edge and its resize zone there; ours drops the margin, and
the free edge resizes from inside the window. Normal, GTK's extents are
61, 61, 55, 67; ours are the 30, 30, 24, 36 the visible shadow needs (the
resize band, step 2, fits in them). ThemeDemo's minimum width (722) doesn't fit half
of a 1280px screen, so Mutter won't tile it there: test tiling at
1920x1080.

Step 2 done (2026-10-02, same session setup, against libadwaita 1.7 in
the same session). Measured first: libadwaita resizes from a band 1 to 12
px outside its visible edge on every side, and not from inside (a press
inside the top is the header bar's: a move). Ours resized from 5px inside
the edges and passed every press in the shadow through. Now, while the
shadow shows, ours does as libadwaita, to the pixel (edge row and inside:
no resize; 1 and 12px out: resize; 13px out: the window behind):

- libs-back: the input shape takes the visible part plus a 12px band
  (within the margin) for resizable windows. The window style libs-back
  keeps when the gui decorates has no resize bit, so the device records
  `shadow_resizable` when the shadow is set up.
- Theme: `GnomeThemeWindowManagerShadowExtents()` gives the margin now;
  the header bar's edges are the band outside its bounds (hit test,
  cursor rects, corners as the band's two arms), none inside. Without a
  shadow (maximised, tiled, no compositor) the 5px inside edges stay, as
  GTK's without a compositor. Edge and title bar tests use the pixel's
  centre: GNUstep gives an event its pixel's top edge, so the row just
  below the window came as y 0, inside the bounds.

Verified: all four sides and corners resize (Mutter does it, from 6px
out at the corners, diagonally), cursors over the band are the resize
ones (XFixes cursor names), a drag on the bar is Mutter's move (past the
screen's edge), a click 20px out in the shadow activates and raises the
window behind, and a tiled window still resizes from inside its free
edge. `make check-quirks` and `make check-mutter` (installed libraries)
pass.

Step 3 done (2026-10-02): `make check-mutter-shadow` runs
`Tests/Scripts/run-mutter-check.sh --shadow` against `MUTTER_CHECK_GUI`
and `MUTTER_CHECK_BACK` (by default the two worktrees' builds; skipped
when they aren't there). GNUstep's user defaults and user Library are
scratch directories (an isolated GNUstep.conf; libs-base takes an
absolute `GNUSTEP_USER_DIR_LIBRARY`), so the theme alone asks for the
decorations and nothing is linked into `~/GNUstep`; the check confirms
the libraries loaded from `/proc/PID/maps`. GNOME Shell's settings are a
scratch keyfile with a solid #777777 background, so the shadow can be
measured. Ten checks: allowed actions; a 32-bit window with extents 30,
30, 24, 36; darker 3px outside the edge, the background 40px out, the
top left corner rounded off; maximised, extents 0 and a square corner;
restored, the same frame and extents; Mutter's move; the right edge
resizing from 6px out, not from 3px in; and the window under the pointer
12px out but not 13px out. `make check-mutter` (installed libraries)
takes positions from the visible window too and still passes.

Step 4 done (2026-10-02, a scratch app opening one kind at a time under
GNOME Shell with the patched libraries): panels, utility panels
(`_NET_WM_WINDOW_TYPE_UTILITY`), resizable panels, a standalone alert and
an alert as a sheet (transient for its window) all get the 32-bit window,
the 30, 30, 24, 36 extents, the shadow and rounded corners. Only the
resizable ones take presses in the resize band (a fixed panel's band
goes through). Menus and tool tips are borderless: 24-bit, no shadow, as
planned.

Found on the way:

- Menus drew rounded corners and left what's outside the curve
  unpainted, which a compositor shows black (also with the installed
  0.32 libraries, so on GNOME today). Fixed in the theme: a menu is
  square, with its border, unless its window has an alpha channel
  (`GnomeThemeWindowManagerHasAlpha()`). QuirkProbe's offscreen renders
  paint the corners from the window background, so no probe check can
  see this; verified on screen.
- libadwaita's popover menus have 15px rounded corners and a soft shadow,
  and its tool tips 9px rounded corners (no shadow). Ours stay square
  until libs-back gives such borderless windows an alpha channel too: a
  decision for Dan (which windows, and whether menus get a shadow).
- libs-back types menus and tool tips `_NET_WM_WINDOW_TYPE_DIALOG` (GTK:
  `POPUP_MENU`/`DROPDOWN_MENU`, `TOOLTIP`) and panels `NORMAL` (GTK's
  dialogs: `DIALOG`).
- GNUstep enables cursor rects only in the key window, so the resize
  band's cursors don't show over an inactive window (GTK shows them).
- The standalone alert's heading and text are right-aligned;
  libadwaita's alert dialogs centre them.
- Against the patched libs-gui (master) a click on a menu bar title under
  Mutter showed no menu, though the same click with the installed 0.32
  did. xdotool clicks open neither on a bare Xvfb, and QuirkProbe's
  in-app clicks do open it on master, so this may be the synthetic input
  (see Testing); try it by hand in step 5. QuirkProbe against master also
  differs on table headers (header text at 113pt) and the menu shortcut
  inset (30pt for 16 to 20): theme work for when master is released.

Step 5 feedback (Dan, 2026-10-02, real desktop via `~/bin/gs-patched`):
everything looked right, but resizing was not smooth enough to sit next to
GPU-drawn GTK 4 apps, and menus opened on the release.

- Resizing, measured with timing in libs-back (a 200px drag in 40 steps
  under Mutter): with the shadow only 25 of 40 steps reached the window,
  each flush copy took 4.7 ms (0.34 without the shadow) and a new shadow
  4.4 ms. The copy drew the window through a rounded clip path and the
  shadow through its even-odd complement; it now copies rectangles (the
  window less its four corner squares, the margin from the shadow) and
  takes the rounded clip only in the corner squares: 0.44 ms. The shadow
  was computed per pixel over the whole window (sqrt and exp each); its
  corners and short edges are now computed once per margin and radius,
  kept in the X server, and each size's shadow is put together from them
  there: about 1 ms. Now 40 of 40 steps, configure to first copy 5.8 ms
  (6.9 without the shadow). libs-back already answers
  `_NET_WM_SYNC_REQUEST` (in `-flushwindowrect::`), so Mutter paces the
  resize to the redraws; what's left per step is GNUstep redrawing the
  window. `make check-mutter-shadow` gives the same shadow pixels.
- Menus: see the menu audit in the commit "Menus open on the press, as
  GTK's"; the theme no longer holds a menu bar press until its release.

Step 5 done (2026-10-02): Dan confirmed the shadow, resizing and menus on
his desktop. Style pass for upstream: the `_NET_WM_STATE` and GTK atoms
come from libs-back's atom table (`_GTK_FRAME_EXTENTS` and
`_GTK_EDGE_CONSTRAINTS` added to `XGGeneric.h`), braces and comments in
GNUstep's style, ChangeLog entries in both worktrees. The patches are
exported to `Docs/upstream-patches/` and the proposal says what each does;
`make check-mutter`, `make check-mutter-shadow` and `make check-quirks`
pass against them. Still local and uncommitted in the worktrees; sending
the proposal is Dan's.

Rounded menus and tool tips (Dan, 2026-10-02): libs-back gives borderless
windows the 32-bit visual when `GSBackBorderlessWindowAlpha` is YES (the
theme's GSThemeDomain sets it) and a compositing manager runs; the theme
rounds a menu (10pt) and a tool tip (libadwaita's 9pt, with its 1pt light
outline) when the window has an alpha channel, and keeps them square
otherwise. No shadow for them. `make check-mutter-shadow` checks a menu's
corner. Still open: window types for menus, tool tips and panels.

How to run against the patched libraries:

- libs-gui: `LD_LIBRARY_PATH=$HOME/git/gnustep/libs-gui-csd/Source/obj:$LD_LIBRARY_PATH`.
- libs-back: `ln -sfn ~/git/gnustep/libs-back-csd/Source/libgnustep-back-032.bundle
  ~/GNUstep/Library/Bundles/libgnustep-backcsd-032.bundle` and launch with
  `-GSBackend libgnustep-backcsd`; remove the link afterwards (it was
  removed at the end of the session).
- Mutter test session: GNOME Shell `--x11` on a private Xvfb with its own
  D-Bus session, settings in memory, scratch XDG directories and
  `GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 GIO_USE_VOLUME_MONITOR=unix`
  (see `Tests/Scripts/run-mutter-check.sh`; never delete its directories
  across file systems).
- Isolated GNUstep defaults (Dan has `GSX11HandlesWindowDecorations NO` set
  globally): a copy of `/etc/GNUstep/GNUstep.conf` with
  `GNUSTEP_USER_DEFAULTS_DIR` pointing at an empty directory, mode 0600,
  passed as `GNUSTEP_CONFIG_FILE`.

Then phase 3. The proposal to send to libs-back's maintainers
is `Docs/PROPOSAL_LIBS_BACK_CSD.md`.

## Testing

- `make check-quirks` runs `Examples/QuirkProbe` twice (menu bar and primary
  menu) on a private Xvfb display and must stay green (38 and 41 checks at
  the time of writing, plus one KNOWN upstream bug). Add header bar checks
  there: render the decoration view offscreen (see how `saveWindow:named:`
  renders the frame view) and measure; run the probe with
  `QUIRK_PROBE_ARGS="-GSX11HandlesWindowDecorations NO …"`.
- For clicks, send events through `NSApp`/the window inside the probe (see
  `QuirkProbeSendApplicationEvent` and `checkPrimaryMenu`, which uses a timer
  in `NSEventTrackingRunLoopMode` to inspect a menu while it tracks).
  Synthetic X input (xdotool) proved unreliable for GNUstep windows, even on
  Xvfb.
- Do not drive Dan's real GNOME desktop with xdotool. He works on it while
  sessions run; XTest input can't reach GNOME Shell (so it can't undo what it
  starts), and a stray pointer move to the top-left corner opened the
  Activities overview in an earlier session. Use a private `Xvfb :N` display
  and `import -window root` for screenshots. Gorm's and other apps' panels
  hide when the app isn't active, which happens on Dan's desktop because of
  focus-stealing prevention.
- libadwaita references: `Reference/AdwaitaDemo/adwaita_demo.py --screenshot`
  renders pages offscreen; small GTK4/libadwaita scripts rendered the same
  way (Gtk.WidgetPaintable + Gsk.CairoRenderer) give pixel-exact references
  for the header bar, window buttons and spacing. Measure, don't guess: the
  earlier work matched tabs, alerts and rows to the pixel this way.
- Compare against the GNUstep theme (`-GSTheme GNUstep`) to tell theme bugs
  from GNUstep's.

## Deferred, not part of this

- "Design surfaces" in Gorm (WYSIWYG palette and document windows drawn with
  GNOME metrics while Gorm's own panels stay compact): designed but deferred
  until Dan has talked to Gorm's maintainer. Notes: the private
  `+[NSFont _fontWithName:size:role:]` can make a default-size system font at
  GNOME's size that archives identically; Gorm's design windows are
  `GormNSWindow`/`GormNSPanel`, the palette area `GormPaletteView`.
