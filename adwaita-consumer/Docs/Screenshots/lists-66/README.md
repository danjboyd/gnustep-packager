# Combo box lists and source lists as libadwaita's lists (#66)

These shots were taken on 2026-10-08 on a private Xvfb, with GNOME Shell 48.7 (X11) as the window manager. The setup was the same as the README's shots: `Tests/Scripts/readme-shots/`, Cantarell 11 and empty GNUstep user defaults. The installed libs-gui and libs-back were used; that libs-back draws popover shadows.

In `light-gtk-theme.png` and `dark-gtk-theme.png`, GTK 4.18 and libadwaita 1.7 are on the left and the theme is on the right.

**GTK (left).** This is `Reference/DropDownList/dropdown_list.py --open [--dark]`:

- a GtkDropDown with its list open, the third item chosen;
- a GtkListView with the `navigation-sidebar` style class.

**The theme (right).** This is QuirkProbe `-ProbeOnly lists-demo`:

- an NSPopUpButton, closed;
- an NSComboBox (not editable) with its list open;
- a table whose `selectionHighlightStyle` is `NSTableViewSelectionHighlightStyleSourceList`. Its first row is a group row (`-tableView:isGroupRow:`), and it draws its text itself.

## Measured

These are from GTK's widget allocations at Cantarell 11, as `dropdown_list.py --metrics` prints them, and from libadwaita's stylesheet.

**The drop-down's list.**

- The list sits 6pt from the popover's top and bottom.
- Rows are 37pt: 9pt above and below a 19pt line. There is no gap between rows.
- The text is 18pt in from the popover's side: a 6pt pill inset plus 12pt of padding.
- The checkmark is 16pt wide and sits 6pt after the chosen row's text.
- The popover is as wide as its longest item plus 58pt (162pt for 104pt of text), at least 120pt, and at least as wide as its button.
- It sits 2pt below the button, with 15pt corners.
- The pill under the pointer is the text colour at 10%. The chosen row has no fill.

The theme matches all of these. Its row height is the font's line plus 18pt.

**The sidebar list.**

- Rows are 36pt high with 2pt below each. The pills are inset 6pt from the sides, with 9pt corners.
- The selected pill is the text colour at 10%, the hovered one at 7%, and a selected row under the pointer at 13%.
- The list has no background.

The theme matches these, given the app's 38pt rows. The selected pill is within 2 levels of GTK's: #e4e4e5 against #e6e6e7 in light, and #37373a against #39393c in dark.

## Known differences

- **The dark popover's colour.** In dark style the popover is the theme's menu colour, #303030, where libadwaita's popovers are #36363a. The theme's menus share this colour; changing it is palette work, not this issue's.
- **The popover's outline.** The outline is the theme's menu border colour, a little darker than GTK's.
- **The open button's look.** While its list is open, GTK draws the drop-down's button pressed. The theme's combo box shows its focus ring instead.
