/** <title>GSWindowTabbing</title>

   <abstract>Apple's NSWindow tabbing API for GNUstep, and the GSTheme
   methods that draw the tab bar.</abstract>

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

/* Upstream, this header's parts go to: the tabbing types and the
   NSWindow and NSResponder methods to AppKit/NSWindow.h, the GSTheme
   methods to GNUstepGUI/GSTheme.h, and the two classes are
   AppKit/NSWindowTab.h and AppKit/NSWindowTabGroup.h as they are.  The
   functions at the end stay GNUstep extensions. */

#ifndef _GNUstep_H_GSWindowTabbing
#define _GNUstep_H_GSWindowTabbing

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>

/* GSWT_EXPORT declares this code's public functions and constants.  The
   code is compiled into the theme or app that uses it, never into a DLL
   of its own, so GS_EXPORT (dllimport on Windows outside GNUstep's own
   libraries) is wrong here: it warns with clang and lld (LNK4217).  In
   libs-gui these become APPKIT_EXPORT.  Define GSWT_EXPORT before
   including this header to change it. */
#ifndef GSWT_EXPORT
#  define GSWT_EXPORT extern
#endif

/* libs-gui defines GS_HAS_WINDOW_TABBING once it implements the API
   itself; this code then declares and installs nothing. */
#ifndef GS_HAS_WINDOW_TABBING

#import "AppKit/NSWindowTab.h"
#import "AppKit/NSWindowTabGroup.h"

/**
 * How a window joins tab groups.
 * <deflist>
 * <term>NSWindowTabbingModeAutomatic</term>
 * <desc>As the user prefers (+[NSWindow userTabbingPreference]) and
 * +[NSWindow allowsAutomaticWindowTabbing] allows.</desc>
 * <term>NSWindowTabbingModePreferred</term>
 * <desc>A new window joins the key window's group when their tabbing
 * identifiers match.</desc>
 * <term>NSWindowTabbingModeDisallowed</term>
 * <desc>The window is never a tab.</desc>
 * </deflist>
 */
typedef enum
{
  NSWindowTabbingModeAutomatic = 0,
  NSWindowTabbingModePreferred = 1,
  NSWindowTabbingModeDisallowed = 2
} NSWindowTabbingMode;

/**
 * The user's preference for tabbing new windows, as macOS keeps it.
 */
typedef enum
{
  NSWindowUserTabbingPreferenceManual = 0,
  NSWindowUserTabbingPreferenceAlways = 1,
  NSWindowUserTabbingPreferenceInFullScreen = 2
} NSWindowUserTabbingPreference;

@interface NSWindow (GSWindowTabbing)

/**
 * Returns NO if the app has turned automatic tabbing off; YES by
 * default.
 */
+ (BOOL) allowsAutomaticWindowTabbing;

/**
 * Turns automatic tabbing on or off for all windows of the app.
 */
+ (void) setAllowsAutomaticWindowTabbing: (BOOL)flag;

/**
 * Returns the user's preference, read as on macOS from the
 * AppleWindowTabbingMode default: <code>always</code>,
 * <code>manual</code>, or (unset) in full screen.  GNUstep has no
 * full-screen spaces, so the last means manual.
 */
+ (NSWindowUserTabbingPreference) userTabbingPreference;

/**
 * Returns how the window joins tab groups (automatic by default).
 */
- (NSWindowTabbingMode) tabbingMode;

/**
 * Sets how the window joins tab groups.
 */
- (void) setTabbingMode: (NSWindowTabbingMode)mode;

/**
 * Returns the identifier windows must share to be tabbed together; by
 * default the name of the window's class.
 */
- (NSWindowTabbingIdentifier) tabbingIdentifier;

/**
 * Sets the window's tabbing identifier.
 */
- (void) setTabbingIdentifier: (NSWindowTabbingIdentifier)identifier;

/**
 * Returns the windows of the window's tab group, or nil unless the group
 * has other windows.
 */
- (NSArray *) tabbedWindows;

/**
 * Returns the window's tab.
 */
- (NSWindowTab *) tab;

/**
 * Returns the window's tab group, creating a group of the window alone
 * if it has none.
 */
- (NSWindowTabGroup *) tabGroup;

/**
 * Adds window to the receiver's group, as the tab after the receiver's
 * (NSWindowAbove) or before it (NSWindowBelow), and selects it.
 */
- (void) addTabbedWindow: (NSWindow *)window
                 ordered: (NSWindowOrderingMode)ordered;

