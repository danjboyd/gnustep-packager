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

/* X11 only, and kept to this file so Xlib's names stay out of the rest of
   the theme. The display and the windows' X ids come from GSDisplayServer's
   public -serverDevice and -windowDevice:, which the X11 backend answers
   with its Display and each window's client window. The messages are the
   ones GTK sends (gdk/x11/gdksurface-x11.c). */

#import "GnomeThemeWindowManager.h"

#import <GNUstepGUI/GSDisplayServer.h>
#import <objc/runtime.h>

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>

/* EWMH _NET_WM_STATE actions, and the source indication for a request from
   an application acting for the user. */
enum
{
  GnomeThemeStateRemove = 0,
  GnomeThemeStateAdd = 1,
  GnomeThemeStateToggle = 2,
  GnomeThemeSourceApplication = 1
};

/* The display, when GNUstep's backend is the X11 one. (The Wayland
   backend's -serverDevice is a wl_display.) */
static Display *
GnomeThemeX11Display(void)
{
  GSDisplayServer *server = GSCurrentServer ();
  Class x11Server = NSClassFromString (@"XGServer");

  if (server == nil || x11Server == Nil || [server isKindOfClass: x11Server] == NO)
    {
      return NULL;
    }
  return (Display *)[server serverDevice];
}

static Window
GnomeThemeX11Window(NSWindow *window)
{
  if ([window windowNumber] <= 0)
    {
      return None;
    }
  return (Window)[GSCurrentServer () windowDevice: [window windowNumber]];
}

/* Whether the window manager lists `name` in _NET_SUPPORTED. Read each
   time: the window manager can be replaced while the app runs, and this
   is asked once per press. */
static BOOL
GnomeThemeX11Supports(Display *display, const char *name)
{
  Atom supported = XInternAtom (display, "_NET_SUPPORTED", False);
  Atom wanted = XInternAtom (display, name, False);
  Atom type;
  int format;
  unsigned long count, remaining;
  unsigned char *data = NULL;
  BOOL found = NO;

  if (XGetWindowProperty (display, DefaultRootWindow (display), supported, 0, 4096, False, XA_ATOM,
                          &type, &format, &count, &remaining, &data) == Success && data != NULL)
    {
      Atom *atoms = (Atom *)data;
      unsigned long i;

      for (i = 0; i < count && found == NO; i++)
        {
          found = (atoms[i] == wanted);
        }
      XFree (data);
    }
  return found;
}

static void
GnomeThemeX11SendToRoot(Display *display, Window window, const char *type, long l0, long l1, long l2, long l3,
                        long l4)
{
  XEvent event;

  memset (&event, 0, sizeof (event));
  event.xclient.type = ClientMessage;
  event.xclient.window = window;
  event.xclient.message_type = XInternAtom (display, type, False);
  event.xclient.format = 32;
  event.xclient.data.l[0] = l0;
  event.xclient.data.l[1] = l1;
  event.xclient.data.l[2] = l2;
  event.xclient.data.l[3] = l3;
  event.xclient.data.l[4] = l4;
  XSendEvent (display, DefaultRootWindow (display), False,
              SubstructureRedirectMask | SubstructureNotifyMask, &event);
  XFlush (display);
}

/* The pointer, in root window coordinates, and the X number of the
   button held down (0 when none is). */
static BOOL
GnomeThemeX11Pointer(Display *display, int *x, int *y, int *button)
{
  Window root, child;
  int windowX, windowY;
  unsigned int mask;
  unsigned int masks[] = { Button1Mask, Button2Mask, Button3Mask, Button4Mask, Button5Mask };
  int i;

  if (XQueryPointer (display, DefaultRootWindow (display), &root, &child, x, y,
                     &windowX, &windowY, &mask) == False)
    {
      return NO;
    }
  *button = 0;
  for (i = 0; i < 5 && *button == 0; i++)
    {
      if (mask & masks[i])
        {
          *button = i + 1;
        }
    }
  return YES;
}

