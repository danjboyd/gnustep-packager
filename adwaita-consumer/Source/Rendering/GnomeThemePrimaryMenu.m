/*
   Copyright (C) 2025-2026 Daniel Boyd

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

/* GNOME's primary menu instead of a menu bar (GnomeThemeMenuStyle =
   "primary"). The window's menu bar becomes a single ☰ button: in the
   header bar when the theme draws one (GnomeThemeHeaderBar.m), otherwise at
   the end of the toolbar when the window shows one (the toolbar is narrowed
   to make room), otherwise alone in a slim bar styled like a toolbar. Clicking it
   shows a copy of the main menu: its menus, then the application menu's
   items (About, Preferences, Quit), as GNOME's primary menu orders them.
   The app's menu itself is untouched, so key equivalents, validation and
   Services keep working; the copy is made each time it opens, so it shows
   the menu as it is then. */

#import "../GnomeTheme.h"
#import "../Settings/GnomeThemeMetrics.h"

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>

/* libadwaita header bar buttons: 34px, with 6px to the window's edge. */
static const CGFloat GnomeThemePrimaryButtonSize = 34.0;
static const CGFloat GnomeThemePrimaryButtonMargin = 6.0;
/* The bar that holds the button when there's no toolbar. */
static const CGFloat GnomeThemePrimaryBarHeight = 40.0;

/* On a window: the menu bar height it was given (see -menuHeightForWindow:).
   On a toolbar view: its ☰ button. */
static char GnomeThemePrimaryBarHeightKey;
static char GnomeThemePrimaryToolbarButtonKey;

@interface NSWindow (GnomeThemePrimaryMenuPrivate)
- (id) windowView;
- (void) _setMenu: (NSMenu *)menu;
@end

@interface NSView (GnomeThemePrimaryMenuDecoration)
- (void) addMenuView: (NSMenuView *)menuView;
- (NSMenuView *) removeMenuView;
- (void) updateRects;
@end

/* An app's window delegate can say whether the window shows the menu bar
   (and, in the primary menu style, ☰). */
@interface NSObject (GnomeThemeMenuBar)
- (BOOL) windowShouldShowMenuBar: (NSWindow *)window;
@end

@interface NSToolbar (GnomeThemePrimaryMenuPrivate)
- (NSView *) _toolbarView;
@end

BOOL
GnomeThemeUsesPrimaryMenu(void)
{
  NSString *style = [[NSUserDefaults standardUserDefaults] stringForKey: @"GnomeThemeMenuStyle"];
  id declared = [[[NSBundle mainBundle] infoDictionary] objectForKey: @"GnomeThemeMenuStyle"];

  /* The user's default, then the app's own choice in its Info.plist, then
     GNOME's: a GNOME app keeps its menus in the primary menu (☰), with no
     menu bar. */
  if (style == nil && [declared isKindOfClass: [NSString class]])
    {
      style = declared;
    }

  return style == nil || [style caseInsensitiveCompare: @"menubar"] != NSOrderedSame;
}

static BOOL
GnomeThemeWindowShowsToolbar(NSWindow *window)
{
  NSToolbar *toolbar = [window toolbar];

  return toolbar != nil && [toolbar isVisible];
}

/* The height of the bar that holds the ☰: none when the header bar or the
   toolbar holds it. */
static CGFloat
GnomeThemePrimaryBarHeightForWindow(NSWindow *window)
{
  if (GnomeThemeUsesHeaderBar () || GnomeThemeWindowShowsToolbar (window))
    {
      return 0.0;
    }
  return GnomeThemePrimaryBarHeight;
}

static NSMenu *
GnomeThemeCopyPrimaryMenu(void)
{
  NSMenu *mainMenu = [NSApp mainMenu];
  NSMenu *primary = [[NSMenu alloc] initWithTitle: @""];
  NSEnumerator *enumerator = [[mainMenu itemArray] objectEnumerator];
  NSMenuItem *item;
  NSMenuItem *appItem = nil;

  while ((item = [enumerator nextObject]) != nil)
    {
      NSMenuItem *copy;

      if (GnomeThemeIsApplicationMenuItem (item))
        {
          appItem = item;
          continue;
        }
      copy = [item copy];
      [primary addItem: copy];
      RELEASE (copy);
    }
  if ([[appItem submenu] numberOfItems] > 0)
    {
      if ([primary numberOfItems] > 0)
        {
          [primary addItem: [NSMenuItem separatorItem]];
        }
      enumerator = [[[appItem submenu] itemArray] objectEnumerator];
      while ((item = [enumerator nextObject]) != nil)
        {
          NSMenuItem *copy = [item copy];

          [primary addItem: copy];
          RELEASE (copy);
        }
    }
  /* Copies share the originals' targets, actions and states; adding them
     links their copied submenus to the copy. */
  return AUTORELEASE (primary);
}

/* Ends menu tracking without running an item: with nothing highlighted, a
   mouse up ends it. Two are posted: libs-gui 0.32 stops at the first,
   while master (commit a84b42471) ignores a first release when the
   pointer hasn't left the first item; a spare release does nothing. They
   carry no window, which tells them from the user's. */
