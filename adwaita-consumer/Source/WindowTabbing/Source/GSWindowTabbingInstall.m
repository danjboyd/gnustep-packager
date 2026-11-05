/** <title>GSWindowTabbingInstall</title>

   <abstract>Installs window tabbing into NSWindow, GSWindowDecorationView
   and GSTheme at run time.</abstract>

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

/* This file is the part that would not go upstream.  The tabbing itself
   is written as NSWindow's, GSWindowDecorationView's and GSTheme's own
   methods (GSWindowTabbingWindow.m, GSWindowTabbingDecorationView.m,
   GSWindowTabbingTheme.m).  Here they are copied into those classes, a
   window's tabbing state is kept beside it, and the methods those
   classes already have are wrapped so they call the tabbing's: upstream
   each wrapper is one call inside the method itself, and this file is
   deleted. */

/* dladdr() needs _GNU_SOURCE before any system header. */
#if !defined(_WIN32) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif
#include <stdlib.h>
#include <math.h>

#import "GSWindowTabbingPrivate.h"
#import "GSWindowTabBarView.h"
#import <GNUstepGUI/GSDisplayServer.h>
#import <objc/runtime.h>

/* Which loaded object holds an address: dladdr() where there is one,
   GetModuleHandleExW() on Windows, whose MinGW toolchains have no
   <dlfcn.h>.  <windows.h> comes after GNUstep's headers, which include
   <winsock2.h> (it must precede <windows.h>). */
#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

/* X11's types, for the window manager's maximized state; its functions
   are looked up at run time (libs-back's X11 server has loaded Xlib), so
   nothing links against it. */
#if !defined(_WIN32) && defined(__has_include)
#if __has_include(<X11/Xlib.h>)
#define GSWT_HAVE_X11 1
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#endif
#endif

#ifndef GS_HAS_WINDOW_TABBING

/* The tabbing state of each window, keyed by the window (not retained). */
static NSMapTable *states = NULL;
static BOOL installed = NO;

@implementation GSWindowTabbingState

/* When an app and its theme both build this code in, the runtime keeps
   one copy of each class (libobjc2 warns "Loading two versions of ..."),
   while each copy's C functions keep their own static state.  Only the
   copy whose classes were kept can work, so the other copy's public
   functions call these, which run in the kept copy. */
+ (BOOL) _installTabbing
{
  return GSWindowTabbingInstall();
}

+ (NSView *) _tabBarViewForWindow: (NSWindow *)window
{
  return GSWindowTabBarViewForWindow(window);
}

/* NSWindowDidMoveNotification and NSWindowDidResizeNotification, for any
   window: where un-maximizing a tab shown in its place returns.
   Upstream, a line in -[NSWindow setFrame:display:]'s callers. */
+ (void) _windowFrameDidChange: (NSNotification *)notification
{
  NSWindow *window = [notification object];

  if ([window isKindOfClass: [NSWindow class]] && [window isVisible])
    {
      [window _tabbingNoteNormalFrame];
    }
}

- (void) dealloc
{
  RELEASE(identifier);
  RELEASE(tab);
  RELEASE(group);
  [barView removeFromSuperview];
  RELEASE(barView);
  [super dealloc];
}

@end

GSWindowTabbingState *
GSWindowTabbingStateForWindow(NSWindow *window, BOOL create)
{
  GSWindowTabbingState *state;

  if (states == NULL || window == nil)
    {
      return nil;
    }
  state = NSMapGet(states, window);
  if (state == nil && create)
    {
      state = [GSWindowTabbingState new];
      state->mode = NSWindowTabbingModeAutomatic;
      NSMapInsert(states, window, state);
      RELEASE(state);
    }
  return state;
}

void
GSWindowTabbingForgetWindow(NSWindow *window)
{
  if (states != NULL)
    {
      NSMapRemove(states, window);
    }
}

