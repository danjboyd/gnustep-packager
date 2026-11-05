# Adwaita theme: notes for OneDriveServiceManager

From the plugins-themes-adwaita project, 2026-09-24. This answers the "GNUstep
quirks found so far" list in OneDriveServiceManager's
`docs/gnustep_frontend.md` (section 4, v3 conventions). Each item was checked
with a probe app under this theme and under GNUstep's default theme.

## First: you were running an old theme build

Apps load the theme from `~/GNUstep/Library/Themes/Adwaita.theme`. Until
today that copy was built on **Jul 27**, before the fixes below. The clipped
titles, invisible toolbar items and one-line labels and alerts came from
that copy. The current build is now installed there.

To check which build an app gets:

```sh
ls -la --time-style=long-iso ~/GNUstep/Library/Themes/Adwaita.theme/Adwaita
```

It should be dated 2026-09-24 or later.

## Workarounds you can remove

These are theme bugs, fixed in the installed build.

| Your note | Now |
|---|---|
| "`NSButton` needs `sizeToFit` plus about 24 px, or its title is clipped (checkboxes about 30 px)" | `sizeToFit` alone is enough. Buttons measure with the theme's bezel and title insets; checkboxes and radios allow for the theme's indicator. Remove the padding. |
| "`NSTextField` labels don't wrap; keep notes to one line or stack several labels" | Labels wrap when the frame is tall enough for more than one line. Size the frame for the lines you need. |
| "`NSAlert` shows one unwrapped line of informative text; keep it short" | Informative text wraps across as many lines as it needs. |
| "Toolbar items with only an image don't draw under the Adwaita theme" | Image-only items (`[item setImage:]`, no view) draw. |

### Toolbar: going back to plain image items

With image-only items working, you can drop the `NSImageView` under a
transparent `NSButton`:

```objc
NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier: identifier];
[item setImage: [NSImage imageNamed: @"sync"]];   /* or an image loaded from your PNGs */
[item setLabel: @"Sync Now"];
[item setTarget: self];
[item setAction: @selector(syncNow:)];
```

GNUstep validates image items, and doesn't validate view items
(`-[NSToolbarItem validate]` returns early when the item has a view). It asks
the target's `validateToolbarItem:` (or `validateUserInterfaceItem:`), so
enabling and disabling no longer needs `-updateToolbarItems`. Changing a
label ("Pause" and "Resume") is still your code's job: call `setLabel:`.

If you keep a button inside a view item, see the toolbar bug below.

## Still true: GNUstep bugs (not the theme)

These happen under GNUstep's default theme too, including on libs-gui and
libs-base master as of 2026-09-22/23. Keep the workarounds; they are being
reported upstream.

1. **A button inside a toolbar view item loses its image.** Your note
   blamed GNUstep copying the item. The actual cause: when the toolbar lays
   the item out, it passes the item's own image, which is nil for a view
   item, on to the view. **Workaround:** also set the same image on the item:
   `[item setView: button]; [item setImage: [button image]];`.
2. **With `NSWindows95InterfaceStyle`, the menu bar appears only in windows
   that existed when the menu was set up.** Windows created later (detail
   window, wizards) get none. **The theme now handles this** (since
   2026-09-24, sprint 1): when a window that can become main becomes key or
   main without a menu, the theme gives it the main menu. Your
   `[window setMenu: [NSApp mainMenu]]` calls are no longer needed with this
   theme. They're harmless, and still needed under other themes.
3. **`beginSheet:` blocks main-queue work.** GNUstep services the main
   dispatch queue only in `NSDefaultRunLoopMode`. A sheet or modal panel
   (`NSModalPanelRunLoopMode`), or menu and scroller tracking
   (`NSEventTrackingRunLoopMode`), holds back every
   `dispatch_async(dispatch_get_main_queue(), ...)` until it ends. Your rule
   stands: anything that reports through the main queue must not be a sheet
   or run modally.

## Not reproduced: please send exact steps

These didn't happen in the probe, under this theme or the default one. If
you still see them with the new theme installed, send the code that builds
the view: frame, line break mode, and how and when it's added.

- **"A label holding one long 'word' (a path) draws nothing when it
  doesn't fit."** It clipped at the edge at every height from 14 to 26 pt,
  with and without `/` in the text. `NSLineBreakByTruncatingMiddle` works and
  is still the better choice for paths. One thing to check: the label wasn't
  one of the rows the `__block` y-offset bug stacked on the first line.