static BOOL GnomeThemeMenuDismissed = NO;
/* Posted releases not yet fetched: one is left over when the first ends
   tracking, and is dropped rather than reach the next menu or a window. */
static NSUInteger GnomeThemeSpareReleases = 0;
/* Each outermost menu tracking, and the one the spares were posted for. */
static NSUInteger GnomeThemeTrackingSession = 0;
static NSUInteger GnomeThemeSpareSession = 0;

static void
GnomeThemeEndMenuTracking(NSMenu *menu, NSTimeInterval timestamp)
{
  NSEvent *release;

  GnomeThemeMenuDismissed = YES;
  while (menu != nil)
    {
      [[menu menuRepresentation] setHighlightedItemIndex: -1];
      menu = [menu attachedMenu];
    }
  release = [NSEvent mouseEventWithType: NSLeftMouseUp
                               location: NSZeroPoint
                          modifierFlags: 0
                              timestamp: timestamp
                           windowNumber: 0
                                context: nil
                            eventNumber: 0
                             clickCount: 1
                               pressure: 0.0];
  [NSApp postEvent: release atStart: YES];
  [NSApp postEvent: release atStart: NO];
  GnomeThemeSpareReleases = 2;
  GnomeThemeSpareSession = GnomeThemeTrackingSession;
}

/* Escape closes a menu, as it closes GNOME's popovers. GNUstep's menu
   tracking ignores keys, so a timer in the tracking mode looks for it.
   Other keys stay queued for the window. */
@interface GnomeThemeMenuEscape : NSObject
+ (void) closeMenuOnEscape: (NSTimer *)timer;
@end

@implementation GnomeThemeMenuEscape

+ (void) closeMenuOnEscape: (NSTimer *)timer
{
  NSEvent *key = [NSApp nextEventMatchingMask: NSKeyDownMask
                                    untilDate: [NSDate distantPast]
                                       inMode: NSEventTrackingRunLoopMode
                                      dequeue: NO];
  NSMenu *menu = [timer userInfo];

  if (key == nil || [[key charactersIgnoringModifiers] isEqualToString: [NSString stringWithFormat: @"%C", (unichar)0x1b]] == NO)
    {
      return;
    }
  [NSApp nextEventMatchingMask: NSKeyDownMask
                     untilDate: [NSDate distantPast]
                        inMode: NSEventTrackingRunLoopMode
                       dequeue: YES];
  GnomeThemeEndMenuTracking (menu, [key timestamp]);
  [timer invalidate];
}

@end

void
GnomeThemeTrackMenu(NSMenu *menu, NSPoint corner, BOOL rightAligned)
{
  NSMenuView *menuView = [menu menuRepresentation];
  NSWindow *menuWindow;
  NSEvent *press;

  /* Shown as a context menu is, then moved to the corner. */
  [menu displayTransient];
  menuWindow = [menuView window];
  [menuWindow setFrameOrigin: NSMakePoint (rightAligned ? corner.x - NSWidth ([menuWindow frame]) : corner.x,
                                           corner.y - NSHeight ([menuWindow frame]))];
  /* Tracking starts from a fresh press: in libs-gui 0.32 (commit
     82717eefe) any mouse up ends menu tracking, so the release of the
     click that opened the menu would close it again. (Fixed on master by
     a84b42471, not yet released.) Between clicks the menu follows the
     pointer, submenus included. */
  press = [NSEvent mouseEventWithType: NSLeftMouseDown
                             location: [menuWindow mouseLocationOutsideOfEventStream]
                        modifierFlags: 0
                            timestamp: [[NSApp currentEvent] timestamp]
                         windowNumber: [menuWindow windowNumber]
                              context: nil
                          eventNumber: 0
                           clickCount: 1
                             pressure: 1.0];
  [menuView mouseDown: press];
  [menu closeTransient];
}

/* The ☰ button: a flat header bar button, drawn on the toolbar's background
   with the toolbar's bottom edge, so it reads as part of the toolbar or bar
   it sits in. */
@interface GnomeThemePrimaryMenuButton : NSView
{
  NSTrackingRectTag _tracking;
  BOOL _hover;
  BOOL _pressed;
  BOOL _drawsBar;
}
- (void) setDrawsBar: (BOOL)flag;
@end

@implementation GnomeThemePrimaryMenuButton

- (id) initWithFrame: (NSRect)frame
{
  if ((self = [super initWithFrame: frame]) != nil)
    {
      _drawsBar = YES;
      [self setToolTip: @"Main Menu"];
    }
  return self;
}

- (void) setDrawsBar: (BOOL)flag
{
  _drawsBar = flag;
  [self setNeedsDisplay: YES];
}

- (NSRect) buttonRect
{
  NSRect bounds = [self bounds];

  return NSMakeRect (NSMaxX (bounds) - GnomeThemePrimaryButtonMargin - GnomeThemePrimaryButtonSize,
                     floor (NSMidY (bounds) - GnomeThemePrimaryButtonSize / 2.0),
                     GnomeThemePrimaryButtonSize, GnomeThemePrimaryButtonSize);
}

