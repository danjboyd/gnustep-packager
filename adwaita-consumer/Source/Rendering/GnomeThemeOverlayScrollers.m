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

/* libadwaita's overlay scrollbars: the content runs under them, and they
   show only while the content scrolls or the pointer is over them, then
   fade out. At rest a 3px slider 4px from the edge; under the pointer an
   8px one in a faint trough (base.css, scrollbar.overlay-indicator).

   With GNOME's overlay-scrolling off (or GnomeThemeOverlayScrollbars NO)
   the scrollers keep their strips and stay visible while the content
   overflows, as before.

   libs-gui lays the scroll view out (-tile) with the scrollers beside the
   content; here the clip view (and a table's header) is widened under
   them and they're put on top. Overlapping the content brings three
   things to take care of: the clip view must redraw rather than copy its
   pixels on scrolling (it would copy the scroller's along), a scroller's
   redraws go through the scroll view (it's no longer opaque), and a
   hidden scroller lets presses through to the content. */

#import "../GnomeTheme.h"
#import "../Settings/GnomeThemeSettings.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

/* How long the scrollers stay after the last scroll, and how long they
   take to fade. */
static const NSTimeInterval GnomeThemeOverlayLinger = 1.0;
static const NSTimeInterval GnomeThemeOverlayFade = 0.2;
static const NSTimeInterval GnomeThemeOverlayStep = 0.04;

static char GnomeThemeOverlayStateKey;

@interface NSObject (GnomeThemeOverlayScrollers)
- (NSView *) headerView;
@end

BOOL
GnomeThemeUsesOverlayScrollers(void)
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  GSTheme *theme = [GSTheme theme];

  if ([theme isKindOfClass: [GnomeTheme class]] == NO)
    {
      return NO;
    }
  if ([defaults objectForKey: @"GnomeThemeOverlayScrollbars"] != nil)
    {
      return [defaults boolForKey: @"GnomeThemeOverlayScrollbars"];
    }
  return [[(GnomeTheme *)theme settings] overlayScrollingEnabled];
}

/* A scroll view's overlay scrollers: shown how much, the pointer over
   which, when to start fading. */
@interface GnomeThemeOverlayState : NSObject
{
@public
  NSScrollView *scrollView;     /* Not retained: it holds this. */
  CGFloat alpha;
  NSScroller *hovered;          /* Not retained: a subview of scrollView. */
  /* Whose knob is being dragged. Not -hitPart: libs-gui resets that when
     the scroller's frame is set, which -tile does, and apps tile while
     scrolling (MarkdownViewer's preview, on every scroll). */
  NSScroller *dragged;          /* Not retained: a subview of scrollView. */
  NSDate *hideAt;
  NSTimer *timer;
  NSPoint origin;
  BOOL originKnown;
  /* Widening the clip view has libs-gui reflect the scroll and, with
     auto-hiding scrollers, tile again: that nested tile is skipped. */
  BOOL adjusting;
  /* libs-gui's -tile sets the clip view's frame, which reflects the
     scroll; auto-hiding then tiles again, inside it. A tile asked for
     while one runs is noted (retile) and run by the outer one after it
     (#75): nested, they recursed until the stack ran out where libs-gui
     and the overlay layout disagreed on whether a scroller was needed. */
  BOOL tiling;
  BOOL retile;
  NSTrackingRectTag tags[2];
}
- (void) reveal;
- (void) redisplay;
- (void) tick: (NSTimer *)timer;
- (void) stopTimer;
@end

/* The fade timer's target. A timer retains its target, so the state
   can't be: it would outlive its scroll view (which holds it) and tick
   on freed views (plugins-themes-Adwaita#38). The state stops the timer
   and lets go of this when it goes. */
@interface GnomeThemeOverlayTicker : NSObject
{
@public
  GnomeThemeOverlayState *state;        /* Not retained. */
}
@end

@implementation GnomeThemeOverlayTicker

- (void) tick: (NSTimer *)timer
{
  [state tick: timer];
}

@end

