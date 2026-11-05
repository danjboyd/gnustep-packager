/** <title>GSWindowTabBarView</title>

   <abstract>The tab bar of a group of tabbed windows.</abstract>

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

/* Upstream this is a private libs-gui class as it is (Source/
   GSWindowTabBarView.m). */

#include <math.h>

#import "GSWindowTabBarView.h"
#import "GSWindowTabbingPrivate.h"

#ifndef GS_HAS_WINDOW_TABBING

/* How far the pointer moves before a press on a tab becomes a drag: GTK's
   default gtk-dnd-drag-threshold, which AdwTabBar uses. */
static const CGFloat GSWindowTabDragThreshold = 8.0;

/* How far above or below the bar the pointer goes before a dragged tab
   is pulled out of it, to become a window of its own or a tab of another
   window: four times the drag threshold, as AdwTabBar does (measured: 32
   pixels beyond the bar's edge). */
static const CGFloat GSWindowTabDetachDistance = 4.0 * 8.0;

/* How far one step of a scroll wheel moves the tabs: GTK's scrolled
   window step, the visible width to the power 2/3 (67 pixels for 549). */
static CGFloat
GSWindowTabScrollStep(CGFloat visible)
{
  return (visible > 0.0) ? pow(visible, 2.0 / 3.0) : 0.0;
}

/* While a dragged tab is held past an end of a bar whose tabs scroll,
   the bar scrolls every GSWindowTabAutoscrollPeriod seconds by how far
   past it is, at most GSWindowTabAutoscrollStep, as AdwTabBox scrolls
   under a tab held at its edge. */
static const NSTimeInterval GSWindowTabAutoscrollPeriod = 0.05;
static const CGFloat GSWindowTabAutoscrollStep = 24.0;

/* How tall a window's top strip is that takes a dropped tab when the
   window shows no tab bar (its title or header bar). */
static const CGFloat GSWindowTabDropStripHeight = 48.0;

/* The point on the screen an event happened at. */
static NSPoint
GSWindowTabScreenPoint(NSEvent *event)
{
  NSWindow *window = [event window];
  NSPoint point = [event locationInWindow];

  return (window != nil) ? [window convertBaseToScreen: point] : point;
}

/* Used before they are defined. */
/* The events that tell a press tracked by the bar it has ended without
   its release reaching the app: the window system took the pointer away
   (on Windows, lost capture; on X11, another client's grab) and the
   button went up elsewhere.  Then the pointer moves with no button down,
   or a new press starts.  Such an event ends the tracking as a cancel,
   and is put back for the app to handle. */
static const NSUInteger GSWindowTabLostPressMask = NSMouseMovedMask
  | NSLeftMouseDownMask | NSRightMouseDownMask | NSOtherMouseDownMask;

static BOOL
GSWindowTabPressWasLost(NSEvent *event)
{
  switch ([event type])
    {
      /* libs-back's Windows server reports a lost release as a left
         mouse-up it makes up, ahead of the move it saw it in (which it
         may then drop as no move): no release happened here, so it ends
         the press as a cancel and isn't put back. */
      case NSLeftMouseUp:
        return (GSWindowTabbingReleaseWasReal(event) == NO);
      case NSMouseMoved:
      case NSLeftMouseDown:
      case NSRightMouseDown:
      case NSOtherMouseDown:
        [NSApp postEvent: event atStart: YES];
        return YES;
      default:
        return NO;
    }
}

@interface GSWindowTabBarView (Private)
- (void) updateToolTips;
- (void) observeKeyAndMainOfWindow: (NSWindow *)window;
@end

@implementation GSWindowTabBarView

- (id) initWithWindow: (NSWindow *)window
{
  if ((self = [super initWithFrame: NSMakeRect(0.0, 0.0, 100.0, 30.0)]) != nil)
    {
      _tabWindow = window;
      _hoveredTab = -1;
      _pressedTab = -1;
      _dropGapSlot = -1;
      [self setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
      [self observeKeyAndMainOfWindow: window];
    }
  return self;
}

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [super dealloc];
}

/* The bar draws the window's key state, and whether there is a "+"
   button can change with it (the responder chain that answers
   -newWindowForTab:), so it is laid out and drawn again whenever the
   window becomes or stops being key or main.  A tab selected while its
   window wasn't key yet was otherwise drawn as it was then: no "+", and
   tabs as wide as before, where clicks found other widths. */
- (void) observeKeyAndMainOfWindow: (NSWindow *)window
{
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

  [center addObserver: self selector: @selector(windowKeyOrMainDidChange:)
                 name: NSWindowDidBecomeKeyNotification object: window];
  [center addObserver: self selector: @selector(windowKeyOrMainDidChange:)
                 name: NSWindowDidResignKeyNotification object: window];
  [center addObserver: self selector: @selector(windowKeyOrMainDidChange:)
                 name: NSWindowDidBecomeMainNotification object: window];
  [center addObserver: self selector: @selector(windowKeyOrMainDidChange:)
                 name: NSWindowDidResignMainNotification object: window];
}

