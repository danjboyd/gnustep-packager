x11: list WM_DELETE_WINDOW on closable windows the gui decorates

With `GSBackHandlesWindowDecorations` (or `GSX11HandlesWindowDecorations`) NO, `-window::::` creates the X window with only `NSIconWindowMask` and `NSMiniWindowMask` kept from its style, and `-_setSupportedWMProtocols:` took the closable bit from that stripped style. So no window the gui decorates lists `WM_DELETE_WINDOW`. A window manager asked to close one (Alt+F4, its window menu, a task bar) then has no way to ask the client. Mutter falls back to killing it (`XKillClient`): the whole application quits at once, with nothing saved or asked.

`-_setSupportedWMProtocols:` now takes the closable bit from the NSWindow's own style mask when the gui draws the decorations. The method runs again each time a window is ordered in, when the NSWindow exists, and sets `WM_PROTOCOLS` before the window is mapped. The window manager's request then arrives as `WM_DELETE_WINDOW`, becomes `GSAppKitWindowClose` and goes through `-performClose:`, as a click on the gui's close button does. Nothing changes for windows the window manager decorates.

**Relation to #244.** Window managers only offer close for a window whose Motif hints allow it. On master a window the gui decorates allows no functions, so today Mutter doesn't close it at all and Alt+F4 does nothing. #244 keeps the style's functions, close included. On its own, that turns "Alt+F4 does nothing" into "Alt+F4 kills the application". So this change should be merged before #244, or together with it. The two touch different functions and apply in either order (only the ChangeLog's top entry needs a hand merge).

Alt+F4 under GNOME Shell 48.7 (X11), with a small program showing a closable window and a panel and the gui drawing the decorations:

```
master                   nothing happens (Mutter doesn't offer close)
master + this change     nothing happens
#244                     the client is killed ("X connection broken")
#244 + this change       the panel, then the window, close through -performClose:; the program keeps running
```

`Tests/x11/wmdeletewindow.m` is new. It sets `GSBackHandlesWindowDecorations` NO for the test process only, orders in windows of four styles and reads back their `WM_PROTOCOLS`:
- A fully styled window and a closable, non-resizable one must list `WM_DELETE_WINDOW`.
- A titled window that isn't closable, and a borderless one, must not. That guards against the change spreading to windows that can't be closed.

It reads only the property the backend sets, so it needs a display but no window manager. Without the change, the two closable checks fail (3 of 5 pass); with it, all 5 pass. The whole suite: 291 passed, 0 failed, against 286 on master. The changed file and the test also pass a syntax check with GCC's Objective-C front end.

Not covered by the test: a window that becomes closable through `-setStyleMask:` while it's on screen gets the protocol the next time it's ordered in.

AI assistance: this change, its test and this description were written with Claude (Anthropic's Claude Code).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
