/*
   Copyright (C) 2026 Daniel Boyd

   This file is part of the GNUstep Adwaita theme.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef GnomeThemeLists_h
#define GnomeThemeLists_h

#import <AppKit/AppKit.h>

@class GnomeTheme;

/* Tables drawn as libadwaita's lists (GnomeThemeLists.m, #66): a combo
   box's list as GtkDropDown's, and a source-list table as a
   navigation-sidebar list. Other tables are None. */
typedef enum
{
  GnomeThemeListStyleNone = 0,
  GnomeThemeListStyleDropDown,
  GnomeThemeListStyleSidebar
} GnomeThemeListStyle;

GnomeThemeListStyle GnomeThemeTableListStyle(NSTableView *tableView);

/* The rows' rounded pills (hover, and selection in a sidebar) in
   `clipRect`, in place of the table's background and selection. */
void GnomeThemeDrawListPills(GnomeTheme *theme, NSTableView *tableView, NSRect clipRect);

/* A drop-down list's checkmark on `row` (the combo box's value), after the
   row's text. */
void GnomeThemeDrawDropDownCheckmark(GnomeTheme *theme, NSTableView *tableView, NSInteger row);

/* GtkDropDown's row height for `font` (9pt above and below the text), and
   how many rows show before the list scrolls (GTK's 400pt list). */
CGFloat GnomeThemeDropDownRowHeight(NSFont *font);
NSInteger GnomeThemeDropDownVisibleRows(CGFloat rowHeight, NSInteger count);

/* Makes a combo box's list window (GSComboWindow) a popover: rounded,
   with the list 6pt from its top and bottom and the rows' pills. */
void GnomeThemeInstallDropDownPopover(NSWindow *window);

/* Forgets the row under the pointer (a combo box's list opening again). */
void GnomeThemeListClearHover(void);

#endif