- (void) windowKeyOrMainDidChange: (NSNotification *)notification
{
  [self tabsDidChange];
}

- (BOOL) isFlipped
{
  return NO;
}

- (NSArray *) tabWindows
{
  return [[_tabWindow tabGroup] windows];
}

- (NSUInteger) numberOfTabs
{
  return [[self tabWindows] count];
}


/* Layout. */

- (NSRect) newTabButtonRect
{
  CGFloat width;

  if ([_tabWindow _tabbingCanCreateNewTab] == NO)
    {
      return NSZeroRect;
    }
  width = [[GSTheme theme] windowTabNewTabButtonWidthForWindow: _tabWindow];
  if (width <= 0.0)
    {
      return NSZeroRect;
    }
  return NSMakeRect(NSMaxX([self bounds]) - [self margin] - width, 0.0,
                    width, NSHeight([self bounds]));
}

- (CGFloat) margin
{
  return MAX(0.0, [[GSTheme theme] windowTabBarMarginForWindow: _tabWindow]);
}

- (CGFloat) spacing
{
  return MAX(0.0, [[GSTheme theme] windowTabSpacingForWindow: _tabWindow]);
}

- (NSRect) tabsRect
{
  NSRect bounds = [self bounds];
  CGFloat margin = [self margin];
  CGFloat newTab = NSWidth([self newTabButtonRect]);
  CGFloat width = NSWidth(bounds) - 2.0 * margin - newTab;

  if (newTab > 0.0)
    {
      width -= [self spacing];
    }
  return NSMakeRect(margin, 0.0, MAX(0.0, width), NSHeight(bounds));
}

/* The slots laid out: one per tab, and one more for a drop gap. */
- (NSUInteger) numberOfSlots
{
  return [self numberOfTabs] + ((_dropGapSlot >= 0) ? 1 : 0);
}

/* The tabs' area less the spacing between them, shared by the tabs. */
- (CGFloat) tabWidth
{
  GSTheme *theme = [GSTheme theme];
  NSUInteger count = [self numberOfSlots];
  CGFloat available = NSWidth([self tabsRect]);

  if (count > 1)
    {
      available -= [self spacing] * (count - 1);
    }
  return GSWindowTabWidth(count, available,
                           [theme windowTabMinimumWidthForWindow: _tabWindow],
                           [theme windowTabMaximumWidthForWindow: _tabWindow]);
}

/* All the tabs side by side; wider than tabsRect when they don't fit. */
- (CGFloat) contentWidth
{
  NSUInteger count = [self numberOfSlots];

  if (count == 0)
    {
      return 0.0;
    }
  return count * [self tabWidth] + (count - 1) * [self spacing];
}

- (CGFloat) scrollOffset
{
  return _scrollOffset;
}

- (CGFloat) maximumScrollOffset
{
  return MAX(0.0, [self contentWidth] - NSWidth([self tabsRect]));
}

- (void) setScrollOffset: (CGFloat)offset
{
  offset = MAX(0.0, MIN(offset, [self maximumScrollOffset]));
  if (offset != _scrollOffset)
    {
      _scrollOffset = offset;
      [self updateToolTips];
      [self setNeedsDisplay: YES];
    }
}

- (BOOL) isDraggingTab
{
  return _dragging;
}

- (NSUInteger) draggedTabIndex
{
  return _dragIndex;
}

- (NSInteger) dropGapSlot
{
  return _dropGapSlot;
}

/* Opens (or closes, with -1) the gap a tab dragged from another window
   would drop into, as AdwTabBox makes room for it. */
- (void) setDropGapSlot: (NSInteger)slot
{
  NSInteger count = (NSInteger)[self numberOfTabs];

  if (slot > count)
    {
      slot = count;
    }
  if (slot < 0)
    {
      slot = -1;
    }
  if (slot != _dropGapSlot)
    {
      _dropGapSlot = slot;
      [self setScrollOffset: _scrollOffset];
      [self updateToolTips];
      [self setNeedsDisplay: YES];
    }
}

/* The slot the tab at index is shown in: its index, unless a dragged tab
   has moved the others aside. */
- (NSUInteger) slotForTabAtIndex: (NSUInteger)index
{
  if (_dragging == NO)
    {
      if (_dropGapSlot >= 0 && (NSInteger)index >= _dropGapSlot)
        {
          return index + 1;
        }
      return index;
    }
  return GSWindowTabSlot(index, _dragIndex, _dragSlot, _dragDetached);
}

