/*
   Copyright (C) 2025-2026 Daniel Boyd

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

#import "GnomeThemeMetrics.h"
#import "GnomeThemeSettings.h"

#import <Foundation/Foundation.h>

@implementation GnomeThemeMetrics

- (void) reloadFromSettings: (GnomeThemeSettings *)settings
{
  [self reloadFromSettings: settings compact: [settings compactMetrics]];
}

- (void) reloadFromSettings: (GnomeThemeSettings *)settings compact: (BOOL)compact
{
  CGFloat base = compact ? [settings compactInterfaceFontSize] : [settings interfaceFontSize];

  if (base <= 0.0)
    {
      base = 11.0;
    }

  _menuItemHeight = ceil (MAX (32.0, base + 19.0));
  _menuBarHeight = ceil (MAX (_menuItemHeight + 2.0, base + 21.0));
  _menuSeparatorHeight = ceil (MAX (10.0, floor (base * 0.95)));
  _scrollerWidth = [settings prefersDarkAppearance] ? 12.0 : 13.0;
  _horizontalMenuTitlePadding = ceil (MAX (8.0, floor (base * 0.75)));
  /* GtkNotebook's header: 36px of tabs between the frame and the line under
     them. */
  _minimumTabHeight = ceil (MAX (38.0, base + 23.0));
  _maximumTabHeight = ceil (_minimumTabHeight + 10.0);
  _textFieldHeight = ceil (MAX (34.0, base + 20.0));
  _buttonHorizontalPadding = ceil (MAX (14.0, floor (base * 1.2)));
  _buttonVerticalPadding = ceil (MAX (6.0, floor (base * 0.55)));
  /* GTK list rows: a line of text (about base + 3) with 8px above and below. */
  _tableRowHeight = ceil (MAX (34.0, base + 19.0));
  _indicatorMinimumSize = 18.0;
  _emphasizesButtonTitles = YES;
  _compact = compact;

  /* Compact metrics fit layouts made at GNUstep's: no minimum tab height
     (GSTheme's own), GNUstep's button margins, regular-weight button titles
     and smaller indicators. */
  if (_compact)
    {
      _minimumTabHeight = 0.0;
      _maximumTabHeight = 0.0;
      _buttonHorizontalPadding = 0.0;
      _buttonVerticalPadding = 0.0;
      _tableRowHeight = ceil (base + 12.0);
      _indicatorMinimumSize = 14.0;
      _emphasizesButtonTitles = NO;
    }
}

- (CGFloat) menuBarHeight
{
  return _menuBarHeight;
}

- (CGFloat) menuItemHeight
{
  return _menuItemHeight;
}

- (CGFloat) menuSeparatorHeight
{
  return _menuSeparatorHeight;
}

- (CGFloat) scrollerWidth
{
  return _scrollerWidth;
}

- (CGFloat) horizontalMenuTitlePadding
{
  return _horizontalMenuTitlePadding;
}

- (CGFloat) minimumTabHeight
{
  return _minimumTabHeight;
}

- (CGFloat) maximumTabHeight
{
  return _maximumTabHeight;
}

- (CGFloat) textFieldHeight
{
  return _textFieldHeight;
}

- (CGFloat) buttonHorizontalPadding
{
  return _buttonHorizontalPadding;
}

- (CGFloat) buttonVerticalPadding
{
  return _buttonVerticalPadding;
}

- (CGFloat) tableRowHeight
{
  return _tableRowHeight;
}

- (CGFloat) indicatorMinimumSize
{
  return _indicatorMinimumSize;
}

- (BOOL) emphasizesButtonTitles
{
  return _emphasizesButtonTitles;
}

- (BOOL) compact
{
  return _compact;
}

@end
