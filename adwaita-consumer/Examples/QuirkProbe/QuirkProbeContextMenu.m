/* Copyright (C) 2026 Daniel Boyd

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

/* Context menus open as GTK 4's do, by the pointer (#20).

   -ProbeOnly context-menu: where the menu window goes for a right click,
   in the middle of the screen and by its right and bottom edges.
   -ProbeOnly context-menu-demo: a dark window at the screen's top left
   with a context menu, left open, for comparing with GTK's under Mutter
   (Tests/Scripts/measure-context-menu.sh). */

#import "QuirkProbe.h"

@interface QuirkProbe (ContextMenuResults)
- (void) pass: (NSString *)ident detail: (NSString *)detail;
- (void) fail: (NSString *)ident detail: (NSString *)detail;
- (void) finish;
@end

@interface QuirkProbeDarkView : NSView
@end

@implementation QuirkProbeDarkView
- (void) drawRect: (NSRect)rect
{
  [[NSColor colorWithCalibratedWhite: 0.125 alpha: 1.0] set];
  NSRectFill (rect);
}
@end

static NSMenu *
QuirkProbeContextMenu(id target)
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Context"]);
  NSArray *titles = [NSArray arrayWithObjects: @"Cut", @"Copy", @"Paste", @"Select All", nil];
  NSUInteger i;

  for (i = 0; i < [titles count]; i++)
    {
      [[menu addItemWithTitle: [titles objectAtIndex: i] action: @selector(description) keyEquivalent: @""]
        setTarget: target];
    }
  return menu;
}

/* Closes the context menu once its window is placed, noting where. */
@interface QuirkProbeContextMenuWatcher : NSObject
{
@public
  NSMenu *menu;
  NSRect frame;
}
@end

@implementation QuirkProbeContextMenuWatcher
- (void) look: (NSTimer *)timer
{
  NSWindow *menuWindow = [[menu menuRepresentation] window];

  frame = [menuWindow frame];
  /* Releases away from the menu end tracking without choosing; it takes
     both a left and a right one (either alone leaves it tracking). */
  [NSApp postEvent: [NSEvent mouseEventWithType: NSLeftMouseUp
                                       location: NSMakePoint (-50.0, -50.0)
                                  modifierFlags: 0
                                      timestamp: 0
                                   windowNumber: [menuWindow windowNumber]
                                        context: nil
                                    eventNumber: 0
                                     clickCount: 1
                                       pressure: 0.0]
           atStart: NO];
  [NSApp postEvent: [NSEvent mouseEventWithType: NSRightMouseUp
                                       location: NSMakePoint (-50.0, -50.0)
                                  modifierFlags: 0
                                      timestamp: 0
                                   windowNumber: [menuWindow windowNumber]
                                        context: nil
                                    eventNumber: 0
                                     clickCount: 1
                                       pressure: 0.0]
           atStart: NO];
}
@end

@implementation QuirkProbe (ContextMenu)

- (void) showContextMenuDemo
{
  NSRect screen = [[NSScreen mainScreen] frame];
  NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect (0, NSMaxY (screen) - 532, 700, 500)
                                                 styleMask: NSBorderlessWindowMask
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
  QuirkProbeDarkView *view = AUTORELEASE ([[QuirkProbeDarkView alloc] initWithFrame: NSMakeRect (0, 0, 700, 500)]);

  [view setMenu: QuirkProbeContextMenu (self)];
  [window setContentView: view];
  [window setTitle: @"ctx"];
  [window orderFront: nil];
  printf ("# context menu demo up\n");
  fflush (stdout);
}

/* The menu's window frame for a right click at `point` in `window`. */
- (NSRect) contextMenuFrameAt: (NSPoint)point inWindow: (NSWindow *)window
{
  QuirkProbeContextMenuWatcher *watcher = AUTORELEASE ([QuirkProbeContextMenuWatcher new]);
  NSEvent *press = [NSEvent mouseEventWithType: NSRightMouseDown
                                      location: point
                                 modifierFlags: 0
                                     timestamp: 0
                                  windowNumber: [window windowNumber]
                                       context: nil
                                   eventNumber: 0
                                    clickCount: 1
                                      pressure: 1.0];
  NSTimer *timer;

  watcher->menu = QuirkProbeContextMenu (self);
  timer = [NSTimer timerWithTimeInterval: 0.2 target: watcher selector: @selector(look:) userInfo: nil repeats: NO];
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSEventTrackingRunLoopMode];
  [NSMenu popUpContextMenu: watcher->menu withEvent: press forView: [window contentView]];
  return watcher->frame;
}

- (void) checkContextMenu
{
  NSRect screen = [[NSScreen mainScreen] visibleFrame];
  NSWindow *window = [[NSWindow alloc] initWithContentRect: screen
                                                 styleMask: NSBorderlessWindowMask
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
  NSPoint points[3] = { NSMakePoint (NSMidX (screen), NSMidY (screen)),
                        NSMakePoint (NSMaxX (screen) - 20, NSMidY (screen)),
                        NSMakePoint (NSMidX (screen), NSMinY (screen) + 20) };
  NSString *names[3] = { @"middle", @"right edge", @"bottom edge" };
  NSMutableArray *problems = [NSMutableArray array];
  NSMutableArray *frames = [NSMutableArray array];
  int i;

  [window setContentView: AUTORELEASE ([[QuirkProbeDarkView alloc] initWithFrame: screen])];
  [window orderFront: nil];
  [window display];
  for (i = 0; i < 3; i++)
    {
      NSPoint local = [window convertScreenToBase: points[i]];
      NSRect frame = [self contextMenuFrameAt: local inWindow: window];

      [frames addObject: NSStringFromRect (frame)];
      if (NSContainsRect (screen, frame) == NO)
        {
          [problems addObject: [NSString stringWithFormat: @"%@: %@ leaves the screen %@", names[i],
                                         NSStringFromRect (frame), NSStringFromRect (screen)]];
        }
      if (NSPointInRect (points[i], frame))
        {
          [problems addObject: [NSString stringWithFormat: @"%@: the pointer %@ is over the menu %@", names[i],
                                         NSStringFromPoint (points[i]), NSStringFromRect (frame)]];
        }
      if (i == 0 && (NSMinX (frame) != points[i].x || NSMaxY (frame) != points[i].y - 1.0))
        {
          [problems addObject: [NSString stringWithFormat: @"middle: %@, want its top left at (%g, %g)",
                                         NSStringFromRect (frame), points[i].x, points[i].y - 1.0]];
        }
    }
  [window orderOut: nil];
  if ([problems count] == 0)
    {
      [self pass: @"context-menu-place" detail: [frames componentsJoinedByString: @", "]];
    }
  else
    {
      [self fail: @"context-menu-place" detail: [problems componentsJoinedByString: @"; "]];
    }
  [self finish];
}

@end
