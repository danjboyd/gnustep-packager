**Repository:** gnustep/libs-gui

**Filed:** [gnustep/libs-gui#991](https://github.com/gnustep/libs-gui/issues/991), 2026-10-08, the version signed off (draft 62c82f0, reproducer 8501413), with the reproducer's source attached.

**Title:** NSWindows95InterfaceStyle: windows created after launch get no menu bar

### Summary

With `NSMenuInterfaceStyle = NSWindows95InterfaceStyle`, the main menu is
drawn inside each window. That only happens for windows that already exist
when the main menu is first updated. A window created later (a document
window, a detail window, a window opened from a menu command) has no menu
bar unless the app calls `[window setMenu: [NSApp mainMenu]]` itself.

### Steps to reproduce

Excerpt below; the complete program is `win95_late_window_menu.m`, to paste in or attach. Run it with
`-GSTheme GNUstep -NSMenuInterfaceStyle NSWindows95InterfaceStyle` (a theme
that attaches menus itself hides the bug). It sets the main menu,
opens one window in `applicationDidFinishLaunching:` and a second window one
second later, then checks both.

```objc
- (void) applicationDidFinishLaunching: (NSNotification *)n
{
  early = [self windowAt: 100 title: @"Early"];
  [early makeKeyAndOrderFront: nil];
  /* openLate: creates a second window the same way and makes it key. */
  [NSTimer scheduledTimerWithTimeInterval: 1.0 target: self
                                 selector: @selector(openLate:) userInfo: nil repeats: NO];
  [NSTimer scheduledTimerWithTimeInterval: 2.0 target: self
                                 selector: @selector(check:) userInfo: nil repeats: NO];
}
```

Output:

```
window created at launch: menu attached
window created later:     menu none  (FAIL)
```

On screen (Xvfb, no window manager, GNUstep's default theme), the second
window has no menu bar, though it is the key window; the first has one.

### Expected

Every window that can become main shows the application menu, as on
Windows, without app code.

### Cause

The menu reaches windows only through `-[NSMenu update]`
(Source/NSMenu.m, line 1088 on master):

```objc
if (_menu.mainMenuChanged)
  {
    if (NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil) == NSWindows95InterfaceStyle)
      {
        [[GSTheme theme] updateAllWindowsWithMenu: self];
      }
    _menu.mainMenuChanged = NO;
  }
```

`-updateAllWindowsWithMenu:` (Source/GSThemeMenu.m, line 163) walks
`[NSApp windows]` at that moment. `mainMenuChanged` is set only when the
menu changes (`-menuChanged`, line 536). Nothing attaches the menu to a
window that is created, or becomes main, afterwards.
`-[NSApplication _windowDidBecomeKey:]` calls `[_main_menu update]`, but the
flag is already clear by then.

### Suggested fix

When a window becomes key or main in this style and can become main, but its
menu isn't the main menu, call `[[GSTheme theme] updateMenu: [NSApp mainMenu]
forWindow: window]`. This could go in `-[NSApplication _windowDidBecomeMain:]`
or in `-[NSWindow becomeMainWindow]`.

### Workaround

`[window setMenu: [NSApp mainMenu]]` on every window the app creates after
launch.

### Environment

- Reproduced 2026-10-07 with libs-gui master 549f639 (2026-10-02, unpatched,
  run uninstalled through `LD_LIBRARY_PATH`) and with the installed gui
  (a Debian build of the master snapshot 7892137bd, 2026-03-31, with two
  unrelated patches); libs-base 1.31.1 in both runs.
- Debian 13, clang 19, libobjc2 2.3 (gnustep-2.2 runtime), cairo/xlib
  backend, under Xvfb with no window manager.

---

Investigated, reproduced and written up with AI assistance (Claude).
