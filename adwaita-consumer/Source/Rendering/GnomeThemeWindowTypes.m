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

/* Window types as GTK sets them (_NET_WM_WINDOW_TYPE): menus, tool tips,
   drag images and dialogs. Mutter neither focuses nor animates a menu or
   tool tip, keeps it above other windows and keeps its parent drawn as
   focused; other window managers and compositors key their shadows and
   fades on the type.

   libs-back types windows from their level alone: a context or pop-up
   menu becomes a dialog, a menu bar's menu a torn-off menu, an alert a
   normal window, and a tool tip a dialog because its level is set before
   its class is known (libs-gui#965). A libs-back with the window types of
   Docs/upstream-patches/libs-back-csd.diff sets most of these itself; the
   theme reads the type before writing it, so it then does nothing. */

#import "../GnomeTheme.h"
#import "../Adapters/GnomeThemeWindowManager.h"

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSDragView.h>
#import <objc/runtime.h>

@interface NSObject (GnomeThemeWindowTypesPrivate)
- (NSMenu *) _menu;
@end

static const char *
GnomeThemeMenuWindowType(NSWindow *window, NSMenu *menu)
{
  NSInteger level = [window level];

  if (menu == nil || [menu isTornOff])
    {
      return NULL;
    }
  /* Context menus, pop-up buttons' menus, ☰ and the window menu: shown
     transient at the pop-up menu level. */
  if (level == NSPopUpMenuWindowLevel)
    {
      return "_NET_WM_WINDOW_TYPE_POPUP_MENU";
    }
  /* With an in-window menu bar, a menu opened from it drops down (as
     GtkMenuBar's do) and the menus opened from those pop up. GNUstep's own
     menus (NSNextStepInterfaceStyle) stay open as windows, which is what
     libs-back's _MENU says. */
  if (level == NSSubmenuWindowLevel
    && NSInterfaceStyleForKey (@"NSMenuInterfaceStyle", nil) == NSWindows95InterfaceStyle)
    {
      if ([menu supermenu] != nil && [menu supermenu] == [NSApp mainMenu] && GnomeThemeUsesPrimaryMenu () == NO)
        {
          return "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU";
        }
      return "_NET_WM_WINDOW_TYPE_POPUP_MENU";
    }
  return NULL;
}

/* The type GTK would give the window, or NULL to leave libs-back's. */
static const char *
GnomeThemeWindowType(NSWindow *window)
{
  Class toolTipClass = NSClassFromString (@"GSTTPanel");
  Class menuPanelClass = NSClassFromString (@"NSMenuPanel");

  if (toolTipClass != Nil && [window isKindOfClass: toolTipClass])
    {
      return "_NET_WM_WINDOW_TYPE_TOOLTIP";
    }
  /* The drag view is the content view of the drag window. */
  if ([[window contentView] isKindOfClass: [GSDragView class]])
    {
      return "_NET_WM_WINDOW_TYPE_DND";
    }
  if (menuPanelClass != Nil && [window isKindOfClass: menuPanelClass]
    && [window respondsToSelector: @selector(_menu)])
    {
      return GnomeThemeMenuWindowType (window, [(id)window _menu]);
    }
  /* Alerts, and the open and save panels (GtkFileChooserDialog). */
  if ([window level] == NSModalPanelWindowLevel || [window isKindOfClass: [NSSavePanel class]])
    {
      return "_NET_WM_WINDOW_TYPE_DIALOG";
    }
  return NULL;
}

/* The window an alert interrupts: the main window, else the key window,
   else (the app isn't active) its frontmost titled window that isn't a
   panel. */
static NSWindow *
GnomeThemeAlertParent(NSWindow *alert)
{
  NSWindow *candidates[2] = { [NSApp mainWindow], [NSApp keyWindow] };
  NSEnumerator *enumerator;
  NSWindow *window;
  int i;

  for (i = 0; i < 2; i++)
    {
      if (candidates[i] != nil && candidates[i] != alert && [candidates[i] isVisible])
        {
          return candidates[i];
        }
    }
  enumerator = [[NSApp orderedWindows] objectEnumerator];
  while ((window = [enumerator nextObject]) != nil)
    {
      if (window != alert && [window isVisible] && ([window styleMask] & NSTitledWindowMask)
        && [window isKindOfClass: [NSPanel class]] == NO)
        {
          return window;
        }
    }
  return nil;
}

/* Set on a window made a modal dialog of another, until it's shown. */
static char GnomeThemeAttachedKey;