/* The tab shown in slot, or -1. */
- (NSInteger) tabIndexAtSlot: (NSInteger)slot
{
  NSUInteger count = [self numberOfTabs];
  NSUInteger i;

  for (i = 0; i < count; i++)
    {
      if (_dragging && _dragDetached && i == _dragIndex)
        {
          continue;
        }
      if ((NSInteger)[self slotForTabAtIndex: i] == slot)
        {
          return i;
        }
    }
  return -1;
}

/* The last slot in use: one fewer while a tab is pulled out. */
- (NSUInteger) lastSlot
{
  NSUInteger count = [self numberOfTabs];

  if (_dragging && _dragDetached && count > 0)
    {
      count--;
    }
  if (_dragging == NO && count > 0)
    {
      return [self slotForTabAtIndex: count - 1];
    }
  return (count > 0) ? count - 1 : 0;
}

- (NSRect) rectForSlot: (NSUInteger)slot
{
  CGFloat width = [self tabWidth];

  return NSMakeRect(NSMinX([self tabsRect]) - _scrollOffset
                    + slot * (width + [self spacing]),
                    0.0, width, NSHeight([self bounds]));
}

- (NSRect) rectForTabAtIndex: (NSUInteger)index
{
  if (_dragging && index == _dragIndex)
    {
      if (_dragDetached)
        {
          return NSZeroRect;
        }
      return NSMakeRect(_dragX, 0.0, [self tabWidth], NSHeight([self bounds]));
    }
  return [self rectForSlot: [self slotForTabAtIndex: index]];
}

/* The tab at index is selected, under the pointer or pressed. */
- (BOOL) isTabHighlightedAtIndex: (NSUInteger)index
{
  NSWindow *window = [[self tabWindows] objectAtIndex: index];

  return window == [[_tabWindow tabGroup] selectedWindow]
    || (NSInteger)index == _hoveredTab || (NSInteger)index == _pressedTab
    || (_dragging && index == _dragIndex);
}

- (GSWindowTabState) stateForTabAtIndex: (NSUInteger)index
{
  NSArray *windows = [self tabWindows];
  NSWindow *window = [windows objectAtIndex: index];
  NSUInteger slot = [self slotForTabAtIndex: index];
  GSWindowTabState state = 0;
  NSInteger previous;

  if (window == [[_tabWindow tabGroup] selectedWindow])
    {
      state |= GSWindowTabSelected;
    }
  if ((NSInteger)index == _hoveredTab)
    {
      state |= GSWindowTabHovered;
      if (_closeHovered)
        {
          state |= GSWindowTabCloseHovered;
        }
    }
  if ((NSInteger)index == _pressedTab)
    {
      state |= GSWindowTabPressed;
      if (_closePressed)
        {
          state |= GSWindowTabClosePressed;
        }
    }
  if (_dragging && index == _dragIndex)
    {
      state |= GSWindowTabDragged;
    }
  if ([_tabWindow isKeyWindow])
    {
      state |= GSWindowTabWindowKey;
    }
  if ([window isDocumentEdited])
    {
      state |= GSWindowTabEdited;
    }
  if (slot == 0)
    {
      state |= GSWindowTabFirst;
    }
  else
    {
      previous = [self tabIndexAtSlot: slot - 1];
      if (previous >= 0 && [self isTabHighlightedAtIndex: previous])
        {
          state |= GSWindowTabPreviousHighlighted;
        }
    }
  if (slot == [self lastSlot])
    {
      state |= GSWindowTabLast;
    }
  return state;
}

- (NSRect) closeButtonRectForTabAtIndex: (NSUInteger)index
{
  GSTheme *theme = [GSTheme theme];
  NSRect tabRect = [self rectForTabAtIndex: index];
  GSWindowTabState state = [self stateForTabAtIndex: index];

  return [theme windowTabCloseButtonRectForTabRect: tabRect
                                             state: state
                                            window: _tabWindow];
}

/* Only the part of a tab inside tabsRect can be clicked; a dragged tab
   is over the others. */
- (NSInteger) tabIndexAtPoint: (NSPoint)point
{
  NSUInteger count = [self numberOfTabs];
  NSUInteger i;

  if (NSPointInRect(point, [self tabsRect]) == NO)
    {
      return -1;
    }
  if (_dragging && _dragDetached == NO && _dragIndex < count
    && NSPointInRect(point, [self rectForTabAtIndex: _dragIndex]))
    {
      return _dragIndex;
    }
  for (i = 0; i < count; i++)
    {
      if (NSPointInRect(point, [self rectForTabAtIndex: i]))
        {
          return i;
        }
    }
  return -1;
}

