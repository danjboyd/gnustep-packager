**Repository:** gnustep/libs-gui

**Status:** draft, not filed. Found for plugins-themes-Adwaita#70.
Before filing, confirm the Cocoa behaviour on macOS with the reproducer
(it builds unchanged with `clang -framework AppKit`).

**Title:** NSComboBox: -selectItemAtIndex: doesn't put the item in the field

### Summary

`-[NSComboBox selectItemAtIndex:]` selects the item in the list but
leaves the combo box's string value as it was, empty for a new combo box.
An app that selects an item at launch to show a default choice (a common
idiom with Cocoa, where the field shows the selected item) gets an empty
field, and `-stringValue` returns "" though `-objectValueOfSelectedItem`
is the item. A theme that draws the selected item when the string is empty
hides this until the field editor comes up, which shows the empty string.

Choosing an item from the list with the mouse does set the string value
(`-[GSComboWindow validateSelection]`), so the two ways of selecting
disagree.

### Steps to reproduce

The complete program is `combo_select_string.m`, to paste in or attach.

```objc
combo = [[NSComboBox alloc] initWithFrame: NSMakeRect (0, 0, 200, 26)];
[combo addItemsWithObjectValues:
  [NSArray arrayWithObjects: @"Largest files", @"Duplicates", nil]];
[combo selectItemAtIndex: 1];
printf ("string value: \"%s\"\n", [[combo stringValue] UTF8String]);
```

`./combo_select_string -GSTheme GNUstep`, libs-gui master (ff49ac830) and
0.32:

```
selected index: 1
selected item: Duplicates
string value: ""
FAIL
```

### Expected

`string value: "Duplicates"`, and the field showing it.

### Cause

`-[NSComboBoxCell selectItemAtIndex:]` (Source/NSComboBoxCell.m) records
the index (`-_setSelectedItem:`), selects the row in the pop-up and posts
NSComboBoxSelectionDidChangeNotification. Only `-[GSComboWindow
validateSelection]`, run when the user picks a row, sets the cell's
string value from `-_stringValueAtIndex:`.

### Suggested fix

In `-[NSComboBoxCell selectItemAtIndex:]`, when the selection changes,
set the string value as `-validateSelection` does:

```objc
[self setStringValue: [self _stringValueAtIndex: index]];
```
