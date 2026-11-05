**Repository:** gnustep/libs-gui

**Not filed:** fixed by [gnustep/libs-gui#952](https://github.com/gnustep/libs-gui/pull/952) (open, by probonopd, with a test); we confirmed it there on 2026-10-02 instead of filing.

**Title:** NSToolbarItem with a custom view: -_layout sets the view's image to nil

### Summary

When a toolbar item uses a custom view that has an image (for example an
`NSButton` with `setImage:`), the view's image is cleared as soon as the
toolbar lays the item out. The button then draws its default title
("Button", clipped) instead of the image.

### Steps to reproduce

Excerpt below; the complete program is `toolbar_view_image.m`, to paste in or attach. It puts an `NSButton` with an image into a toolbar
item, then checks the button's image one second later.

```objc
- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar
      itemForItemIdentifier: (NSString *)identifier
  willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier: identifier];
  NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(24, 24)];

  [image lockFocus];
  NSRectFill(NSMakeRect(4, 4, 16, 16));
  [image unlockFocus];

  button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 36, 32)];
  [button setImage: image];
  [button setImagePosition: NSImageOnly];
  [item setView: button];
  [item setLabel: @"Item"];
  NSLog(@"button image after setView: %@", [button image] ? @"set" : @"nil");
  return item;
}

/* ...one second after the window with the toolbar is shown: */
NSLog(@"button image after layout:  %@", [button image] ? @"set" : @"nil");
```

Output:

```
button image after setView: set
button image after layout:  nil
```

The button in the toolbar is the same object the delegate returned; it is not
a copy.

### Expected

The view keeps its image. A view item's image belongs to the view.

### Cause

`-[NSToolbarItem _layout]` (Source/NSToolbarItem.m, line 1521 on master)
re-applies the item's own `_image` to the back view:

```objc
if ([[self toolbar] displayMode] != NSToolbarDisplayModeLabelOnly)
  {
    [(GSToolbarButton*)_backView setImage: _image];
  }
```

For a view item, `_backView` is a `GSToolbarBackView`, whose `-setImage:`
(line 867) forwards to the custom view when it responds to `setImage:`. The
item's `_image` was never set, because the image was set on the view, so the
view's image is replaced with nil.

### Suggested fix

Only re-apply the image when the item has no custom view (`_view == nil`),
or when `_image` is not nil. The comment says the call exists to restore the
image after leaving `NSToolbarDisplayModeLabelOnly`, and that only concerns
`GSToolbarButton` back views.

### Workaround

Also set the same image on the toolbar item: `[item setImage: [button image]]`.

### Environment

- libs-gui master ff49ac8 (2026-09-22), libs-base master a8dd1b8. Also seen
  with the released gui 0.32.0 and base 1.31.1.
- Debian 13, clang 19, libobjc2 (gnustep-2.2 runtime), cairo/xlib backend.
- Same result with the default theme and with a custom theme.