/* The window manager's maximized state.  Upstream this belongs in the
   display server (libs-back), next to its other window manager hints;
   here it is done for libs-back's X11 and Windows servers directly.

   X11: EWMH's _NET_WM_STATE_MAXIMIZED_VERT and _HORZ, read from the
   window's _NET_WM_STATE.  A window the group is about to show is
   withdrawn (ordered out), and the window manager reads _NET_WM_STATE
   when it maps one, so the property itself is changed (EWMH's rule for
   withdrawn windows).
   Windows: IsZoomed(), and SetWindowPlacement() once the window is
   shown. */

#if defined(GSWT_HAVE_X11)
typedef Atom (*GSWTInternAtom)(Display *, const char *, Bool);
typedef int (*GSWTGetWindowProperty)(Display *, Window, Atom, long, long,
  Bool, Atom, Atom *, int *, unsigned long *, unsigned long *,
  unsigned char **);
typedef int (*GSWTChangeProperty)(Display *, Window, Atom, Atom, int, int,
  const unsigned char *, int);
typedef int (*GSWTFree)(void *);

static struct
{
  BOOL looked;
  GSWTInternAtom internAtom;
  GSWTGetWindowProperty getWindowProperty;
  GSWTChangeProperty changeProperty;
  GSWTFree free;
} x11;

/* The X display and window of window, or NO when it has none (not
   libs-back's X11 server, or not created yet). */
static BOOL
GSWindowTabbingX11Window(NSWindow *window, Display **display, Window *xwindow)
{
  GSDisplayServer *server = GSServerForWindow(window);
  Class x11Server = NSClassFromString(@"XGServer");

  if (x11.looked == NO)
    {
      x11.looked = YES;
      x11.internAtom = (GSWTInternAtom)dlsym(RTLD_DEFAULT, "XInternAtom");
      x11.getWindowProperty
        = (GSWTGetWindowProperty)dlsym(RTLD_DEFAULT, "XGetWindowProperty");
      x11.changeProperty
        = (GSWTChangeProperty)dlsym(RTLD_DEFAULT, "XChangeProperty");
      x11.free = (GSWTFree)dlsym(RTLD_DEFAULT, "XFree");
    }
  if (x11.internAtom == NULL || x11.getWindowProperty == NULL
    || x11.changeProperty == NULL || x11.free == NULL
    || server == nil || x11Server == Nil
    || [server isKindOfClass: x11Server] == NO
    || [window windowNumber] <= 0)
    {
      return NO;
    }
  *display = (Display *)[server serverDevice];
  *xwindow = (Window)(uintptr_t)[server windowDevice: [window windowNumber]];
  return (*display != NULL && *xwindow != None);
}

/* The atoms in the window's _NET_WM_STATE, at most max of them, or -1
   when it can't be read. */
static int
GSWindowTabbingX11State(Display *display, Window xwindow, Atom *atoms, int max)
{
  Atom type;
  int format;
  unsigned long count, remaining, i;
  unsigned char *data = NULL;
  int n = 0;

  if (x11.getWindowProperty(display, xwindow,
        x11.internAtom(display, "_NET_WM_STATE", False), 0, max, False,
        XA_ATOM, &type, &format, &count, &remaining, &data) != Success)
    {
      return -1;
    }
  if (data != NULL)
    {
      if (type == XA_ATOM && format == 32)
        {
          for (i = 0; i < count && n < max; i++)
            {
              atoms[n++] = ((Atom *)data)[i];
            }
        }
      x11.free(data);
    }
  return n;
}
#endif