static GnomeThemeOverlayState *
GnomeThemeOverlayStateFor(NSScrollView *scrollView, BOOL create)
{
  GnomeThemeOverlayState *state = objc_getAssociatedObject (scrollView, &GnomeThemeOverlayStateKey);

  if (state == nil && create)
    {
      state = AUTORELEASE ([GnomeThemeOverlayState new]);
      state->scrollView = scrollView;
      objc_setAssociatedObject (scrollView, &GnomeThemeOverlayStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  return state;
}

@implementation GnomeThemeOverlayState

- (void) dealloc
{
  [self stopTimer];
  RELEASE (hideAt);
  [super dealloc];
}

- (void) stopTimer
{
  if (timer != nil)
    {
      GnomeThemeOverlayTicker *ticker = [timer userInfo];

      ticker->state = nil;
      [timer invalidate];
      DESTROY (timer);
    }
}

/* The scrollers' strips, redrawn from the scroll view: they aren't
   opaque, and what's under them has to be drawn first. */
- (void) redisplay
{
  NSScroller *scrollers[2] = { [scrollView verticalScroller], [scrollView horizontalScroller] };
  int i;

  for (i = 0; i < 2; i++)
    {
      if (scrollers[i] != nil && [scrollers[i] superview] == scrollView && [scrollers[i] isHidden] == NO)
        {
          [scrollView setNeedsDisplayInRect: [scrollers[i] frame]];
        }
    }
}

- (void) startTimer
{
  if (timer == nil)
    {
      GnomeThemeOverlayTicker *ticker = AUTORELEASE ([GnomeThemeOverlayTicker new]);

      ticker->state = self;
      timer = RETAIN ([NSTimer timerWithTimeInterval: GnomeThemeOverlayStep
                                              target: ticker
                                            selector: @selector(tick:)
                                            userInfo: ticker
                                             repeats: YES]);
      [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSDefaultRunLoopMode];
      [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSEventTrackingRunLoopMode];
      [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSModalPanelRunLoopMode];
    }
}

- (void) reveal
{
  ASSIGN (hideAt, [NSDate dateWithTimeIntervalSinceNow: GnomeThemeOverlayLinger]);
  if (alpha < 1.0)
    {
      alpha = 1.0;
      [self redisplay];
    }
  [self startTimer];
}

- (void) tick: (NSTimer *)aTimer
{
  NSTimeInterval left = [hideAt timeIntervalSinceNow];

  /* Kept while the pointer is over a scroller or its knob is dragged. */
  if (hovered != nil || dragged != nil)
    {
      ASSIGN (hideAt, [NSDate dateWithTimeIntervalSinceNow: GnomeThemeOverlayLinger]);
      return;
    }
  if (left > 0.0)
    {
      return;
    }
  alpha = MAX (0.0, 1.0 + left / GnomeThemeOverlayFade);
  [self redisplay];
  if (alpha <= 0.0)
    {
      [self stopTimer];
    }
}

@end

/* The scroller's slider (and, under the pointer, its trough), at the
   state's opacity. */
static void
GnomeThemeDrawOverlayScroller(NSScroller *scroller, GnomeThemeOverlayState *state)
{
  NSRect bounds = [scroller bounds];
  BOOL horizontal = NSWidth (bounds) >= NSHeight (bounds);
  BOOL hovering = state != nil && state->hovered == scroller;
  BOOL dragging = state != nil && state->dragged == scroller;
  CGFloat alpha = state != nil ? state->alpha : 0.0;
  CGFloat thickness = hovering || dragging ? 8.0 : 3.0;
  CGFloat edge = hovering || dragging ? 3.0 : 4.0;
  NSColor *text = [[NSColor controlTextColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSRect knob = [scroller rectForPart: NSScrollerKnob];
  NSRect slot = [scroller rectForPart: NSScrollerKnobSlot];
  NSRect slider, trough;
  CGFloat inset = 2.0;

  if (alpha <= 0.0 || [scroller knobProportion] >= 0.999 || [scroller isEnabled] == NO || text == nil)
    {
      return;
    }
  if (horizontal)
    {
      CGFloat y = [scroller isFlipped] ? NSMaxY (bounds) - edge - thickness : NSMinY (bounds) + edge;

      slider = NSMakeRect (NSMinX (knob) + inset, y, MAX (0.0, NSWidth (knob) - 2.0 * inset), thickness);
      trough = NSMakeRect (NSMinX (slot) + inset, y, MAX (0.0, NSWidth (slot) - 2.0 * inset), thickness);
    }
  else
    {
      CGFloat x = NSMaxX (bounds) - edge - thickness;

      slider = NSMakeRect (x, NSMinY (knob) + inset, thickness, MAX (0.0, NSHeight (knob) - 2.0 * inset));
      trough = NSMakeRect (x, NSMinY (slot) + inset, thickness, MAX (0.0, NSHeight (slot) - 2.0 * inset));
    }
  if (hovering || dragging)
    {
      [[text colorWithAlphaComponent: [text alphaComponent] * 0.10 * alpha] set];
      [[NSBezierPath bezierPathWithRoundedRect: trough xRadius: thickness / 2.0 yRadius: thickness / 2.0] fill];
    }
  /* The text colour at 20% (40% under the pointer, 60% dragged), with a
     faint dark outline so it shows over any content. */
  [[text colorWithAlphaComponent: [text alphaComponent] * (dragging ? 0.6 : hovering ? 0.4 : 0.2) * alpha] set];
  [[NSBezierPath bezierPathWithRoundedRect: slider xRadius: thickness / 2.0 yRadius: thickness / 2.0] fill];
  [[NSColor colorWithCalibratedWhite: 0.0 alpha: 0.5 * (hovering || dragging ? 0.6 : 0.35) * alpha] set];
  [[NSBezierPath bezierPathWithRoundedRect: NSInsetRect (slider, -0.5, -0.5)
                                   xRadius: thickness / 2.0 + 0.5
                                   yRadius: thickness / 2.0 + 0.5] stroke];
}

/* Tracking rects on the scrollers' strips (whose presses the scrollers
   take only while shown): the pointer reveals and widens them. Owned by
   the scroll view, so they go with it. */
static void
GnomeThemeUpdateOverlayTracking(NSScrollView *scrollView, GnomeThemeOverlayState *state)
{
  NSScroller *scrollers[2] = { [scrollView verticalScroller], [scrollView horizontalScroller] };
  BOOL has[2] = { [scrollView hasVerticalScroller], [scrollView hasHorizontalScroller] };
  int i;

  for (i = 0; i < 2; i++)
    {
      if (state->tags[i] != 0)
        {
          [scrollView removeTrackingRect: state->tags[i]];
          state->tags[i] = 0;
        }
      if ([scrollView window] != nil && has[i] && scrollers[i] != nil && [scrollers[i] isHidden] == NO)
        {
          state->tags[i] = [scrollView addTrackingRect: [scrollers[i] frame]
                                                 owner: scrollView
                                              userData: (void *)scrollers[i]
                                          assumeInside: NO];
        }
    }
}

/* libs-gui's -setFrame: and -setFrameSize: reset the scroller's part to
   none, which ends a knob drag's scrolling (NSScrollView scrolls to the
   knob only while it is the part hit) when an app tiles its scroll view
   during the drag. */
@interface NSScroller (GnomeThemeOverlayScrollers)
- (void) gnomeThemeSetHitPart: (NSScrollerPart)part;
@end

@implementation NSScroller (GnomeThemeOverlayScrollers)
- (void) gnomeThemeSetHitPart: (NSScrollerPart)part
{
  _hitPart = part;
}
@end

/* Whether the theme is tracking this scroller's knob. */
static BOOL
GnomeThemeScrollerIsDragged(NSScroller *scroller)
{
  NSView *superview = [scroller superview];
  GnomeThemeOverlayState *state;

  if ([superview isKindOfClass: [NSScrollView class]] == NO)
    {
      return NO;
    }
  state = GnomeThemeOverlayStateFor ((NSScrollView *)superview, NO);
  return state != nil && state->dragged == scroller;
}

static void GnomeThemeOverlayLayout(NSScrollView *scrollView, GnomeThemeOverlayState *state);

@implementation GnomeTheme (OverlayScrollers)

- (void) _overrideNSScrollViewMethod_tile
{
  typedef void (*TileIMP)(id, SEL);
  TileIMP originalIMP = (TileIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScrollView class]);
  NSScrollView *scrollView = (NSScrollView *)self;
  GnomeThemeOverlayState *state = GnomeThemeOverlayStateFor (scrollView, NO);
  int pass;

  if (state != nil && state->adjusting)
    {
      return;
    }
  if (GnomeThemeUsesOverlayScrollers () == NO)
    {
      if (originalIMP != NULL)
        {
          originalIMP (self, _cmd);
        }
      return;
    }
  state = GnomeThemeOverlayStateFor (scrollView, YES);
  if (state->tiling)
    {
      state->retile = YES;
      return;
    }
  state->tiling = YES;
  /* A scroller shown or hidden during a pass is laid out by the next;
     three at most, where auto-hiding never settles. */
  for (pass = 0; pass < 3; pass++)
    {
      state->retile = NO;
      if (originalIMP != NULL)
        {
          originalIMP (self, _cmd);
        }
      GnomeThemeOverlayLayout (scrollView, state);
      if (state->retile == NO)
        {
          break;
        }
    }
  state->tiling = NO;
  GnomeThemeUpdateOverlayTracking (scrollView, state);
}

/* The overlay layout after libs-gui's -tile: the scrollers over the
   content at the edges, the clip view to those edges. */
static void
GnomeThemeOverlayLayout(NSScrollView *scrollView, GnomeThemeOverlayState *state)
{
  NSClipView *clip;
  NSRect content;
  NSScroller *vertical, *horizontal;
  id documentView;
  NSSize border = [[GSTheme theme] sizeForBorderType: [scrollView borderType]];
  NSRect inner;

  state->adjusting = YES;
  clip = [scrollView contentView];
  content = [clip frame];
  vertical = [scrollView hasVerticalScroller] ? [scrollView verticalScroller] : nil;
  horizontal = [scrollView hasHorizontalScroller] ? [scrollView horizontalScroller] : nil;
  /* The scrollers at the edges inside the border, over the content, which
     runs to those edges. libs-gui reserves its own scroller width there
     and the scroller is narrower, which left a strip by the edges where
     the scroll view showed through, with its line by the corner. */
  inner = NSInsetRect ([scrollView bounds], border.width, border.height);
  /* Inside libadwaita's frame the content keeps clear of its 8px
     corners (-drawScrollViewRect:inView: can't clip it): 4px in. */
  if (GnomeThemeScrollViewHasFrame (scrollView))
    {
      inner = NSInsetRect ([scrollView bounds], MAX (border.width, 4.0), MAX (border.height, 4.0));
    }
  if (vertical != nil && [vertical superview] == scrollView)
    {
      NSRect strip = NSIntersectionRect ([vertical frame], inner);
      BOOL right = NSMidX (strip) >= NSMidX (inner);

      strip.origin.x = right ? NSMaxX (inner) - NSWidth (strip) : NSMinX (inner);
      if (NSEqualRects (strip, [vertical frame]) == NO)
        {
          [vertical setFrame: strip];
        }
      if (right)
        {
          content.size.width = NSMaxX (inner) - NSMinX (content);
        }
      else
        {
          content.size.width = NSMaxX (content) - NSMinX (inner);
          content.origin.x = NSMinX (inner);
        }
    }
  if (horizontal != nil && [horizontal superview] == scrollView)
    {
      NSRect strip = NSIntersectionRect ([horizontal frame], inner);
      BOOL low = NSMidY (strip) >= NSMidY (inner);   /* The scroll view is flipped. */

      strip.origin.y = low ? NSMaxY (inner) - NSHeight (strip) : NSMinY (inner);
      /* Along the edge up to the vertical scroller. */
      if (vertical != nil && [vertical superview] == scrollView && NSMinX ([vertical frame]) >= NSMaxX (strip) - 1.0)
        {
          strip.size.width = NSMinX ([vertical frame]) - NSMinX (strip);
        }
      else if (vertical != nil && [vertical superview] == scrollView && NSMaxX ([vertical frame]) <= NSMinX (strip) + 1.0)
        {
          strip.size.width = NSMaxX (strip) - NSMaxX ([vertical frame]);
          strip.origin.x = NSMaxX ([vertical frame]);
        }
      if (NSEqualRects (strip, [horizontal frame]) == NO)
        {
          [horizontal setFrame: strip];
        }
      /* As GTK's: with both, the vertical one stops at the horizontal one,
         so their sliders don't meet in the corner. */
      if (vertical != nil && [vertical superview] == scrollView)
        {
          NSRect column = [vertical frame];

          if (low && NSMaxY (column) > NSMinY (strip))
            {
              column.size.height = NSMinY (strip) - NSMinY (column);
            }
          else if (low == NO && NSMinY (column) < NSMaxY (strip))
            {
              column.size.height = NSMaxY (column) - NSMaxY (strip);
              column.origin.y = NSMaxY (strip);
            }
          if (NSEqualRects (column, [vertical frame]) == NO)
            {
              [vertical setFrame: column];
            }
        }
      if (low)
        {
          content.size.height = NSMaxY (inner) - NSMinY (content);
        }
      else
        {
          content.size.height = NSMaxY (content) - NSMinY (inner);
          content.origin.y = NSMinY (inner);
        }
    }
  content = NSIntersectionRect (content, inner);
  if (NSEqualRects (content, [clip frame]) == NO)
    {
      [clip setFrame: content];
    }
  [clip setCopiesOnScroll: NO];
  /* A table's header runs as wide as its rows. */
  documentView = [scrollView documentView];
  if ([documentView respondsToSelector: @selector(headerView)])
    {
      NSView *headerClip = [[documentView headerView] superview];

      if ([headerClip superview] == scrollView)
        {
          NSRect header = [headerClip frame];

          header.origin.x = NSMinX (content);
          header.size.width = NSWidth (content);
          [headerClip setFrame: header];
        }
    }
  /* Above the content they overlap. */
  if (vertical != nil && [vertical superview] == scrollView && [[scrollView subviews] lastObject] != vertical)
    {
      RETAIN (vertical);
      [vertical removeFromSuperviewWithoutNeedingDisplay];
      [scrollView addSubview: vertical];
      RELEASE (vertical);
    }
  if (horizontal != nil && [horizontal superview] == scrollView && [[scrollView subviews] lastObject] != horizontal
    && [[scrollView subviews] lastObject] != vertical)
    {
      RETAIN (horizontal);
      [horizontal removeFromSuperviewWithoutNeedingDisplay];
      [scrollView addSubview: horizontal positioned: NSWindowBelow relativeTo: vertical];
      RELEASE (horizontal);
    }
  state->adjusting = NO;
}

/* Freed: its overlay state stops its fade timer and forgets it, even
   where the state itself outlives it (plugins-themes-Adwaita#38). */
- (void) _overrideNSScrollViewMethod_dealloc
{
  typedef void (*DeallocIMP)(id, SEL);
  DeallocIMP originalIMP = (DeallocIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScrollView class]);
  GnomeThemeOverlayState *state = objc_getAssociatedObject (self, &GnomeThemeOverlayStateKey);

  if (state != nil)
    {
      [state stopTimer];
      state->scrollView = nil;
      state->hovered = nil;
      state->dragged = nil;
      objc_setAssociatedObject (self, &GnomeThemeOverlayStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
}

- (void) _overrideNSScrollViewMethod_viewDidMoveToWindow
{
  typedef void (*MovedIMP)(id, SEL);
  MovedIMP originalIMP = (MovedIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScrollView class]);
  GnomeThemeOverlayState *state;

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
  state = GnomeThemeOverlayStateFor ((NSScrollView *)self, NO);
  if (state != nil && GnomeThemeUsesOverlayScrollers ())
    {
      GnomeThemeUpdateOverlayTracking ((NSScrollView *)self, state);
    }
}

/* The content scrolled (by the wheel, the keyboard, the app): show the
   scrollers for a while. The first call only records where it is. */
- (void) _overrideNSScrollViewMethod_reflectScrolledClipView: (NSClipView *)clipView
{
  typedef void (*ReflectIMP)(id, SEL, NSClipView *);
  ReflectIMP originalIMP = (ReflectIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScrollView class]);
  GnomeThemeOverlayState *state;
  NSPoint origin;

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, clipView);
    }
  if (GnomeThemeUsesOverlayScrollers () == NO)
    {
      return;
    }
  state = GnomeThemeOverlayStateFor ((NSScrollView *)self, YES);
  origin = [[(NSScrollView *)self contentView] bounds].origin;
  if (state->originKnown && NSEqualPoints (origin, state->origin) == NO)
    {
      [state reveal];
      /* The clip view redraws what it shows (it doesn't copy on scroll),
         and an opaque document view keeps that as its own invalid rect.
         Where the scrollers' redraws don't cover all of it (the vertical
         scroller stops at the horizontal one's strip, even while that is
         hidden), libs-gui draws the document again after the scrollers,
         over them: the scroller vanishes while its knob is dragged. Redraw
         the clip view's area from the scroll view, so the document is drawn
         first and the scrollers on top. */
      [(NSScrollView *)self setNeedsDisplayInRect: [[(NSScrollView *)self contentView] frame]];
    }
  state->origin = origin;
  state->originKnown = YES;
}