/* Scrolls the least that shows the selected tab whole. */
- (void) scrollToSelectedTab
{
  NSUInteger index;
  CGFloat width = [self tabWidth];
  CGFloat left;

  index = [[self tabWindows] indexOfObjectIdenticalTo:
    [[_tabWindow tabGroup] selectedWindow]];
  if (index == NSNotFound || _dragging)
    {
      [self setScrollOffset: _scrollOffset];
      return;
    }
  left = index * (width + [self spacing]);
  [self setScrollOffset:
    GSWindowTabScrollToShow(_scrollOffset, left, width,
                            NSWidth([self tabsRect]),
                            [self maximumScrollOffset])];
}

- (void) updateToolTips
{
  NSArray *windows = [self tabWindows];
  NSRect tabs = [self tabsRect];
  NSUInteger i;

  [self removeAllToolTips];
  for (i = 0; i < [windows count]; i++)
    {
      NSString *toolTip = [[[windows objectAtIndex: i] tab] toolTip];
      NSRect rect = NSIntersectionRect([self rectForTabAtIndex: i], tabs);

      if (toolTip != nil && NSIsEmptyRect(rect) == NO)
        {
          [self addToolTipRect: rect owner: toolTip userData: NULL];
        }
    }
}

- (void) tabsDidChange
{
  if (_hoveredTab >= (NSInteger)[self numberOfTabs])
    {
      _hoveredTab = -1;
    }
  [self scrollToSelectedTab];
  [self updateToolTips];
  [self setNeedsDisplay: YES];
}


/* Drawing. */

- (void) drawTabAtIndex: (NSUInteger)index
{
  GSTheme *theme = [GSTheme theme];
  NSRect tabRect = [self rectForTabAtIndex: index];
  GSWindowTabState state = [self stateForTabAtIndex: index];
  NSRect closeRect;

  [theme drawWindowTab: [[[self tabWindows] objectAtIndex: index] tab]
                inRect: tabRect
                 state: state
                window: _tabWindow];
  closeRect = [theme windowTabCloseButtonRectForTabRect: tabRect
                                                  state: state
                                                 window: _tabWindow];
  if (NSIsEmptyRect(closeRect) == NO)
    {
      [theme drawWindowTabCloseButtonInRect: closeRect
                                      state: state
                                     window: _tabWindow];
    }
}

/* The theme's fade at an end of the tabs' area (NSMinXEdge or
   NSMaxXEdge), or NSZeroRect when no tabs are out of sight that way. */
- (NSRect) scrollFadeRectAtEdge: (NSRectEdge)edge
{
  NSRect tabs = [self tabsRect];
  CGFloat width;

  width = [[GSTheme theme] windowTabBarScrollFadeWidthForWindow: _tabWindow];
  width = MIN(width, NSWidth(tabs) / 2.0);
  if (width <= 0.0)
    {
      return NSZeroRect;
    }
  if (edge == NSMinXEdge && _scrollOffset > 0.0)
    {
      return NSMakeRect(NSMinX(tabs), 0.0, width, NSHeight(tabs));
    }
  if (edge == NSMaxXEdge && _scrollOffset < [self maximumScrollOffset])
    {
      return NSMakeRect(NSMaxX(tabs) - width, 0.0, width, NSHeight(tabs));
    }
  return NSZeroRect;
}

/* The close button of the tab at index, where it can be clicked: not
   under a scroll fade, which hides it.  The tab itself can still be
   clicked there, and scrolls into sight, as GTK's tabs do. */
- (NSRect) liveCloseButtonRectForTabAtIndex: (NSUInteger)index
{
  NSRect button = [self closeButtonRectForTabAtIndex: index];

  if (NSIsEmptyRect(button)
    || NSIntersectsRect(button, [self scrollFadeRectAtEdge: NSMinXEdge])
    || NSIntersectsRect(button, [self scrollFadeRectAtEdge: NSMaxXEdge]))
    {
      return NSZeroRect;
    }
  return button;
}

/* The theme's fade at each end where more tabs are out of sight. */
- (void) drawScrollFades
{
  GSTheme *theme = [GSTheme theme];
  NSRect rect;

  rect = [self scrollFadeRectAtEdge: NSMinXEdge];
  if (NSIsEmptyRect(rect) == NO)
    {
      [theme drawWindowTabBarScrollFadeInRect: rect
                                         edge: NSMinXEdge
                                       window: _tabWindow];
    }
  rect = [self scrollFadeRectAtEdge: NSMaxXEdge];
  if (NSIsEmptyRect(rect) == NO)
    {
      [theme drawWindowTabBarScrollFadeInRect: rect
                                         edge: NSMaxXEdge
                                       window: _tabWindow];
    }
}

