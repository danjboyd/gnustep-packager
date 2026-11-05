/** <title>NSWindowTabGroup</title>

   <abstract>The windows shown as tabs of one window.</abstract>

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

#import "GSWindowTabbingPrivate.h"

#ifndef GS_HAS_WINDOW_TABBING

/* The group's windows, as non-retained pointers (NSValue): a window on
   its own is not held by its group.  With two or more windows the group
   retains them all, as the hidden ones have nothing else showing
   them. */
static id
GSTabGroupWindowAt(NSArray *windows, NSUInteger index)
{
  return [[windows objectAtIndex: index] nonretainedObjectValue];
}

/* Private helpers, used before they are defined. */
@interface NSWindowTabGroup (GSWindowTabGroupInternal)
- (NSUInteger) _indexOfWindow: (id)window;
- (void) _moveWindowAtIndex: (NSUInteger)current toIndex: (NSInteger)index;
- (void) _takeWindow: (id)window fromGroup: (NSWindowTabGroup *)old;
- (void) _updateRetention;
- (void) _windowsDidChangeAlso: (id)extra;
- (void) _switchToWindow: (id)window;
- (id) _neighbourOfWindowAtIndex: (NSUInteger)index;
@end

@implementation NSWindowTabGroup

- (id) init
{
  return [self initWithIdentifier: nil];
}

- (void) dealloc
{
  NSUInteger i;

  if (_retainsWindows)
    {
      for (i = 0; i < [_windows count]; i++)
        {
          RELEASE(GSTabGroupWindowAt(_windows, i));
        }
    }
  RELEASE(_windows);
  RELEASE(_identifier);
  [super dealloc];
}

- (NSWindowTabbingIdentifier) identifier
{
  return _identifier;
}

- (NSArray *) windows
{
  NSMutableArray *windows;
  NSUInteger i;

  windows = [NSMutableArray arrayWithCapacity: [_windows count]];
  for (i = 0; i < [_windows count]; i++)
    {
      [windows addObject: GSTabGroupWindowAt(_windows, i)];
    }
  return windows;
}

- (NSWindow *) selectedWindow
{
  return _selectedWindow;
}

- (void) setSelectedWindow: (NSWindow *)window
{
  if (window == nil || window == _selectedWindow
    || [self _indexOfWindow: window] == NSNotFound)
    {
      return;
    }
  [self _switchToWindow: window];
  [self _windowsDidChangeAlso: nil];
}

- (BOOL) isTabBarVisible
{
  switch (_barState)
    {
      case GSWindowTabBarShown:
        return YES;
      case GSWindowTabBarHidden:
        return NO;
      default:
        return [_windows count] > 1;
    }
}

- (BOOL) isOverviewVisible
{
  return NO;
}

- (void) setOverviewVisible: (BOOL)flag
{
  /* No tab overview yet. */
}

- (void) addWindow: (NSWindow *)window
{
  [self insertWindow: window atIndex: [_windows count]];
}

- (void) insertWindow: (NSWindow *)window atIndex: (NSInteger)index
{
  NSUInteger current;

  if (window == nil)
    {
      return;
    }
  current = [self _indexOfWindow: window];
  if (current != NSNotFound)
    {
      [self _moveWindowAtIndex: current toIndex: index];
      return;
    }

  /* Keep the window alive while it moves between groups. */
  RETAIN(window);
  [self _takeWindow: window fromGroup: [(id)window _tabbingGroup]];
  index = MAX(0, MIN(index, (NSInteger)[_windows count]));
  [_windows insertObject: [NSValue valueWithNonretainedObject: window]
                 atIndex: index];
  if (_retainsWindows)
    {
      RETAIN(window);
    }
  [self _updateRetention];
  [(id)window _setTabbingGroup: self];
  if (_selectedWindow == nil)
    {
      _selectedWindow = window;
    }
  else
    {
      [self _switchToWindow: window];
    }
  [self _windowsDidChangeAlso: nil];
  RELEASE(window);
}

- (void) removeWindow: (NSWindow *)window
{
  if (window == nil || [self _indexOfWindow: window] == NSNotFound)
    {
      return;
    }
  RETAIN(window);
  [self _windowWillLeave: window];
  [(id)window _setTabbingGroup: nil];
  [(id)window _tabbingGroupDidChange];
  RELEASE(window);
}

- (NSString *) description
{
  return [NSString stringWithFormat: @"<%@ %p identifier %@, %lu window(s)>",
    NSStringFromClass([self class]), self, _identifier,
    (unsigned long)[_windows count]];
}

@end


@implementation NSWindowTabGroup (GSWindowTabGroupInternal)

- (NSUInteger) _indexOfWindow: (id)window
{
  NSUInteger i;

  for (i = 0; i < [_windows count]; i++)
    {
      if (GSTabGroupWindowAt(_windows, i) == window)
        {
          return i;
        }
    }
  return NSNotFound;
}

/* A window already in the group only changes its place. */
- (void) _moveWindowAtIndex: (NSUInteger)current toIndex: (NSInteger)index
{
  NSValue *value = RETAIN([_windows objectAtIndex: current]);

  [_windows removeObjectAtIndex: current];
  index = MAX(0, MIN(index, (NSInteger)[_windows count]));
  [_windows insertObject: value atIndex: index];
  RELEASE(value);
  [self _windowsDidChangeAlso: nil];
}