BOOL
GSWindowTabbingWindowIsMaximized(NSWindow *window, BOOL *known)
{
#if defined(_WIN32)
  *known = ([window windowNumber] > 0);
  return *known && IsZoomed((HWND)(intptr_t)[window windowNumber]);
#elif defined(GSWT_HAVE_X11)
  Display *display;
  Window xwindow;
  Atom atoms[32];
  Atom vertical, horizontal;
  BOOL hasVertical = NO, hasHorizontal = NO;
  int n, i;

  *known = NO;
  if (GSWindowTabbingX11Window(window, &display, &xwindow) == NO)
    {
      return NO;
    }
  n = GSWindowTabbingX11State(display, xwindow, atoms, 32);
  if (n < 0)
    {
      return NO;
    }
  *known = YES;
  vertical = x11.internAtom(display, "_NET_WM_STATE_MAXIMIZED_VERT", False);
  horizontal = x11.internAtom(display, "_NET_WM_STATE_MAXIMIZED_HORZ", False);
  for (i = 0; i < n; i++)
    {
      hasVertical = hasVertical || atoms[i] == vertical;
      hasHorizontal = hasHorizontal || atoms[i] == horizontal;
    }
  return hasVertical && hasHorizontal;
#else
  *known = NO;
  return NO;
#endif
}

void
GSWindowTabbingWillShowMaximized(NSWindow *window, BOOL maximized)
{
#if defined(GSWT_HAVE_X11)
  Display *display;
  Window xwindow;
  Atom atoms[34];
  Atom vertical, horizontal;
  int n, i, kept = 0;

  if ([window isVisible]
    || GSWindowTabbingX11Window(window, &display, &xwindow) == NO)
    {
      return;
    }
  n = GSWindowTabbingX11State(display, xwindow, atoms, 32);
  if (n < 0)
    {
      return;
    }
  vertical = x11.internAtom(display, "_NET_WM_STATE_MAXIMIZED_VERT", False);
  horizontal = x11.internAtom(display, "_NET_WM_STATE_MAXIMIZED_HORZ", False);
  for (i = 0; i < n; i++)
    {
      if (atoms[i] != vertical && atoms[i] != horizontal)
        {
          atoms[kept++] = atoms[i];
        }
    }
  if (maximized)
    {
      atoms[kept++] = vertical;
      atoms[kept++] = horizontal;
    }
  x11.changeProperty(display, xwindow,
    x11.internAtom(display, "_NET_WM_STATE", False), XA_ATOM, 32,
    PropModeReplace, (const unsigned char *)atoms, kept);
#endif
}

/* X11: a window is shown maximized by mapping it at its normal frame
   with _NET_WM_STATE saying maximized (GSWindowTabbingWillShowMaximized):
   the window manager maximizes it as it maps it, and keeps the frame it
   was mapped at as the one to restore.  Mapped at the maximized frame,
   un-maximizing it left it filling the screen.
   Windows: the window is shown at frame, and the restore rect comes from
   previous's placement in GSWindowTabbingDidShowMaximized. */
NSRect
GSWindowTabbingFrameToShow(NSWindow *window, NSRect frame, BOOL maximized,
                           NSRect normal, BOOL hasNormal)
{
#if defined(GSWT_HAVE_X11)
  if (maximized && hasNormal)
    {
      return normal;
    }
#endif
  return frame;
}

/* Windows: the window takes previous's restore rect (rcNormalPosition,
   which Windows keeps while it is hidden) with the maximized or normal
   state, in one SetWindowPlacement().  ShowWindow(SW_MAXIMIZE) on a
   window already at the maximized frame made that frame its restore
   rect.  Ordering a window to the top makes it the foreground window
   (libs-back's -orderwindow::: calls SetForegroundWindow()), and so does
   showing it maximized, so when the tab wasn't to be key the window
   that was in front before it was ordered in (front) gets the front
   back, maximized or not. */