- (void) _overrideNSScrollViewMethod_mouseEntered: (NSEvent *)event
{
  typedef void (*MouseIMP)(id, SEL, NSEvent *);
  GnomeThemeOverlayState *state = GnomeThemeOverlayStateFor ((NSScrollView *)self, NO);

  if (state != nil && ([event trackingNumber] == state->tags[0] || [event trackingNumber] == state->tags[1])
    && [event trackingNumber] != 0)
    {
      state->hovered = (NSScroller *)[event userData];
      [state reveal];
      [state redisplay];
      return;
    }
  {
    MouseIMP originalIMP = (MouseIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScrollView class]);

    if (originalIMP != NULL)
      {
        originalIMP (self, _cmd, event);
      }
  }
}

- (void) _overrideNSScrollViewMethod_mouseExited: (NSEvent *)event
{
  typedef void (*MouseIMP)(id, SEL, NSEvent *);
  GnomeThemeOverlayState *state = GnomeThemeOverlayStateFor ((NSScrollView *)self, NO);

  if (state != nil && ([event trackingNumber] == state->tags[0] || [event trackingNumber] == state->tags[1])
    && [event trackingNumber] != 0)
    {
      state->hovered = nil;
      [state reveal];
      [state redisplay];
      return;
    }
  {
    MouseIMP originalIMP = (MouseIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScrollView class]);

    if (originalIMP != NULL)
      {
        originalIMP (self, _cmd, event);
      }
  }
}

