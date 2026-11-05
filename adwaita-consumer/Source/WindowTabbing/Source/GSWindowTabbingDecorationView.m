/** <title>GSWindowTabbingDecorationView</title>

   <abstract>Where a window's decoration puts the tab bar.</abstract>

   Copyright (C) 2026 Daniel Boyd

   Author: Daniel Boyd <danieljboyd@icloud.com>
   Date: 2026

   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the
   Free Software Foundation, 51 Franklin Street, Fifth Floor,
   Boston, MA 02110-1301, USA.
*/

/* GSWindowDecorationView's tabbing method.  Upstream it goes into
   GSWindowDecorationView.m, and the decoration view's -layout calls it at
   its end, as it lays out an in-window menu bar and a toolbar now;
   -contentRectForFrameRect:styleMask: and
   -frameRectForContentRect:styleMask: subtract and add the window's
   -_tabBarReservedHeight.  Here it is written in a subclass that is
   never instantiated, and GSWindowTabbingInstall() copies it into
   GSWindowDecorationView (so self is always a GSWindowDecorationView;
   it may not use super). */

#import "GSWindowTabbingPrivate.h"
#import "GSWindowTabBarView.h"

#ifndef GS_HAS_WINDOW_TABBING

@interface GSWindowTabbingDecorationView : GSWindowDecorationView
@end

@implementation GSWindowTabbingDecorationView

/* After the title bar, menu bar and toolbar are laid out, the tab bar
   takes the top of what is left, and the content view the rest. */
- (void) _layoutTabBar
{
  NSWindow *tabWindow = [self window];
  CGFloat height = [tabWindow _tabBarReservedHeight];
  NSView *bar = [tabWindow _tabBarView];
  NSView *content = [tabWindow contentView];
  NSRect frame;

  if (height <= 0.0 || bar == nil || [content superview] != self)
    {
      return;
    }
  frame = [content frame];
  [bar setFrame: NSMakeRect(NSMinX(frame), NSMaxY(frame) - height,
                            NSWidth(frame), height)];
  frame.size.height -= height;
  [content setFrame: frame];
}

@end

#endif /* GS_HAS_WINDOW_TABBING */
