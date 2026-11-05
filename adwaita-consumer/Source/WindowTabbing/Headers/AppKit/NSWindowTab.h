/** <title>NSWindowTab</title>

   <abstract>What the tab bar shows for one window of a tab group.</abstract>

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

#ifndef _GNUstep_H_NSWindowTab
#define _GNUstep_H_NSWindowTab

#import <Foundation/NSObject.h>

@class NSAttributedString;
@class NSString;
@class NSView;
@class NSWindow;

/**
 * <p>An NSWindowTab describes how a window appears as a tab in its tab
 * group's tab bar.  Every window has one (see -[NSWindow tab]); it is
 * created on demand and lives as long as its window.</p>
 * <p>As on macOS, the tab shows the window's title unless a title of its
 * own is set.</p>
 */
@interface NSWindowTab : NSObject
{
  NSWindow *_window;
  NSString *_title;
  NSAttributedString *_attributedTitle;
  NSString *_toolTip;
  NSView *_accessoryView;
}

/**
 * Returns the title the tab bar shows: the title set with -setTitle:,
 * else the string of the attributed title, else the window's title.  For
 * a window showing a file (-setTitleWithRepresentedFilename:) it is the
 * file's name, as on macOS, where GNUstep's window title also names the
 * file's folder.
 */
- (NSString *) title;

/**
 * Sets the tab's title; nil goes back to following the window's title.
 */
- (void) setTitle: (NSString *)title;

/**
 * Returns the attributed title set with -setAttributedTitle:, or nil.
 */
- (NSAttributedString *) attributedTitle;

/**
 * Sets an attributed title for the tab.
 */
- (void) setAttributedTitle: (NSAttributedString *)title;

/**
 * Returns the tab's tool tip, or nil for none.
 */
- (NSString *) toolTip;

/**
 * Sets the tool tip shown over the tab.
 */
- (void) setToolTip: (NSString *)toolTip;

/**
 * Returns the tab's accessory view, or nil.  (Kept for Apple
 * compatibility; the tab bar doesn't show it yet.)
 */
- (NSView *) accessoryView;

/**
 * Sets the tab's accessory view.
 */
- (void) setAccessoryView: (NSView *)view;

@end

#endif /* _GNUstep_H_NSWindowTab */