- (void) drawNewTabButton
{
  GSWindowTabState state = 0;

  if (_newTabHovered)
    {
      state |= GSWindowTabHovered;
    }
  if (_newTabPressed)
    {
      state |= GSWindowTabPressed;
    }
  if ([_tabWindow isKeyWindow])
    {
      state |= GSWindowTabWindowKey;
    }
  [[GSTheme theme] drawWindowTabNewTabButtonInRect: [self newTabButtonRect]
                                             state: state
                                            window: _tabWindow];
}

/* The tabs are clipped to their area, so scrolled ones don't run under
   the "+" button; a dragged tab is drawn last, over the others and the
   scroll fades. */
- (void) drawRect: (NSRect)rect
{
  NSUInteger count = [self numberOfTabs];
  NSUInteger i;

  [[GSTheme theme] drawWindowTabBarBackgroundInRect: [self bounds]
                                             window: _tabWindow];
  [NSGraphicsContext saveGraphicsState];
  NSRectClip([self tabsRect]);
  for (i = 0; i < count; i++)
    {
      if (_dragging && i == _dragIndex)
        {
          continue;
        }
      if (NSIntersectsRect([self rectForTabAtIndex: i], rect))
        {
          [self drawTabAtIndex: i];
        }
    }
  [self drawScrollFades];
  if (_dragging && _dragDetached == NO && _dragIndex < count)
    {
      [self drawTabAtIndex: _dragIndex];
    }
  [NSGraphicsContext restoreGraphicsState];
  if (NSIsEmptyRect([self newTabButtonRect]) == NO)
    {
      [self drawNewTabButton];
    }
}


/* Hover: mouse-moved events only while the pointer is over the bar. */

- (void) updateTrackingRect
{
  if (_tracking)
    {
      [self removeTrackingRect: _trackingTag];
      _tracking = NO;
    }
  if ([self window] != nil)
    {
      _trackingTag = [self addTrackingRect: [self bounds] owner: self
                                  userData: NULL assumeInside: NO];
      _tracking = YES;
    }
}

- (void) viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  [self updateTrackingRect];
}

- (void) setFrame: (NSRect)frame
{
  [super setFrame: frame];
  [self updateTrackingRect];
  [self scrollToSelectedTab];
  [self updateToolTips];
}

- (void) updateHover: (NSPoint)point
{
  NSInteger tab = [self tabIndexAtPoint: point];
  BOOL closeHovered = (tab >= 0
    && NSPointInRect(point, [self liveCloseButtonRectForTabAtIndex: tab]));
  BOOL newTabHovered = NSPointInRect(point, [self newTabButtonRect]);

  if (tab != _hoveredTab || closeHovered != _closeHovered
    || newTabHovered != _newTabHovered)
    {
      _hoveredTab = tab;
      _closeHovered = closeHovered;
      _newTabHovered = newTabHovered;
      [self setNeedsDisplay: YES];
    }
}

/* GNUstep gives an entered event's location in the view's coordinates,
   Apple's in the window's, so ask the window where the pointer is. */
- (void) mouseEntered: (NSEvent *)event
{
  NSPoint point = [[self window] mouseLocationOutsideOfEventStream];

  _windowAcceptedMouseMoved = [[self window] acceptsMouseMovedEvents];
  [[self window] setAcceptsMouseMovedEvents: YES];
  [self updateHover: [self convertPoint: point fromView: nil]];
}

- (void) mouseMoved: (NSEvent *)event
{
  NSPoint point = [event locationInWindow];

  [self updateHover: [self convertPoint: point fromView: nil]];
}

- (void) mouseExited: (NSEvent *)event
{
  [[self window] setAcceptsMouseMovedEvents: _windowAcceptedMouseMoved];
  [self updateHover: NSMakePoint(-1.0, -1.0)];
}


/* Buttons. */

/* Tracks the button under the mouse until it's released; YES if it's
   released inside rect.  A lost press is no click. */
- (BOOL) trackButtonInRect: (NSRect)rect pressed: (BOOL *)pressed
{
  NSUInteger mask = NSLeftMouseUpMask | NSLeftMouseDraggedMask
    | GSWindowTabLostPressMask;
  NSEvent *event;
  NSPoint point;
  BOOL inside = YES;

  *pressed = YES;
  [self setNeedsDisplay: YES];
  GSWindowTabbingBeginPressWatch();
  while (1)
    {
      event = [NSApp nextEventMatchingMask: mask
                                 untilDate: [NSDate distantFuture]
                                    inMode: NSEventTrackingRunLoopMode
                                   dequeue: YES];
      if (GSWindowTabPressWasLost(event))
        {
          inside = NO;
          break;
        }
      point = [self convertPoint: [event locationInWindow] fromView: nil];
      inside = NSPointInRect(point, rect);
      if (inside != *pressed)
        {
          *pressed = inside;
          [self setNeedsDisplay: YES];
        }
      if ([event type] == NSLeftMouseUp)
        {
          break;
        }
    }
  GSWindowTabbingEndPressWatch();
  *pressed = NO;
  [self setNeedsDisplay: YES];
  return inside;
}