- **"A pop-up button with the focus takes Return."** With the pop-up as first
  responder and a default button set (`setDefaultButtonCell:` plus
  `setKeyEquivalent: @"\r"`), Return fired the default button.
- **"After another panel closes, Return/Esc stop working."** After a panel
  was shown and closed, Return and Esc still fired, with or without
  `makeKeyAndOrderFront:`. This test ran under Xvfb without a window manager,
  so it may depend on GNOME's focus handling. Steps from the real app would
  settle it.

## Fonts

`[NSFont systemFontOfSize: 0]` gives Cantarell at the GNOME interface size.
`[NSFont boldSystemFontOfSize: 0]` now gives Cantarell Bold; before today it
fell back to DejaVu Sans Bold. `userFixedPitchFontOfSize: 0` gives the GNOME
monospace font (Noto Sans Mono here). No change needed on your side.

## Tables and lists (theme change, 2026-09-24, sprint 2)

Tables and outline views now look like libadwaita lists:

- **No grid lines unless you ask.** GNUstep draws a grid on every table by
  default; the theme now draws none unless the app calls `setGridStyleMask:`
  or `setDrawsGrid:` (or the table comes from a nib or Gorm file with a grid).
  If a table needs row lines, call
  `[table setGridStyleMask: NSTableViewSolidHorizontalGridLineMask]`.
- **No frame** around a scroll view holding a table, even with
  `NSBezelBorder`. The list is a plain area on the window background, so
  leave some margin around it.
- **Headers** are small, dim and bold. Centred titles (GNUstep's default)
  start at the leading edge; titles you align left or right keep that.
- **Scrollbars** are thin indicators with no track, and hidden when nothing
  overflows.

## Toolbar and menu bar (theme change, 2026-09-25, sprint 3)

- **The greyed "OneDriveServiceManager" item is gone.** GNUstep adds an item
  named after the app to the start of a Win95-style menu bar and moves loose
  menu items (ones without a submenu) into it. When there are none it was
  drawn disabled; the theme now removes it. If the app has such items (About,
  Quit at the top level), the item stays, drawn as GNOME's ☰ main-menu icon.
- **Toolbar buttons get hover and pressed backgrounds**, like GNOME header bar
  buttons, and the toolbar has a light bottom edge instead of a dark line.
  This works for image items (`setImage:`); view items draw themselves.
- Toolbars keep the display mode you set. For the GNOME look, use
  `NSToolbarDisplayModeIconOnly` with a tooltip on each item.

## Focus rings on buttons (theme change, 2026-09-25)

The Cancel button in the Resync, sign-in and wizard panels is the first key
view, so it has focus when the panel opens. It drew a ring around its title
and blue marks in its corners. Now, as in GNOME, a panel opened with the
mouse shows no ring on its buttons. After a key press (Tab, Return, Escape,
anything) the focused button gets a ring just inside its edge; the next click
hides it again. No change needed on your side.

## GNOME-native polish (theme change, 2026-09-25)

- **Tab views** (the Details window) look like a GtkNotebook: a thin frame,
  plain text tabs with a blue underline under the selected one, and the
  pages on a white background.
- **Alerts** look like GNOME's: no app icon, a centred bold heading over
  centred text, and buttons of equal width in a row, the default at the
  right. Nothing to change; `NSAlert` gets this.
- **The ☰ main menu** sits at the right end of the menu bar.
- **Checkbox and radio labels** sit closer to their box (4pt instead of
  10pt); `sizeToFit` accounts for it.
- **Toolbars** the app gives no display mode are icon-only, and each button
  shows its label as a tool tip. `MainWindowController.m` sets
  `NSToolbarDisplayModeIconAndLabel`, so yours keeps its labels; drop that
  line for the GNOME look (and `setToolTip:` where the label isn't the tip
  you want).
- **Tables** built in code get GNOME's 34pt rows and no cell spacing. Your
  outline sets `MAX(22, lineHeight + 8)`, about 25pt, and keeps it; drop the
  `setRowHeight:` call for GNOME's density.

## Where to report theme problems

Add them to plugins-themes-adwaita's `Docs/IMPROVEMENTS.md` or tell the theme
project directly. Include a screenshot and the code that builds the view.
Test against the installed build (see the `ls` command above).