/**
 * Selects the next tab of the window's group, wrapping round.
 */
- (IBAction) selectNextTab: (id)sender;

/**
 * Selects the previous tab of the window's group, wrapping round.
 */
- (IBAction) selectPreviousTab: (id)sender;

/**
 * Takes the window out of its group, as a window of its own a little
 * below and to the right of the group.
 */
- (IBAction) moveTabToNewWindow: (id)sender;

/**
 * Adds every window that can be tabbed with this one (same tabbing
 * identifier) to its group, keeping this one selected.
 */
- (IBAction) mergeAllWindows: (id)sender;

/**
 * Shows the tab bar if it is hidden, hides it if it is shown.
 */
- (IBAction) toggleTabBar: (id)sender;

@end

@interface NSResponder (GSWindowTabbingNewTab)

/**
 * Sent along the responder chain by the tab bar's "+" button, which is
 * shown only when something responds.  The implementation makes a new
 * window; it joins the group of the window whose button was pressed.
 */
- (IBAction) newWindowForTab: (id)sender;

@end

#endif /* GS_HAS_WINDOW_TABBING */

/**
 * Where the tab bar goes.
 * <deflist>
 * <term>GSWindowTabBarAboveContent</term>
 * <desc>Its own row above the content: below a title or header bar, a
 * menu bar and a toolbar.  The content shrinks by the bar's
 * height.</desc>
 * <term>GSWindowTabBarInTitleBar</term>
 * <desc>Placed by the theme's window decoration (for example in the
 * title bar): no row is reserved; the theme asks for the bar's view with
 * GSWindowTabBarViewForWindow() and lays it out itself, when
 * GSWindowTabBarDidChangeNotification says the bar changed.</desc>
 * </deflist>
 */
typedef enum
{
  GSWindowTabBarAboveContent = 0,
  GSWindowTabBarInTitleBar = 1
} GSWindowTabBarPlacement;

/**
 * A tab's or a button's state, as bits, for the GSTheme methods that
 * draw them.
 * <deflist>
 * <term>GSWindowTabSelected</term><desc>The selected tab.</desc>
 * <term>GSWindowTabHovered</term><desc>Under the pointer.</desc>
 * <term>GSWindowTabPressed</term><desc>Pressed.</desc>
 * <term>GSWindowTabWindowKey</term>
 * <desc>The tab bar's window is the key window.</desc>
 * <term>GSWindowTabCloseHovered</term>
 * <desc>The pointer is over the tab's close button.</desc>
 * <term>GSWindowTabClosePressed</term>
 * <desc>The tab's close button is pressed.</desc>
 * <term>GSWindowTabEdited</term>
 * <desc>The tab's window has unsaved changes.</desc>
 * <term>GSWindowTabFirst</term><desc>The first tab.</desc>
 * <term>GSWindowTabLast</term><desc>The last tab.</desc>
 * <term>GSWindowTabPreviousHighlighted</term>
 * <desc>The tab before this one is selected, hovered or pressed (a
 * theme may leave out the separator between them).</desc>
 * <term>GSWindowTabDragged</term>
 * <desc>The tab is being dragged: drawn last, over the others, where
 * the pointer has taken it.</desc>
 * </deflist>
 */
enum
{
  GSWindowTabSelected = 1 << 0,
  GSWindowTabHovered = 1 << 1,
  GSWindowTabPressed = 1 << 2,
  GSWindowTabWindowKey = 1 << 3,
  GSWindowTabCloseHovered = 1 << 4,
  GSWindowTabClosePressed = 1 << 5,
  GSWindowTabEdited = 1 << 6,
  GSWindowTabFirst = 1 << 7,
  GSWindowTabLast = 1 << 8,
  GSWindowTabPreviousHighlighted = 1 << 9,
  GSWindowTabDragged = 1 << 10
};
typedef unsigned int GSWindowTabState;

/**
 * Posted with a window as its object when the window's tab bar is shown,
 * hidden or changes, for a theme that places the bar itself
 * (GSWindowTabBarInTitleBar).
 */
GSWT_EXPORT NSString *const GSWindowTabBarDidChangeNotification;

/**
 * The theme's part of window tabbing.  GSTheme has a plain default for
 * each method, in system colours; a theme overrides what it draws
 * differently.  Every method gets the tab bar's window.
 */
@interface GSTheme (GSWindowTabbing)

/**
 * Returns the tab bar's height (default 28).
 */