/* A window joining this group leaves the one it was in; a group with no
   identifier yet takes the window's. */
- (void) _takeWindow: (id)window fromGroup: (NSWindowTabGroup *)old
{
  if (old != nil && old != self)
    {
      [old _windowWillLeave: window];
    }
  if (_identifier == nil)
    {
      ASSIGNCOPY(_identifier, [window tabbingIdentifier]);
    }
}

/* Retains the windows while there are two or more, releases them when
   one is left. */
- (void) _updateRetention
{
  BOOL retain = ([_windows count] > 1);
  NSUInteger i;

  if (retain == _retainsWindows)
    {
      return;
    }
  _retainsWindows = retain;
  for (i = 0; i < [_windows count]; i++)
    {
      if (retain)
        {
          RETAIN(GSTabGroupWindowAt(_windows, i));
        }
      else
        {
          RELEASE(GSTabGroupWindowAt(_windows, i));
        }
    }
}

/* Tells the group's windows, and extra (a window that has just left),
   that the group changed. */
- (void) _windowsDidChangeAlso: (id)extra
{
  NSArray *windows = [self windows];
  NSUInteger i;

  for (i = 0; i < [windows count]; i++)
    {
      [[windows objectAtIndex: i] _tabbingGroupDidChange];
    }
  if (extra != nil && [windows indexOfObjectIdenticalTo: extra] == NSNotFound)
    {
      [extra _tabbingGroupDidChange];
    }
}

/* Shows window in place of the selected one: at its frame, maximized
   if it was, and key if it was, as macOS does. */
- (void) _switchToWindow: (id)window
{
  id previous = _selectedWindow;
  NSRect frame;
  BOOL maximized;
  BOOL key;

  if (window == previous)
    {
      return;
    }
  _selectedWindow = window;
  if (previous == nil)
    {
      return;
    }
  frame = [previous frame];
  maximized = [previous _tabbingIsMaximized];
  key = [previous isKeyWindow];
  /* The new tab first, over the old one, then the old one out: hidden
     first, no window of the group would be on screen for a moment, and
     the window manager would animate both (the window vanishes and
     reappears). */
  [window _tabbingShowWithFrame: frame
                      maximized: maximized
                        makeKey: key
                      inPlaceOf: previous];
  [previous _tabbingHide];
}

/* The window that takes the place of the window at index when it
   leaves: the next tab, or the previous one for the last tab. */
- (id) _neighbourOfWindowAtIndex: (NSUInteger)index
{
  NSUInteger count = [_windows count];
  NSUInteger neighbour = (index + 1 < count) ? index + 1 : index - 1;

  return GSTabGroupWindowAt(_windows, neighbour);
}

@end


@implementation NSWindowTabGroup (GSWindowTabbingPrivate)

- (id) initWithIdentifier: (NSString *)identifier
{
  if ((self = [super init]) != nil)
    {
      ASSIGNCOPY(_identifier, identifier);
      _windows = [NSMutableArray new];
      _selectedWindow = nil;
      _barState = GSWindowTabBarAutomatic;
      _retainsWindows = NO;
    }
  return self;
}

- (void) _windowWillLeave: (id)window
{
  NSUInteger index = [self _indexOfWindow: window];

  if (index == NSNotFound)
    {
      return;
    }
  RETAIN(self);
  if (window == _selectedWindow)
    {
      if ([_windows count] > 1)
        {
          id neighbour = [self _neighbourOfWindowAtIndex: index];

          _selectedWindow = neighbour;
          [neighbour _tabbingShowWithFrame: [window frame]
                                 maximized: [window _tabbingIsMaximized]
                                   makeKey: [window isKeyWindow]
                                 inPlaceOf: window];
        }
      else
        {
          _selectedWindow = nil;
        }
    }
  [_windows removeObjectAtIndex: index];
  if (_retainsWindows)
    {
      /* Balanced by the caller's retain, or the window is released by
         whoever closed it. */
      AUTORELEASE(window);
    }
  [self _updateRetention];
  [self _windowsDidChangeAlso: window];
  RELEASE(self);
}

/* Shows or hides the bar; back to automatic when that's what automatic
   would show (hidden, then shown again, with two tabs). */
- (void) _toggleTabBar
{
  BOOL show = ([self isTabBarVisible] == NO);

  if (show == ([_windows count] > 1))
    {
      _barState = GSWindowTabBarAutomatic;
    }
  else
    {
      _barState = show ? GSWindowTabBarShown : GSWindowTabBarHidden;
    }
  [self _windowsDidChangeAlso: nil];
}

- (void) _selectNextTab: (BOOL)forward
{
  NSUInteger count = [_windows count];
  NSUInteger index;

  if (count < 2)
    {
      return;
    }
  index = [self _indexOfWindow: _selectedWindow];
  if (index == NSNotFound)
    {
      index = 0;
    }
  index = forward ? (index + 1) % count : (index + count - 1) % count;
  [self setSelectedWindow: GSTabGroupWindowAt(_windows, index)];
}

@end

#endif /* GS_HAS_WINDOW_TABBING */
