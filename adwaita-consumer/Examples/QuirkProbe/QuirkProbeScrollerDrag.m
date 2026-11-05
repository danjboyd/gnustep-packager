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

/* -ProbeOnly scroller-drag: overlay scrollers in the corner where two
   meet (below), and staying on screen while
   its knob is dragged, for longer than it lingers. The window's pixels in
   the scroller's strip are read during the drag, from what is in the
   window, not redrawn; and the drag scrolls. Twice: once plainly, once
   with the scroll view tiled each time it scrolls, as MarkdownViewer's
   preview does. */

#import "QuirkProbe.h"

#import <GNUstepGUI/GSTheme.h>

@interface QuirkProbe (ScrollerDragResults)
- (void) pass: (NSString *)ident detail: (NSString *)detail;
- (void) fail: (NSString *)ident detail: (NSString *)detail;
- (void) finish;
@end

/* A tall white page. */
@interface QuirkProbeWhitePage : NSView
@end

@implementation QuirkProbeWhitePage
- (void) drawRect: (NSRect)rect
{
  [[NSColor whiteColor] set];
  NSRectFill (rect);
}

- (BOOL) isOpaque
{
  return YES;
}
@end

/* Tiles its scroll view whenever the content scrolls. */
@interface QuirkProbeTiler : NSObject
{
@public
  NSScrollView *scrollView;
  NSUInteger tiles;
}
@end

@implementation QuirkProbeTiler
- (void) boundsChanged: (NSNotification *)notification
{
  tiles++;
  [scrollView tile];
}
@end

/* One drag of the knob, from a timer in the scroller's tracking loop. */
@interface QuirkProbeScrollerDrag : NSObject
{
@public
  NSWindow *window;
  NSScrollView *scrollView;
  NSPoint start;
  NSInteger step;
  NSInteger steps;
  NSMutableArray *inks;
  BOOL done;
}
@end

@implementation QuirkProbeScrollerDrag

- (NSEvent *) event: (NSEventType)type at: (NSPoint)point
{
  return [NSEvent mouseEventWithType: type
                            location: point
                       modifierFlags: 0
                           timestamp: 0
                        windowNumber: [window windowNumber]
                             context: nil
                         eventNumber: 0
                          clickCount: 1
                            pressure: (type == NSLeftMouseUp ? 0.0 : 1.0)];
}

/* Pixels of the scroller's strip that aren't the white page: the slider
   and its trough, as they are in the window now. */
- (NSUInteger) stripInk
{
  NSScroller *scroller = [scrollView verticalScroller];
  NSView *contentView = [window contentView];
  NSRect strip = [contentView convertRect: [scroller bounds] fromView: scroller];
  NSBitmapImageRep *rep;
  NSUInteger ink = 0;
  NSInteger x, y;

  [contentView lockFocus];
  rep = AUTORELEASE ([[NSBitmapImageRep alloc] initWithFocusedViewRect: NSIntegralRect (strip)]);
  [contentView unlockFocus];
  for (y = 0; y < [rep pixelsHigh]; y++)
    {
      for (x = 0; x < [rep pixelsWide]; x++)
        {
          NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

          if ([color redComponent] < 0.9 || [color greenComponent] < 0.9 || [color blueComponent] < 0.9)
            {
              ink++;
            }
        }
    }
  return ink;
}

- (void) step: (NSTimer *)timer
{
  NSPoint point = NSMakePoint (start.x, start.y - 4.0 * step);

  if (step > 0)
    {
      [inks addObject: [NSNumber numberWithUnsignedInteger: [self stripInk]]];
    }
  step++;
  if (step <= steps)
    {
      [NSApp postEvent: [self event: NSLeftMouseDragged at: point] atStart: NO];
    }
  else
    {
      [timer invalidate];
      [NSApp postEvent: [self event: NSLeftMouseUp at: point] atStart: NO];
      done = YES;
    }
}

@end

@implementation QuirkProbe (ScrollerDrag)

/* Both scrollers of a scroll view at the edges inside its border, the
   content under all of it, the vertical one stopping at the horizontal
   one, and each knob inside its scroller at both ends: the corner looked
   broken, with a strip by the edges and the vertical knob running out of
   its scroller. */