void
GSWindowTabbingDidShowMaximized(NSWindow *window, BOOL maximized,
                                NSWindow *previous, BOOL makeKey,
                                intptr_t front)
{
#if defined(_WIN32)
  HWND hwnd = (HWND)(intptr_t)[window windowNumber];
  WINDOWPLACEMENT placement;
  WINDOWPLACEMENT from;
  BOOL hasNormal = NO;
  BOOL zoomed;

  if ([window windowNumber] <= 0)
    {
      return;
    }
  placement.length = sizeof(placement);
  if (GetWindowPlacement(hwnd, &placement) != 0)
    {
      if (previous != nil && [previous windowNumber] > 0)
        {
          from.length = sizeof(from);
          hasNormal = (GetWindowPlacement(
            (HWND)(intptr_t)[previous windowNumber], &from) != 0);
        }
      zoomed = (IsZoomed(hwnd) ? YES : NO);
      if (zoomed != maximized || (maximized && hasNormal))
        {
          if (hasNormal)
            {
              placement.rcNormalPosition = from.rcNormalPosition;
            }
          placement.flags = 0;
          if (maximized)
            {
              placement.showCmd = SW_SHOWMAXIMIZED;
            }
          else
            {
              placement.showCmd = makeKey ? SW_SHOWNORMAL : SW_SHOWNOACTIVATE;
            }
          SetWindowPlacement(hwnd, &placement);
        }
    }
  if (makeKey == NO && front != 0 && (HWND)front != hwnd
    && IsWindow((HWND)front) && GetForegroundWindow() == hwnd)
    {
      SetForegroundWindow((HWND)front);
    }
#endif
}

intptr_t
GSWindowTabbingForegroundWindow(void)
{
#if defined(_WIN32)
  return (intptr_t)GetForegroundWindow();
#else
  return 0;
#endif
}

/* Windows: libs-back's server takes its messages off the thread's queue
   with PeekMessage(), which calls a WH_GETMESSAGE hook with each one,
   in the order the server turns them into events.  The hook keeps
   libs-back's own record of the left button (process_mouse_event()'s
   lDown) and notes each left mouse-up the server will post: a real one
   for WM_LBUTTONUP, and a made-up one for a WM_MOUSEMOVE without
   MK_LBUTTON while the button was down (the release went elsewhere,
   after capture was lost).  Each is noted with the message's time,
   which the server gives the event as its timestamp (GetMessageTime()
   in seconds, as a float).  A mouse-up is told by the noted up nearest
   its timestamp; one that matches nothing noted counts as real, as
   before: the hook watches only while the bar tracks a press, and a
   quick click's release can be taken off the queue before it starts. */
#if defined(_WIN32)
#define GSWT_NOTED_UPS 8
static HHOOK pressWatchHook = NULL;
static unsigned pressWatchDepth = 0;
static BOOL pressWatchDown = NO;
static struct
{
  LONG time;
  BOOL madeUp;
} notedUps[GSWT_NOTED_UPS];
static unsigned notedUpCount = 0;

static void
GSWindowTabbingNoteUp(LONG time, BOOL madeUp)
{
  unsigned i = notedUpCount++ % GSWT_NOTED_UPS;

  notedUps[i].time = time;
  notedUps[i].madeUp = madeUp;
}

static LRESULT CALLBACK
GSWindowTabbingPressWatchProc(int code, WPARAM wParam, LPARAM lParam)
{
  if (code == HC_ACTION && wParam == PM_REMOVE)
    {
      const MSG *msg = (const MSG *)lParam;

      switch (msg->message)
        {
          case WM_LBUTTONDOWN:
            pressWatchDown = YES;
            break;
          case WM_LBUTTONUP:
            GSWindowTabbingNoteUp((LONG)msg->time, NO);
            pressWatchDown = NO;
            break;
          case WM_MOUSEMOVE:
            if (msg->wParam & MK_LBUTTON)
              {
                pressWatchDown = YES;
              }
            else if (pressWatchDown)
              {
                GSWindowTabbingNoteUp((LONG)msg->time, YES);
                pressWatchDown = NO;
              }
            break;
        }
    }
  return CallNextHookEx(pressWatchHook, code, wParam, lParam);
}
#endif