/* The "+" button acts on the release, inside it. */
- (void) pressNewTabButton
{
  if ([self trackButtonInRect: [self newTabButtonRect]
                      pressed: &_newTabPressed])
    {
      [_tabWindow _tabbingCreateNewTab];
    }
}

/* A tab's close button acts on the release, inside it. */
- (void) pressCloseButtonOfTabAtIndex: (NSInteger)tab
{
  NSWindow *window = [[self tabWindows] objectAtIndex: tab];
  NSRect button = [self closeButtonRectForTabAtIndex: tab];
  BOOL released;

  _pressedTab = tab;
  released = [self trackButtonInRect: button pressed: &_closePressed];
  _pressedTab = -1;
  if (released)
    {
      [window performClose: self];
    }
}


/* Dragging a tab: along the bar to reorder it, out of the bar to give it
   a window of its own, or onto another window's bar to make it one of
   that window's tabs, as AdwTabBar does.  A loop tracks the pointer over
   the app's own windows rather than GNUstep's drag and drop: the tab
   only ever moves within the app, the loop sees every event in order (so
   Escape can cancel and tests can drive it), and the window under the
   pointer is found from the app's window list. */

/* The point in this view's coordinates. */
- (NSPoint) pointFromScreen: (NSPoint)screen
{
  return [self convertPoint: [[self window] convertScreenToBase: screen]
                   fromView: nil];
}

/* A dragged tab whose left edge would be at left, past an end of the
   tabs' area: tabs that don't fit scroll that way, by how far past it
   is, up to GSWindowTabAutoscrollStep, so every slot can be reached. */
- (void) autoscrollForDraggedTabAt: (CGFloat)left
{
  NSRect tabs = [self tabsRect];
  CGFloat width = [self tabWidth];
  CGFloat past = 0.0;

  if ([self maximumScrollOffset] <= 0.0)
    {
      return;
    }
  if (left < NSMinX(tabs))
    {
      past = left - NSMinX(tabs);
    }
  else if (left + width > NSMaxX(tabs))
    {
      past = left + width - NSMaxX(tabs);
    }
  past = MAX(-GSWindowTabAutoscrollStep,
             MIN(past, GSWindowTabAutoscrollStep));
  if (past != 0.0)
    {
      [self setScrollOffset: _scrollOffset + past];
    }
}

/* Follows the pointer: the tab's left edge stays the same distance from
   the pointer, within the tabs' area, and the slot it would drop into is
   the nearest one; far enough above or below the bar it is pulled out. */
- (void) dragToPoint: (NSPoint)point grab: (CGFloat)grab
{
  NSRect bounds = [self bounds];
  NSRect tabs = [self tabsRect];
  CGFloat width = [self tabWidth];
  CGFloat left;

  _dragPoint = point;
  _dragDetached = (point.y < NSMinY(bounds) - GSWindowTabDetachDistance
    || point.y > NSMaxY(bounds) + GSWindowTabDetachDistance);
  if (_dragDetached == NO)
    {
      left = point.x - grab;
      [self autoscrollForDraggedTabAt: left];
      left = MAX(NSMinX(tabs), MIN(left, NSMaxX(tabs) - width));
      _dragX = left;
      _dragSlot = GSWindowTabSlotAtOffset(left - NSMinX(tabs) + _scrollOffset,
                                          width, [self spacing],
                                          [self numberOfTabs]);
    }
  [self setNeedsDisplay: YES];
}

/* Where a tab dropped on window would land: its bar if it shows one,
   otherwise the top of the window, where its title or header bar is. */
- (NSRect) dropZoneOfWindow: (NSWindow *)window
{
  GSWindowTabBarView *bar = [window _tabBarView];
  NSRect frame = [window frame];
  NSRect zone;

  if (bar != nil && [bar window] == window)
    {
      zone = [bar convertRect: [bar bounds] toView: nil];
      zone.origin = [window convertBaseToScreen: zone.origin];
      return zone;
    }
  return NSMakeRect(NSMinX(frame), NSMaxY(frame) - GSWindowTabDropStripHeight,
                    NSWidth(frame), GSWindowTabDropStripHeight);
}

/* The window whose tabs the tab would join when dropped at screen: the
   front window under the pointer, if the pointer is over its drop zone
   and the two can be tabbed together; nil otherwise.  The tab's own
   window is one of them: over it, the pointer is over no window the tab
   could join, even if one is behind it. */