- (void) checkScrollerCornerWithBorder: (NSBorderType)borderType
{
  NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect (100, 100, 300, 220)
                                                 styleMask: NSTitledWindowMask
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
  NSScrollView *scrollView = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (0, 0, 300, 220)]);
  QuirkProbeWhitePage *page = AUTORELEASE ([[QuirkProbeWhitePage alloc] initWithFrame: NSMakeRect (0, 0, 3000, 3000)]);
  NSScroller *vertical, *horizontal;
  NSSize border;
  NSRect inner, verticalFrame, horizontalFrame;
  NSMutableArray *problems = [NSMutableArray array];
  NSString *ident = [NSString stringWithFormat: @"scroller-corner-%@", borderType == NSNoBorder ? @"plain" : @"bezel"];
  int end;

  [scrollView setHasVerticalScroller: YES];
  [scrollView setHasHorizontalScroller: YES];
  [scrollView setBorderType: borderType];
  [scrollView setDocumentView: page];
  [[window contentView] addSubview: scrollView];
  [window orderFront: nil];
  [scrollView tile];
  border = [[GSTheme theme] sizeForBorderType: borderType];
  /* With a border the theme draws libadwaita's frame, and the content
     keeps 4px clear of its rounded corners (plugins-themes-Adwaita#58). */
  if (borderType != NSNoBorder)
    {
      border.width = MAX (border.width, 4.0);
      border.height = MAX (border.height, 4.0);
    }
  inner = NSInsetRect ([scrollView bounds], border.width, border.height);
  vertical = [scrollView verticalScroller];
  horizontal = [scrollView horizontalScroller];
  verticalFrame = [vertical frame];
  horizontalFrame = [horizontal frame];
  if (NSEqualRects ([[scrollView contentView] frame], inner) == NO)
    {
      [problems addObject: [NSString stringWithFormat: @"content %@, inside the border %@",
                                     NSStringFromRect ([[scrollView contentView] frame]), NSStringFromRect (inner)]];
    }
  if (NSMaxX (verticalFrame) != NSMaxX (inner) || NSMaxY (horizontalFrame) != NSMaxY (inner))
    {
      [problems addObject: [NSString stringWithFormat: @"scrollers %@ and %@ not at the edges of %@",
                                     NSStringFromRect (verticalFrame), NSStringFromRect (horizontalFrame),
                                     NSStringFromRect (inner)]];
    }
  if (NSIntersectsRect (verticalFrame, horizontalFrame))
    {
      [problems addObject: [NSString stringWithFormat: @"scrollers overlap: %@ and %@",
                                     NSStringFromRect (verticalFrame), NSStringFromRect (horizontalFrame)]];
    }
  for (end = 0; end < 2; end++)
    {
      NSRect knobs[2];
      NSScroller *scrollers[2] = { vertical, horizontal };
      int i;

      [[scrollView contentView] scrollToPoint: end ? NSMakePoint (2700, 0) : NSMakePoint (0, 2780)];
      [scrollView reflectScrolledClipView: [scrollView contentView]];
      for (i = 0; i < 2; i++)
        {
          knobs[i] = [scrollers[i] rectForPart: NSScrollerKnob];
          if (NSContainsRect ([scrollers[i] bounds], knobs[i]) == NO)
            {
              [problems addObject: [NSString stringWithFormat: @"%@ knob %@ outside %@ at value %g",
                                             i == 0 ? @"vertical" : @"horizontal", NSStringFromRect (knobs[i]),
                                             NSStringFromRect ([scrollers[i] bounds]), [scrollers[i] doubleValue]]];
            }
        }
    }
  [window orderOut: nil];
  if ([problems count] == 0)
    {
      [self pass: ident detail: nil];
    }
  else
    {
      [self fail: ident detail: [problems componentsJoinedByString: @"; "]];
    }
}

