# Pop-up buttons, menus and placeholders (#67)

Taken 2026-10-08 on a private Xvfb (no window manager), Cantarell 11, from
the QuirkProbe windows of the checks `popup-menu-no-arrow-image`,
`popup-title-truncation` and `search-placeholder-focused`
(`Tests/Scripts/run-quirk-probe.sh --output DIR`; `QUIRK_PROBE_STYLE=dark`
for the dark one). Before (left) is the theme on `main` at 6764b51, after
(right) this change.

- The pop-up's menu, after "Heading 1", "Heading 2", "Paragraph" and
  "Heading 1" were selected in code, each drawn, with "Heading 1" hovered.
  Before, "Heading 1" carried GNUstep's nibble image into the open menu
  (in ObjcMarkdown, items selected earlier kept it too), and the
  hovered row was the pale inactive selection (#cde1f9 light, #233651 dark)
  with white text. After, no item has an image, and the hovered row is
  libadwaita's popover menu row: the foreground at 10% over the menu
  (`popover.menu modelbutton:hover` in libadwaita 1.7's stylesheet), #ebebeb
  on #ffffff in light, with the normal text colour.
- A 120pt pop-up titled "DejaVu Math TeX Gyre": before, the title ran under
  the chevron (and wrapped word by word out of sight); after, it stops at
  the chevron's box with an ellipsis, as GtkDropDown's label.
- A search field and a text field with placeholders, the text field
  focused and empty: before, no placeholder while editing; after, the
  placeholder shows with the caret at its start, as GTK's entries, in the
  colour it has unfocused.

The dark menu is on the theme's menu colour (#303030); libadwaita's
popover is #36363a, so its hovered row is #4a4a4e against the theme's
#444444. That difference is the menu's background, not this change.
