/* GSWindowTabbingPrivate.h: window tabbing's private interfaces.

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

#ifndef _GNUstep_H_GSWindowTabbingPrivate
#define _GNUstep_H_GSWindowTabbingPrivate

#import "../Headers/GSWindowTabbing.h"
#import <GNUstepGUI/GSWindowDecorationView.h>

#ifndef GS_HAS_WINDOW_TABBING

@class GSWindowTabBarView;

/* What the tab group needs from a window.  The group talks to its
   windows only through these, so the model can be tested with stand-in
   windows and no display (Tests/gui/NSWindowTabGroup).  NSWindow has
   them through GSWindowTabbingWindow.m. */
@protocol GSWindowTabbable
- (NSRect) frame;
- (NSString *) title;
/* The file the window shows; nil or empty for none (NSWindow's
   -representedFilename). */
- (NSString *) representedFilename;
- (BOOL) isKeyWindow;
- (BOOL) isDocumentEdited;
- (NSWindowTabbingIdentifier) tabbingIdentifier;
/* Whether the window manager has the window maximized (on Windows, the
   window is zoomed); NO where that can't be told.  GNUstep's own zoomed
   state is its frame, which the group carries anyway. */
- (BOOL) _tabbingIsMaximized;
/* Puts the window on screen at frame, maximized or not, key if makeKey,
   as the group's selected window, in place of previous (the window it
   takes over from, which un-maximizing it returns to the frame of). */
- (void) _tabbingShowWithFrame: (NSRect)frame
                     maximized: (BOOL)maximized
                       makeKey: (BOOL)makeKey
                     inPlaceOf: (id)previous;
/* Takes it off screen while it stays in its group. */
- (void) _tabbingHide;
/* The group's windows, selection or bar changed: redraw the bar and
   reserve or release its row. */
- (void) _tabbingGroupDidChange;
/* The group the window is in, or nil; set by the group. */
- (NSWindowTabGroup *) _tabbingGroup;
- (void) _setTabbingGroup: (NSWindowTabGroup *)group;
@end

/* The tab bar is shown with more than one window, unless toggled. */
enum
{
  GSWindowTabBarAutomatic = 0,
  GSWindowTabBarShown = 1,
  GSWindowTabBarHidden = 2
};

@interface NSWindowTabGroup (GSWindowTabbingPrivate)
- (id) initWithIdentifier: (NSString *)identifier;
/* -[NSWindow toggleTabBar:]. */
- (void) _toggleTabBar;
/* -[NSWindow selectNextTab:] (forward) and -selectPreviousTab:. */
- (void) _selectNextTab: (BOOL)forward;
/* The window leaves the group (closed, or moved to a window of its
   own); if it was selected its neighbour takes its place at its frame. */
- (void) _windowWillLeave: (id)window;
@end

@interface NSWindowTab (GSWindowTabbingPrivate)
- (id) initWithWindow: (NSWindow *)window;
/* The tab's title, tool tip or accessory view changed. */
- (void) _tabDidChange;
@end

/* A window's tabbing state.  Upstream these are instance variables of
   NSWindow; here they live beside each window, in a table kept by
   GSWindowTabbingInstall.m. */
@interface GSWindowTabbingState : NSObject
{
@public
  NSWindowTabbingMode mode;
  NSString *identifier;
  NSWindowTab *tab;
  NSWindowTabGroup *group;
  GSWindowTabBarView *barView;
  /* The window has been ordered in at least once: only a window shown
     for the first time joins a group automatically. */
  BOOL shown;
  /* Where it last was while the window manager didn't have it
     maximized: where un-maximizing a tab shown in its place returns. */
  NSRect normalFrame;
  BOOL hasNormalFrame;
}
@end

/* The state of window; created when create is YES and it has none.
   GSWindowTabbingInstall.m. */
GSWindowTabbingState *GSWindowTabbingStateForWindow(NSWindow *window,
                                                    BOOL create);
/* Forgets window's state (it is being deallocated). */
void GSWindowTabbingForgetWindow(NSWindow *window);

/* The window manager's maximized state, from GSWindowTabbingInstall.m
   (upstream: the display server's).  GSWindowTabbingWindowIsMaximized
   sets *known to NO where it can't be told.  FrameToShow gives the frame
   to put a window the group is about to show at, before WillShow is
   called on it (ordered out), and DidShow once it is on screen, in place
   of previous (nil for none); normal is where un-maximizing it should
   return (hasNormal NO when that isn't known).  front is
   GSWindowTabbingForegroundWindow() from before the window was ordered
   in: what DidShow gives the front back to when the window wasn't to be
   key. */