- (CGFloat) windowTabBarHeightForWindow: (NSWindow *)window;

/**
 * Returns where the tab bar goes (default GSWindowTabBarAboveContent).
 */
- (GSWindowTabBarPlacement) windowTabBarPlacementForWindow: (NSWindow *)window;

/**
 * Returns the narrowest a tab may be (default 80).  Tabs share the
 * bar's width equally, between this and the maximum.
 */
- (CGFloat) windowTabMinimumWidthForWindow: (NSWindow *)window;

/**
 * Returns the widest a tab may be (default 240).
 */
- (CGFloat) windowTabMaximumWidthForWindow: (NSWindow *)window;

/**
 * Returns the width of the "+" button at the bar's end (default 28; 0
 * for none).
 */
- (CGFloat) windowTabNewTabButtonWidthForWindow: (NSWindow *)window;

/**
 * Returns the space left free at each end of the bar (default 0).
 */
- (CGFloat) windowTabBarMarginForWindow: (NSWindow *)window;

/**
 * Returns the space between two tabs and before the "+" button
 * (default 0).
 */
- (CGFloat) windowTabSpacingForWindow: (NSWindow *)window;

/**
 * Returns a tab's close button, in the tab's rect, for the tab's state;
 * NSZeroRect for none in that state (it can't then be clicked).  The
 * default shows it on the selected tab and the one under the pointer.
 */
- (NSRect) windowTabCloseButtonRectForTabRect: (NSRect)tabRect
                                        state: (GSWindowTabState)state
                                       window: (NSWindow *)window;

/**
 * Draws the bar behind the tabs.
 */
- (void) drawWindowTabBarBackgroundInRect: (NSRect)rect
                                   window: (NSWindow *)window;

/**
 * Draws one tab, its title included (GSWindowTabFittedTitle() shortens
 * a title to fit); the close button is drawn after it.
 */
- (void) drawWindowTab: (NSWindowTab *)tab
                inRect: (NSRect)rect
                 state: (GSWindowTabState)state
                window: (NSWindow *)window;

/**
 * Draws a tab's close button.
 */
- (void) drawWindowTabCloseButtonInRect: (NSRect)rect
                                  state: (GSWindowTabState)state
                                 window: (NSWindow *)window;

/**
 * Draws the "+" button.
 */
- (void) drawWindowTabNewTabButtonInRect: (NSRect)rect
                                   state: (GSWindowTabState)state
                                  window: (NSWindow *)window;

/**
 * Returns how wide the fade is at an end of the bar where tabs that
 * don't fit are scrolled out of sight (default 24; 0 for none).
 */
- (CGFloat) windowTabBarScrollFadeWidthForWindow: (NSWindow *)window;

/**
 * Draws the fade over the tabs at the bar's edge (NSMinXEdge or
 * NSMaxXEdge) where more tabs are scrolled out of sight.  The default
 * fades the bar's background colour in towards the edge.
 */
- (void) drawWindowTabBarScrollFadeInRect: (NSRect)rect
                                     edge: (NSRectEdge)edge
                                   window: (NSWindow *)window;

@end

/**
 * <p>Installs window tabbing: the NSWindow methods and the GSTheme
 * defaults NSWindow and GSTheme don't have already.  Returns NO if
 * libs-gui already has window tabbing (and then installs nothing).
 * Later calls do nothing.</p>
 * <p>A theme calls it from its -initWithBundle:, before calling
 * super's, because GSTheme records the theme's overrides of other
 * classes' methods there and those must wrap the installed methods.  An
 * app calls it from main() after +[NSApplication sharedApplication],
 * as loading the user's theme may need the backend.</p>
 * <p>This function and the installing it does are the part that would
 * not go upstream: in libs-gui the methods would be NSWindow's and
 * GSTheme's own.</p>
 */
GSWT_EXPORT BOOL GSWindowTabbingInstall(void);

/**
 * Returns the tab bar's view for window, for a theme whose placement is
 * GSWindowTabBarInTitleBar; nil when the bar is hidden.
 */
GSWT_EXPORT NSView *GSWindowTabBarViewForWindow(NSWindow *window);

/**
 * Returns title shortened with an ellipsis at its end so it fits width
 * when drawn with attributes; the title itself if it fits.
 */
GSWT_EXPORT NSString *GSWindowTabFittedTitle(NSString *title,
                                           NSDictionary *attributes,
                                           CGFloat width);

#endif /* _GNUstep_H_GSWindowTabbing */
