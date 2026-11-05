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

#import <Foundation/Foundation.h>

@class GnomeThemeSettings;

@interface GnomeThemeMetrics : NSObject
{
  CGFloat _menuBarHeight;
  CGFloat _menuItemHeight;
  CGFloat _menuSeparatorHeight;
  CGFloat _scrollerWidth;
  CGFloat _horizontalMenuTitlePadding;
  CGFloat _minimumTabHeight;
  CGFloat _maximumTabHeight;
  CGFloat _textFieldHeight;
  CGFloat _buttonHorizontalPadding;
  CGFloat _buttonVerticalPadding;
  CGFloat _tableRowHeight;
  CGFloat _indicatorMinimumSize;
  BOOL _emphasizesButtonTitles;
  BOOL _compact;
}

/* The app's metrics: GNOME's, or compact ones. */
- (void) reloadFromSettings: (GnomeThemeSettings *)settings;
/* Compact metrics whatever the app uses, for windows loaded from nib or
   Gorm files in an app with GNOME's (#24), or GNOME's. */
- (void) reloadFromSettings: (GnomeThemeSettings *)settings compact: (BOOL)compact;

- (CGFloat) menuBarHeight;
- (CGFloat) menuItemHeight;
- (CGFloat) menuSeparatorHeight;
- (CGFloat) scrollerWidth;
- (CGFloat) horizontalMenuTitlePadding;
- (CGFloat) minimumTabHeight;
- (CGFloat) maximumTabHeight;
- (CGFloat) textFieldHeight;
- (CGFloat) buttonHorizontalPadding;
- (CGFloat) buttonVerticalPadding;
- (CGFloat) tableRowHeight;
/* The smallest checkbox or radio indicator. */
- (CGFloat) indicatorMinimumSize;
/* Whether push button titles are bold, as libadwaita's are. */
- (BOOL) emphasizesButtonTitles;
- (BOOL) compact;

@end
