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

#ifndef _GNUstep_H_NSWindowTabGroup
#define _GNUstep_H_NSWindowTabGroup

#import <Foundation/NSObject.h>

@class NSArray;
@class NSMutableArray;
@class NSString;
@class NSWindow;

/**
 * Identifies the windows that may be tabbed together (see
 * -[NSWindow tabbingIdentifier]).
 */
typedef NSString *NSWindowTabbingIdentifier;

/**
 * <p>An NSWindowTabGroup holds the windows shown as tabs of one window.
 * Only its selected window is on screen; the others are ordered out but
 * stay in the group.  Selecting a tab gives the newly selected window the
 * frame of the one it replaces, and makes it key if that one was.</p>
 * <p>A window always has a group (see -[NSWindow tabGroup]), possibly of
 * that window alone.  While a group has two or more windows it retains
 * them, since the hidden ones have nothing else keeping them on screen;
 * a window on its own is not retained by its group.</p>
 */
@interface NSWindowTabGroup : NSObject
{
  NSString *_identifier;
  NSMutableArray *_windows;
  NSWindow *_selectedWindow;
  int _barState;
  BOOL _retainsWindows;
}

/**
 * Returns the tabbing identifier of the group's windows.
 */
- (NSWindowTabbingIdentifier) identifier;

/**
 * Returns the group's windows in tab order.
 */
- (NSArray *) windows;

/**
 * Returns the window whose tab is selected: the one on screen.
 */
- (NSWindow *) selectedWindow;

/**
 * Selects the tab of window, which must be in the group: it takes the
 * frame of the window it replaces, which is ordered out.
 */
- (void) setSelectedWindow: (NSWindow *)window;

/**
 * Returns YES if the tab bar is shown: with two or more windows, unless
 * -[NSWindow toggleTabBar:] showed or hid it.
 */
- (BOOL) isTabBarVisible;

/**
 * Returns NO: the tab overview isn't implemented.
 */
- (BOOL) isOverviewVisible;

/**
 * Does nothing: the tab overview isn't implemented.
 */
- (void) setOverviewVisible: (BOOL)flag;

/**
 * Adds window as the last tab and selects it.  A window in another group
 * leaves that group first.
 */
- (void) addWindow: (NSWindow *)window;

/**
 * Inserts window as the tab at index and selects it.  A window already in
 * the group only moves to index.
 */
- (void) insertWindow: (NSWindow *)window atIndex: (NSInteger)index;

/**
 * Removes window from the group, as a window of its own.  If it was
 * selected, its neighbour takes its place, at its frame.
 */
- (void) removeWindow: (NSWindow *)window;

@end

#endif /* _GNUstep_H_NSWindowTabGroup */
