**Repository:** gnustep/libs-gui

**Status:** draft, not filed. Found for plugins-themes-Adwaita#71.
Before filing, confirm on macOS that Cocoa shows the indicator by itself,
with the reproducer below (it builds unchanged against Cocoa with
`clang -framework AppKit`).

**Title:** NSTableView: sorting by a column header shows no sort indicator

### Summary

When a user clicks the header of a column that has a sort descriptor
prototype, NSTableView updates `-sortDescriptors` and tells its delegate
(`-tableView:sortDescriptorsDidChange:`), but nothing shows which column
the table is sorted by, or in which direction. Cocoa shows the ascending
or descending indicator in the header of the primary sort descriptor's
column. In GNUstep:

- the column gets no indicator image (`-indicatorImageInTableColumn:`
  stays nil);
- `-[NSTableHeaderCell drawSortIndicatorWithFrame:inView:ascending:priority:]`,
  which GNUstep implements, is never called;
- the `NSAscendingSortIndicator` and `NSDescendingSortIndicator` images it
  draws don't exist in GNUstep's images, so `+imageNamed:` returns nil for
  them, and an app that sets them itself (`-setIndicatorImage:inTableColumn:`)
  sets nil.

### Steps to reproduce

The complete program is `sort_indicator.m`, to paste in or attach. It
makes a table whose column has a sort descriptor prototype, clicks the
column's header (a mouse down on the header view with the release already
queued), redraws the window, and counts the header cell's
`-drawSortIndicatorWithFrame:...` calls.

```objc
[column setSortDescriptorPrototype:
  [[NSSortDescriptor alloc] initWithKey: @"name" ascending: YES]];
...
[NSApp postEvent: mouseEvent (NSLeftMouseUp, click, window) atStart: NO];
[header mouseDown: mouseEvent (NSLeftMouseDown, click, window)];
[window display];
indicator = [table indicatorImageInTableColumn: column];
```

`./sort_indicator -GSTheme GNUstep`, libs-gui master (ff49ac830) and 0.32:

```
sort descriptors: ("<NSSortDescriptor: 0x55bbe2539778>")
indicator image in the column: nil
highlighted column: none
header cell asked to draw a sort indicator: 0 time(s)
FAIL
```

On 0.32 `-indicatorImageInTableColumn:` also logs "Method
indicatorImageInTableColumn: is not implemented"; master implements the
accessors since 7eec43e3b.

### Expected

After the click, the sorted column's header shows the ascending indicator,
and after a second click the descending one, as in Cocoa.

### Cause

`-[NSTableView _clickTableColumn:]` (Source/NSTableView.m) changes the
sort descriptors and stops there. `-[GSTheme drawTableHeaderRect:inView:]`
(Source/GSThemeDrawing.m) draws only an indicator image an app has set;
nothing calls the header cell's `-drawSortIndicatorWithFrame:...`.

### Suggested fix

In `-drawTableHeaderRect:inView:`, when a column has no indicator image of
its own, and the table's first sort descriptor has the key of that column's
`-sortDescriptorPrototype`, ask the header cell to draw the indicator:

```objc
NSSortDescriptor *primary = [[tableView sortDescriptors] firstObject];

if (indicatorImage == nil && primary != nil
    && [[primary key] isEqual: [[column sortDescriptorPrototype] key]])
  {
    [(NSTableHeaderCell *)cell drawSortIndicatorWithFrame: drawingRect
                                                   inView: tableHeaderView
                                                ascending: [primary ascending]
                                                 priority: 0];
  }
```

and add `NSAscendingSortIndicator` and `NSDescendingSortIndicator` images
(with `nsmapping.strings` entries) so the cell has something to draw.
Themes can then draw their own indicator by overriding the cell's method
or `-drawTableHeaderRect:inView:`.
