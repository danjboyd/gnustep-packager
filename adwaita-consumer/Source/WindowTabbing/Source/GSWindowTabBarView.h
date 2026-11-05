/* GSWindowTabBarView.h: the tab bar of a group of tabbed windows.

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

#ifndef _GNUstep_H_GSWindowTabBarView
#define _GNUstep_H_GSWindowTabBarView

#import <AppKit/AppKit.h>
#import "GSWindowTabbing.h"

/* Each window of a group has one; the selected window's is on screen.
   It lays the tabs out and handles the mouse; GSTheme draws. */
@interface GSWindowTabBarView : NSView
{
  NSWindow *_tabWindow;
  NSInteger _hoveredTab;
  NSInteger _pressedTab;
  BOOL _closeHovered;
  BOOL _closePressed;
  BOOL _newTabHovered;
  BOOL _newTabPressed;
  NSTrackingRectTag _trackingTag;
  BOOL _tracking;
  BOOL _windowAcceptedMouseMoved;
  /* How far the tabs are scrolled, when they don't fit. */
  CGFloat _scrollOffset;
  /* A tab being dragged: its index, its left edge, the slot it would
     drop into, and whether it has been pulled out of the bar. */
  BOOL _dragging;
  NSUInteger _dragIndex;
  CGFloat _dragX;
  NSUInteger _dragSlot;
  BOOL _dragDetached;
  /* Where the pointer last was during a drag, for the autoscroll ticks. */
  NSPoint _dragPoint;
  /* A gap opened at this slot for a tab dragged from another window, or
     -1. */
  NSInteger _dropGapSlot;
}
- (id) initWithWindow: (NSWindow *)window;
/* The tabs, a title or the selection changed. */
- (void) tabsDidChange;
/* The layout, in the view's coordinates: */
- (NSUInteger) numberOfTabs;
/* The theme's margin at each end and spacing between tabs. */
- (CGFloat) margin;
- (CGFloat) spacing;
- (CGFloat) tabWidth;
/* The part of the bar the tabs take: the bar less its margins and the
   "+" button.  Tabs that don't fit scroll inside it. */
- (NSRect) tabsRect;
/* The scroll offset, from 0 to -maximumScrollOffset (0 when the tabs
   fit). */
- (CGFloat) scrollOffset;
- (CGFloat) maximumScrollOffset;
- (void) setScrollOffset: (CGFloat)offset;
/* Where the tab at index is drawn (scrolled, and moved aside by a
   dragged tab); a pulled-out tab has an empty rect. */
- (NSRect) rectForTabAtIndex: (NSUInteger)index;
/* Whether a tab is being dragged, and which. */
- (BOOL) isDraggingTab;
- (NSUInteger) draggedTabIndex;
/* A gap at slot, where a tab dragged from another window would drop
   (-1 for none); the tabs from slot on move one slot along. */
- (NSInteger) dropGapSlot;
- (void) setDropGapSlot: (NSInteger)slot;
- (NSRect) closeButtonRectForTabAtIndex: (NSUInteger)index;
/* The theme's scroll fade at edge (NSMinXEdge or NSMaxXEdge), or
   NSZeroRect when no tabs are out of sight that way. */
- (NSRect) scrollFadeRectAtEdge: (NSRectEdge)edge;
/* The close button where it can be clicked: NSZeroRect under a fade. */
- (NSRect) liveCloseButtonRectForTabAtIndex: (NSUInteger)index;
/* NSZeroRect when nothing responds to -newWindowForTab:. */
- (NSRect) newTabButtonRect;
/* The tab at point, or -1. */
- (NSInteger) tabIndexAtPoint: (NSPoint)point;
/* The state the theme draws the tab at index in. */
- (GSWindowTabState) stateForTabAtIndex: (NSUInteger)index;
@end

/* The width of each of count tabs sharing width equally, between minimum
   and maximum (0 for no maximum).  GSWindowTabBarLayout.m, so tests can
   use it without a view. */
CGFloat GSWindowTabWidth(NSUInteger count, CGFloat width,
                         CGFloat minimum, CGFloat maximum);

/* The slot a tab is shown in while the tab at dragged is dragged to slot
   (detached: pulled out of the bar, leaving no gap).  The dragged tab
   itself gets slot.  GSWindowTabBarLayout.m. */
NSUInteger GSWindowTabSlot(NSUInteger index, NSUInteger dragged,
                           NSUInteger slot, BOOL detached);

/* The slot nearest left (a tab's left edge, measured from the first
   slot's) for tabs width wide with spacing between them, among count. */
NSUInteger GSWindowTabSlotAtOffset(CGFloat left, CGFloat width,
                                   CGFloat spacing, NSUInteger count);

/* The scroll offset, from 0 to the most the tabs can scroll, that shows
   the whole of [left, left + width] in a visible area visible wide;
   offset when it already does.  All measured from the first slot. */
CGFloat GSWindowTabScrollToShow(CGFloat offset, CGFloat left, CGFloat width,
                                CGFloat visible, CGFloat maximum);

#endif /* _GNUstep_H_GSWindowTabBarView */
