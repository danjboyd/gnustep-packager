**Repository:** gnustep/libs-gui

**Filed:** [gnustep/libs-gui#972](https://github.com/gnustep/libs-gui/issues/972), 2026-10-02 (from plugins-themes-Adwaita#8)

**Title:** Toolbar heights are fixed constants: item content can't change them, empty labels still take space, and view items taller than 32pt are removed

### Summary

The height of a toolbar comes from constants in `NSToolbarItem.m` and
`GSToolbarView.m`, not from its items, and neither a theme nor an app can
change it:

- Every item's back view starts at `ItemBackViewRegularHeight` (60) or
  `ItemBackViewSmallHeight` (50), plus 1pt per missing border
  (`-[GSToolbarButton layout]`, `-[GSToolbarBackView layout]`).
  `GSToolbarView` takes its height from the tallest back view
  (`-_handleBackViewsFrame`, `-_heightFromLayout`), and
  `GSWindowDecorationView` sizes the window from that.
- In icon-and-label mode an item whose label is empty measures the string
  `@"Dummy"` instead, so the label row is reserved even when no item has a
  label.
- `-[GSToolbarBackView layout]` removes the item's view from the toolbar
  when it's taller than 32pt (24pt in small mode). `minSize`/`maxSize`
  can't bring it back. The item simply disappears.
- `-[GSToolbarButton layout]` resizes the item's image to 32x32 (24x24 in
  small mode), whatever size the app gave it.

There is no `GSTheme` method or user default for any of this.

### Steps to reproduce

`toolbar_heights.m` puts two items in a window's toolbar: an image item with
a 16x16 image, and a view item holding a 34x34 button (min and max size
34x34). It does this once in icon-only mode, and once in icon-and-label mode
with empty labels. Run with `-GSTheme GNUstep`. Checked on 2026-10-02 under
Xvfb:

```
gui 0.32.0 (installed):
icon only: toolbar 43 pt high, 34pt button view removed, image item's image 32x32
icon and label, empty labels: toolbar 62 pt high, 34pt button view removed, image item's image 32x32

gui master ff49ac8 (the constants are unchanged at 549f63913):
icon only: toolbar 43 pt high, 34pt button view removed, image item's image 32x32
icon and label, empty labels: toolbar 62 pt high, 34pt button view removed, image item's image 32x32
```

### How macOS behaves

From Apple's documentation and developer reports, not checked on a Mac:

- Item size comes from the item. A view item's size was its
  `minSize`/`maxSize`; since macOS 12 those are deprecated, and AppKit
  measures the item's view with Auto Layout
  ([NSToolbarItem](https://developer.apple.com/documentation/appkit/nstoolbaritem)).
- The toolbar grows with its items: a report from macOS 12 describes large
  items making the toolbar "way too big"
  ([forum thread 696389](https://developer.apple.com/forums/thread/696389)).
  Old Cocoa-dev posts (2003, 2009) describe a 32pt limit, so this has
  changed over the years.
- On macOS 12, a view too big for its constraints is hidden
  ([forum thread 667826](https://developer.apple.com/forums/thread/667826)).
- AppKit has no API to set the height either. Since macOS 11 the window's
  `toolbarStyle` (unified, unified compact, expanded) picks the overall
  look. We found no documented minimum heights.
- Unverified: whether AppKit reserves the label row when every label is
  empty.

### Expected

Something closer to that:

1. Derive each back view's height from its content: the view's frame (or
   `minSize`/`maxSize`), or the image's size, plus padding. Keep the
   current numbers as minimums.
2. Don't remove a view item for being taller than 32pt. Grow the toolbar
   instead, perhaps up to a limit.
3. Don't reserve label space when an item's label is empty. Perhaps skip the
   label row altogether when no item has a label.
4. Leave an item's image at the size the app gave it, or scale it down only
   when it's larger than the slot.
5. Add a `GSTheme` hook for toolbar metrics (item padding, minimum row
   height, image size per size mode), so themes like Adwaita (a 46pt row,
   34pt buttons, 16px icons) don't need to override private layout
   methods.

### Theme workaround

Since 2026-10-02, with GNOME metrics, the theme lays toolbars out itself
(`GnomeThemeControls.m`):
- It overrides `-[GSToolbarButton layout]` and `-[GSToolbarBackView layout]`
  to size each item from its content.
- After `-[GSToolbarView _handleBackViewsFrame]`, it gives every item the
  row's height and writes that to `_heightFromLayout`.
- It puts back views libs-gui removed.
- It keeps images at their own size, up to 24pt (16pt in small mode).
- It draws view items' labels in the text colour. libs-gui draws them in
  black, which is unreadable in a dark palette.

The probe's `toolbar-row-height` check measures 47pt for icon only,
label only, small, and icon and label with empty labels; and 58pt for icon
and label with labels. Compact metrics (Gorm and nib apps) keep libs-gui's
layout. Drop all of this once libs-gui sizes items from their content or
has a theme hook for it.