- (NSWindow *) windowForDropAtScreenPoint: (NSPoint)screen
{
  NSArray *windows = [NSApp orderedWindows];
  NSWindowTabGroup *group = [_tabWindow tabGroup];
  NSUInteger i;

  for (i = 0; i < [windows count]; i++)
    {
      NSWindow *window = [windows objectAtIndex: i];

      if ([window isVisible] == NO
        || NSPointInRect(screen, [window frame]) == NO)
        {
          continue;
        }
      if (window == _tabWindow || [window _tabbingGroup] == group
        || NSPointInRect(screen, [self dropZoneOfWindow: window]) == NO
        || [_tabWindow _canBeTabbedWith: window] == NO)
        {
          return nil;
        }
      return window;
    }
  return nil;
}

/* The index the tab takes in window's group when dropped at screen:
   the slot under the pointer in its bar, or the end. */
- (NSUInteger) dropIndexInWindow: (NSWindow *)window
                     screenPoint: (NSPoint)screen
{
  GSWindowTabBarView *bar = [window _tabBarView];
  NSUInteger count = [[[window tabGroup] windows] count];
  NSPoint point;
  CGFloat width;

  if (bar == nil || [bar window] != window)
    {
      return count;
    }
  point = [bar pointFromScreen: screen];
  width = [bar tabWidth];
  return GSWindowTabSlotAtOffset(point.x - width / 2.0
                                 - NSMinX([bar tabsRect]) + [bar scrollOffset],
                                 width, [bar spacing], count + 1);
}

- (void) endDrag
{
  _dragging = NO;
  _dragDetached = NO;
  [self scrollToSelectedTab];
  [self updateToolTips];
  [self setNeedsDisplay: YES];
}

/* The drag ends: the tab moves to its slot, to another window's tabs or
   to a window of its own, where the pointer has taken it. */
- (void) dropDraggedTabAtScreenPoint: (NSPoint)screen
                            pressedAt: (NSPoint)press
{
  NSWindow *dragged = [[self tabWindows] objectAtIndex: _dragIndex];
  NSUInteger slot = _dragSlot;
  BOOL detached = _dragDetached;
  NSWindow *target;
  NSPoint origin;

  [self endDrag];
  if (detached == NO)
    {
      if (slot != _dragIndex)
        {
          [[_tabWindow tabGroup] insertWindow: dragged atIndex: slot];
        }
      return;
    }
  target = [self windowForDropAtScreenPoint: screen];
  if (target != nil)
    {
      NSUInteger index = [self dropIndexInWindow: target
                                     screenPoint: screen];

      [[target _tabBarView] setDropGapSlot: -1];
      [[target tabGroup] insertWindow: dragged atIndex: index];
      return;
    }
  /* A window of its own, under the pointer where the press was in this
     one; it appears on the release: GNUstep can't move a window smoothly
     while the pointer drags it. */
  origin = NSMakePoint(screen.x - press.x, screen.y - press.y);
  [dragged _tabbingMoveToNewWindowAt: origin];
}

/* Opens a gap in the bar of the window the pulled-out tab would join at
   screen, where it would drop, and closes the one in bar (the bar that
   had it) if that is another; returns the bar with the gap, or nil. */
- (GSWindowTabBarView *) showDropGapAtScreenPoint: (NSPoint)screen
                                            inBar: (GSWindowTabBarView *)bar
{
  NSWindow *target = nil;
  GSWindowTabBarView *targetBar = nil;

  if (_dragging && _dragDetached)
    {
      target = [self windowForDropAtScreenPoint: screen];
      targetBar = [target _tabBarView];
      if (targetBar != nil && [targetBar window] != target)
        {
          targetBar = nil;
        }
    }
  if (bar != targetBar)
    {
      [bar setDropGapSlot: -1];
    }
  if (targetBar != nil)
    {
      [targetBar setDropGapSlot:
        [self dropIndexInWindow: target screenPoint: screen]];
    }
  return targetBar;
}

/* Tracks a press on the tab at index from point (in this view) until the
   button is released: a drag once it has moved far enough, which Escape
   or a lost press cancels. */
