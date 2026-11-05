# GNUstep Adwaita Theme

`plugins-themes-adwaita` is an Adwaita-targeted theme plugin for GNUstep.

The goal is pragmatic rather than literal pixel-perfect GTK emulation: make
GNUstep applications feel at home on a modern GNOME desktop while staying
inside the GNUstep theme layer wherever possible.

The current priority is forward-looking GNOME integration, not strict backward
compatibility with the appearance of existing GNUstep applications. The main
use case today is making it possible to build new GNUstep apps that feel at
home on GNOME. Backward-compatibility improvements may still happen later, but
they are not the primary design constraint for this release.

## GNUstep's theme and Adwaita, side by side

The same apps, the same windows, left with GNUstep's default theme and right
with this one:

<table>
  <tr>
    <th width="50%">GNUstep theme</th>
    <th width="50%">Adwaita</th>
  </tr>
  <tr>
    <td><img src="Docs/Screenshots/compare/markdownviewer-gnustep.png" alt="MarkdownViewer with GNUstep's theme: the window manager's title bar, a grey in-window menu bar and toolbar, and arrow scrollers"></td>
    <td><img src="Docs/Screenshots/compare/markdownviewer-adwaita.png" alt="MarkdownViewer with Adwaita: a header bar holding the toolbar, the Read, Edit and Split switcher and the primary menu, rounded corners and a window shadow"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><a href="https://github.com/danjboyd/ObjcMarkdown">MarkdownViewer</a></td>
  </tr>
  <tr>
    <td><img src="Docs/Screenshots/compare/screenshottool-gnustep.png" alt="ScreenshotTool with GNUstep's theme, annotating a chart: bevelled toolbar buttons and a grey toolbar under the window manager's title bar"></td>
    <td><img src="Docs/Screenshots/compare/screenshottool-adwaita.png" alt="ScreenshotTool with Adwaita, annotating the same chart: its tools as a linked button group in the header bar with the primary menu, symbolic icons and round window buttons"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><a href="https://github.com/danjboyd/ScreenshotTool">ScreenshotTool</a></td>
  </tr>
  <tr>
    <td><img src="Docs/Screenshots/compare/gorm-gnustep.png" alt="Gorm with GNUstep's theme: document window, a window being designed, the Controls palette and the button inspector, all grey and bevelled"></td>
    <td><img src="Docs/Screenshots/compare/gorm-adwaita.png" alt="Gorm with Adwaita: the same windows with header bars, flat controls, libadwaita's check boxes and pop-up buttons"></td>
  </tr>
  <tr>
    <td colspan="2" align="center">Gorm, GNUstep's interface builder (its windows come from Gorm files, so it runs with compact metrics)</td>
  </tr>
</table>

<table>
  <tr>
    <th colspan="2">Adwaita, dark style</th>
  </tr>
  <tr>
    <td width="50%"><img src="Docs/Screenshots/compare/markdownviewer-adwaita-dark.png" alt="MarkdownViewer with Adwaita in GNOME's dark style: a dark header bar with the toolbar, the Read, Edit and Split switcher and the primary menu, over the same document"></td>
    <td width="50%"><img src="Docs/Screenshots/compare/themedemo-controls-adwaita-dark.png" alt="The theme's demo app in dark style: blue default button and checked boxes with white marks, ringed unchecked radio, the slider's light knob, pop-up and stepper"></td>
  </tr>
  <tr>
    <td align="center"><a href="https://github.com/danjboyd/ObjcMarkdown">MarkdownViewer</a></td>
    <td align="center">ThemeDemo's controls page</td>
  </tr>
</table>

What changes: libadwaita's header bar, with the window's toolbar in it and
GNOME's window buttons; its buttons, entries, switches, check boxes and
pop-ups; menus as popovers with the primary ☰ menu; overlay scrollbars;
GNOME's fonts, dark style and high contrast; GNOME's file chooser for open
and save panels, and its print dialog. All taken on GNOME Shell 48 (X11)
with libs-gui and libs-back built with the patches below; how each shot was
made is in
[`Docs/Screenshots/README.md`](Docs/Screenshots/README.md).

## Status and requirements

The theme as it stands relies on **GNUstep patches that are not upstream
yet** (see [`Docs/upstream-patches/README.md`](Docs/upstream-patches/README.md)):