void
GSWindowTabbingBeginPressWatch(void)
{
#if defined(_WIN32)
  if (pressWatchDepth++ == 0)
    {
      /* The bar tracks a press, so the button is down. */
      pressWatchDown = YES;
      notedUpCount = 0;
      pressWatchHook = SetWindowsHookExW(WH_GETMESSAGE,
                                         GSWindowTabbingPressWatchProc,
                                         NULL, GetCurrentThreadId());
    }
#endif
}

BOOL
GSWindowTabbingReleaseWasReal(NSEvent *event)
{
#if defined(_WIN32)
  NSTimeInterval timestamp = [event timestamp];
  NSTimeInterval best = 0.5;
  BOOL madeUp = NO;
  unsigned n = (notedUpCount < GSWT_NOTED_UPS) ? notedUpCount : GSWT_NOTED_UPS;
  unsigned i;

  for (i = 0; i < n; i++)
    {
      /* As libs-back computes it: time = ltime / 1000.0f. */
      NSTimeInterval noted = notedUps[i].time / 1000.0f;
      NSTimeInterval distance = fabs(noted - timestamp);

      if (distance < best || (distance == best && notedUps[i].madeUp == NO))
        {
          best = distance;
          madeUp = notedUps[i].madeUp;
        }
    }
  return madeUp == NO;
#else
  return YES;
#endif
}

void
GSWindowTabbingEndPressWatch(void)
{
#if defined(_WIN32)
  if (pressWatchDepth > 0 && --pressWatchDepth == 0 && pressWatchHook != NULL)
    {
      UnhookWindowsHookEx(pressWatchHook);
      pressWatchHook = NULL;
    }
#endif
}

/* The base address of the loaded object (shared library, bundle or
   executable) that holds address, or NULL when it can't be told. */
static const void *
GSWindowTabbingObjectBase(const void *address)
{
#if defined(_WIN32)
  HMODULE module = NULL;

  if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
                         | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                         (LPCWSTR)address, &module) == 0)
    {
      return NULL;
    }
  return (const void *)module;
#else
  Dl_info info;

  if (dladdr((void *)address, &info) == 0)
    {
      return NULL;
    }
  return info.dli_fbase;
#endif
}

/* Is this copy of the code the one whose classes the runtime kept (see
   +[GSWindowTabbingState _installTabbing])?  The kept class's method
   lives in the same loaded object as this function only then. */
static BOOL
GSWindowTabbingClassesAreOurs(void)
{
  static int ours = -1;

  if (ours < 0)
    {
      Method method;
      const void *classes;
      const void *functions;

      method = class_getClassMethod([GSWindowTabbingState class],
                                    @selector(_installTabbing));
      ours = 1;
      if (method != NULL)
        {
          classes = GSWindowTabbingObjectBase
            ((const void *)method_getImplementation(method));
          functions = GSWindowTabbingObjectBase
            ((const void *)GSWindowTabbingClassesAreOurs);
          if (classes != NULL && functions != NULL && classes != functions)
            {
              ours = 0;
            }
        }
    }
  return ours == 1;
}


/* Copying and wrapping methods. */

/* Adds donor's methods to target where target has none of that name:
   donor is a subclass of target written only to hold them. */
static void
GSWindowTabbingAddMissingMethods(Class donor, Class target)
{
  unsigned int count = 0;
  unsigned int i;
  Method *methods = class_copyMethodList(donor, &count);

  for (i = 0; i < count; i++)
    {
      SEL selector = method_getName(methods[i]);

      if (class_getInstanceMethod(target, selector) == NULL)
        {
          class_addMethod(target, selector,
                          method_getImplementation(methods[i]),
                          method_getTypeEncoding(methods[i]));
        }
    }
  free(methods);
}

/* Replaces cls's method selector with imp, keeping the old one in
   *original.  An inherited method is overridden in cls rather than
   changed in its superclass. */