/* Motif hints (MwmUtil.h). */
enum
{
  GnomeThemeMwmHintsFunctions = 1 << 0,
  GnomeThemeMwmHintsDecorations = 1 << 1,
  GnomeThemeMwmFuncResize = 1 << 1,
  GnomeThemeMwmFuncMove = 1 << 2,
  GnomeThemeMwmFuncMinimize = 1 << 3,
  GnomeThemeMwmFuncMaximize = 1 << 4,
  GnomeThemeMwmFuncClose = 1 << 5
};

/* Set on a window whose functions the theme allows: whether close was
   among them. */
static char GnomeThemeAllowedCloseKey;

/* Whether the window lists WM_DELETE_WINDOW in WM_PROTOCOLS; with `add`,
   lists it if it doesn't. */
static BOOL
GnomeThemeX11ListsDeleteWindow(Display *display, Window xwindow, BOOL add)
{
  Atom deleteWindow = XInternAtom (display, "WM_DELETE_WINDOW", False);
  Atom *protocols = NULL;
  Atom *more;
  int count = 0;
  int i;
  BOOL listed = NO;

  if (XGetWMProtocols (display, xwindow, &protocols, &count) == 0)
    {
      protocols = NULL;
      count = 0;
    }
  for (i = 0; i < count && listed == NO; i++)
    {
      listed = protocols[i] == deleteWindow;
    }
  if (listed == NO && add)
    {
      more = malloc ((count + 1) * sizeof (Atom));
      if (more != NULL)
        {
          for (i = 0; i < count; i++)
            {
              more[i] = protocols[i];
            }
          more[count] = deleteWindow;
          listed = XSetWMProtocols (display, xwindow, more, count + 1) != 0;
          free (more);
          XFlush (display);
        }
    }
  if (protocols != NULL)
    {
      XFree (protocols);
    }
  return listed;
}

