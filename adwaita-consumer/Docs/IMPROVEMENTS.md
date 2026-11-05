# Improvement Backlog

A running list of theme bugs and GNOME-native polish, collected while building
OneDriveServiceManager with this theme (started 2026-09-24). Each item notes how
it was found. Compare against the libadwaita reference with
`python3 Reference/AdwaitaDemo/adwaita_demo.py --page PAGE --screenshot OUT.png`.

## Fixed

| Item | Fix |
| --- | --- |
| Image-only `NSToolbarItem`s drew nothing (image and label) | `GnomeThemeOriginalMethod()`: overrides reached from a subclass (`GSToolbarButtonCell`) found no original method |
| `sizeToFit` buttons clipped their last word ("Sign In" → "Sign") | `cellSize` measures with the drawing geometry (bezel margins + title insets) |
| `sizeToFit` checkboxes/radios clipped ("Errors only" → "Errors") | `cellSize` accounts for the ≥18pt indicator and the label gap |
| Multi-line labels and `NSAlert` informative text showed one line | `titleRectForBounds:` keeps the full rect for labels that need (and have room for) more lines |
| Password field text sat 10pt left of other fields' text | same subclass fix (`NSSecureTextFieldCell`) |
| ThemeDemo stuck at 2× after a `capture-theme-demo.sh --scale 2` run | the script passes `-GSScaleFactor`/`-GSTheme` as launch arguments |
| Bold text (`boldSystemFontOfSize:`, title bar, table headers) drew in DejaVu Sans Bold | the theme sets `NSBoldFont` to the interface font's bold face (`Cantarell_700wght`) |
| With `NSWindows95InterfaceStyle`, windows created after launch had no menu bar (GNUstep bug, upstream issue 2) | the theme attaches the main menu when a window that can become main, and has no menu, becomes key or main |
| Demo and capture scripts tested the installed theme (`-GSTheme Adwaita`), which was from Jul 27 | they pass the built bundle by absolute path (`--theme`/`ADWAITA_THEME` to override) and no longer save `GSTheme` in ThemeDemo's defaults |
| Table headers were bold, centred, on a grey band with separators | libadwaita style: small bold text in a dim colour (full colour for a clicked or sorted column), on the list's background, no separators; GNUstep's default centred titles start at the leading edge, lined up with the rows' text |
| Every table drew horizontal grid lines | grid lines only when the app asks (`setGridStyleMask:`/`setDrawsGrid:`, including tables decoded from a nib or Gorm file); GNUstep's own default of drawing a grid is treated as none, the GNOME and Cocoa default |
| Table scroll views had a bezel frame and lines between content and scrollers | no frame; the space is filled with the table's background, so the list reads as one plain area (other scroll views keep their frame) |
| Scrollers drew a grey track with a faint knob | overlay-style indicator: no track, a thin dim slider along the outer edge, thicker and darker while dragged; hidden when nothing overflows |
| A dark grey line under every toolbar | toolbars sit on the window background with a light bottom edge (the palette's `toolbarBackgroundColor`/`toolbarBorderColor`; GSTheme looked for them in a ThemeExtra colour list and fell back to dark grey) |
| Toolbar buttons had no hover or pressed look (pressed labels turned white) | libadwaita flat-button backgrounds: the text colour at 7% under the pointer, 16% pressed, 6pt corners; hover comes from tracking rects the theme adds in `-[GSToolbarButton layout]` |
| The menu bar started with the app's name, greyed when its menu was empty ("OneDriveServiceManager") | an empty app menu is removed; a non-empty one is drawn as GNOME's main-menu icon (☰) |
| `NSMenuItemCell` overrides used the exact-class lookup, and pop-up buttons' layout depended on it failing | they use `GnomeThemeOriginalMethod()`; pop-up button cells get their geometry explicitly, so an upstream fix to `-overriddenMethod:for:` can't move pop-up titles |
| Under GNOME Wayland, tool tips and drag images showed only the first time (GNOME/mutter#5080, upstream items 5 and 6) | on Wayland the tool tip panel and the drag window are ordered out without first being shrunk to `NSZeroRect`; elsewhere GNUstep's shrink is kept |
| A focused push button (OneDriveServiceManager's Cancel, the first key view in its panels) had a ring around its title and blue fragments in its corners | NSCell's inner ring is no longer drawn for buttons, and the button's own ring runs just inside its edge, like libadwaita's (a ring outside the frame was clipped to the corners); as in GTK (focus-visible), rings on buttons, checkboxes, radios and sliders show only after a key press and hide on a pointer press, while text fields keep theirs whenever focused |
| Table rows were about 28px (GNUstep's default 16pt clipped the text) with 3–4px of text inset | tables built in code start with GTK's list density: 34pt rows (scaled with the interface font) and no intercell spacing; table cells and headers inset their text 6px, as GTK list cells do; apps that set a row height or spacing keep theirs, and nib/Gorm tables keep their archived values |
| Toolbars showed icon and label; GNOME header bars show icons with tool tips | a toolbar the app gives no display mode starts icon-only (later toolbars with its identifier copy it); a button without its label gets the label as its tool tip unless the item has one; `setDisplayMode:` and nib/Gorm toolbars are respected |
| The ☰ main menu sat at the start of the menu bar; GNOME puts it at the end | its rect moves to the right end of the bar (`-[NSMenuView rectOfItemAtIndex:]`), which drawing, hit testing and highlighting follow; its menu opens right-aligned under it |
| Alerts had GNUstep's layout: app icon, left title, a groove line, buttons at the right | laid out like `AdwAlertDialog`: no icon or line, a centred bold heading (title-2 size) over centred body text, and 44pt buttons of equal width in a row (stacked full width when the titles don't fit), default button at the right |
| Tab views drew pill tabs with a blue top bar and no frame | GtkNotebook style: a 1px frame, plain text tabs on the window background, a 4pt accent underline under the selected tab, content on the view background (tab views built in code now draw their background, Cocoa's default) |
| Checkbox and radio labels sat 10pt after the indicator | 4pt, GTK's spacing (about 5px before the first glyph) |
| Cocoa apps' application menu (the main menu's first item, usually untitled or "NewApplication") showed as a blank or wrongly named item, with GSTheme's own empty app menu beside it | an untitled first item, the menu passed to `setAppleMenu:` (a no-op in GNUstep), a nib's `_NSAppleMenu`, or a first menu holding About or Hide is named after the app, so GSTheme adopts it and it becomes the ☰ menu |
| Hide, Hide Others and Show All were offered, but GNOME has no hidden apps: `-hide:` orders the windows out and relies on GNUstep's app icon to bring them back (with `GSSuppressAppIcon` it leaves the windows up and puts an icon tile on the desktop) | they are left out of the application menu, with the separators they leave doubled |
| In a narrow window whose menu items overflow the bar (Gorm's document window), ☰ covered the last items | it moves to the end only when every item fits; otherwise it stays first |
| Gorm's document toolbar (Objects, Images, Sounds, Classes, File) lost its labels to the icon-only default | a toolbar whose delegate lists selectable items is a view switcher, which GNOME shows with icon and label, so it keeps them; an app that sets a mode itself is left alone |
| Switches with the box after the title (`imagePosition` NSImageRight, all over Gorm's inspectors: "Command [ ]") drew the box first | the indicator goes at the end and the title before it, in the cell's alignment |
| Grooved and bezelled boxes (Gorm's inspectors) had blue edges | `controlHighlightColor`/`controlLightHighlightColor` are the light edges of GNUstep's 3D bevels, not selection colours: white in the light palette, a light grey in the dark one |
| Box titles drawn by an `NSTextFieldCell` (Gorm's "Type", "Options", "Alignment") came out upside down | text in a cell drawn by a non-flipped view (an NSBox) is drawn with string drawing; flipping the context by hand mirrored the glyphs |
| `NSForm` entries (Gorm's "Title:" fields) were white boxes | the entry is drawn as an Adwaita entry; NSFormCell filled it with `textBackgroundColor` after the border |
| Gorm and nib layouts clipped at GNOME's font size ("Miniaturize" as "Miniatur") | compact metrics for apps with a main Gorm or nib file: GNUstep's 12pt, regular button titles, GNUstep's button margins and tab height, 14pt indicators; `GnomeThemeMetrics` (`gnome`/`compact`) overrides the choice per app (see the README) |
| Menu bar titles were about 37px apart; GTK's are about 20px | about 22px, so narrow windows (Gorm's document window) fit their menus |
| GNOME apps have no menu bar | `GnomeThemeMenuStyle = primary` (a user default, or the app's Info.plist) turns it into GNOME's main menu button: at the end of the toolbar when the window shows one (the toolbar is narrowed for it), otherwise alone in a slim bar; it shows a copy of the main menu (the menus, then the application menu's items) right-aligned under the button, rebuilt each time it opens |
| An app laid out in Gorm for GNOME's metrics would get compact metrics (it has a main nib) | apps can declare `GnomeThemeMetrics` in their Info.plist; the user's default still wins |
| Compact metrics were per app: a code-built app's Gorm or nib windows (its own, libs-gui's panels) came out cramped at GNOME's metrics ([#24](https://github.com/danjboyd/plugins-themes-Adwaita/issues/24)) | with no choice made (or `auto`), windows loaded from a nib or Gorm file get compact metrics of their own: their controls' fonts at GNUstep's size, GNUstep's margins, indicators and tab height; the app's other windows, menus and fonts keep GNOME's. `gnome` or `compact` still applies to every window, so a code-built app whose Gorm files were made for GNOME's metrics (with `Palettes/Adwaita`) declares `gnome` |
| Gorm's palettes make controls at GNUstep's sizes (22pt buttons) | `Palettes/Adwaita`: a Gorm palette of controls at GNOME's sizes, with fonts left at the system font's default size so they follow the app's metrics (checked: archived at 12pt in a compact process, read back at 14.7pt in a GNOME one) |
| The header bar was drawn at 1× with a scale factor (`GSScaleFactor 2`: a 23pt bar), and the content sat 1pt off (gap at the left and bottom) | offsets and the minimum width are in device pixels, scaled by the factor; `-[GSWindowDecorationView layout]` places the content from an origin `+contentRectForFrameRect:styleMask:` leaves unscaled (a GNUstep bug that also shifts its own title bar), which the header bar corrects |
| In Arabic, Hebrew and other right-to-left languages the header bar kept its left-to-right order | mirrored as GTK mirrors it (checked against a GTK render): button-layout's start at the right, close outermost at the left, ☰ to the right of the buttons; the direction comes from the first preferred language (`NSForceRightToLeftWritingDirection` forces it) |
| Right and middle clicks on the header bar did nothing; the double-click actions "menu" and "lower" did nothing | GNOME's `action-right-click-titlebar` (default: the window menu), `action-middle-click-titlebar` and all double-click actions: "lower" orders the window back, "menu" opens a window menu with the entries of Mutter's that GNUstep can carry out (Hide, Maximize/Restore, Always on Top, Close), which stays open after the click |
| Header bar windows couldn't be dragged past the screen's edge or to the top to maximise, and got none of Mutter's snapping, tiling or Super-drag | on X11 the header bar hands moves and resizes to the window manager (`_NET_WM_MOVERESIZE`, after GTK's 8px drag threshold), asks it to maximise and restore (`_NET_WM_STATE`), shows its window menu on right-click (`_GTK_SHOW_WINDOW_MENU`) and reads its maximised state for the restore icon, as GTK does (`Source/Adapters/GnomeThemeWindowManager.m`, Xlib through `GSDisplayServer`'s `-serverDevice` and `-windowDevice:`); its own loops and menu remain for window managers without these |
| Mutter refused to move, maximise, minimise or close windows GNUstep decorates, even when asked (libs-back's `_MOTIF_WM_HINTS` allow no functions: proposal item 0) | once the X window exists, the header bar rewrites the hints: no decorations, and the functions the window's style allows |
| The header bar in high contrast looked as in the normal palette | libadwaita's high contrast details: a 1px ring round each window button's circle and a darker window border |
| Clicking ☰ opened its menu and the release closed it again (libs-gui 0.32, upstream item 8) | the menu opens on the click's release and stays open until a click picks an item or lands outside it; Escape closes it |
| With `GSX11HandlesWindowDecorations NO`, GNUstep drew a NeXT title bar (black, round miniaturise and close buttons, resizable only from a bottom bar) | libadwaita's header bar, measured against libadwaita 1.7 renders (`Reference/HeaderBar`): 46pt including a 1px window border, bold centred title (shifted clear of the buttons when they're in the way, shortened with an ellipsis), round 34pt window buttons with Adwaita's icons in `button-layout` order, ☰ before them with the primary menu, title and icons dimmed when the window isn't key; moving by the bar, resizing from every edge and corner (5pt strips inside the border), and the `action-double-click-titlebar` action, with maximise going back to the frame before. The theme can't turn this on itself: the backend reads the flag before the theme loads. Alerts (alone or as sheets) have no bar, as AdwAlertDialog: a border only. Panels get the bar with a close button; windows with buttons and no title get the bar without one; borderless windows and `NSFullScreenWindowMask` get neither bar nor border |
| Push buttons narrower than their padding clipped short titles (ScreenshotTool's 64pt "12" drew as "1", a 44pt "20" drew nothing: plugins-themes-Adwaita#3) | rounded buttons are padded once (GTK's 17px, from the bezel margins), not again by the title rect; in a frame too narrow for it the padding shrinks to 4pt before the title is cut; `sizeToFit` buttons are about 15pt narrower |
| Steppers at Cocoa's size (about 19x27pt) drew "−" and "+" side by side in 9pt each (plugins-themes-Adwaita#6) | a stepper taller than it is wide has an up half above a down half, with chevrons; wider ones keep GTK's spin button "−" and "+"; a button that can't change the value is dimmed, as in GTK |
| Colour wells drew NeXT's bevelled well (plugins-themes-Adwaita#2) | GTK's colour button: the theme's push button (pressed while the colour panel is attached) holding a rounded swatch with a faint inner border |
| Tool tips were GNUstep's pale yellow box with a black border (plugins-themes-Adwaita#1) | libadwaita's: dark (80% black over the window background, in every palette), white text, 6px by 10px padding, no border (a white one in high contrast); square corners, rounded where the window has an alpha channel (see the row on menus and tool tips) |
| Clicking a menu bar title (and the bar's ☰) opened its menu and the release closed it again (libs-gui 0.32, upstream item 8; plugins-themes-Adwaita#5) | first fixed by opening the menu on the release; now as GTK's menu bar (see the row on menu tracking) |
| With the menu bar style, every window that could become main got the app's menus, Preferences windows included (ScreenshotTool's: plugins-themes-Adwaita#4) | windows titled Preferences or Settings get no menu bar or ☰ (unless they're the app's only window that can be main); a window delegate's `-windowShouldShowMenuBar:` decides instead when it's implemented (README, "Windows without the menu bar") |
| Toolbars were libs-gui's fixed heights: 62pt with labels (empty ones included), about 40pt icon only; views taller than 32pt (GNOME's 34pt buttons) disappeared; images were forced to 32x32; view items' labels were black, unreadable in the dark palette (plugins-themes-Adwaita#8, upstream item 9) | with GNOME metrics, items are sized from their content: libadwaita's 46pt row with 34pt buttons for icons or labels alone, an icon over a caption-sized label otherwise (no label row for empty labels), images at their own size up to 24pt (16pt small), views kept with the row growing to fit; every item gets the row's height; labels in the text colour. Compact metrics keep libs-gui's layout |
| The selected segment of a segmented control was 2/255 darker than the others in the dark palette, and only a little darker in the light one (plugins-themes-Adwaita#7) | libadwaita's checked linked button: the text colour at 30% over the window background, darker in the light palette and lighter in the dark one; checked in the light, dark and high contrast runs |
| Toolbar items with a custom view and no `-sizeToFit` (ScreenshotTool's colour, Copy, Preferences and zoom items) shrank to nothing (plugins-themes-Adwaita#9) | libs-gui sets each view to its slot less 10pt insets after every layout; the theme gives it back its slot less its own 3pt insets, within the item's minSize and maxSize |
| Menu shortcuts touched the menu's right edge (plugins-themes-Adwaita#10) | shortcuts and submenu arrows end 12pt inside the row, as in libadwaita's popover menus |
| Menu separators were two rows of mid grey (plugins-themes-Adwaita#11) | one hairline on a pixel row, the text colour at 15% over the menu (50% in high contrast) |
| Menu bar menus opened on the release; a click outside reached the window under it; context menus closed when the right button came up; Escape didn't close context menus | audited against GTK 4 under Mutter: menu bar titles and context menus open on the press and stay open on its release (on 0.32 the theme drops that release, as master does; master is told by `-[NSImage isTemplate]`); a press outside closes them and goes nowhere else; Escape closes the menu bar's, ☰ and context menus. ☰ opens on the release, as GTK's menu buttons do |
| A click on a pop-up button opened its menu and closed it again at once, keeping the current item (from the second click on: the first time, making the menu's window let the release come before the tracking) | pop-up menus open on the press and get the menu bar's treatment: the opening click's release is ignored (`-doesProcessEventsForPopUpMenu` in master, dropped by the theme in 0.32), Escape or a press outside closes them; QuirkProbe `popup-click-stays-open` |
| With libs-gui master (gui ff49ac8) alerts were right-aligned, table header titles sat centred (about 110pt in) and menu shortcuts were centred (30pt from the edge): master (3237efda8) numbers `NSTextAlignment` as AppKit does, swapping centre and right, so the constants of a theme built against 0.32 meant the other alignment | `GnomeThemeCenterTextAlignment()` and `GnomeThemeRightTextAlignment()` take the values from `NSParagraphStyle`'s class version (4 since the change); QuirkProbe passes against 0.32 and master, its alert check measuring the heading's ink |
| Menus drew rounded corners on an opaque window, black under a compositor | square, with the border, unless the window has an alpha channel and a compositing manager runs; then menus (10pt) and tool tips (libadwaita's 9pt, with its light outline) are rounded. The alpha channel needs the libs-back patch (`GSBackBorderlessWindowAlpha`) |
| Window managers saw context and pop-up menus as dialogs (Mutter focused them, drawing their window unfocused), tool tips as dialogs (libs-gui#965), alerts as normal windows and menu bar menus as torn-off menus (plugins-themes-Adwaita#15) | the theme types windows as GTK does (`GnomeThemeWindowTypes.m`): `_TOOLTIP`, `_DROPDOWN_MENU` for an in-window menu bar's menus, `_POPUP_MENU` for other menus, `_DND`, and `_DIALOG` for alerts and open and save panels. It reads the type first and writes only a different one, so with the libs-back patch (item 5, which types all but the menu bar's menus itself) it mostly does nothing. QuirkProbe `window-types`; `make check-mutter` `menu-type` |
| With the toolbar in the header bar, an item whose view acts only on the release (ScreenshotTool's Copy, zoom and colour items) did nothing: its press went up to the bar, which read up to the release to see whether it was a drag (plugins-themes-Adwaita#33) | the bar leaves a press that came from a toolbar item's view alone, so the release reaches the item; only the bar's background and spaces drag the window, as in GTK. QuirkProbe `header-bar-toolbar-item-click` |
| A document window's header bar showed GNUstep's "white.png  --  ~/Pictures", pushing the name aside (plugins-themes-Adwaita#31) | when the title is the one `-setTitleWithRepresentedFilename:` made, the bar shows the file's display name and the folder as a tool tip over it (AdwWindowTitle's subtitle); other titles are untouched. QuirkProbe `header-bar-document-title` |
| The toolbar-in-the-header-bar choice was per app, read only when a toolbar was attached: apps re-attached their toolbars to apply it, and the bar re-read the setting rather than remembering where it had put the toolbar (plugins-themes-Adwaita#30) | `GnomeThemeHeaderBarToolbar` in `NSGlobalDomain` turns it on for every app (a per-app setting still wins; an Info.plist `NO` keeps the app's row); a change moves open windows' toolbars, keeping their frames; the bar tracks where its toolbar is. QuirkProbe `header-bar-toolbar-live` |
| Apps shipped light and dark icon sets and chose between them (plugins-themes-Adwaita#32) | template images (`-isTemplate`, or a name ending in `Template` or `-symbolic`) are tinted with the text colour around them in buttons, toolbar items and menus: the header bar's (dimmed in the backdrop state), the suggested button's title colour, the disabled colour. QuirkProbe `template-images`, in the light, dark and high contrast palettes |
| Alerts weren't modal dialogs of the window they interrupt: Mutter didn't attach them (no centring on the window, no dimming it) (plugins-themes-Adwaita#22) | before an alert is shown the theme makes it transient for the app's main window with `_NET_WM_STATE_MODAL` and the window's `_NET_WM_USER_TIME`, as GTK does, and asks for the focus again once it's mapped (libs-back's first request comes too early and it ignores the window manager's offer). With the header bar the alert already had no bar (a border only). `make check-mutter` `alert-attached` |
| Tool tips were the opaque colour 80% black makes over the window background, wrong over anything else (plugins-themes-Adwaita#21) | where the tip's window has an alpha channel under a compositor (the installed backend gives it one with the header bar) it is libadwaita's 80% black, translucent; opaque otherwise, and in high contrast. `make check-mutter` `tooltip` measures one over the desktop |
| Menus had 10pt corners and no shadow; libadwaita's popover menus have 15px corners and a soft shadow (plugins-themes-Adwaita#19) | 15px corners; with the header bar the theme marks menu windows as popovers, and the libs-back patch (`GSBackPopoverShadows`) draws libadwaita's popover shadow in a transparent margin round them, as GTK 4 does (Mutter draws none for a 32-bit window). Under Mutter, KWin and Xfwm4; none where the window manager lacks `_GTK_FRAME_EXTENTS`. `make check-mutter-shadow` `menu-shadow`; libs-back `Tests/x11/shadowmargin.m` |
| High contrast was GNOME 3's: a white-on-black palette chosen by a `gtk-theme` name with "HighContrast" (plugins-themes-Adwaita#18) | current GNOME's `org.gnome.desktop.a11y.interface high-contrast` (the theme names remain a fallback, HighContrastInverse dark) over the light or dark palette, as libadwaita's base-hc.css: borders and separators the text colour at 50%, disabled controls at 40%, hovered menu items outlined; tool tips as in normal contrast. `make check-quirks` runs high contrast over both palettes |
| Scrollbars always took a strip beside the content and showed while it overflowed; libadwaita's are overlay indicators (plugins-themes-Adwaita#17) | with GNOME's `overlay-scrolling` on, the clip view (and a table's header) runs under the scrollers, which draw nothing and let presses through at rest; they show on scrolling or with the pointer over them (an 8px slider in a trough then, 3px otherwise) and fade out after a second. The clip view redraws instead of copying on scroll (the scroller's pixels would be copied along) and nested tiling from auto-hiding scrollers is skipped. `GnomeThemeOverlayScrollbars NO` keeps classic ones. QuirkProbe `overlay-scrollers` |
| With the toolbar in the header bar, a press on an item's empty part or a label didn't drag the window (MarkdownViewer's status area), since #33's fix left every press inside an item alone (plugins-themes-Adwaita#36) | as a GTK header bar: a press that an item passed on drags the window past the threshold, and a click gives its release back to the item (which libs-gui sends it to), so release-only views still work; labels hit-test as bar background. QuirkProbe `header-bar-toolbar-item-drag` |
| A segmented control's template images kept their own colour, dark on dark in the dark palette: they're drawn by the segmented cell, not `NSButtonCell` (plugins-themes-Adwaita#37) | the segment drawing tints them as buttons do: the segment's text colour, the disabled colour, the header bar's in a toolbar in the bar. QuirkProbe `template-images` |
| NSSwitch was the initial import's track inset into the frame: a thin pill in a short frame, nothing like GNOME's (plugins-themes-Adwaita#35) | libadwaita's switch: a 46x26 pill round a 20pt knob (shrunk to a smaller frame, centred in a larger one), the accent when on, the text colour at 15% when off (30% in high contrast), a white knob with a soft shadow, faded to 50% (40%) when disabled, the focus ring. QuirkProbe `switch-adwaita`, in every palette. (libs-gui 0.32's NSSwitch starts disabled until `-setEnabled: YES`; #29) |
| A window or scroll view freed within a second of scrolling crashed later: the overlay scrollers' fade timer retained their state, which outlived the scroll view and messaged it (plugins-themes-Adwaita#38) | the timer's target is a go-between that doesn't keep the state alive, and a freed scroll view stops its state's timer. QuirkProbe `overlay-scrollers` frees one mid-fade (no messages to freed objects under `NSZombieEnabled`) |
| A window with unsaved changes (`-setDocumentEdited: YES`) showed no sign of it in the header bar (plugins-themes-Adwaita#39) | a dot before the title ("• readme.md"), in the title's weight, as GNOME's document apps; the bar redraws when the state changes. QuirkProbe `header-bar-document-title` |
| GNOME apps keep their toolbar's buttons in the header bar | `GnomeThemeHeaderBarToolbar` (a user default, or the app's Info.plist) puts the window's toolbar in the header bar's row: items before its flexible space at the start, after it at the end, the title in the space; icons without labels; the » menu for items that don't fit; mirrored right to left |
| Print showed GNUstep's own print panel, while open and save were already GNOME's file chooser (plugins-themes-Adwaita#52) | `Source/Adapters/GnomeThemePrintDialog.m`: the print panel asks the portal's PreparePrint, maps its settings and page setup into the `NSPrintInfo`, and `-[GSPrintOperation deliverResult]` hands the drawn PDF to the portal's Print; GNUstep's panel without a portal, with accessories, or with `GnomeThemeNativePrintDialog NO`. `make check-print-dialog` |
| A disabled pop-up button drew its title as an enabled one's, so it looked clickable (plugins-themes-Adwaita#69) | the title takes the disabled text colour when the button is disabled, not only when its item is (the selected item stays enabled); the fill already dimmed |
| Submenus opened right of their menu whatever the screen: from a ☰ popover near the right edge they ran off it, their items out of reach (plugins-themes-Adwaita#77) | as GTK places submenus: one that doesn't fit to the right opens to the left (and its own submenus go on left), and one that would leave the screen at the bottom or top is moved into it (`-[NSMenuView locationForSubmenu:]`) |
| A column's sort indicator never showed, and GNUstep has no `NSAscendingSortIndicator` or `NSDescendingSortIndicator` image, so the Cocoa idiom set nil; libs-gui 0.32 doesn't even keep an indicator image (plugins-themes-Adwaita#71) | the theme has both images (GNOME's pan-up and pan-down), keeps a column's indicator image on 0.32, and draws the named indicators as GTK 4 does: a 16pt chevron 6pt after the title, in the title's colour. With no image set, the column of the table's primary sort descriptor shows its indicator, as in Cocoa; libs-gui shows none by itself (`Docs/upstream-issues/17-libs-gui-sort-indicator-not-shown.md`) |
| A combo box that can't be edited lost its look when it took the focus (a click or Tab): GNUstep started the field editor, which drew the text in regular weight over a lighter strip, or nothing when the cell had no string value yet (plugins-themes-Adwaita#70) | it is GtkDropDown in every state: no field editor (`-selectText:` does nothing for it), the bold label kept, the ring after a key press as on a button, and Space, Return or an arrow key opens its list |
| NSBrowser's column titles (GNUstep's own Open panel, with `GnomeThemeNativeFileDialogs` off) were white on white (plugins-themes-Adwaita#72) | drawn as the theme's table headers: small bold text in the dim header colour, with no bezel. The "Window" X windows the panel leaves are libs-gui's image caches (`GSCacheW` in `NSCachedImageRep.m`, one per cached image, never mapped; the default theme leaves more), not a bug to report |
| Tinted template images were drawn once at the image's size, so a 32pt toolbar icon with exact 16, 22, 24 and 32pt bitmaps became one 32px bitmap, scaled down to 24pt in the header bar and soft (plugins-themes-Adwaita#68) | an image made of bitmaps is tinted one bitmap at a time, each at its own pixel size, so the tinted copy has the same bitmaps and NSImage still picks the one that fits; PDF, EPS and drawn images are tinted as before |
| Window tabs could not be dragged or scrolled (plugins-themes-Adwaita#65) | the shared code's phase 2 (gnustep-window-tabbing a052823) drags and scrolls them; the theme draws them as AdwTabBar: the dragged tab is the foreground at 19% (`tab:selected:active`), opaque, with its close button; the scroll fades are 42pt, the bar's colour opaque for 6pt at the edge and fading out over 36pt (`Docs/Screenshots/window-tabs/`) |
| In a tab view from a Gorm or nib file (GNUstep's Page Layout panel), the tab labels touched the frame and the underline, with bits of GNUstep's own label above and below them: its 17pt tab row (compact metrics, #24) has no room for GNOME's 4pt underline | in a tab row under 24pt the underline is 2pt and the label sits just above it; the whole tab is painted over GNUstep's label, and the line under the tabs drawn again |
| NSBrowser's columns (GNUstep's Open and Save panels, the font panel) had grey rows ending on a white (#303030 dark) column, and NeXT's 3D arrows on rows with more inside | the rows and the space below them are the list colour (`rowBackgroundColor`), set on the columns' matrices and scroll views as the browser draws; the arrows are GtkTreeExpander's pan-end chevron, in the text colour (white on the selected row) |
| Disclosure buttons (`NSDisclosureBezelStyle`) drew nothing; help and circular buttons were rounded squares, the help button without its "?" | a disclosure button is GtkExpander's arrow, pan-end closed and pan-down open, with no bezel; help and circular buttons are round, as libadwaita's `.circular`, the help button with a bold "?" |
| An editable combo box drew its text bold, as a drop-down's label, and regular once the field editor came up | an editable combo box is an entry: its text in the regular weight; only a combo box that can't be edited (a drop-down) is bold |
| Level indicators were bevelled boxes in green, yellow and red (red everywhere with no warning or critical value); the rating style drew garbage (GNUstep has no `NSRatingLevelIndicator` image); indeterminate progress bars were grey stripes; spinners were NeXT's image sequence | as libadwaita: GtkLevelBar's 8pt pill trough (the foreground at 15%) with the level in the accent, libadwaita's warning or error colour past those values (`GnomeThemeWarningColor`, `GnomeThemeErrorColor`); discrete blocks 2pt apart with rounded ends; GNOME's starred and non-starred icons for ratings; a pulse a fifth of the trough long going end to end; AdwSpinner's ring with a turning quarter (`Reference/LevelBar`). Tick marks and the relevancy style keep GNUstep's drawing |
| Sliders drew no tick marks (`setNumberOfTickMarks:`; libs-gui has no drawing for them) | GtkScale's marks: 1x6pt lines in the foreground at 55%, 6pt from the trough on the cell's tick mark side, one at each end of the knob's travel and evenly between |
| Split view dividers were NeXT's dimple (thick and pane splitter styles) or a line in whatever colour was set (thin) | GtkPaned's separators: a thin divider is a 1pt line in the separator colour (the foreground at 15%), a thick one GtkPaned's wide handle, a line at each edge with the window between |
| Bottom tabs (`NSBottomTabsBezelBorder`) kept GNUstep's curved NeXT tabs; in the dark palette a tab view's frame and the line under its tabs all but vanished (controlShadowColor blended toward the window) | bottom tabs are the top tabs' GtkNotebook row below the content, the line and the selected tab's underline on the content's side; the frame and line are the separator colour, GtkNotebook's border (the foreground at 15%, 50% in high contrast). Left and right tabs keep GNUstep's |
| A borderless pop-up button (`setBordered: NO`, as a table's pop-up cells usually are) drew a full button, making rows tall and busy: libs-gui's NSPopUpButtonCell asks for its bezel whether or not it is bordered | libadwaita's flat drop-down: its title and chevron on what is behind it, the pressed fill only while pressed |
| Image views' frames (photo, grey bezel, groove) were NeXT bevels, nearly invisible in the dark palette | GtkFrame's border: 1pt in the separator colour (the foreground at 15%, 50% in high contrast), rounded 6pt so an image's corners stay clear of it; the button style keeps the theme's button |
| A text view's ruler (NSRulerView) was a controlColor band with marks and labels in black, all but lost in the dark palette | the ruler is on the window's colour with a separator line along the text, and libs-gui's marks, labels and markers are redrawn in the foreground at 55%: drawn in black, read back from the window and drawn again as a mask (`GnomeThemeInkMask`) |
| A pop-up item carrying GNUstep's arrow image, as items archived in a Gorm file do, showed it beside the chevron (the Page Layout panel's empty Custom pop-up) | GNUstep's pop-up and pull-down arrow images (`common_Nibble`, `common_3DArrow…`) are left out by name, as the arrow put on an item at run time already was |
| A browser's horizontal scroller (GNUstep's Open and Save panels) sat in a grey bezel box, round the theme's thin overlay indicator | no box: the theme draws the browser's titles itself and leaves GSTheme's scroller bezel out (browsers whose columns aren't separated keep GSTheme's drawing) |
| GNUstep's own Open and Save panels' Home, Mount and Unmount buttons had NeXT's icons | GNOME's symbolic icons under GNUstep's names (`Resources/ThemeImages/common_Home.tiff` and the rest: user-home, drive-removable-media, media-eject), drawn as templates in the text colour |
| A window tab without a close button (neither selected nor hovered) kept room for one at each end, so a 126pt tab cut "Document 3.txt" to "Doc…" | the title has the tab's width less 8pt each side, as AdwTab's |
| Recessed and textured buttons (Cocoa's scope bar and toolbar styles) were the regular filled button | libadwaita's flat buttons: nothing at rest, the foreground at 16% pressed, 10% when a toggle is on, 19% for both (no hover fill: GNUstep's buttons don't track the pointer) |

Regression checks for these live in `Examples/QuirkProbe`; run
`make check-quirks` (see the README).

## GNOME-native polish

The six items found side by side with the libadwaita reference (row density,
icon-only toolbars, the main menu's position, alerts, tab views and checkbox
spacing) are in the Fixed table. Still different from GNOME:

- **Packing of option groups.** GTK stacks checkboxes and radios tighter
  than most GNUstep layouts; that spacing belongs to the app.
- **Text width.** ([#23](https://github.com/danjboyd/plugins-themes-Adwaita/issues/23)) At the same font and size, GNUstep's text runs about 5%
  wider than GTK's, so a paragraph can wrap a line earlier (seen in alerts).
- **Alerts keep a title bar without the header bar.** `AdwAlertDialog` has
  none; with the window manager's decorations GNUstep's alert has the
  window manager's (Mutter 48 keeps a frame on attached dialogs too).
- **Menus have no shadow without the libs-back patch** (their corners are
  rounded wherever the window has an alpha channel).
- **Context menus open at the pointer;** ([#20](https://github.com/danjboyd/plugins-themes-Adwaita/issues/20)) GTK's open just below it.

## Gorm and other nib-based apps

Found putting Gorm through its paces (its palettes, inspectors and document
window, compared with the GNUstep theme). Still open:

- **Menu bars in very narrow windows** ([#25](https://github.com/danjboyd/plugins-themes-Adwaita/issues/25)) can still run past the edge; ☰ stays
  first so the application menu is always reachable.
- **Designing for GNOME's metrics in Gorm** ([#26](https://github.com/danjboyd/plugins-themes-Adwaita/issues/26)) means running Gorm with
  `-GnomeThemeMetrics gnome`, where its own inspectors are cramped. The
  Adwaita palette (`Palettes/Adwaita`, see the README) provides controls at
  GNOME's sizes; roomier inspectors would need changes in Gorm itself.
- **Gorm's CustomView palette item** ([#27](https://github.com/danjboyd/plugins-themes-Adwaita/issues/27)) draws as a pale disabled button instead
  of a dark tile.

## Theme follow-ups

- **Install after merging.** Apps load `~/GNUstep/Library/Themes/Adwaita.theme`.
  On 2026-09-24 that copy was from Jul 27, and all of OneDriveServiceManager's
  quirks (clipped titles, invisible toolbar items, one-line labels and alerts)
  came from it. Run `make install GNUSTEP_INSTALLATION_DOMAIN=USER` after each
  merge.
- **Remove workarounds when upstream fixes land.** ([#28](https://github.com/danjboyd/plugins-themes-Adwaita/issues/28)) The probe's
  `toolbar-view-item-image` check reports PASS instead of KNOWN once libs-gui
  stops clearing view images. Also drop `GnomeThemeOriginalMethod()`'s fallback
  when `-overriddenMethod:for:` walks superclasses, `-windowNeedsMainMenu:`
  when libs-gui attaches the menu to late windows, and the toolbar button
  tracking rects if libs-gui starts tracking for
  `showsBorderOnlyWhileMouseInside`. Drop the `GSTTPanel` and
  `GSDragView` overrides once Mutter thaws unmapped windows (GNOME/mutter#5080)
  or libs-gui stops shrinking them (libs-gui#964). When a libs-gui release
  sizes toolbar items from their content (upstream item 9), drop the
  toolbar layout overrides (`GSToolbarButton`/`GSToolbarBackView` -layout,
  `GSToolbarView -_handleBackViewsFrame`). Once no supported libs-gui
  release lacks a84b42471 (upstream item 8), drop the release-dropping
  `-[NSApplication nextEventMatchingMask:...]` hook for 0.32 in
  GnomeThemePrimaryMenu.m (keep the Escape timer and the press outside:
  GNUstep's menu tracking ignores keys and passes that press on). Once no
  supported libs-gui release lacks 7eec43e3b (indicator image accessors),
  drop the `-setIndicatorImage:inTableColumn:` and
  `-indicatorImageInTableColumn:` overrides for 0.32 (#71). When libs-gui
  shows the sort descriptors' indicator itself (upstream draft 17), drop the
  theme's (in `-drawTableHeaderRect:inView:`, and the `-setSortDescriptors:`
  override that redraws the header).

## GNUstep issues to report upstream

Confirmed on 2026-09-24 with a minimal program under the default theme, both on
the installed gui 0.32.0 / base 1.31.1 and on master (gui ff49ac8, base
a8dd1b8). Draft issues and their programs are in `Docs/upstream-issues/`. Drafts 2 and 4, still to file, are tracked in [#29](https://github.com/danjboyd/plugins-themes-Adwaita/issues/29).

1. **libs-gui: a toolbar view item loses its view's image.** Not filed:
   fixed by [libs-gui#952](https://github.com/gnustep/libs-gui/pull/952),
   which we confirmed on 2026-10-02. The cause is
   `-[NSToolbarItem _layout]`. It re-applies the item's own image, which is
   nil for a view item, and `GSToolbarBackView -setImage:` passes that nil to
   the view. The item isn't copied or archived. Workaround: also call
   `[item setImage:]` with the view's image.
2. **libs-gui: `NSWindows95InterfaceStyle` windows created after launch get
   no menu bar.** The menu reaches windows only through
   `-updateAllWindowsWithMenu:`, which runs when the main menu changes. Seen
   under GNOME/Mutter and under Xvfb. This theme works around it
   (`-[GnomeTheme windowNeedsMainMenu:]`); elsewhere, apps call
   `[window setMenu: [NSApp mainMenu]]`.
3. **libs-base: the main dispatch queue is drained only in
   `NSDefaultRunLoopMode`.** Filed as
   [gnustep/libs-base#806](https://github.com/gnustep/libs-base/issues/806). Main-queue blocks stall in the modal-panel and
   event-tracking modes, so they wait while a sheet, a modal panel or menu
   tracking is active (`NSRunLoop.m`, where the drainer is registered).
4. **libs-gui: `-[GSTheme overriddenMethod:for:]` matches only the receiver's
   exact class.** An override reached from a subclass gets 0 and can't call
   the original. This was the root cause of the invisible toolbar items; the
   theme works around it with `GnomeThemeOriginalMethod()`.

Found on 2026-09-25 while tracking down tool tips that show only once under
GNOME Wayland. Confirmed on master (gui ff49ac8, back 5db2ae7) and on the
installed 0.32.0, using the default theme.

5. **Mutter: an Xwayland window resized and then unmapped stays frozen.**
   Filed as [GNOME/mutter#5080](https://gitlab.gnome.org/GNOME/mutter/-/issues/5080).
   Mutter freezes commits on a resize and thaws them only after it next
   paints the window, which never happens if the window is unmapped first.
   `_XWAYLAND_ALLOW_COMMITS` stays 0 and the window is blank when mapped
   again. Reproduced with plain Xlib (`xwayland_resize_unmap.c`); this is the
   root cause.
6. **libs-gui: tool tips shrink the visible panel before ordering it out.**
   Filed as [gnustep/libs-gui#964](https://github.com/gnustep/libs-gui/issues/964).
   `-[GSToolTips _endDisplay:]` sets `NSZeroRect` and then orders out, which
   triggers item 5 on every hide. Without the shrink, tool tips showed every
   time. `GSDragView` does the same, and drag images are affected too.
7. **libs-gui: `_initBackendWindow` sets the level before the window is
   registered.** Filed as
   [gnustep/libs-gui#965](https://github.com/gnustep/libs-gui/issues/965). The backend can't identify the tool tip panel, so it types
   it `_NET_WM_WINDOW_TYPE_DIALOG` instead of `_TOOLTIP`. The theme sets
   `_TOOLTIP` itself, and the libs-back patch types the window again just
   before mapping it (`Docs/PROPOSAL_LIBS_BACK_CSD.md`, item 5).

Found on 2026-09-25 while building the header bar; already fixed on master.

8. **libs-gui: a click on a menu title closes the menu on the release.** In
   gui 0.32.0 every mouse up ends menu tracking (commit 82717eefe), so
   menu bar menus and ☰ closed as soon as the click that opened them was
   released. Fixed on master by a84b42471; not in a release yet. The theme
   works around it for ☰ (see `8-libs-gui-menu-click-closes-fixed-on-master.md`).

9. **libs-gui: toolbar heights are fixed constants** ([libs-gui#972](https://github.com/gnustep/libs-gui/issues/972)). Items get a 60pt (50pt
   small) slot whatever their content, empty labels still take a label row,
   views taller than 32pt are removed and images are made 32x32; there's no
   theme hook. The theme lays toolbars out itself with GNOME metrics (see
   `9-libs-gui-toolbar-fixed-heights.md`, with the repro `toolbar_heights.m`).

### Reported by OneDriveServiceManager: withdrawn

OneDriveServiceManager rechecked these on 2026-09-24 with the current theme
installed. None is a GNUstep bug; don't report them upstream.

- **A label holding one long "word" (a path) draws nothing.** Its text was
  four leading spaces and then the path. GNUstep wrapped at the spaces and
  put the path on a second line, which the one-line frame hid. Expected
  behaviour.
- **A pop-up button with the focus takes Return.** The window had no default
  button cell, only a button with a Return key equivalent.
  `setDefaultButtonCell:` fixes it, matching the probe.
- **Return/Esc key equivalents stop working after another panel closes.**
  Seen only with xdotool's synthetic events, sent to a window that had lost
  the focus. Not a proven bug. Calling `makeKeyAndOrderFront:` on the window
  again is still good UX.
- **The toolbar view-item image loss is not caused by copying or archiving**
  (OneDriveServiceManager's first guess). Upstream item 1 above gives the real
  cause. OneDriveServiceManager now uses plain image items, so it no longer
  needs the workaround.
