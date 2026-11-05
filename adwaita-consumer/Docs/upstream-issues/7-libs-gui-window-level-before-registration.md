**Repository:** gnustep/libs-gui

**Filed:** [gnustep/libs-gui#965](https://github.com/gnustep/libs-gui/issues/965), 2026-09-25

**Title:** _initBackendWindow sets the window level before the window is registered, so tool tips get _NET_WM_WINDOW_TYPE_DIALOG

### Summary

libs-back's X11 `-setwindowlevel::` gives the tool tip panel
`_NET_WM_WINDOW_TYPE_TOOLTIP`. It identifies the panel by looking up the
NSWindow (`GSWindowWithNumber()`) and checking for `GSTTPanel`. The first
time that runs, the NSWindow isn't registered yet, so the lookup returns nil
and the panel gets `_NET_WM_WINDOW_TYPE_DIALOG`. Later calls with the same
level return early, so the type is never corrected. Window managers
therefore treat tool tips as dialogs.

### Related

As a dialog, the tool tip is a normal managed window to the window manager;
GNOME can then flag it as demanding attention, which may be the
`"Window" is ready` notification mentioned in #404.

### Steps to reproduce

The complete program is `tooltip_rehover.m` (also used for the tool tip
freezing issue). Each time the tool tip is shown, it prints the tool tip
window's `_NET_WM_WINDOW_TYPE`.

Hover over the button until the tool tip appears. Output on master (the
same on 0.32.0):

```
tool tip shown (1): visible YES, ..., _NET_WM_WINDOW_TYPE _NET_WM_WINDOW_TYPE_DIALOG, ...
```

With `--GNU-Debug=XGTrace` (on 0.32.0), `setwindowlevel` for the new panel
comes before `windowdevice`. `windowdevice` is called when
`-_startBackendWindow` creates the window's graphics context, just after it
registers the window:

```
DPSsetwindowlevel: 101 : 18
DPSwindowdevice: 18
```

### Expected

`_NET_WM_WINDOW_TYPE_TOOLTIP`, as `-setwindowlevel::` intends.

### Cause

The tool tip panel is created with `defer: YES`, so its backend window is
created when it is first ordered front. `-[NSWindow _initBackendWindow]`
(Source/NSWindow.m on master) sets the level before `-_startBackendWindow`
puts the window in `windowmaps`:

```objc
_windowNum = [srv window: _frame : _backingType : _styleMask
                        : [_screen screenNumber]];
...
[srv setwindowlevel: [self level] : _windowNum];     /* line 1045 */
...
[self _startBackendWindow];                          /* line 1053: NSMapInsert(windowmaps, ...) */
```

In libs-back, `-setwindowlevel::` (Source/x11/XGServerWindow.m, line 3646 on
master) checks `[[GSWindowWithNumber(window->number) className] isEqual:
@"GSTTPanel"]`, which is nil at that point. The early return at line 3572
(`window_level != level`) then skips every later call with the same level.

### Suggested fix

In `-_initBackendWindow`, call `-_startBackendWindow` before
`setwindowlevel`, so the backend can look the window up. Tested on master:
the tool tip is then `_NET_WM_WINDOW_TYPE_TOOLTIP` when it is first shown
(four runs; without the patch it is `_DIALOG` every time).

```diff
--- a/Source/NSWindow.m
+++ b/Source/NSWindow.m
@@ -1042,6 +1042,10 @@
     {
       [NSException raise: @"No Window" format: @"Failed to obtain window from the back end"];
     }
+  // Set up context.  This registers the window number, which the backend
+  // may use to look the window up when the level is set.
+  [self _startBackendWindow];
+
   [srv setwindowlevel: [self level] : _windowNum];
   if (_parent != nil)
     {
@@ -1049,9 +1053,6 @@
             forChildWindow: _windowNum];
     }
 
-  // Set up context
-  [self _startBackendWindow];
-
   /* Ok, now add the drag types back */
   if (dragTypes)
     {
```

Alternatively, libs-back could decide the type when the window is mapped
rather than when the level is set.

### Also seen (not investigated)

On master, with or without this patch, the type sometimes reads
`_NET_WM_WINDOW_TYPE_NORMAL` on later showings (3 of the 4 later showings in
two runs with the patch). It didn't happen with `--GNU-Debug=XGTrace`, where
the level stayed at `NSPopUpMenuWindowLevel` throughout, so I don't know the
cause yet.

### Environment

- libs-gui master ff49ac8 (2026-09-22), libs-back master 5db2ae7
  (2026-09-11), libs-base 1.31.1. Also seen with the released gui 0.32.0 and
  back 0.32.0.
- Debian 13, GNOME Shell / Mutter 48.7 (Xwayland 24.1.6), clang 19,
  libobjc2, cairo/xlib backend, default theme.