- (void) updateTracking
{
  if (_tracking != 0)
    {
      [self removeTrackingRect: _tracking];
      _tracking = 0;
    }
  if ([self window] != nil)
    {
      _tracking = [self addTrackingRect: [self buttonRect] owner: self userData: NULL assumeInside: NO];
    }
}

- (void) viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  [self updateTracking];
}

- (void) setFrame: (NSRect)frame
{
  [super setFrame: frame];
  [self updateTracking];
}

- (void) mouseEntered: (NSEvent *)event
{
  _hover = YES;
  [self setNeedsDisplay: YES];
}

- (void) mouseExited: (NSEvent *)event
{
  _hover = NO;
  [self setNeedsDisplay: YES];
}

- (void) drawRect: (NSRect)rect
{
  GSTheme *theme = [GSTheme theme];
  NSRect bounds = [self bounds];
  NSColor *background = [theme toolbarBackgroundColor];
  NSColor *textColor = [NSColor controlTextColor];
  NSRect button = [self buttonRect];

  if (_drawsBar)
    {
      [background set];
      NSRectFill (bounds);
      [[theme toolbarBorderColor] set];
      NSRectFill (NSMakeRect (NSMinX (bounds), [self isFlipped] ? NSMaxY (bounds) - 1.0 : NSMinY (bounds),
                              NSWidth (bounds), 1.0));
    }
  /* libadwaita's flat buttons: the text colour at 7% under the pointer,
     16% pressed, 6px corners (as the toolbar's buttons). */
  if (_drawsBar == NO && GnomeThemeUsesHeaderBar ())
    {
      /* In the header bar: on the window's background, dimmed with the
         title when the window isn't focused. */
      background = [NSColor windowBackgroundColor];
      textColor = GnomeThemeHeaderBarTextColor ([self window]);
    }
  if (_hover || _pressed)
    {
      NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect: button xRadius: 6.0 yRadius: 6.0];
      CGFloat fraction = _pressed ? 0.16 : 0.07;

      [[background blendedColorWithFraction: fraction ofColor: textColor] set];
      [path fill];
    }
  GnomeThemeDrawApplicationMenuIcon (button, textColor);
}

- (BOOL) acceptsFirstMouse: (NSEvent *)event
{
  return YES;
}

/* Shows the primary menu under the button, right edges aligned, as
   GNOME's primary menu popover sits. */
- (void) showPrimaryMenu
{
  NSMenu *primary = GnomeThemeCopyPrimaryMenu ();
  NSRect button = [self convertRect: [self buttonRect] toView: nil];

  if ([primary numberOfItems] > 0)
    {
      GnomeThemeTrackMenu (primary, [[self window] convertBaseToScreen: NSMakePoint (NSMaxX (button), NSMinY (button))],
                           YES);
    }
}

/* As a GTK menu button: pressed while the pointer is on it, and the menu
   opens when the click is released there. */
- (void) mouseDown: (NSEvent *)event
{
  NSEvent *current = event;

  if (NSPointInRect ([self convertPoint: [event locationInWindow] fromView: nil], [self buttonRect]) == NO)
    {
      return;
    }
  _pressed = YES;
  [self display];
  while ([current type] != NSLeftMouseUp)
    {
      BOOL inside;

      current = [[self window] nextEventMatchingMask: NSLeftMouseUpMask | NSLeftMouseDraggedMask
                                           untilDate: [NSDate distantFuture]
                                              inMode: NSEventTrackingRunLoopMode
                                             dequeue: YES];
      inside = NSPointInRect ([self convertPoint: [current locationInWindow] fromView: nil], [self buttonRect]);
      if (inside != _pressed)
        {
          _pressed = inside;
          [self display];
        }
    }
  if (_pressed)
    {
      [self showPrimaryMenu];
    }

  _pressed = NO;
  _hover = NSPointInRect ([self convertPoint: [[self window] mouseLocationOutsideOfEventStream] fromView: nil],
                          [self buttonRect]);
  [self setNeedsDisplay: YES];
}

@end

NSView *
GnomeThemeNewHeaderBarMenuButton(void)
{
  GnomeThemePrimaryMenuButton *button = [[GnomeThemePrimaryMenuButton alloc] initWithFrame: NSZeroRect];

  [button setDrawsBar: NO];
  return button;
}

/* The ☰ button's width in a toolbar. */
static CGFloat
GnomeThemePrimaryToolbarButtonWidth(void)
{
  return GnomeThemePrimaryButtonSize + 2.0 * GnomeThemePrimaryButtonMargin;
}

/* Puts a toolbar view's ☰ button beside it (the toolbar is narrowed to
   leave room, see -[GSToolbarView setFrame:]), or takes it away. */
