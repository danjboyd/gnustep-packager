# Tables on libadwaita's view colour (#62)

Taken 2026-10-08 on a private Xvfb (no window manager), Cantarell 11.

- `libadwaita-light.png`, `libadwaita-dark.png`: what libadwaita 1.7 draws
  (`Reference/TableCard/table_card.py`): a plain GtkColumnView (1), with
  the scrolled window's frame (2), with `data-table` (3), an outline (4),
  `boxed-list` (5) and a GtkTreeView (6). A plain list draws its view colour
  (#ffffff light, #1d1d20 dark, the same in high contrast) over the window
  (#fafafb, #222226), with no border, no rounded corners and no row
  separators; only `boxed-list`, GNOME's list of setting rows, is a card.
- `dark-before-after.png`, `light-before-after.png`: ThemeDemo's Data Views
  page under the theme, before (left) and after (right). Dark tables drew on
  #303030 (the table's controlBackgroundColor: the palette's table colours
  were never found) and now on #1d1d20. Light was already #ffffff; its
  alternating rows now show (#f6f6f6), as the demo asks for them.