/* The knob is dragged: shown, wide, until the button comes up. */
- (void) _overrideNSScrollerMethod_trackKnob: (NSEvent *)event
{
  typedef void (*TrackIMP)(id, SEL, NSEvent *);
  TrackIMP originalIMP = (TrackIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScroller class]);
  NSView *superview = [(NSView *)self superview];
  GnomeThemeOverlayState *state = nil;

  if (GnomeThemeUsesOverlayScrollers () && [superview isKindOfClass: [NSScrollView class]])
    {
      state = GnomeThemeOverlayStateFor ((NSScrollView *)superview, YES);
      state->dragged = (NSScroller *)self;
      [state reveal];
      [state redisplay];
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, event);
    }
  /* The scroll view may have gone with the drag; its state then forgot it. */
  if (state != nil && state->scrollView != nil)
    {
      state->dragged = nil;
      [state reveal];
      [state redisplay];
    }
}

/* Moved or resized during a knob drag (an app tiling its scroll view):
   still dragging the knob. */
- (void) _overrideNSScrollerMethod_setFrame: (NSRect)frame
{
  typedef void (*SetFrameIMP)(id, SEL, NSRect);
  SetFrameIMP originalIMP = (SetFrameIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScroller class]);
  NSScroller *scroller = (NSScroller *)self;
  NSScrollerPart part = [scroller hitPart];

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, frame);
    }
  if (part == NSScrollerKnob && GnomeThemeScrollerIsDragged (scroller))
    {
      [scroller gnomeThemeSetHitPart: part];
    }
}