BOOL GSWindowTabbingWindowIsMaximized(NSWindow *window, BOOL *known);
NSRect GSWindowTabbingFrameToShow(NSWindow *window, NSRect frame,
                                  BOOL maximized, NSRect normal,
                                  BOOL hasNormal);
void GSWindowTabbingWillShowMaximized(NSWindow *window, BOOL maximized);
void GSWindowTabbingDidShowMaximized(NSWindow *window, BOOL maximized,
                                     NSWindow *previous, BOOL makeKey,
                                     intptr_t front);
/* The window system's foreground window (Windows' HWND), 0 elsewhere. */
intptr_t GSWindowTabbingForegroundWindow(void);

/* Windows: whether a left mouse-up ending a press the bar tracks was a
   real release.  libs-back's Windows server makes one up when the
   pointer moves with the button no longer down (capture was lost and the
   release went elsewhere); as an event it looks like a real one.  Begin
   and End bracket the tracking (they nest); ReleaseWasReal tells a
   mouse-up event from that time.  Elsewhere every release is real.
   GSWindowTabbingInstall.m. */
void GSWindowTabbingBeginPressWatch(void);
BOOL GSWindowTabbingReleaseWasReal(NSEvent *event);
void GSWindowTabbingEndPressWatch(void);

/* NSWindow's private tabbing methods (GSWindowTabbingWindow.m).  The
   methods NSWindow already has call these: upstream each call is a line
   in that method; here GSWindowTabbingInstall.m wraps the method. */
@interface NSWindow (GSWindowTabbingPrivate) <GSWindowTabbable>
/* From -orderWindow:relativeTo:, before ordering in; YES if tabbing
   handled it (the window was selected in its group, or joined one). */
- (BOOL) _tabbingOrderWindow: (NSWindowOrderingMode)place;
/* From -setTitle:, -setTitleWithRepresentedFilename: and
   -setDocumentEdited:, after them. */
- (void) _tabbingTitleDidChange;
/* From -performKeyEquivalent: and -sendEvent:, first; YES if the event
   was a tab shortcut and has been handled. */
- (BOOL) _tabbingHandleKeyEvent: (NSEvent *)event;
/* From -close, first. */
- (void) _tabbingWillClose;
/* From -validateUserInterfaceItem:, first; YES if item is a tabbing
   action, with its validity in *valid. */
- (BOOL) _tabbingValidateUserInterfaceItem: (id)item valid: (BOOL *)valid;
/* From -dealloc, first. */
- (void) _tabbingDealloc;
/* From -[GSWindowDecorationView changeWindowHeight:], last: an
   in-window menu bar or a toolbar was added or removed, and the frame
   was frame before. */
- (void) _tabbingDecorationsDidChangeFromFrame: (NSRect)frame;
/* The height the window gives up for its tab bar (0 for none). */
- (CGFloat) _tabBarReservedHeight;
/* Remembers the window's frame as where un-maximizing a tab shown in
   its place returns, while the window manager doesn't have it maximized
   (on its being ordered in, moved or resized). */
- (void) _tabbingNoteNormalFrame;
/* The tab bar's view while the bar is shown, else nil. */
- (GSWindowTabBarView *) _tabBarView;
/* The tab bar's "+" button: what answers -newWindowForTab: for this
   window, key or not (nil for nothing), is there something, and ask
   it. */
- (id) _tabbingNewTabTarget;
- (BOOL) _tabbingCanCreateNewTab;
- (void) _tabbingCreateNewTab;
/* A tab dragged out of the bar: the window leaves its group as a window
   of its own with its frame's origin at origin (and -moveTabToNewWindow:,
   a little below and to the right). */
- (void) _tabbingMoveToNewWindowAt: (NSPoint)origin;
/* Whether other can be tabbed with the window: both can be tabs, and
   their tabbing identifiers match. */
- (BOOL) _canBeTabbedWith: (NSWindow *)other;
@end

/* GSWindowDecorationView's private tabbing method
   (GSWindowTabbingDecorationView.m).  Upstream, -layout calls it at its
   end. */
@interface GSWindowDecorationView (GSWindowTabbingPrivate)
- (void) _layoutTabBar;
@end

#endif /* GS_HAS_WINDOW_TABBING */

#endif /* _GNUstep_H_GSWindowTabbingPrivate */