BOOL
GnomeThemeWindowManagerAllowFunctions(NSWindow *window)
{
  Display *display = GnomeThemeX11Display ();
  Window xwindow = display != NULL ? GnomeThemeX11Window (window) : None;
  NSUInteger style = [window styleMask];
  long hints[5] = { GnomeThemeMwmHintsFunctions | GnomeThemeMwmHintsDecorations, 0, 0, 0, 0 };
  BOOL closable;

  if (xwindow == None || (style & (NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
                                   | NSResizableWindowMask | NSDocModalWindowMask)) == 0)
    {
      return NO;
    }
  hints[1] = GnomeThemeMwmFuncMove;
  /* Close only while the window lists WM_DELETE_WINDOW: offered close
     without it, Mutter kills the whole app (XKillClient). libs-back lists
     it only for windows it decorates (until libs-back 0006 in
     Docs/upstream-patches); GnomeThemeWindowManagerWindowOrderedIn adds
     it, then calls this again. */
  closable = (style & NSClosableWindowMask) != 0
    && GnomeThemeX11ListsDeleteWindow (display, xwindow, NO);
  if (closable)
    {
      hints[1] |= GnomeThemeMwmFuncClose;
    }
  if (style & NSMiniaturizableWindowMask)
    {
      hints[1] |= GnomeThemeMwmFuncMinimize;
    }
  if (style & NSResizableWindowMask)
    {
      hints[1] |= GnomeThemeMwmFuncResize | GnomeThemeMwmFuncMaximize;
    }
  /* hints[2], the decorations: none, the header bar draws them. */
  XChangeProperty (display, xwindow, XInternAtom (display, "_MOTIF_WM_HINTS", False),
                   XInternAtom (display, "_MOTIF_WM_HINTS", False), 32, PropModeReplace,
                   (unsigned char *)hints, 5);
  XFlush (display);
  objc_setAssociatedObject (window, &GnomeThemeAllowedCloseKey, [NSNumber numberWithBool: closable],
                            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  return YES;
}

BOOL
GnomeThemeWindowManagerCloseState(NSWindow *window, BOOL *listsDeleteWindow, BOOL *allowsClose)
{
  Display *display = GnomeThemeX11Display ();
  Window xwindow = display != NULL ? GnomeThemeX11Window (window) : None;
  Atom motifHints, type;
  int format;
  unsigned long count, after;
  unsigned char *data = NULL;

  if (xwindow == None)
    {
      return NO;
    }
  XSync (display, False);
  *listsDeleteWindow = GnomeThemeX11ListsDeleteWindow (display, xwindow, NO);
  *allowsClose = NO;
  motifHints = XInternAtom (display, "_MOTIF_WM_HINTS", False);
  if (XGetWindowProperty (display, xwindow, motifHints, 0, 5, False, motifHints, &type, &format,
                          &count, &after, &data) == Success && data != NULL)
    {
      if (format == 32 && count >= 2)
        {
          long *hints = (long *)data;

          *allowsClose = (hints[0] & GnomeThemeMwmHintsFunctions) != 0
            && (hints[1] & GnomeThemeMwmFuncClose) != 0;
        }
      XFree (data);
    }
  return YES;
}

BOOL
GnomeThemeWindowManagerWindowOrderedIn(NSWindow *window)
{
  Display *display = GnomeThemeX11Display ();
  Window xwindow = display != NULL ? GnomeThemeX11Window (window) : None;
  NSNumber *allowedClose = objc_getAssociatedObject (window, &GnomeThemeAllowedCloseKey);
  BOOL closable;

  if (xwindow == None || allowedClose == nil)
    {
      return NO;
    }
  /* libs-back sets WM_PROTOCOLS again each time the window is ordered in.
     Close follows: allowed once it's listed, taken back from a window that
     is no longer closable. */
  closable = ([window styleMask] & NSClosableWindowMask) != 0
    && GnomeThemeX11ListsDeleteWindow (display, xwindow, YES);
  if (closable != [allowedClose boolValue])
    {
      GnomeThemeWindowManagerAllowFunctions (window);
    }
  return closable;
}

BOOL
GnomeThemeWindowManagerMoveResize(NSWindow *window, GnomeThemeMoveResizeDirection direction)
{
  Display *display = GnomeThemeX11Display ();
  Window xwindow = display != NULL ? GnomeThemeX11Window (window) : None;
  int x, y, button;

  /* The window manager follows the pointer only while the button named in
     the request is held down, so name the one the X server says is down.
     (NSEvent's -buttonNumber can't say: libs-back 0.32 gives the X number,
     master since b037ebf AppKit's, where the left button is 0.) */
  if (xwindow == None || GnomeThemeX11Supports (display, "_NET_WM_MOVERESIZE") == NO
    || GnomeThemeX11Pointer (display, &x, &y, &button) == NO || button == 0)
    {
      return NO;
    }
  /* The press's implicit grab would keep the pointer from the window
     manager. */
  XUngrabPointer (display, CurrentTime);
  GnomeThemeX11SendToRoot (display, xwindow, "_NET_WM_MOVERESIZE", x, y, direction, button,
                           GnomeThemeSourceApplication);
  return YES;
}

BOOL
GnomeThemeWindowManagerToggleMaximized(NSWindow *window)
{
  Display *display = GnomeThemeX11Display ();
  Window xwindow = display != NULL ? GnomeThemeX11Window (window) : None;

  if (xwindow == None || GnomeThemeX11Supports (display, "_NET_WM_STATE_MAXIMIZED_VERT") == NO
    || GnomeThemeX11Supports (display, "_NET_WM_STATE_MAXIMIZED_HORZ") == NO)
    {
      return NO;
    }
  GnomeThemeX11SendToRoot (display, xwindow, "_NET_WM_STATE", GnomeThemeStateToggle,
                           XInternAtom (display, "_NET_WM_STATE_MAXIMIZED_VERT", False),
                           XInternAtom (display, "_NET_WM_STATE_MAXIMIZED_HORZ", False),
                           GnomeThemeSourceApplication, 0);
  return YES;
}

BOOL
GnomeThemeWindowManagerShowWindowMenu(NSWindow *window)
{
  Display *display = GnomeThemeX11Display ();
  Window xwindow = display != NULL ? GnomeThemeX11Window (window) : None;
  int x, y, button;

  if (xwindow == None || GnomeThemeX11Supports (display, "_GTK_SHOW_WINDOW_MENU") == NO
    || GnomeThemeX11Pointer (display, &x, &y, &button) == NO)
    {
      return NO;
    }
  XUngrabPointer (display, CurrentTime);
  /* The input device (0: the core pointer), then the root position. */
  GnomeThemeX11SendToRoot (display, xwindow, "_GTK_SHOW_WINDOW_MENU", 0, x, y, 0, 0);
  return YES;
}

BOOL
GnomeThemeWindowManagerShadowExtents(NSWindow *window, CGFloat extents[4])
{
  Display *display = GnomeThemeX11Display ();
  Window xwindow = display != NULL ? GnomeThemeX11Window (window) : None;
  Atom type;
  int format;
  unsigned long count, remaining;
  unsigned char *data = NULL;
  BOOL shadow = NO;
  int i;

  for (i = 0; i < 4; i++)
    {
      extents[i] = 0.0;
    }
  if (xwindow == None)
    {
      return NO;
    }
  if (XGetWindowProperty (display, xwindow, XInternAtom (display, "_GTK_FRAME_EXTENTS", False), 0, 4, False,
                          XA_CARDINAL, &type, &format, &count, &remaining, &data) == Success && data != NULL)
    {
      /* Present even while the extents are 0 (maximised or tiled): the
         window then has neither shadow nor border, as libadwaita's. */
      shadow = type == XA_CARDINAL;
      for (i = 0; shadow && i < 4 && (unsigned long)i < count; i++)
        {
          extents[i] = ((unsigned long *)data)[i];
        }
      XFree (data);
    }
  return shadow;
}

BOOL
GnomeThemeWindowManagerHasAlpha(NSWindow *window)
{
  Display *display = GnomeThemeX11Display ();
  Window xwindow = display != NULL ? GnomeThemeX11Window (window) : None;
  XWindowAttributes attributes;

  if (xwindow == None || XGetWindowAttributes (display, xwindow, &attributes) == 0)
    {
      return NO;
    }
  /* The alpha shows only while a compositing manager draws it; without
     one, transparent pixels are black. */
  {
    char name[32];

    snprintf (name, sizeof (name), "_NET_WM_CM_S%d", DefaultScreen (display));
    if (XGetSelectionOwner (display, XInternAtom (display, name, False)) == None)
      {
        return NO;
      }
  }
  return attributes.depth == 32;
}

BOOL
GnomeThemeWindowManagerHasShadow(NSWindow *window)
{
  CGFloat extents[4];

  return GnomeThemeWindowManagerShadowExtents (window, extents);
}

BOOL
GnomeThemeWindowManagerIsMaximized(NSWindow *window, BOOL *known)
{
  Display *display = GnomeThemeX11Display ();
  Window xwindow = display != NULL ? GnomeThemeX11Window (window) : None;
  Atom vertical, horizontal, type;
  int format;
  unsigned long count, remaining;
  unsigned char *data = NULL;
  BOOL hasVertical = NO, hasHorizontal = NO;

  *known = NO;
  if (xwindow == None || GnomeThemeX11Supports (display, "_NET_WM_STATE_MAXIMIZED_VERT") == NO)
    {
      return NO;
    }
  vertical = XInternAtom (display, "_NET_WM_STATE_MAXIMIZED_VERT", False);
  horizontal = XInternAtom (display, "_NET_WM_STATE_MAXIMIZED_HORZ", False);
  if (XGetWindowProperty (display, xwindow, XInternAtom (display, "_NET_WM_STATE", False), 0, 64, False, XA_ATOM,
                          &type, &format, &count, &remaining, &data) == Success)
    {
      *known = YES;
      if (data != NULL)
        {
          Atom *atoms = (Atom *)data;
          unsigned long i;

          for (i = 0; i < count; i++)
            {
              hasVertical = hasVertical || atoms[i] == vertical;
              hasHorizontal = hasHorizontal || atoms[i] == horizontal;
            }
          XFree (data);
        }
    }
  return hasVertical && hasHorizontal;
}

BOOL
GnomeThemeWindowManagerSetWindowType(NSWindow *window, const char *type)
{
  Display *display = GnomeThemeX11Display ();
  Window xwindow = display != NULL ? GnomeThemeX11Window (window) : None;
  Atom property, wanted, actualType;
  int format;
  unsigned long count, remaining;
  unsigned char *data = NULL;
  BOOL same = NO;

  if (xwindow == None || GnomeThemeX11Supports (display, type) == NO)
    {
      return NO;
    }
  property = XInternAtom (display, "_NET_WM_WINDOW_TYPE", False);
  wanted = XInternAtom (display, type, False);
  /* Read first: a libs-back that types windows as GTK does has set it
     already (perhaps with fallbacks after it), and the theme then leaves
     it alone. */
  if (XGetWindowProperty (display, xwindow, property, 0, 1, False, XA_ATOM,
                          &actualType, &format, &count, &remaining, &data) == Success && data != NULL)
    {
      same = (count >= 1 && ((Atom *)data)[0] == wanted);
      XFree (data);
    }
  if (same == NO)
    {
      long value = (long)wanted;

      XChangeProperty (display, xwindow, property, XA_ATOM, 32, PropModeReplace,
                       (unsigned char *)&value, 1);
      XFlush (display);
    }
  return YES;
}

BOOL
GnomeThemeWindowManagerSetModalParent(NSWindow *dialog, NSWindow *parent)
{
  Display *display = GnomeThemeX11Display ();
  Window xwindow = display != NULL ? GnomeThemeX11Window (dialog) : None;
  Window xparent = display != NULL ? GnomeThemeX11Window (parent) : None;
  Atom state, modal, actualType;
  int format;
  unsigned long count, remaining, i;
  unsigned char *data = NULL;
  Atom atoms[32];
  unsigned long n = 0;
  BOOL found = NO;

  if (xwindow == None || xparent == None || GnomeThemeX11Supports (display, "_NET_WM_STATE_MODAL") == NO)
    {
      return NO;
    }
  XSetTransientForHint (display, xwindow, xparent);
  /* A window that isn't mapped sets its own _NET_WM_STATE; the window
     manager reads it when it maps the window. */
  state = XInternAtom (display, "_NET_WM_STATE", False);
  modal = XInternAtom (display, "_NET_WM_STATE_MODAL", False);
  if (XGetWindowProperty (display, xwindow, state, 0, 31, False, XA_ATOM, &actualType, &format, &count,
                          &remaining, &data) == Success && data != NULL)
    {
      for (i = 0; i < count && n < 31; i++)
        {
          atoms[n++] = ((Atom *)data)[i];
          found = found || ((Atom *)data)[i] == modal;
        }
      XFree (data);
    }
  if (found == NO)
    {
      long values[32];

      atoms[n++] = modal;
      for (i = 0; i < n; i++)
        {
          values[i] = (long)atoms[i];
        }
      XChangeProperty (display, xwindow, state, XA_ATOM, 32, PropModeReplace, (unsigned char *)values, n);
    }
  /* Shown for the user's last action in the parent, as GTK stamps a
     dialog with the time of the event that opened it: without a time
     Mutter keeps the focus on the parent (focus-stealing prevention), and
     the alert's keys (Return, Escape) go nowhere. */
  {
    Atom userTime = XInternAtom (display, "_NET_WM_USER_TIME", False);

    data = NULL;
    if (XGetWindowProperty (display, xparent, userTime, 0, 1, False, XA_CARDINAL, &actualType, &format, &count,
                            &remaining, &data) == Success && data != NULL)
      {
        if (count == 1)
          {
            long time = (long)((unsigned long *)data)[0];

            XChangeProperty (display, xwindow, userTime, XA_CARDINAL, 32, PropModeReplace,
                             (unsigned char *)&time, 1);
          }
        XFree (data);
      }
  }
  XFlush (display);
  return YES;
}

NSString *
GnomeThemeWindowManagerPortalHandle(NSWindow *window)
{
  Window xwindow;

  if (window == nil || GnomeThemeX11Display () == NULL)
    {
      return nil;
    }
  xwindow = GnomeThemeX11Window (window);
  if (xwindow == None)
    {
      return nil;
    }
  return [NSString stringWithFormat: @"x11:%lx", (unsigned long)xwindow];
}