static void
GnomeThemePlaceToolbarButton(NSView *toolbarView)
{
  GnomeThemePrimaryMenuButton *button = objc_getAssociatedObject (toolbarView, &GnomeThemePrimaryToolbarButtonKey);
  NSWindow *window = [toolbarView window];
  NSView *superview = [toolbarView superview];
  BOOL wanted = (window != nil && superview != nil && GnomeThemeUsesPrimaryMenu ()
                 && GnomeThemeUsesHeaderBar () == NO
                 && [window menu] != nil && GnomeThemeWindowShowsToolbar (window));
  NSRect frame = [toolbarView frame];

  if (wanted == NO)
    {
      [button removeFromSuperview];
      return;
    }
  if (button == nil)
    {
      button = AUTORELEASE ([[GnomeThemePrimaryMenuButton alloc] initWithFrame: NSZeroRect]);
      objc_setAssociatedObject (toolbarView, &GnomeThemePrimaryToolbarButtonKey, button,
                                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  [button setFrame: NSMakeRect (NSMaxX (frame), NSMinY (frame),
                                NSMaxX ([superview bounds]) - NSMaxX (frame), NSHeight (frame))];
  [button setAutoresizingMask: NSViewMinXMargin | ([toolbarView autoresizingMask] & (NSViewMinYMargin | NSViewMaxYMargin))];
  if ([button superview] != superview)
    {
      [superview addSubview: button];
    }
  [button setNeedsDisplay: YES];
}

/* Re-lays out a window's menu bar and toolbar for the primary menu: the
   bar's height depends on whether the toolbar shows (the ☰ is in the
   toolbar then), so re-add the menu view when that changed. */
static void
GnomeThemeUpdatePrimaryMenuPlacement(NSWindow *window)
{
  NSView *windowView = [window windowView];
  NSToolbar *toolbar = [window toolbar];
  NSNumber *given = objc_getAssociatedObject (window, &GnomeThemePrimaryBarHeightKey);
  CGFloat wanted = GnomeThemePrimaryBarHeightForWindow (window);

  if ([window menu] != nil && given != nil && [given floatValue] != wanted
    && [windowView respondsToSelector: @selector(removeMenuView)])
    {
      NSMenuView *menuView = RETAIN ([windowView removeMenuView]);

      objc_setAssociatedObject (window, &GnomeThemePrimaryBarHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      if (menuView != nil)
        {
          [windowView addMenuView: menuView];
        }
      RELEASE (menuView);
    }
  if (toolbar != nil && [toolbar respondsToSelector: @selector(_toolbarView)])
    {
      NSView *toolbarView = [toolbar _toolbarView];

      [toolbarView setFrame: [toolbarView frame]];
      GnomeThemePlaceToolbarButton (toolbarView);
    }
}

/* Where a context menu opens: GTK 4's popover menu has its border one
   pixel below the pointer and at its column, so the pointer is just
   outside the menu, not over its first item (measured under Mutter with a
   GtkTextView's menu, #20). libs-gui puts the corner under the pointer. */
static const CGFloat GnomeThemeContextMenuDrop = 1.0;

/* The menu window's origin for a context menu opened at `point` (screen
   coordinates): below and to the right of it, or flipped to the left
   and above where it would leave `screen`, as GTK flips a popover. */
NSPoint
GnomeThemeContextMenuOrigin(NSPoint point, NSSize size, NSRect screen)
{
  NSPoint origin = NSMakePoint (point.x, point.y - GnomeThemeContextMenuDrop - size.height);

  if (origin.x + size.width > NSMaxX (screen))
    {
      origin.x = MAX (NSMinX (screen), point.x - size.width);
    }
  if (origin.y < NSMinY (screen))
    {
      origin.y = MIN (NSMaxY (screen) - size.height, point.y + GnomeThemeContextMenuDrop);
    }
  return origin;
}

@implementation GnomeTheme (PrimaryMenu)

/* A context menu (+popUpContextMenu:withEvent:forView:, a right click):
   opened at GTK's place by the pointer, then tracked from the press as
   libs-gui does. */
- (void) rightMouseDisplay: (NSMenu *)menu forEvent: (NSEvent *)theEvent
{
  NSMenuView *menuView = [menu menuRepresentation];
  NSWindow *menuWindow;
  NSWindow *eventWindow = [theEvent window];
  NSPoint point;
  NSScreen *screen;

  if ([menuView isHorizontal])
    {
      return;
    }
  point = eventWindow != nil ? [eventWindow convertBaseToScreen: [theEvent locationInWindow]] : [NSEvent mouseLocation];
  [menu displayTransient];
  menuWindow = [menuView window];
  screen = [eventWindow screen] ?: [menuWindow screen] ?: [NSScreen mainScreen];
  [menuWindow setFrameOrigin: GnomeThemeContextMenuOrigin (point, [menuWindow frame].size, [screen visibleFrame])];
  [menuView mouseDown: theEvent];
  [menu closeTransient];
}

/* The window's menu bar: a slim bar for the ☰ when there's no toolbar, none
   when the toolbar holds it. The height is kept per window so the menu view
   is removed with the height it was added with. */
- (float) menuHeightForWindow: (NSWindow *)window
{
  NSNumber *given;

  if (GnomeThemeUsesPrimaryMenu () == NO)
    {
      return [super menuHeightForWindow: window];
    }
  given = objc_getAssociatedObject (window, &GnomeThemePrimaryBarHeightKey);
  if (given == nil)
    {
      given = [NSNumber numberWithFloat: GnomeThemePrimaryBarHeightForWindow (window)];
      objc_setAssociatedObject (window, &GnomeThemePrimaryBarHeightKey, given, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  return [given floatValue];
}

/* Whether a window is a preferences window by its title: "Preferences" or
   "Settings", with or without an ellipsis. */
static BOOL
GnomeThemeIsPreferencesTitle(NSString *title)
{
  NSString *trimmed = [title stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];

  if ([trimmed hasSuffix: @"..."])
    {
      trimmed = [trimmed substringToIndex: [trimmed length] - 3];
    }
  else if ([trimmed hasSuffix: [NSString stringWithFormat: @"%C", (unichar)0x2026]])
    {
      trimmed = [trimmed substringToIndex: [trimmed length] - 1];
    }
  return [trimmed isEqualToString: @"Preferences"] || [trimmed isEqualToString: @"Settings"];
}

/* GNOME apps keep their menus in the main window: preferences and other
   auxiliary windows have none (plugins-themes-Adwaita#4). The window's
   delegate decides with -windowShouldShowMenuBar: when it implements it.
   Otherwise a window titled Preferences or Settings goes without, unless it
   is the app's only window that could have the menu bar. Key equivalents
   don't need the bar: NSApplication sends them to the main menu. */
static BOOL
GnomeThemeWindowHidesMenuBar(NSWindow *window)
{
  id delegate = [window delegate];
  NSEnumerator *enumerator;
  NSWindow *other;

  if ([delegate respondsToSelector: @selector(windowShouldShowMenuBar:)])
    {
      return [delegate windowShouldShowMenuBar: window] == NO;
    }
  if (GnomeThemeIsPreferencesTitle ([window title]) == NO)
    {
      return NO;
    }
  enumerator = [[NSApp windows] objectEnumerator];
  while ((other = [enumerator nextObject]) != nil)
    {
      if (other != window && [other canBecomeMainWindow]
        && GnomeThemeIsPreferencesTitle ([other title]) == NO)
        {
          return YES;
        }
    }
  return NO;
}

/* As GSTheme's, with the ☰ button added to the menu view, and the stored
   height dropped between taking the old menu view out and putting the new
   one in. The main menu isn't attached to auxiliary windows. */
- (void) setMenu: (NSMenu *)menu
       forWindow: (NSWindow *)window
{
  id windowView = [window windowView];

  if (menu != nil && menu == [NSApp mainMenu] && GnomeThemeWindowHidesMenuBar (window))
    {
      menu = nil;
    }
  if (GnomeThemeUsesPrimaryMenu () == NO)
    {
      [super setMenu: menu forWindow: window];
      return;
    }
  if ([window menu] == menu)
    {
      return;
    }
  [window _setMenu: menu];
  [windowView removeMenuView];
  objc_setAssociatedObject (window, &GnomeThemePrimaryBarHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  if (menu != nil)
    {
      NSMenuView *menuView = AUTORELEASE ([[NSMenuView alloc] initWithFrame: NSZeroRect]);
      GnomeThemePrimaryMenuButton *button;

      [menuView setMenu: menu];
      [menuView setHorizontal: YES];
      [menuView setInterfaceStyle: NSWindows95InterfaceStyle];
      [windowView addMenuView: menuView];
      [menuView sizeToFit];
      if (GnomeThemeUsesHeaderBar () == NO)
        {
          button = AUTORELEASE ([[GnomeThemePrimaryMenuButton alloc] initWithFrame: [menuView bounds]]);
          [button setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
          [menuView addSubview: button];
        }
    }
  GnomeThemeUpdatePrimaryMenuPlacement (window);
  /* The header bar shows or hides its ☰ with the window's menu. */
  if (GnomeThemeUsesHeaderBar () && [windowView respondsToSelector: @selector(updateRects)])
    {
      [windowView updateRects];
    }
}

/* The menu view holds only the ☰ button, which draws the bar; the menu's
   own titles and clicks are left out. */
- (void) _overrideNSMenuViewMethod_drawRect: (NSRect)rect
{
  typedef void (*DrawIMP)(id, SEL, NSRect);
  DrawIMP originalIMP = (DrawIMP)GnomeThemeOriginalMethod (_cmd, self, [NSMenuView class]);

  if (GnomeThemeUsesPrimaryMenu () && [(NSMenuView *)self isHorizontal])
    {
      return;
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, rect);
    }
}

/* Menus open on the press, as GTK's menu bar and context menus do, and stay
   open when the press's own release lands where it started: a click opens
   a menu, a press, drag and release picks an item. libs-gui master
   (a84b42471) does this itself, ignoring that first release while nothing
   else has happened. In 0.32 any release ends menu tracking (upstream item
   8), so there the theme drops that release while menu tracking runs, as
   master would ignore it; master, which has -[NSImage isTemplate] (added
   after a84b42471, not in 0.32), is left alone. */
static NSMenuView *GnomeThemeTrackingMenuView = nil;
static NSInteger GnomeThemeTrackingFirstIndex = -1;
static BOOL GnomeThemeTrackingIgnoresRelease = NO;

/* A press outside the menus closes them and goes nowhere else, as with
   GTK's menus (GNUstep would pass it to the window under it, and master
   may keep the menu open if the pointer jumped there). The outermost menu
   view tracking, and whether the press's release is still to come. */
static NSMenuView *GnomeThemeTrackingRootView = nil;
static BOOL GnomeThemeDropNextRelease = NO;

static BOOL
GnomeThemeEventIsOutsideMenus(NSEvent *event)
{
  NSWindow *window = [event window];
  NSPoint point = window != nil ? [window convertBaseToScreen: [event locationInWindow]] : [event locationInWindow];
  NSMenuView *root = GnomeThemeTrackingRootView;
  NSMenu *menu = [root menu];

  if ([root isHorizontal])
    {
      NSRect bar = [root convertRect: [root bounds] toView: nil];

      bar.origin = [[root window] convertBaseToScreen: bar.origin];
      if (NSPointInRect (point, bar))
        {
          return NO;
        }
      menu = [menu attachedMenu];
    }
  while (menu != nil)
    {
      NSWindow *menuWindow = [[menu menuRepresentation] window];

      if (menuWindow != nil && [menuWindow isVisible] && NSPointInRect (point, [menuWindow frame]))
        {
          return NO;
        }
      menu = [menu attachedMenu];
    }
  return YES;
}

static BOOL
GnomeThemeMenuTrackingEndsOnFirstRelease(void)
{
  static int ends = -1;

  if (ends < 0)
    {
      ends = [NSImage instancesRespondToSelector: @selector(isTemplate)] ? 0 : 1;
    }
  return ends == 1;
}

/* The item under an event in the tracking menu view: where the event is
   when it's in that view's window, else where the pointer is. */
static NSInteger
GnomeThemeTrackingIndexForEvent(NSEvent *event)
{
  NSMenuView *menuView = GnomeThemeTrackingMenuView;
  NSWindow *window = [menuView window];
  NSPoint location = (event != nil && [event window] == window)
    ? [event locationInWindow] : [window mouseLocationOutsideOfEventStream];

  return [menuView indexOfItemAtPoint: [menuView convertPoint: location fromView: nil]];
}

/* While a menu tracks in 0.32: a press, or the pointer onto another item,
   is something happening, and the release after it ends tracking as
   usual; a release still on the first item is dropped. */
- (NSEvent *) _overrideNSApplicationMethod_nextEventMatchingMask: (NSUInteger)mask
                                                       untilDate: (NSDate *)expiration
                                                          inMode: (NSString *)mode
                                                         dequeue: (BOOL)flag
{
  typedef NSEvent *(*NextIMP)(id, SEL, NSUInteger, NSDate *, NSString *, BOOL);
  NextIMP originalIMP = (NextIMP)GnomeThemeOriginalMethod (_cmd, self, [NSApplication class]);
  NSEvent *event = originalIMP (self, _cmd, mask, expiration, mode, flag);

  while (event != nil && flag)
    {
      NSEventType type = [event type];

      if (GnomeThemeSpareReleases > 0 && type == NSLeftMouseUp && [event windowNumber] == 0)
        {
          GnomeThemeSpareReleases--;
          if (GnomeThemeTrackingRootView == nil || GnomeThemeSpareSession != GnomeThemeTrackingSession)
            {
              event = originalIMP (self, _cmd, mask, expiration, mode, flag);
              continue;
            }
          break;
        }
      if (GnomeThemeDropNextRelease && [event windowNumber] != 0
        && (type == NSLeftMouseUp || type == NSRightMouseUp || type == NSOtherMouseUp))
        {
          GnomeThemeDropNextRelease = NO;
          event = originalIMP (self, _cmd, mask, expiration, mode, flag);
          continue;
        }
      if (GnomeThemeTrackingRootView != nil
        && (type == NSLeftMouseDown || type == NSRightMouseDown || type == NSOtherMouseDown)
        && GnomeThemeEventIsOutsideMenus (event))
        {
          GnomeThemeTrackingIgnoresRelease = NO;
          GnomeThemeDropNextRelease = YES;
          GnomeThemeEndMenuTracking ([GnomeThemeTrackingRootView menu], [event timestamp]);
          event = originalIMP (self, _cmd, mask, expiration, mode, flag);
          continue;
        }
      break;
    }
  while (GnomeThemeTrackingIgnoresRelease && event != nil && flag)
    {
      NSEventType type = [event type];

      if (type == NSLeftMouseDown || type == NSRightMouseDown || type == NSOtherMouseDown)
        {
          GnomeThemeTrackingIgnoresRelease = NO;
        }
      else if (type == NSPeriodic || type == NSLeftMouseDragged || type == NSRightMouseDragged
        || type == NSOtherMouseDragged || type == NSMouseMoved)
        {
          if (GnomeThemeTrackingIndexForEvent (event) != GnomeThemeTrackingFirstIndex)
            {
              GnomeThemeTrackingIgnoresRelease = NO;
            }
        }
      else if (type == NSLeftMouseUp || type == NSRightMouseUp || type == NSOtherMouseUp)
        {
          GnomeThemeTrackingIgnoresRelease = NO;
          if (GnomeThemeTrackingIndexForEvent (event) == GnomeThemeTrackingFirstIndex)
            {
              event = originalIMP (self, _cmd, mask, expiration, mode, flag);
              continue;
            }
        }
      break;
    }
  return event;
}

/* Pop-up buttons open their menu on the press, as the menu bar does, so
   the release of a click that opens one must not end the tracking either:
   it would pick the item under the pointer, the current one, and close the
   menu at once (when the release comes before the tracking starts, as
   while the menu's window is first made, the menu stays open, so this
   showed only from the second opening on). With this, libs-gui ignores
   that release in master; 0.32 has the theme drop it, as for the menu
   bar. A modifier key also closes the menu, and the menu works in modal
   sessions. */
- (BOOL) doesProcessEventsForPopUpMenu
{
  return YES;
}

static BOOL
GnomeThemeMenuIsOwnedByPopUp(NSMenu *menu)
{
  return [menu respondsToSelector: @selector(_ownedByPopUp)]
    && [(id)menu _ownedByPopUp];
}

/* A pop-up button's list keeps its size while it's on screen. Picking an
   item changes the items' states, and -[NSMenu update] then sizes the list
   down to its own width (from the button's) just before it closes. Under
   GNOME on Wayland, Mutter freezes an XWayland window's commits when it's
   resized and thaws them only after its next paint; withdrawn first, the
   list keeps _XWAYLAND_ALLOW_COMMITS at 0, which only the window manager
   may change, so it never shows again (only its first opening did;
   GNOME/mutter#5080, gnustep/libs-gui#964). The next opening sizes the list
   anyway. Elsewhere GNUstep's resize stays, as for tool tips. */
- (void) _overrideNSMenuViewMethod_sizeToFit
{
  typedef void (*SizeIMP)(id, SEL);
  SizeIMP originalIMP = (SizeIMP)GnomeThemeOriginalMethod (_cmd, self, [NSMenuView class]);
  NSMenuView *menuView = (NSMenuView *)self;

  if (GnomeThemeKeepsHiddenWindowSize () && GnomeThemeMenuIsOwnedByPopUp ([menuView menu])
    && [[menuView window] isVisible])
    {
      return;
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
}

/* The menu bar's, transient (context, ☰) and pop-up buttons' menus in
   in-window style: Escape closes them (GNUstep has no key for it), and in
   0.32 the release that ends nothing is dropped (see
   GnomeThemeTrackingMenuView), as master ignores it for these menus. */
- (BOOL) _overrideNSMenuViewMethod_trackWithEvent: (NSEvent *)event
{
  typedef BOOL (*TrackIMP)(id, SEL, NSEvent *);
  TrackIMP originalIMP = (TrackIMP)GnomeThemeOriginalMethod (_cmd, self, [NSMenuView class]);
  NSMenuView *menuView = (NSMenuView *)self;
  NSMenuView *outerView = GnomeThemeTrackingMenuView;
  NSMenuView *outerRoot = GnomeThemeTrackingRootView;
  NSInteger outerIndex = GnomeThemeTrackingFirstIndex;
  BOOL outerIgnores = GnomeThemeTrackingIgnoresRelease;
  BOOL result;

  if (originalIMP == NULL)
    {
      return NO;
    }
  NSTimer *escape;

  if (NSInterfaceStyleForKey (@"NSMenuInterfaceStyle", menuView) != NSWindows95InterfaceStyle
    || ([menuView isHorizontal] == NO && [[menuView menu] isTransient] == NO
      && GnomeThemeMenuIsOwnedByPopUp ([menuView menu]) == NO))
    {
      return originalIMP (self, _cmd, event);
    }
  escape = [NSTimer timerWithTimeInterval: 0.05
                                   target: [GnomeThemeMenuEscape class]
                                 selector: @selector(closeMenuOnEscape:)
                                 userInfo: [menuView menu]
                                  repeats: YES];
  [[NSRunLoop currentRunLoop] addTimer: escape forMode: NSEventTrackingRunLoopMode];
  if (outerRoot == nil)
    {
      GnomeThemeTrackingRootView = menuView;
      GnomeThemeMenuDismissed = NO;
      GnomeThemeTrackingSession++;
    }
  if (GnomeThemeMenuTrackingEndsOnFirstRelease ())
    {
      GnomeThemeTrackingMenuView = menuView;
      GnomeThemeTrackingFirstIndex = GnomeThemeTrackingIndexForEvent (event);
      GnomeThemeTrackingIgnoresRelease = YES;
    }
  NS_DURING
    result = originalIMP (self, _cmd, event);
  NS_HANDLER
    [escape invalidate];
    GnomeThemeTrackingRootView = outerRoot;
    GnomeThemeTrackingMenuView = outerView;
    GnomeThemeTrackingFirstIndex = outerIndex;
    GnomeThemeTrackingIgnoresRelease = outerIgnores;
    [localException raise];
  NS_ENDHANDLER
  [escape invalidate];
  /* Dismissed by Escape or a press outside: master leaves the menu bar's
     menu attached when the pointer isn't on the bar; close it, as master
     does for a modifier key. */
  if (outerRoot == nil && GnomeThemeMenuDismissed && [menuView isHorizontal])
    {
      [menuView setHighlightedItemIndex: -1];
      [[[menuView menu] attachedMenu] close];
    }
  GnomeThemeTrackingRootView = outerRoot;
  GnomeThemeTrackingMenuView = outerView;
  GnomeThemeTrackingFirstIndex = outerIndex;
  GnomeThemeTrackingIgnoresRelease = outerIgnores;
  return result;
}

- (void) _overrideNSMenuViewMethod_mouseDown: (NSEvent *)event
{
  typedef void (*MouseIMP)(id, SEL, NSEvent *);
  MouseIMP originalIMP = (MouseIMP)GnomeThemeOriginalMethod (_cmd, self, [NSMenuView class]);

  if (GnomeThemeUsesPrimaryMenu () && [(NSMenuView *)self isHorizontal]
    && [[(NSMenuView *)self window] menu] == [(NSMenuView *)self menu])
    {
      /* NSMenuView takes its subviews' clicks: pass them to the ☰. */
      NSEnumerator *enumerator = [[(NSView *)self subviews] objectEnumerator];
      NSView *subview;

      while ((subview = [enumerator nextObject]) != nil)
        {
          if ([subview isKindOfClass: [GnomeThemePrimaryMenuButton class]])
            {
              [subview mouseDown: event];
            }
        }
      return;
    }
  if (GnomeThemeMenuBarOverflowMouseDown ((NSMenuView *)self, event))
    {
      return;
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, event);
    }
}

/* A toolbar in a window with the primary menu leaves room at its end for
   the ☰ button. */
- (void) _overrideGSToolbarViewMethod_setFrame: (NSRect)frame
{
  typedef void (*SetFrameIMP)(id, SEL, NSRect);
  SetFrameIMP originalIMP = (SetFrameIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarView"));
  NSView *toolbarView = (NSView *)self;
  NSWindow *window = [toolbarView window];
  NSView *superview = [toolbarView superview];

  if (window != nil && superview != nil && GnomeThemeUsesPrimaryMenu () && [window menu] != nil
    && GnomeThemeUsesHeaderBar () == NO && GnomeThemeWindowShowsToolbar (window))
    {
      frame.size.width = MIN (NSWidth (frame),
                              NSMaxX ([superview bounds]) - NSMinX (frame) - GnomeThemePrimaryToolbarButtonWidth ());
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, frame);
    }
  GnomeThemePlaceToolbarButton (toolbarView);
}

- (void) _overrideGSToolbarViewMethod_viewDidMoveToWindow
{
  typedef void (*MovedIMP)(id, SEL);
  MovedIMP originalIMP = (MovedIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarView"));

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
  if ([(NSView *)self window] == nil)
    {
      GnomeThemePlaceToolbarButton ((NSView *)self);
    }
}

/* A toolbar set or shown after the menu bar, or hidden: move the ☰. */
- (void) _overrideNSWindowMethod_setToolbar: (NSToolbar *)toolbar
{
  typedef void (*SetToolbarIMP)(id, SEL, NSToolbar *);
  SetToolbarIMP originalIMP = (SetToolbarIMP)GnomeThemeOriginalMethod (_cmd, self, [NSWindow class]);
  NSToolbar *old = RETAIN ([(NSWindow *)self toolbar]);

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, toolbar);
    }
  if (GnomeThemeUsesPrimaryMenu ())
    {
      if (old != nil && old != toolbar && [old respondsToSelector: @selector(_toolbarView)])
        {
          GnomeThemePlaceToolbarButton ([old _toolbarView]);
        }
      GnomeThemeUpdatePrimaryMenuPlacement ((NSWindow *)self);
    }
  RELEASE (old);
}

- (void) _overrideNSToolbarMethod_setVisible: (BOOL)flag
{
  typedef void (*SetVisibleIMP)(id, SEL, BOOL);
  SetVisibleIMP originalIMP = (SetVisibleIMP)GnomeThemeOriginalMethod (_cmd, self, [NSToolbar class]);
  NSToolbar *toolbar = (NSToolbar *)self;
  NSView *toolbarView = [toolbar respondsToSelector: @selector(_toolbarView)] ? [toolbar _toolbarView] : nil;
  NSWindow *window = [toolbarView window];

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, flag);
    }
  if (GnomeThemeUsesPrimaryMenu ())
    {
      if (window == nil)
        {
          window = [toolbarView window];
        }
      GnomeThemePlaceToolbarButton (toolbarView);
      if (window != nil)
        {
          GnomeThemeUpdatePrimaryMenuPlacement (window);
        }
    }
}

@end
