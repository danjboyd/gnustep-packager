# Window tabs (#63)

Taken 2026-10-08, Cantarell 11. Each image is libadwaita 1.7's AdwTabBar on
the left (`Reference/AdwaitaTabBar/adwaita_tab_bar.py --width 652`, a
private Xvfb with no window manager) and the gnustep-window-tabbing
example, TabDemo, under the theme on the right (a private GNOME Shell
session; TabDemo has an in-window menu bar, so its tab bar sits below it).

- `light-reference-theme.png`, `dark-reference-theme.png`: three tabs, the
  first selected. The bar is 40pt in the window's colour (#fafafb,
  #222226); tabs are 34pt, 6pt in from the ends and 5pt apart, sharing the
  width; the selected tab is the foreground at 10% (#e6e6e7, #39393c) with
  a 6pt radius and its close button; 1px separators at 15% sit between
  unselected tabs; the "+" button ends the bar.

Hover (7%, close button shown, neighbouring separators hidden) and high
contrast (a 1px outline at 50%, separators at 50%) are checked by
QuirkProbe's `window-tabs-*` checks rather than shown here.

## Phase 2: drag and scroll (#65)

Taken 2026-10-14 on private Xvfb displays with no window manager, Cantarell
11, gnustep-window-tabbing a052823.

- `light-overflow-reference-theme.png`, `dark-overflow-reference-theme.png`:
  eight tabs in a 652pt window, AdwTabBar on the left
  (`adwaita_tab_bar.py --width 652 --tabs 8 --select 4`), the theme on the
  right (eight tabbed windows, the fourth selected). Where tabs run out of
  sight the bar's colour covers them: opaque for 6pt at the edge of the
  tabs' area, then fading out over 36pt (42pt in all; GNUstep's default is
  24pt). On the right, the shared code has scrolled the selected tab partly
  under the left fade; AdwTabBar scrolls a selected tab clear of it.
- `light-dragged-tab-theme.png`: QuirkProbe's `window-tabs-drag` window, the
  second tab dragged 40pt right over the third. A dragged tab is AdwTabBar's
  `tab:selected:active`, the foreground at 19% (#d4d4d6 on #fafafb), opaque,
  with its close button, and no shadow in the bar.