- (void) _overrideNSScrollerMethod_setFrameSize: (NSSize)size
{
  typedef void (*SetFrameSizeIMP)(id, SEL, NSSize);
  SetFrameSizeIMP originalIMP = (SetFrameSizeIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScroller class]);
  NSScroller *scroller = (NSScroller *)self;
  NSScrollerPart part = [scroller hitPart];

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, size);
    }
  if (part == NSScrollerKnob && GnomeThemeScrollerIsDragged (scroller))
    {
      [scroller gnomeThemeSetHitPart: part];
    }
}

/* Over the content: see-through. */
- (BOOL) _overrideNSScrollerMethod_isOpaque
{
  typedef BOOL (*OpaqueIMP)(id, SEL);
  OpaqueIMP originalIMP;

  if (GnomeThemeUsesOverlayScrollers () && [[(NSView *)self superview] isKindOfClass: [NSScrollView class]])
    {
      return NO;
    }
  originalIMP = (OpaqueIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScroller class]);
  return originalIMP != NULL ? originalIMP (self, _cmd) : YES;
}

/* A text view's cursor rects stop at the overlay scrollers over it. The
   scroller's own arrow rect isn't enough: a pointer coming straight onto
   the scroller from outside the window enters both rects at once, and
   libs-gui's order leaves the text view's I-beam on top. Done here rather
   than in NSTextView, which installing an override would initialize while
   the theme loads. An autohiding scroll view takes its scroller out of
   the view tree while the content fits, without hiding it: there's nothing
   to stop at then, and converting from it is wrong (a libs-gui that returns
   the rect unchanged left the text no I-beam at all; another one asserts). */