static void
GSWindowTabbingWrapMethod(Class cls, SEL selector, IMP imp, IMP *original)
{
  Method method = class_getInstanceMethod(cls, selector);

  if (method == NULL)
    {
      *original = NULL;
      return;
    }
  *original = method_getImplementation(method);
  if (class_addMethod(cls, selector, imp,
                      method_getTypeEncoding(method)) == NO)
    {
      method_setImplementation(method, imp);
    }
}


/* The wrappers.  Each calls the tabbing's method, then the original. */

static IMP originalOrderWindow;
static IMP originalSetTitle;
static IMP originalSetTitleWithRepresentedFilename;
static IMP originalSetDocumentEdited;
static IMP originalSendEvent;
static IMP originalPerformKeyEquivalent;
static IMP originalClose;
static IMP originalValidateUserInterfaceItem;
static IMP originalWindowDealloc;
static IMP originalDecorationLayout;
static IMP originalChangeWindowHeight;
static IMP originalContentRectForFrameRect;
static IMP originalFrameRectForContentRect;

/* Upstream: -[NSWindow orderWindow:relativeTo:] begins
   if ([self _tabbingOrderWindow: place]) return; */
static void
GSTabbingOrderWindow(NSWindow *self, SEL _cmd,
                     NSWindowOrderingMode place, NSInteger other)
{
  if ([self _tabbingOrderWindow: place])
    {
      return;
    }
  ((void (*)(id, SEL, NSWindowOrderingMode, NSInteger))originalOrderWindow)
    (self, _cmd, place, other);
}

/* Upstream: -setTitle:, -setTitleWithRepresentedFilename: and
   -setDocumentEdited: end with [self _tabbingTitleDidChange]; */
static void
GSTabbingSetTitle(NSWindow *self, SEL _cmd, NSString *title)
{
  ((void (*)(id, SEL, NSString *))originalSetTitle)(self, _cmd, title);
  [self _tabbingTitleDidChange];
}

static void
GSTabbingSetTitleWithRepresentedFilename(NSWindow *self, SEL _cmd,
                                         NSString *filename)
{
  ((void (*)(id, SEL, NSString *))originalSetTitleWithRepresentedFilename)
    (self, _cmd, filename);
  [self _tabbingTitleDidChange];
}

static void
GSTabbingSetDocumentEdited(NSWindow *self, SEL _cmd, BOOL flag)
{
  ((void (*)(id, SEL, BOOL))originalSetDocumentEdited)(self, _cmd, flag);
  [self _tabbingTitleDidChange];
}

/* Upstream: -performKeyEquivalent: and -sendEvent: begin
   if ([self _tabbingHandleKeyEvent: event]) return YES; (return; in
   -sendEvent:).  NSApp offers a key-down to the key window's
   -performKeyEquivalent: before the window sends it to its first
   responder, so the tab shortcuts come ahead of a text view; -sendEvent:
   catches a key-down sent to the window directly. */
static BOOL
GSTabbingPerformKeyEquivalent(NSWindow *self, SEL _cmd, NSEvent *event)
{
  if ([self _tabbingHandleKeyEvent: event])
    {
      return YES;
    }
  return ((BOOL (*)(id, SEL, NSEvent *))originalPerformKeyEquivalent)
    (self, _cmd, event);
}

static void
GSTabbingSendEvent(NSWindow *self, SEL _cmd, NSEvent *event)
{
  if ([self _tabbingHandleKeyEvent: event])
    {
      return;
    }
  ((void (*)(id, SEL, NSEvent *))originalSendEvent)(self, _cmd, event);
}

/* Upstream: -close begins [self _tabbingWillClose]; */
static void
GSTabbingClose(NSWindow *self, SEL _cmd)
{
  [self _tabbingWillClose];
  ((void (*)(id, SEL))originalClose)(self, _cmd);
}