- (void) trackTabAtIndex: (NSUInteger)index fromPoint: (NSPoint)start
{
  NSUInteger mask = NSLeftMouseUpMask | NSLeftMouseDraggedMask
    | NSKeyDownMask | NSPeriodicMask | GSWindowTabLostPressMask;
  CGFloat grab = start.x - NSMinX([self rectForTabAtIndex: index]);
  NSPoint press = [self convertPoint: start toView: nil];
  NSPoint screen = NSZeroPoint;
  BOOL cancelled = NO;
  BOOL periodic = NO;
  GSWindowTabBarView *gapBar = nil;
  NSEvent *event;
  NSPoint point;

  RETAIN(self);
  GSWindowTabbingBeginPressWatch();
  while (1)
    {
      event = [NSApp nextEventMatchingMask: mask
                                 untilDate: [NSDate distantFuture]
                                    inMode: NSEventTrackingRunLoopMode
                                   dequeue: YES];
      if (GSWindowTabPressWasLost(event))
        {
          cancelled = YES;
          break;
        }
      if ([event type] == NSPeriodic)
        {
          if (_dragging && _dragDetached == NO)
            {
              [self dragToPoint: _dragPoint grab: grab];
            }
          continue;
        }
      if ([event type] == NSKeyDown)
        {
          if (_dragging && [[event charactersIgnoringModifiers] isEqual: @"\e"])
            {
              cancelled = YES;
              break;
            }
          continue;
        }
      screen = GSWindowTabScreenPoint(event);
      point = [self pointFromScreen: screen];
      if (_dragging == NO
        && fabs(point.x - start.x) < GSWindowTabDragThreshold
        && fabs(point.y - start.y) < GSWindowTabDragThreshold)
        {
          if ([event type] == NSLeftMouseUp)
            {
              break;
            }
          continue;
        }
      if (_dragging == NO)
        {
          _dragging = YES;
          _dragIndex = index;
          _dragSlot = [self slotForTabAtIndex: index];
          _hoveredTab = -1;
          [NSEvent startPeriodicEventsAfterDelay: GSWindowTabAutoscrollPeriod
                                      withPeriod: GSWindowTabAutoscrollPeriod];
          periodic = YES;
        }
      [self dragToPoint: point grab: grab];
      gapBar = [self showDropGapAtScreenPoint: screen inBar: gapBar];
      if ([event type] == NSLeftMouseUp)
        {
          break;
        }
    }
  GSWindowTabbingEndPressWatch();
  if (periodic)
    {
      [NSEvent stopPeriodicEvents];
    }
  if (_dragging)
    {
      if (cancelled)
        {
          [gapBar setDropGapSlot: -1];
          [self endDrag];
        }
      else
        {
          [self dropDraggedTabAtScreenPoint: screen pressedAt: press];
        }
    }
  RELEASE(self);
}


/* Events. */

/* A press selects its tab at once, as GTK's tabs do, and may start a
   drag; the close and "+" buttons act on the release.  The selected
   tab's window has its own bar, which tracks the drag. */
- (void) mouseDown: (NSEvent *)event
{
  NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
  NSInteger tab = [self tabIndexAtPoint: point];
  GSWindowTabBarView *bar;
  NSWindow *window;

  if (NSPointInRect(point, [self newTabButtonRect]))
    {
      [self pressNewTabButton];
    }
  else if (tab >= 0
    && NSPointInRect(point, [self liveCloseButtonRectForTabAtIndex: tab]))
    {
      [self pressCloseButtonOfTabAtIndex: tab];
    }
  else if (tab >= 0)
    {
      window = [[self tabWindows] objectAtIndex: tab];
      [[_tabWindow tabGroup] setSelectedWindow: window];
      bar = [window _tabBarView];
      if (bar == nil)
        {
          bar = self;
        }
      [bar trackTabAtIndex: tab
                 fromPoint: [bar pointFromScreen:
                              GSWindowTabScreenPoint(event)]];
    }
}

/* A middle click closes the tab, as in GNOME. */
- (void) otherMouseUp: (NSEvent *)event
{
  NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
  NSInteger tab = [self tabIndexAtPoint: point];

  if ([event buttonNumber] == 2 && tab >= 0)
    {
      [[[self tabWindows] objectAtIndex: tab] performClose: self];
    }
}

/* The wheel scrolls tabs that don't fit, either way it turns: down or
   right shows the tabs further right, as GTK's.  libs-back's X11 and
   Windows servers both give a positive deltaX for the wheel tilted
   right (X11's button 7, WM_MOUSEHWHEEL's positive delta), and a
   positive deltaY for the wheel turned up, as NSScrollView reads
   them. */
- (void) scrollWheel: (NSEvent *)event
{
  CGFloat delta = [event deltaX];

  if (delta == 0.0)
    {
      delta = -[event deltaY];
    }
  if ([self maximumScrollOffset] <= 0.0 || delta == 0.0)
    {
      [super scrollWheel: event];
      return;
    }
  [self setScrollOffset: _scrollOffset
    + delta * GSWindowTabScrollStep(NSWidth([self tabsRect]))];
}

- (BOOL) acceptsFirstMouse: (NSEvent *)event
{
  return YES;
}

- (BOOL) mouseDownCanMoveWindow
{
  return NO;
}

@end

#endif /* GS_HAS_WINDOW_TABBING */