- (void) _overrideNSViewMethod_addCursorRect: (NSRect)rect cursor: (NSCursor *)cursor
{
  typedef void (*AddIMP)(id, SEL, NSRect, NSCursor *);
  AddIMP originalIMP = (AddIMP)GnomeThemeOriginalMethod (_cmd, self, [NSView class]);
  NSView *view = (NSView *)self;

  if ([view isKindOfClass: [NSTextView class]] && GnomeThemeUsesOverlayScrollers ())
    {
      NSScrollView *scrollView = [view enclosingScrollView];
      NSScroller *vertical = [scrollView hasVerticalScroller] ? [scrollView verticalScroller] : nil;
      NSScroller *horizontal = [scrollView hasHorizontalScroller] ? [scrollView horizontalScroller] : nil;

      if (vertical != nil && [vertical isHidden] == NO && [vertical superview] == scrollView
        && [view window] != nil && [vertical window] == [view window])
        {
          NSRect strip = [view convertRect: [vertical bounds] fromView: vertical];

          rect.size.width = MAX (0.0, MIN (NSMaxX (rect), NSMinX (strip)) - NSMinX (rect));
        }
      if (horizontal != nil && [horizontal isHidden] == NO && [horizontal superview] == scrollView
        && [view window] != nil && [horizontal window] == [view window])
        {
          NSRect strip = [view convertRect: [horizontal bounds] fromView: horizontal];

          if ([view isFlipped])
            {
              rect.size.height = MAX (0.0, MIN (NSMaxY (rect), NSMinY (strip)) - NSMinY (rect));
            }
          else
            {
              CGFloat top = NSMaxY (rect);

              rect.origin.y = MAX (NSMinY (rect), NSMaxY (strip));
              rect.size.height = MAX (0.0, top - NSMinY (rect));
            }
        }
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, rect, cursor);
    }
}