- **libs-back:** window manager functions for windows GNUstep decorates
  (sent as [libs-back#244](https://github.com/gnustep/libs-back/pull/244)),
  GTK's window types for menus, tool tips and dialogs, an alpha channel for
  borderless windows, and GNOME's window shadow, rounded corners and popover
  shadow.
- **libs-gui:** letting a theme turn on GNUstep-drawn window decorations,
  which is how the header bar becomes the default.

Until they are released, build libs-gui and libs-back with the patches in
`Docs/upstream-patches/`. With stock GNUstep 0.32 the theme still works, but
the header bar has to be turned on by hand ([below](#header-bar)), and
windows, menus and tool tips have square corners and no shadow.

## Features

- **Header bar:** libadwaita's header bar drawn by GNUstep, with GNOME's
  window buttons, moving, resizing, tiling and the window menu through the
  window manager, the window's toolbar in the bar if the app wants it, and
  a document window's file name as its title with a dot while it has
  unsaved changes ([Header bar](#header-bar)).
- **Menus:** GNOME's primary ☰ menu, or a menu bar inside the window
  ([Settings](#settings)); menus drawn as libadwaita's popovers; titles that
  don't fit a narrow window fold into an overflow menu at the bar's end;
  context menus open at the pointer; inline button rows such as a zoom row
  ([below](#inline-button-rows-in-menus)).
- **Controls:** buttons, entries, search fields, pop-ups, check boxes,
  radios, switches, sliders, steppers, segmented controls and tabs as
  libadwaita draws them, and tables and outlines in Adwaita's style; symbolic icons tinted with the text
  colour ([below](#symbolic-icons)); translucent tool tips.
- **GNOME's settings:** light or dark style (`color-scheme`), the accent
  colour (`accent-color`, GNOME 47), high contrast, the interface and monospace fonts, `font-hinting`,
  overlay scrollbars, the window buttons' layout and the title bar's
  double-click action.
- **Dialogs:** alerts attached to the window they interrupt, without a bar,
  GNOME's file chooser for open and save panels, and GNOME's print dialog.
- **Window types** as GTK sets them, so the window manager and compositor
  treat menus, tool tips, drag images and dialogs as they do GTK's.
- **Metrics per window:** windows built in code at GNOME's sizes, windows
  from Gorm or nib files at GNUstep's ([Settings](#settings)), and an
  Adwaita palette for laying out GNOME-style windows in Gorm
  ([below](#designing-a-gnome-style-app-in-gorm)).

## Controls reference

<p>
  <img src="Docs/Screenshots/theme-controls.png" alt="ThemeDemo controls page" width="32%">
  <img src="Docs/Screenshots/theme-text.png" alt="ThemeDemo text inputs page" width="32%">
  <img src="Docs/Screenshots/theme-data.png" alt="ThemeDemo data views page" width="32%">
</p>

## Known issues

This is an alpha. What is open, with an issue for each in
[the tracker](https://github.com/danjboyd/plugins-themes-Adwaita/issues):

- Text is about 1.4% narrower than GTK's at the same font (#23): libs-back
  hints the metrics to whole pixels, and matching GTK exactly needs libs-gui
  to round the sizes it takes from text.
- Under GNOME Shell, the file chooser isn't attached to the app's window as
  a modal dialog (#44, a Mutter issue: GNOME/mutter#5106).
- Gorm's own inspectors are cramped at GNOME's fonts (#26).
- A few GNUstep bugs are worked around in the theme until fixes land
  upstream (#28, #29; see `Docs/upstream-issues/`).

## Scope

This theme targets stock Adwaita as the visual baseline for GNUstep on GNOME.

It does not currently aim to:

- support arbitrary third-party GTK themes
- reproduce GTK4's rendering architecture
- patch GNUstep where the theme layer can do the job: the libs-back and
  libs-gui patches it needs are the exceptions, kept small and sent
  upstream (`Docs/upstream-patches/`)
- guarantee that existing GNUstep applications will preserve their prior look
  unchanged under this theme

## Repository Layout

```text
Source/                  Theme implementation
Source/WindowTabbing/    Copy of gnustep-window-tabbing (Tools/vendor-window-tabbing.sh refreshes it)
Resources/               Theme bundle metadata and assets
Palettes/Adwaita/        Gorm palette of controls at GNOME's sizes
Examples/ThemeDemo/      GNUstep-side demo app
Examples/QuirkProbe/     Offscreen checks run by make check-quirks
Reference/AdwaitaDemo/   GTK4/libadwaita comparison harness
Reference/HeaderBar/     libadwaita header bar measurements and renders
Reference/AdwaitaTabBar/ libadwaita's AdwTabBar, for the window tabs' measurements
Tests/Scripts/           Check runners and capture helpers (readme-shots/: the README's screenshots)
Docs/                    Design notes and handoffs; Screenshots/
Docs/upstream-patches/   The libs-back and libs-gui patches the theme needs, with review notes
Docs/upstream-issues/    GNUstep (and Mutter) bug reports with reproducers
```

## Requirements

Build requirements for the GNUstep theme bundle:

- GNUstep make and GNUstep GUI development environment
- `pkg-config`
- `gio-2.0`, `glib-2.0` and `gobject-2.0` (GNOME's settings)
- `x11` (window manager integration)

At run time:

- GNUstep 0.32 or later. libs-gui and libs-back built with the patches in
  `Docs/upstream-patches/` give the header bar by default, the window
  shadow, rounded corners and rounded menus (see
  [Status and requirements](#status-and-requirements)).
- For GNOME's file chooser: `xdg-desktop-portal` with a GTK or GNOME
  backend. Without it, open and save panels are GNUstep's own.

Reference app requirements:

- Python 3
- PyGObject
- GTK4
- libadwaita

## Install and use

Releases are on the
[releases page](https://github.com/danjboyd/plugins-themes-Adwaita/releases).
Download a release's source archive, unpack it and build it as below. The
theme is a native bundle, so it has to be built against the GNUstep
installation it will run with.

Build and install the theme for the current user:

```sh
make
make install GNUSTEP_INSTALLATION_DOMAIN=USER
```

The bundle goes to `~/GNUstep/Library/Themes/Adwaita.theme`. Select it for
every app, or for one (by its defaults domain, here TextEdit's):

```sh
defaults write NSGlobalDomain GSTheme Adwaita
defaults write TextEdit GSTheme Adwaita
```

Apps pick the theme up when they start. To try it once without changing
anything, pass `-GSTheme Adwaita` on an app's command line.

## Demo apps

The GNUstep demo app, against the theme built in this checkout:

```sh
make -C Examples/ThemeDemo
bash Tests/Scripts/run-theme-demo.sh
```

The GTK 4 / libadwaita reference app, for comparison, whole or one page:

```sh
python3 Reference/AdwaitaDemo/adwaita_demo.py
python3 Reference/AdwaitaDemo/adwaita_demo.py --page controls   # or data, text
```

## Settings

The theme reads these from the user's defaults for an app
(`defaults write APP KEY VALUE`, or `-KEY VALUE` on the command line), then
from the app's own Info.plist (`GnomeThemeMetrics`, `GnomeThemeMenuStyle`
and `GnomeThemeHeaderBarToolbar`, so an app can declare how it was
designed):

- `GnomeThemeMetrics`: `gnome` or `compact`. Apps whose windows are built in
  code get GNOME's metrics: the interface font at GNOME's size (11pt at
  96dpi, about 14.7px), bold button titles, libadwaita's button padding and
  tab height. Apps with a main Gorm or nib file (`NSMainNibFile`,
  `NSMainStoryboardFile` or `GSMainMarkupFile` in their Info.plist) get
  `compact` metrics instead: GNUstep's 12pt, regular-weight button titles,
  GNUstep's button margins and tab height, so layouts made at those metrics
  fit. In an app built in code, the windows it loads from Gorm or nib files
  (its own, or libs-gui's panels) get compact metrics of their own: their
  controls' text at GNUstep's size and GNUstep's margins, indicators and tab
  height, while its other windows, its menus and its fonts keep GNOME's.
  Set `gnome` or `compact` to give every window the same; `auto` is the
  same as not setting it. A code-built app whose Gorm files were laid out
  for GNOME's metrics (with the Adwaita palette below) sets `gnome`.
- `GnomeThemeMenuStyle`: `primary` (the default) or `menubar`. With
  `primary` the menu bar becomes GNOME's main menu button (☰): at the end of
  the window's toolbar when it shows one, otherwise alone in a slim bar.
  Clicking it shows the app's menus, then its application menu's items
  (Preferences, About, Quit), as GNOME's primary menu lists them. The menu
  itself is unchanged, so key equivalents and validation work as before.
- `GnomeThemeHeaderBarToolbar`: `YES` puts the window's toolbar in the
  header bar's row, as a GNOME app packs its buttons there, instead of a
  row of its own (only with the header bar, below). Items before the
  toolbar's flexible space go at the bar's start, items after it at its
  end, and the title in the space; icons are shown without labels, and an
  item without an icon is a text button. Items that don't fit go into the
  toolbar's » menu; in right-to-left languages the bar is mirrored. Off by
  default: the toolbar has to suit it (a few icons, a flexible space).
  A user can turn it on for every app at once with
  `defaults write NSGlobalDomain GnomeThemeHeaderBarToolbar YES`; a setting
  for one app still wins, and an app whose Info.plist says `NO` (its
  toolbar doesn't suit the bar) keeps its own row. A change applies to open
  windows, which keep their size: the content gives up or takes the
  toolbar's row. Apps don't need to set their toolbars again.
- `GnomeFontScale`: a factor (0.8–2.0) applied to the interface font.
- `GnomeThemeColorScheme`: `force-dark` or `force-light` gives the app the
  dark or light style whatever GNOME's `color-scheme` (or a `-dark` GTK
  theme) says; `default` follows GNOME. Set it for one app
  (`defaults write MarkdownViewer GnomeThemeColorScheme force-dark`), for
  one launch (`-GnomeThemeColorScheme force-dark`), or for every app in
  `NSGlobalDomain`. Without it, `GTK_THEME=Adwaita:dark` or `Adwaita:light`
  in the environment does the same, as it does for a GTK app, so a
  `.desktop` file or a launcher can set it. A forced style holds when GNOME
  switches between light and dark while the app runs; fonts, Large Text and
  high contrast still follow GNOME, with high contrast over the forced
  palette. The choice is the user's, so it isn't read from an Info.plist.
- `GnomeThemeAccentColor`: one of GNOME's accents (`blue`, `teal`, `green`,
  `yellow`, `orange`, `red`, `pink`, `purple`, `slate`) for the app, over
  GNOME's `accent-color`; set it as `GnomeThemeColorScheme` above.

Scrollbars are GNOME's overlay scrollbars while GNOME's `overlay-scrolling`
setting is on (its default): the content runs under them, and they show
only while it scrolls or the pointer is over them (wider then), fading out
a second later. `GnomeThemeOverlayScrollbars NO` (for an app, or in
`NSGlobalDomain`) keeps classic scrollbars, beside the content and shown
while it overflows.

Open and save panels are GNOME's file chooser, asked for through the XDG
desktop portal (`org.freedesktop.portal.FileChooser`) and attached to the
app's window, as a GTK or Flatpak app's are. An app needs no change, and
needs no library such as libs-OpenSave. A panel stays GNUstep's own when it
has an accessory view (other than NSDocument's "File Type" pop-up, whose
types become the chooser's filters), when its delegate filters or
validates names, or when there is no portal.
`GnomeThemeNativeFileDialogs NO` (for an app, or in `NSGlobalDomain`) keeps
GNUstep's panels. The chooser picks files or folders, not both: an open
panel that allows both (GNUstep's default) picks files. Like GNUstep's
panels, sheets block until the chooser closes; meanwhile the app redraws
but takes no input.

The print panel is GNOME's print dialog, asked for through the portal
(`org.freedesktop.portal.Print`) for the app's window, as for a GTK app.
The dialog's copies, pages, scale, paper, orientation and margins go into
the operation's `NSPrintInfo`; the document is drawn to PDF (or PostScript,
when the dialog prints to a PostScript file) and handed to the portal,
which prints it as the dialog was set (the printer chosen there, or Print
to File); GNUstep's Save, Preview and Fax buttons give way to the dialog's.
Landscape pages are drawn landscape, as GTK draws them. GNUstep draws one
range of pages: of several ranges, from the first page to the last. The
panel stays GNUstep's own when it has an accessory view or accessory
controllers, or when there is no portal, and
`GnomeThemeNativePrintDialog NO` keeps it. Page Setup (`NSPageLayout`)
stays GNUstep's: the portal has no dialog of its own for it (its print
dialog has a Page Setup tab). `make check-print-dialog` checks it against
a stand-in portal.

High contrast follows GNOME's accessibility setting
(`org.gnome.desktop.a11y.interface high-contrast`), as libadwaita does: the
light or dark palette with stronger borders and separators. GNOME 3's
`HighContrast` and `HighContrastInverse` themes still turn it on.

Large Text follows GNOME's `text-scaling-factor`
(`org.gnome.desktop.interface`, 0.5 to 3.0), as GTK's text does: the
interface and monospace fonts are multiplied by it, on top of
`GnomeFontScale`, and menus, rows, fields and tabs grow with the text.
Windows with compact metrics (laid out at GNUstep's sizes, such as those
loaded from Gorm or nib files) keep GNUstep's 12pt, since their controls
don't grow with their text and larger text would clip.

These GNOME settings are followed while an app runs, as GTK apps follow
them: the colour scheme, high contrast, Large Text, the interface and
monospace fonts, `font-hinting`, `overlay-scrolling`, the window buttons'
`button-layout` and the title bar's actions. Within a fraction of a second
of a change the system colours and window backgrounds follow, header bars
lay their buttons out again for a new `button-layout`, and fonts asked
for from then on are the new ones (`make check-live-settings` measures
these); menus are sized again and scroll views tiled again, as libs-gui
does when the theme changes. What a window already holds stays as it
was: a control or a text view that was given a font when it was made
keeps that font, and frames laid out at launch aren't laid out again, so
an app shows Large Text in full in the windows it opens after the change.

### Symbolic icons

A template image is drawn in the colour of the text around it, as GTK
draws symbolic icons: the button's or menu's text colour, the header bar's
(dimmed while the window isn't focused), the title colour on a suggested
(default) button, and the disabled text colour. An app can ship one
monochrome icon set, drawn in any colour (only its shape is used), and it
follows the light, dark and high contrast palettes. An image is a template
when `-[NSImage isTemplate]` says so (libs-gui after 0.32), or when its
name ends in `Template` (Cocoa's convention) or `-symbolic` (GNOME's), for
example `[NSImage imageNamed: @"zoom-in-symbolic"]`.

### Inline button rows in menus

GNOME apps put a row of buttons in a menu, such as the "- 100% +" zoom row
(GTK's `horizontal-buttons` menu sections). To get one, give consecutive
menu items the same string as their `representedObject`, starting with
`GnomeThemeInlineGroup:`:

```objc
[zoomOut setRepresentedObject: @"GnomeThemeInlineGroup:zoom"];
[actualSize setRepresentedObject: @"GnomeThemeInlineGroup:zoom"];  /* "110%" */
[zoomIn setRepresentedObject: @"GnomeThemeInlineGroup:zoom"];
```

The theme shows them as one row of flat buttons: each item's image
(symbolic images take the text colour, see above), or its title when it
has none, with the items between the first and the last taking the
spare room. They stay ordinary items, with their actions, key
equivalents and validation; under other themes they show as a plain
list. Two items or more make a row.

### Windows without the menu bar

GNOME apps keep their menus in the main window. The theme leaves the menu
bar (or ☰) out of a window titled "Preferences" or "Settings" (with or
without "…"), unless it is the app's only window that can become main. An
app decides for itself by giving the window a delegate that implements:

```objc
- (BOOL) windowShouldShowMenuBar: (NSWindow *)window;
```

Its answer wins over the title, both ways, so this also covers other
auxiliary windows and titles in other languages. Key equivalents still
work in a window without the menu bar: GNUstep sends them to the main menu.

### Header bar

By default GNUstep draws the window decorations instead of the window
manager, and this theme draws them as libadwaita's header bar: one 46pt
row with the bold title centred and round window buttons in the order of
GNOME's `button-layout` (with `GnomeThemeMenuStyle primary`, the ☰ menu
before them). Drag the bar to move the window; resize
from any edge or corner; double-click the bar for GNOME's
`action-double-click-titlebar` action (maximise by default); right-click it
for the window menu. On X11 (GNUstep apps on GNOME run under Xwayland) the
window manager does the moving, resizing and maximising, as for GTK's
windows: under Mutter that brings snapping, tiling, dragging past the
screen's edge, Super-drag and Mutter's own window menu. Without a window
manager that supports it, the header bar does these itself. It follows the
scale factor (`GSScaleFactor`), mirrors in right-to-left languages, and has
libadwaita's high contrast details. Alerts have no bar, as GNOME's.

The theme asks for this in its `GSThemeDomain`
(`GSBackHandlesWindowDecorations = NO`). GNUstep's backend reads that
setting before any theme loads, so it takes a libs-gui that looks it up in
the theme first: a libs-gui with the patch in
`Docs/upstream-patches/libs-gui/`. With a stock libs-gui, turn the header
bar on yourself:

```
defaults write NSGlobalDomain GSX11HandlesWindowDecorations NO
```

To keep the window manager's title bar instead, for all apps or for one
(by its defaults domain, here TextEdit's):

```
defaults write NSGlobalDomain GSBackHandlesWindowDecorations YES
defaults write TextEdit GSBackHandlesWindowDecorations YES
```

A user's `GSBackHandlesWindowDecorations` or `GSX11HandlesWindowDecorations`
always wins over the theme's.

With `GnomeThemeHeaderBarToolbar` (above) the window's toolbar goes in the
bar's row.

The window's shadow, its rounded corners and resizing from the shadow, and
rounded, translucent menus and tool tips under a compositor, need a
libs-back with the patches in `Docs/upstream-patches/` (see its README and
`Docs/PROPOSAL_LIBS_BACK_CSD.md`).

`make check-mutter` checks the header bar with Mutter as the window manager:
GNOME Shell on a private Xvfb display, with its own D-Bus session and no
gvfs (see `Tests/Scripts/run-mutter-check.sh`).

### Window tabs

The theme gives apps Apple's window tabbing (`NSWindowTab`,
`NSWindowTabGroup`, `-addTabbedWindow:ordered:`, `tabbingIdentifier`,
`tabbingMode`, `newWindowForTab:` and the Window menu's tab items) through
[gnustep-window-tabbing](https://github.com/danjboyd/gnustep-window-tabbing),
built into the theme, and draws the tab bar as libadwaita's AdwTabBar: a
40pt bar in the window's colour below the header bar (and any in-window
menu bar and toolbar), tabs sharing its width, the selected one filled,
close buttons on the selected and hovered tabs, and a "+" button at the end
when something responds to `-newWindowForTab:`. Ctrl+Tab and Ctrl+Page
Up/Down move between tabs, and closing a tab shows its neighbour.

An app needs no code of its own beyond Apple's API: give windows a
`tabbingIdentifier` (and `NSWindowTabbingModePreferred`, or join them with
`-addTabbedWindow:ordered:`), and implement `-newWindowForTab:` in the
responder chain for the "+" button. The tabbing code switches itself off
when NSWindow already has these methods (a libs-gui that implements them).

The code is a copy in `Source/WindowTabbing` of a commit of that
repository (`Source/WindowTabbing/VERSION`); change it there, then refresh
the copy with `bash Tools/vendor-window-tabbing.sh CHECKOUT COMMIT`. An app
that also builds the tabbing code in itself works under the theme (the
runtime keeps one copy of each class, and the other copy hands its calls
to it); the same commit is safest. Screenshots
against libadwaita are in `Docs/Screenshots/window-tabs/`, and
`Reference/AdwaitaTabBar/adwaita_tab_bar.py` is the GTK 4 reference they
were measured from.

### Designing a GNOME-style app in Gorm

Gorm itself runs with compact metrics (its own windows come from Gorm files
laid out at GNUstep's). An app meant to look like a GNOME app needs its
windows laid out at GNOME's metrics instead:

1. Declare it in the app's Info.plist, so it runs with GNOME's metrics even
   though it has a main Gorm file (and, if you like, the primary menu):

   ```
   GnomeThemeMetrics = gnome;
   GnomeThemeMenuStyle = primary;
   ```

   With GNUstep Make, put these in `APPNAMEInfo.plist` next to the makefile.
2. Install the Adwaita palette: controls at GNOME's sizes (34pt buttons,
   entries, pop-ups and search fields, a suggested button, checkboxes,
   radios, heading and body labels). Gorm's own palettes make 22pt controls.

   ```sh
   make palette installpalette GNUSTEP_INSTALLATION_DOMAIN=USER
   defaults write Gorm UserPalettes \
     '("'$HOME'/GNUstep/Library/ApplicationSupport/Palettes/Adwaita.palette")'
   ```

   (or open it once with Palettes ▸ Open… in Gorm's Tools menu, which
   remembers it). It appears as the last icon in Gorm's palette panel.
3. Lay its windows out in Gorm running with GNOME's metrics, so what you see
   is what the app will show:

   ```sh
   openapp Gorm -GnomeThemeMetrics gnome
   ```

   Gorm's own inspectors are cramped at this size (some labels clip), but the
   document's windows show the app's real text and control sizes. Size push
   buttons and text fields 34pt high, and leave GNOME's spacing: 6pt between
   related controls, 12pt between groups, 18pt from the window's edge.
4. Leave control fonts at the system font's default size (Gorm's default,
   and the palette's). Those are archived as "the system font" and follow
   the metrics the app runs with; a font given an explicit size keeps it.

## Development Notes

The fastest practical review loop is:

```sh
make
make -C Examples/ThemeDemo
bash Tests/Scripts/run-theme-demo.sh --page controls
make check-quirks
```

The demo and capture scripts load the theme bundle built in this checkout
(`Adwaita.theme`, by absolute path), not the installed copy: `-GSTheme Adwaita`
finds `~/GNUstep/Library/Themes/Adwaita.theme`, which may be older. Pass
`--theme PATH` (or set `ADWAITA_THEME`) to check another build. Install for
other apps with `make install GNUSTEP_INSTALLATION_DOMAIN=USER`.

`make check-quirks` runs `Tests/Scripts/run-quirk-probe.sh`: it builds
`Examples/QuirkProbe` and runs it on a private Xvfb display against the built
theme. The probe renders controls offscreen and measures them (sized button and
checkbox titles, wrapping labels and alert text, toolbar image items, the bold
font, the menu bar in a window created after launch, table grid lines,
frames and headers, the menu bar's app item, toolbar edges and hover,
pop-up titles, and the size of hidden tool tip and drag windows), prints one
PASS/FAIL/KNOWN/SKIP line per check, and exits with the number of failures.
KNOWN marks a GNUstep bug the theme can't fix (see `Docs/upstream-issues/`).
Add `--output DIR` to save a PNG of each probe window. `make check-quirks`
runs the probe seven times: with the menu bar and with the primary menu
(`QUIRK_PROBE_ARGS="-GnomeThemeMenuStyle primary"`), each with the window
manager's title bar and with the theme's header bar
(`-GSX11HandlesWindowDecorations NO`), then the header bar's checks alone in
the dark palette and in high contrast over the light and the dark palette
(`QUIRK_PROBE_STYLE=dark`, `high-contrast` or `high-contrast-dark` with
`-ProbeOnly header-bar`). The probe sets the decoration
flag itself, so a user default doesn't change the runs.

Other checks, each on private displays with no gvfs (never the desktop
you work on):

- `make check-mutter`: the header bar under GNOME Shell (moving, resizing,
  maximising, tiling, the window menu, menu types).
- `make check-mutter-shadow`: the same against libs-gui and libs-back with
  the patches (`MUTTER_CHECK_GUI`, `MUTTER_CHECK_BACK`), with the shadow,
  rounded corners and popover shadow.
- `make check-wms`: the header bar's checks under GNOME Shell, KWin, Xfwm4
  and Openbox with picom.
- `make check-file-chooser`: open and save panels against a stand-in portal.
- `make check-print-dialog`: the print dialog against a stand-in portal.
- `make check-nib-metrics`: per-window metrics for nib and Gorm windows.
- `make check-text-scaling`: fonts and metrics with GNOME's Large Text
  (text-scaling-factor 1.25 and 2.0).
- `make check-live-settings`: GNOME's settings changed while an app runs
  (dark style and Large Text on, then off; the accent to teal and back),
  and GNOME's accent at launch (teal light, purple dark).
- `make check-color-scheme`: a forced light or dark style
  (`GnomeThemeColorScheme`, `GTK_THEME`) over GNOME's, while GNOME's
  `color-scheme` changes.
- `make check-menu-timing`, `make check-scroller-drag`,
  `make check-context-menu`: menu sizing time, overlay scroller drags and
  context menu placement.

Useful helpers:

- `bash Tests/Scripts/run-theme-demo.sh`
- `bash Tests/Scripts/run-quirk-probe.sh --output /tmp/quirk-probe`
- `bash Tests/Scripts/run-adwaita-demo.sh`
- `bash Tests/Scripts/capture-theme-demo.sh --page controls --output /tmp/theme-controls.png`
  (runs on the current display and clears ThemeDemo's `GSTheme`,
  `GSScaleFactor` and decoration defaults; for the README's screenshots use
  `Tests/Scripts/readme-shots/`, see `Docs/Screenshots/README.md`)
- `bash Tests/Scripts/capture-adwaita-demo.sh --page controls --output /tmp/adwaita-controls.png`
- `python3 Reference/AdwaitaDemo/adwaita_demo.py --dump-metrics`
- `python3 Tests/Scripts/import-adwaita-cursors.py`

`import-adwaita-cursors.py` imports the stock Adwaita diagonal resize Xcursor
assets from `/usr/share/icons/Adwaita/cursors` and writes GNUstep-loadable TIFF
resources into `Resources/ThemeImages`. These resources provide
`GSFrameResizeNWSECursor` and `GSFrameResizeNESWCursor` for Cocoa-style apps
that need frame/corner resize cursors before GNUstep exposes AppKit's
`NSCursor` frame-resize API directly.

ThemeDemo also accepts command automation for focused visual checks:

```sh
Examples/ThemeDemo/ThemeDemo.app/ThemeDemo --command-script /tmp/theme-demo.commands
Examples/ThemeDemo/ThemeDemo.app/ThemeDemo --command-fifo /tmp/theme-demo.fifo
python3 Reference/AdwaitaDemo/adwaita_demo.py --command-script /tmp/adwaita-demo.commands
python3 Reference/AdwaitaDemo/adwaita_demo.py --command-fifo /tmp/adwaita-demo.fifo
```

Supported commands are `page NAME`, `click X Y`, `focus NAME`, `blur-to NAME`,
`select-all`, `open-dropdown NAME`, `type TEXT`, `key TEXT`, `wait SECONDS`,
`display`, `screenshot PATH`, `screenshot-screen PATH`,
`capture-dropdown NAME PATH`, `capture-alert PATH`, and `quit`. Text audit names
are `primary`, `password`, `search`, `disabled`, `body`, and `combo`.
Coordinates are backing-pixel positions from the top-left of the internally
captured content image, so they line up with screenshots produced by
`screenshot PATH`. Use `screenshot-screen PATH` when auditing popups or dropdowns
that render outside the application content view; it uses GNUstep screen capture
first and falls back to `gnome-screenshot` only if needed. Use
`capture-dropdown NAME PATH` for GNUstep combo boxes whose popup tracking is
modal; it schedules the same internal screen capture while the popup is open.
Use `capture-alert PATH` to audit a stock document-close `NSAlert`.

## Internal Notes

If local-only working notes are needed, keep them under `.internal/`.

That directory is ignored on purpose so internal handoff notes, private paths,
and local debug artifacts do not show up in a public GitHub repository.

## License

This project is licensed under the GNU Lesser General Public License, either
version 2 of the License, or (at your option) any later version.

See [COPYING.LIB](./COPYING.LIB).

The icons in `Resources/ThemeImages` (the Open and Save panels' Home, Mount
and Unmount buttons, the rating stars, the sort indicators, the outline
chevron and the corner resize cursors) come from GNOME's
[Adwaita icon theme](https://gitlab.gnome.org/GNOME/adwaita-icon-theme) and
keep its licenses, not the theme's. Most are under the GNU LGPL v3 or
CC-BY-SA 3.0 US; the pan-up, pan-down and pan-end chevrons are under
CC-BY-SA 4.0. Attribution: the GNOME Project. The list of files and the
license notices are in [THIRD-PARTY-NOTICES](./THIRD-PARTY-NOTICES), which
also ships in the theme bundle's Resources.

## Author

Daniel Boyd