/* Upstream: -validateUserInterfaceItem: begins
   if ([self _tabbingValidateUserInterfaceItem: item valid: &valid])
     return valid; */
static BOOL
GSTabbingValidateUserInterfaceItem(NSWindow *self, SEL _cmd, id item)
{
  BOOL valid;

  if ([self _tabbingValidateUserInterfaceItem: item valid: &valid])
    {
      return valid;
    }
  return ((BOOL (*)(id, SEL, id))originalValidateUserInterfaceItem)
    (self, _cmd, item);
}

/* Upstream: -dealloc releases the tabbing instance variables. */
static void
GSTabbingWindowDealloc(NSWindow *self, SEL _cmd)
{
  [self _tabbingDealloc];
  ((void (*)(id, SEL))originalWindowDealloc)(self, _cmd);
}

/* Upstream: -[GSWindowDecorationView layout] ends
   [self _layoutTabBar]; */
static void
GSTabbingDecorationLayout(GSWindowDecorationView *self, SEL _cmd)
{
  ((void (*)(id, SEL))originalDecorationLayout)(self, _cmd);
  [self _layoutTabBar];
}

/* Upstream: -[GSWindowDecorationView changeWindowHeight:] keeps the
   window's frame and ends
   [window _tabbingDecorationsDidChangeFromFrame: frame]; */
static void
GSTabbingChangeWindowHeight(GSWindowDecorationView *self, SEL _cmd,
                            CGFloat difference)
{
  NSWindow *window = [self window];
  NSRect frame = [window frame];

  ((void (*)(id, SEL, CGFloat))originalChangeWindowHeight)
    (self, _cmd, difference);
  [window _tabbingDecorationsDidChangeFromFrame: frame];
}

/* Upstream: GSWindowDecorationView's -contentRectForFrameRect:styleMask:
   leaves out the tab bar's row, and -frameRectForContentRect:styleMask:
   adds it, as they do for an in-window menu bar. */
static NSRect
GSTabbingContentRectForFrameRect(GSWindowDecorationView *self, SEL _cmd,
                                 NSRect frame, NSUInteger style)
{
  NSRect content;

  content = ((NSRect (*)(id, SEL, NSRect, NSUInteger))
             originalContentRectForFrameRect)(self, _cmd, frame, style);
  content.size.height -= [[self window] _tabBarReservedHeight];
  return content;
}

static NSRect
GSTabbingFrameRectForContentRect(GSWindowDecorationView *self, SEL _cmd,
                                 NSRect content, NSUInteger style)
{
  content.size.height += [[self window] _tabBarReservedHeight];
  return ((NSRect (*)(id, SEL, NSRect, NSUInteger))
          originalFrameRectForContentRect)(self, _cmd, content, style);
}

/* Wraps the NSWindow and GSWindowDecorationView methods tabbing takes
   part in. */