/* An overlay scroller lies over the content, whose cursor rects (a text
   view's I-beam) cover it too; over the scroller it's the arrow, as over
   GTK's. A scroller beside its content needs no rect of its own. */
- (void) _overrideNSScrollerMethod_resetCursorRects
{
  typedef void (*ResetIMP)(id, SEL);
  ResetIMP originalIMP = (ResetIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScroller class]);

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
  if (GnomeThemeUsesOverlayScrollers () && [[(NSView *)self superview] isKindOfClass: [NSScrollView class]])
    {
      [(NSView *)self addCursorRect: [(NSView *)self bounds] cursor: [NSCursor arrowCursor]];
    }
}

/* Hidden, a scroller lets presses through to the content under it. */
- (NSView *) _overrideNSScrollerMethod_hitTest: (NSPoint)point
{
  typedef NSView *(*HitIMP)(id, SEL, NSPoint);
  HitIMP originalIMP = (HitIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScroller class]);
  NSView *superview = [(NSView *)self superview];

  if (GnomeThemeUsesOverlayScrollers () && [superview isKindOfClass: [NSScrollView class]])
    {
      GnomeThemeOverlayState *state = GnomeThemeOverlayStateFor ((NSScrollView *)superview, NO);

      if (state == nil || (state->alpha <= 0.0 && state->hovered != (id)self))
        {
          return nil;
        }
    }
  return originalIMP != NULL ? originalIMP (self, _cmd, point) : nil;
}

@end

/* For GnomeThemeControls.m's scroller drawing: YES when it drew (or left
   transparent) an overlay scroller. */
BOOL
GnomeThemeDrawOverlayScrollerIfNeeded(NSScroller *scroller)
{
  NSView *superview = [scroller superview];

  if (GnomeThemeUsesOverlayScrollers () == NO || [superview isKindOfClass: [NSScrollView class]] == NO)
    {
      return NO;
    }
  GnomeThemeDrawOverlayScroller (scroller, GnomeThemeOverlayStateFor ((NSScrollView *)superview, NO));
  return YES;
}
