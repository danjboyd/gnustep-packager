**Repository:** gnustep/libs-gui

**Status:** fixed on master by a84b42471 (Riccardo Mottola, 2026-05-05), not
in a release yet. Nothing to report; kept as the record of why the theme
works around it.

**Title:** A click on a menu title closes the menu on the release

### Summary

In gui 0.32.0, clicking a menu bar title (press and release, no drag) opens
its menu and the release closes it again. The same happens to the theme's
primary menu (☰). `-[NSMenuView _trackWithEvent:startingMenuView:]` sets
`shouldFinish = NO` for horizontal menus, transient menus in
`NSWindows95InterfaceStyle` and pop-ups, to ignore the first mouse up, but
commit 82717eefe (2024-11-18, "fix issue with nsmenu items (#315)") added a
`break` on any mouse up read at the end of the loop, which skips that.

### Steps to reproduce

`menu_click_closes.m`, run on a spare display (it moves the pointer) with
`-NSMenuInterfaceStyle NSWindows95InterfaceStyle -GSTheme GNUstep`. It clicks
"File" in the window's menu bar and checks for the File menu 0.3s later.

Checked on 2026-09-25 under Xvfb with the default theme:

```
gui 0.32.0 (installed): after a click on "File": menu closed on the release (tracking had ended before 0.3s)
gui master ff49ac8:     after a click on "File": menu still open 0.3s later
```

### Theme workaround

The ☰ opens its menu on the click's release and starts tracking from a
fresh press (`-[GnomeThemePrimaryMenuButton showPrimaryMenu]`). Escape posts
two releases: 0.32 stops at the first; master ignores a first release when
the pointer hasn't been over the menu. Both pass the probe's
`primary-menu-opens` and `primary-menu-escape` checks. On master a click
outside the menu, with the pointer never over it, is ignored once, as for
GNUstep's other transient menus.

The menu bar's titles (File, Edit, and the ☰ the application menu becomes)
have the same workaround since 2026-10-01 (plugins-themes-Adwaita#5):
`-[NSMenuView mouseDown:]` holds the press, with the title highlighted,
until the release or a drag past 8px. A drag is GNUstep's own press, drag
and release; a click starts tracking from a fresh press when it's released,
with the same Escape timer. Items without a submenu act on the release, as
before. The probe's `menubar-click-opens`, `menubar-click-opens-app-menu`,
`menubar-click-escape` and `menubar-click-picks` checks cover it (they move
the pointer, so they run only on the probe's own Xvfb).

On master (ff49ac8, in the `libs-gui-csd` build) on 2026-10-01, the probe
opened menus, and picked items, with the workaround. Escape worked only
with it. After a click on a title, moving the pointer into the window and
clicking there left the menu showing, with or without the workaround:
tracking ends with the title still highlighted and keeps its menu
attached. Check this by hand before the next release; it may be master's
behaviour or an artefact of the probe's synthetic clicks.
