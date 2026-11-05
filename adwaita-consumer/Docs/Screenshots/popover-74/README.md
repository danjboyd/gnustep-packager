# An app's popovers as libadwaita's popover (#74)

These shots were taken on 2026-10-09 on a private Xvfb, with GNOME Shell 48.7 (X11) as the window manager. The setup was the README's shots' (`Tests/Scripts/readme-shots/`): Cantarell 11 and empty GNUstep user defaults. The backend was libs-back-csd with the popover body inset (`-setPopoverBodyInsetLeft:right:top:bottom::`), and the libs-gui was the installed one.

In `light-gtk-theme.png`, GTK 4.18 and libadwaita 1.7 are on the left and the theme is on the right. `arrow-gtk-theme.png` shows both popovers at twice the size.

**GTK (left).** This is `Reference/Popover/popover.py`: a GtkMenuButton whose GtkPopover is open below it, with its arrow, and a closed GtkDropDown.

**The theme (right).** This is QuirkProbe `-ProbeOnly popover-demo`:

- a borderless, clear panel that conforms to `GSThemePopoverPanel`, as ScreenshotTool's popovers do, with its arrow on the top edge (12pt high, a 24pt base) pointing at the "Pen" button;
- the same kind of panel with no arrow under "Cantarell", as a drop-down's list is.

## Measured

- **Arrow slope:** both arrows rise 1px for each 1px they narrow on each side (45°).
- **Shadow:** in both, it follows the body. Neither puts a shadow round the arrow, so there is no edge in the strip that holds it.
- **Corners and border:** the body's are as GTK's: 15px corners, and the menu's border colour along the arrow's sides.

## Known differences

- **Arrow size:** with the 12pt height and 24pt base, the theme's arrow is about 1px taller and 3px wider at its base than GTK's (GTK's inside is 18px wide where it meets the body, the theme's 21px).
- **Without a compositing manager** clear pixels show black, so the theme draws a plain square panel over the whole window, with no arrow, as its menus are then.
- **Shadow round the body:** this needs libs-back-csd's body inset. Another libs-back draws the popover shadow round the whole window, arrow strip included.