/* Returns YES when it made the window a modal dialog of another. */
static BOOL
GnomeThemeSetWindowType(NSWindow *window)
{
  const char *type;

  if ([window windowNumber] <= 0)
    {
      return NO;
    }
  type = GnomeThemeWindowType (window);
  if (type != NULL)
    {
      GnomeThemeWindowManagerSetWindowType (window, type);
    }
  /* An alert on its way to the screen is a modal dialog of the window it
     interrupts, as GTK's are: Mutter attaches it (plugins-themes-Adwaita#22). */
  if ([window isVisible] == NO && [window isKindOfClass: NSClassFromString (@"GSAlertPanel")])
    {
      NSWindow *parent = GnomeThemeAlertParent (window);

      if (parent != nil && GnomeThemeWindowManagerSetModalParent (window, parent))
        {
          objc_setAssociatedObject (window, &GnomeThemeAttachedKey, [NSNumber numberWithBool: YES],
                                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          return YES;
        }
    }
  return NO;
}

@implementation GnomeTheme (WindowTypes)

/* For QuirkProbe, which runs with no window manager to set the type for. */
+ (NSString *) windowTypeForWindow: (NSWindow *)window
{
  const char *type = GnomeThemeWindowType (window);

  return type != NULL ? [NSString stringWithUTF8String: type] : nil;
}

/* For QuirkProbe: "WM_DELETE_WINDOW yes, close yes" and so on, or nil
   when there's no X window to read. */
+ (NSString *) windowManagerCloseStateForWindow: (NSWindow *)window
{
  BOOL listed, allowed;

  if (GnomeThemeWindowManagerCloseState (window, &listed, &allowed) == NO)
    {
      return nil;
    }
  return [NSString stringWithFormat: @"WM_DELETE_WINDOW %@, close %@",
                   listed ? @"yes" : @"no", allowed ? @"yes" : @"no"];
}

/* A deferred window gets its X window here, on its way to the screen:
   typed before it's mapped. */
- (void) _overrideNSWindowMethod__initBackendWindow
{
  typedef void (*InitBackendWindowIMP)(id, SEL);
  InitBackendWindowIMP originalIMP
    = (InitBackendWindowIMP)GnomeThemeOriginalMethod (_cmd, self, [NSWindow class]);

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
  GnomeThemeSetWindowType ((NSWindow *)self);
}

/* libs-back types the window again for its new level. */
- (void) _overrideNSWindowMethod_setLevel: (NSInteger)level
{
  typedef void (*SetLevelIMP)(id, SEL, NSInteger);
  SetLevelIMP originalIMP = (SetLevelIMP)GnomeThemeOriginalMethod (_cmd, self, [NSWindow class]);

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, level);
    }
  GnomeThemeSetWindowType ((NSWindow *)self);
}

/* A window made at once, not deferred, got its X window before it was
   known what it's for (a menu's window before its menu was set). */
- (void) _overrideNSWindowMethod_orderWindow: (NSWindowOrderingMode)place
                                  relativeTo: (NSInteger)otherWindow
{
  typedef void (*OrderWindowIMP)(id, SEL, NSWindowOrderingMode, NSInteger);
  OrderWindowIMP originalIMP = (OrderWindowIMP)GnomeThemeOriginalMethod (_cmd, self, [NSWindow class]);

  BOOL attached;

  if (place != NSWindowOut)
    {
      GnomeThemeSetWindowType ((NSWindow *)self);
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, place, otherWindow);
    }
  if (place != NSWindowOut)
    {
      GnomeThemeWindowManagerWindowOrderedIn ((NSWindow *)self);
    }
  /* Attached here or, for a deferred window, as its X window was made. */
  attached = place != NSWindowOut && [objc_getAssociatedObject (self, &GnomeThemeAttachedKey) boolValue];
  objc_setAssociatedObject (self, &GnomeThemeAttachedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  /* libs-back asks for the focus before the window manager has mapped the
     window, which fails, and ignores the window manager's first offer of
     it (WM_TAKE_FOCUS) after mapping: an attached dialog would be left
     without the keyboard. Ask again once it's on the screen. */
  if (attached)
    {
      [(NSWindow *)self performSelector: @selector(makeKeyWindow)
                             withObject: nil
                             afterDelay: 0.2
                                inModes: [NSArray arrayWithObjects: NSDefaultRunLoopMode,
                                                  NSModalPanelRunLoopMode, nil]];
    }
}

@end