/* Drags the knob of a fresh scroll view; the ink of the strip at each step. */
- (NSArray *) scrollerDragInksTiling: (BOOL)tiling tiles: (NSUInteger *)tiles scrolled: (CGFloat *)scrolled
{
  CGFloat before;
  NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect (100, 100, 400, 300)
                                                 styleMask: NSTitledWindowMask
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
  NSScrollView *scrollView = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (0, 0, 400, 300)]);
  QuirkProbeWhitePage *page = AUTORELEASE ([[QuirkProbeWhitePage alloc] initWithFrame: NSMakeRect (0, 0, 380, 6000)]);
  QuirkProbeTiler *tiler = AUTORELEASE ([QuirkProbeTiler new]);
  QuirkProbeScrollerDrag *drag = AUTORELEASE ([QuirkProbeScrollerDrag new]);
  NSScroller *scroller;
  NSRect knob;
  NSTimer *timer;
  NSDate *limit;

  [scrollView setHasVerticalScroller: YES];
  [scrollView setDocumentView: page];
  [[window contentView] addSubview: scrollView];
  [window orderFront: nil];
  [window display];
  if (tiling)
    {
      tiler->scrollView = scrollView;
      [[scrollView contentView] setPostsBoundsChangedNotifications: YES];
      [[NSNotificationCenter defaultCenter] addObserver: tiler
                                               selector: @selector(boundsChanged:)
                                                   name: NSViewBoundsDidChangeNotification
                                                 object: [scrollView contentView]];
    }
  /* Scrolled a little, so the scroller shows and takes the press. */
  [[scrollView contentView] scrollToPoint: NSMakePoint (0, 5600)];
  [scrollView reflectScrolledClipView: [scrollView contentView]];
  [[scrollView contentView] scrollToPoint: NSMakePoint (0, 5000)];
  [scrollView reflectScrolledClipView: [scrollView contentView]];
  [window display];

  scroller = [scrollView verticalScroller];
  knob = [scroller rectForPart: NSScrollerKnob];
  before = NSMinY ([[scrollView contentView] bounds]);
  drag->window = window;
  drag->scrollView = scrollView;
  drag->start = [scroller convertPoint: NSMakePoint (NSMidX (knob), NSMidY (knob)) toView: nil];
  drag->steps = 30;
  drag->inks = [NSMutableArray array];
  /* 30 steps 60ms apart: 1.8s, past the 1s the scroller lingers. */
  timer = [NSTimer timerWithTimeInterval: 0.06 target: drag selector: @selector(step:) userInfo: nil repeats: YES];
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSEventTrackingRunLoopMode];
  [NSApp sendEvent: [drag event: NSLeftMouseDown at: drag->start]];
  limit = [NSDate dateWithTimeIntervalSinceNow: 5.0];
  while (drag->done == NO && [limit timeIntervalSinceNow] > 0)
    {
      [[NSRunLoop currentRunLoop] runMode: NSEventTrackingRunLoopMode
                               beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
    }
  [timer invalidate];
  [[NSNotificationCenter defaultCenter] removeObserver: tiler];
  *tiles = tiler->tiles;
  *scrolled = fabs (NSMinY ([[scrollView contentView] bounds]) - before);
  [window orderOut: nil];
  return drag->inks;
}

- (void) checkScrollerDrag
{
  CGFloat plainScrolled = 0.0;
  int tiling;

  [self checkScrollerCornerWithBorder: NSNoBorder];
  [self checkScrollerCornerWithBorder: NSBezelBorder];

  for (tiling = 0; tiling < 2; tiling++)
    {
      NSUInteger tiles = 0;
      CGFloat scrolled = 0.0;
      NSArray *inks = [self scrollerDragInksTiling: tiling tiles: &tiles scrolled: &scrolled];
      NSUInteger i, gone = 0;
      NSString *ident = tiling ? @"scroller-drag-visible-tiled" : @"scroller-drag-visible";
      NSString *detail;

      for (i = 0; i < [inks count]; i++)
        {
          if ([[inks objectAtIndex: i] unsignedIntegerValue] < 20)
            {
              gone++;
            }
        }
      detail = [NSString stringWithFormat: @"strip ink during the drag %@; %lu of %lu steps without the slider; "
                         @"scrolled %gpt%@",
                         [inks componentsJoinedByString: @","], (unsigned long)gone, (unsigned long)[inks count], scrolled,
                         tiling ? [NSString stringWithFormat: @", %lu tiles", (unsigned long)tiles] : @""];
      if (tiling == 0)
        {
          plainScrolled = scrolled;
        }
      /* Tiled, the drag still scrolls as far: libs-gui forgets the knob is
         dragged when the scroller's frame is set. */
      if ([inks count] >= 20 && gone == 0 && scrolled > 100.0 && scrolled >= 0.9 * plainScrolled)
        {
          [self pass: ident detail: detail];
        }
      else
        {
          [self fail: ident detail: detail];
        }
    }
  [self finish];
}

@end
