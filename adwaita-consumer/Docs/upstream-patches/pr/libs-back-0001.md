x11: keep the window manager functions of windows the gui decorates

With `GSBackHandlesWindowDecorations` (or `GSX11HandlesWindowDecorations`) NO, `setWindowHintsForStyle()` gives every window the borderless window's Motif hints: no decorations, which is right, but also functions 0, which tells the window manager that the window may not be moved, resized, minimized, maximized or closed. Mutter follows that for all but resize, so it won't move, minimize, maximize or close such a window, whether asked through `_NET_WM_MOVERESIZE`, `_NET_WM_STATE`, Super-drag or its window menu. GNUstep's own title bar moves the window itself (`-setFrameOrigin:`, which `-placewindow::` carries out with `XMoveResizeWindow`), and the hints don't restrict that, so this went unnoticed.

A styled window the gui decorates now asks for no decorations but keeps the functions its style allows, plus move. Borderless windows keep functions 0, and nothing changes when the window manager draws the decorations.

This changes behaviour for everyone who uses GNUstep-drawn decorations: every styled window, sheets and utility panels included, now lets the window manager move it (and resize, minimize, maximize or close it as its style allows), where before it allowed nothing.

It may bear on #82. Since #228 the gui draws the decorations when the window manager draws none, and that is the case where these hints asked for no functions at all. I haven't been able to check whether the window manager in #82 honours the functions field, so I don't know whether this fixes it.

`_MOTIF_WM_HINTS` (flags, functions, decorations) with the gui drawing the decorations, before and after:

```
titled, closable, miniaturizable, resizable   3 0 0  ->  3 62 0
titled, closable                              3 0 0  ->  3 36 0
titled                                        3 0 0  ->  3 4 0
borderless                                    3 0 0  ->  3 0 0
```

Under GNOME Shell 48.7 (X11), with the GNUstep theme and the gui drawing the decorations, Mutter's `_NET_WM_ALLOWED_ACTIONS` for a fully styled window lists resize, fullscreen, change desktop, above and below before the change, and includes move, maximize and close after it.

`Tests/x11/motifhints.m` is new: it creates windows of those four styles and compares their hints exactly, so it catches both a missing function and a frame being asked for, and the borderless case guards against the change reaching windows that must stay fixed. It reads only what the backend sets, so it needs a display but no particular window manager. Without the change three of its five checks fail; with it all five pass. `Tests/x11` gives 54 passed, 0 failed, against 49 passed, 0 failed on master. The changed file and the test also pass a syntax check with GCC's Objective-C front end.

AI assistance: this change, its test and this description were written with Claude (Anthropic's Claude Code).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
