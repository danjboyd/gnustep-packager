/*
   Copyright (C) 2026 Daniel Boyd

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

#import <AppKit/AppKit.h>

/* The window manager's part in the header bar, asked for as GTK asks for
   it on X11 (EWMH and GTK's own messages), so that Mutter moves, resizes
   and maximises GNUstep-decorated windows as it does GTK's: snapping,
   tiling, dragging off screen, Super-drag, its window menu.

   Each call returns NO when it can't ask (the backend isn't X11, or the
   window manager doesn't list the message in _NET_SUPPORTED); the header
   bar then does the job itself. */

/* libs-back's Motif hints for a window it doesn't decorate allow the
   window manager no functions, so Mutter won't move, maximise, minimise
   or close it, even when asked. This keeps "no decorations" and allows
   the functions the window's style has, as libs-back does for windows the
   window manager decorates. Call it once the X window exists. Close is
   allowed only while the window lists WM_DELETE_WINDOW. */
BOOL GnomeThemeWindowManagerAllowFunctions(NSWindow *window);

/* libs-back lists WM_DELETE_WINDOW only for windows it decorates, so a
   window manager asked to close a header-bar window (Alt+F4, its window
   menu) has no way to ask the app and kills it instead. For a window whose
   functions the theme allows and that is closable, this lists it, then
   allows close; the request comes back as -performClose:. Call it each
   time the window is ordered in, after libs-back. */
BOOL GnomeThemeWindowManagerWindowOrderedIn(NSWindow *window);

/* For QuirkProbe: whether the window lists WM_DELETE_WINDOW, and whether
   its Motif hints allow close. NO when there's no X window to read. */
BOOL GnomeThemeWindowManagerCloseState(NSWindow *window, BOOL *listsDeleteWindow, BOOL *allowsClose);

/* _NET_WM_MOVERESIZE directions. */
typedef enum
{
  GnomeThemeMoveResizeTopLeft = 0,
  GnomeThemeMoveResizeTop = 1,
  GnomeThemeMoveResizeTopRight = 2,
  GnomeThemeMoveResizeRight = 3,
  GnomeThemeMoveResizeBottomRight = 4,
  GnomeThemeMoveResizeBottom = 5,
  GnomeThemeMoveResizeBottomLeft = 6,
  GnomeThemeMoveResizeLeft = 7,
  GnomeThemeMoveResizeMove = 8
} GnomeThemeMoveResizeDirection;

/* Hands a move or resize, started by the mouse button held down now, to
   the window manager. It follows the pointer until the button is
   released. */
BOOL GnomeThemeWindowManagerMoveResize(NSWindow *window, GnomeThemeMoveResizeDirection direction);

/* Asks the window manager to maximise the window, or to restore it when
   it is maximised. */
BOOL GnomeThemeWindowManagerToggleMaximized(NSWindow *window);

/* Asks the window manager to show its window menu at the pointer. */
BOOL GnomeThemeWindowManagerShowWindowMenu(NSWindow *window);

/* Whether the backend draws the window's shadow (_GTK_FRAME_EXTENTS, with
   a libs-back that draws GNOME's shadow), even while it's maximised or
   tiled and has none: the window then has no border of its own, as
   libadwaita's. */
BOOL GnomeThemeWindowManagerHasShadow(NSWindow *window);

/* As GnomeThemeWindowManagerHasShadow, with the shadow margin now (left,
   right, top, bottom, in pixels; 0 while maximised or tiled). */
BOOL GnomeThemeWindowManagerShadowExtents(NSWindow *window, CGFloat extents[4]);

/* Whether the window's pixels have an alpha channel (a 32-bit visual on
   X11) and a compositing manager shows it, so what the window leaves
   transparent shows what is behind it; NO when the backend can't tell. */
BOOL GnomeThemeWindowManagerHasAlpha(NSWindow *window);

/* Whether the window manager has the window maximised; NO in `known` when
   it can't tell. */
BOOL GnomeThemeWindowManagerIsMaximized(NSWindow *window, BOOL *known);

/* Gives the window the EWMH window type `type` (such as
   "_NET_WM_WINDOW_TYPE_TOOLTIP") unless it has it already, as GTK types its
   menus and tool tips. libs-back types windows from their level alone,
   before a tool tip's class is known (libs-gui#965). NO when it can't (not
   X11, or the window manager doesn't list the type in _NET_SUPPORTED). */
BOOL GnomeThemeWindowManagerSetWindowType(NSWindow *window, const char *type);

/* Makes `dialog`, not yet shown, a modal dialog of `parent`
   (WM_TRANSIENT_FOR and _NET_WM_STATE_MODAL, and the parent's
   _NET_WM_USER_TIME so it gets the focus), as GTK's modal dialogs are:
   Mutter then attaches it to the parent (no title bar, centred under the
   parent's top edge, moving with it) and dims the parent. NO when it
   can't (not X11, or the window manager doesn't list
   _NET_WM_STATE_MODAL). */
BOOL GnomeThemeWindowManagerSetModalParent(NSWindow *dialog, NSWindow *parent);

/* The window's handle for an XDG desktop portal's parent_window
   ("x11:<id>"), with which the portal's dialog is made a modal dialog of
   it; nil when there is none (not X11, or not on screen yet). */
NSString *GnomeThemeWindowManagerPortalHandle(NSWindow *window);