static void
GSWindowTabbingWrapMethods(void)
{
  Class window = [NSWindow class];
  Class decoration = [GSWindowDecorationView class];

  GSWindowTabbingWrapMethod(window, @selector(orderWindow:relativeTo:),
    (IMP)GSTabbingOrderWindow, &originalOrderWindow);
  GSWindowTabbingWrapMethod(window, @selector(setTitle:),
    (IMP)GSTabbingSetTitle, &originalSetTitle);
  GSWindowTabbingWrapMethod(window,
    @selector(setTitleWithRepresentedFilename:),
    (IMP)GSTabbingSetTitleWithRepresentedFilename,
    &originalSetTitleWithRepresentedFilename);
  GSWindowTabbingWrapMethod(window, @selector(setDocumentEdited:),
    (IMP)GSTabbingSetDocumentEdited, &originalSetDocumentEdited);
  GSWindowTabbingWrapMethod(window, @selector(sendEvent:),
    (IMP)GSTabbingSendEvent, &originalSendEvent);
  GSWindowTabbingWrapMethod(window, @selector(performKeyEquivalent:),
    (IMP)GSTabbingPerformKeyEquivalent, &originalPerformKeyEquivalent);
  GSWindowTabbingWrapMethod(window, @selector(close),
    (IMP)GSTabbingClose, &originalClose);
  GSWindowTabbingWrapMethod(window, @selector(validateUserInterfaceItem:),
    (IMP)GSTabbingValidateUserInterfaceItem,
    &originalValidateUserInterfaceItem);
  GSWindowTabbingWrapMethod(window, @selector(dealloc),
    (IMP)GSTabbingWindowDealloc, &originalWindowDealloc);
  GSWindowTabbingWrapMethod(decoration, @selector(layout),
    (IMP)GSTabbingDecorationLayout, &originalDecorationLayout);
  GSWindowTabbingWrapMethod(decoration, @selector(changeWindowHeight:),
    (IMP)GSTabbingChangeWindowHeight, &originalChangeWindowHeight);
  GSWindowTabbingWrapMethod(decoration,
    @selector(contentRectForFrameRect:styleMask:),
    (IMP)GSTabbingContentRectForFrameRect, &originalContentRectForFrameRect);
  GSWindowTabbingWrapMethod(decoration,
    @selector(frameRectForContentRect:styleMask:),
    (IMP)GSTabbingFrameRectForContentRect, &originalFrameRectForContentRect);
}

#endif /* GS_HAS_WINDOW_TABBING */


/* The public functions. */

NSView *
GSWindowTabBarViewForWindow(NSWindow *window)
{
#ifdef GS_HAS_WINDOW_TABBING
  return nil;
#else /* not GS_HAS_WINDOW_TABBING */
  if (GSWindowTabbingClassesAreOurs() == NO)
    {
      return [GSWindowTabbingState _tabBarViewForWindow: window];
    }
  if (installed == NO)
    {
      return nil;
    }
  return [window _tabBarView];
#endif /* GS_HAS_WINDOW_TABBING */
}

BOOL
GSWindowTabbingInstall(void)
{
#ifdef GS_HAS_WINDOW_TABBING
  return NO;
#else /* not GS_HAS_WINDOW_TABBING */
  Class window;

  if (installed)
    {
      return YES;
    }
  if (GSWindowTabbingClassesAreOurs() == NO)
    {
      return [GSWindowTabbingState _installTabbing];
    }
  if ([NSWindow instancesRespondToSelector:
                 @selector(addTabbedWindow:ordered:)])
    {
      /* Native tabbing (or another copy of this code): nothing to do. */
      return NO;
    }
  installed = YES;
  states = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks,
                            NSObjectMapValueCallBacks, 64);

  window = [NSWindow class];
  GSWindowTabbingAddMissingMethods(NSClassFromString(@"GSWindowTabbingWindow"),
                                   window);
  /* The class methods: the donor's metaclass to NSWindow's. */
  GSWindowTabbingAddMissingMethods(
    object_getClass(NSClassFromString(@"GSWindowTabbingWindow")),
    object_getClass(window));
  GSWindowTabbingAddMissingMethods(
    NSClassFromString(@"GSWindowTabbingDecorationView"),
    [GSWindowDecorationView class]);
  GSWindowTabbingAddMissingMethods(NSClassFromString(@"GSWindowTabbingTheme"),
                                   [GSTheme class]);
  GSWindowTabbingWrapMethods();
  [[NSNotificationCenter defaultCenter]
    addObserver: [GSWindowTabbingState class]
       selector: @selector(_windowFrameDidChange:)
           name: NSWindowDidMoveNotification
         object: nil];
  [[NSNotificationCenter defaultCenter]
    addObserver: [GSWindowTabbingState class]
       selector: @selector(_windowFrameDidChange:)
           name: NSWindowDidResizeNotification
         object: nil];
  return YES;
#endif /* GS_HAS_WINDOW_TABBING */
}
