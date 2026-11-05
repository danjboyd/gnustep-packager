/** <title>GSWindowTabbingTheme</title>

   <abstract>GSTheme's plain tab bar, the default a theme
   overrides.</abstract>

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

/* GSTheme's tab bar methods.  Upstream they go into a GSTheme category
   in libs-gui (GSThemeDrawing.m or a file of their own) as they are.
   Here they are written in GSWindowTabbingTheme, a subclass of GSTheme
   that is never instantiated: GSWindowTabbingInstall() copies its
   methods into GSTheme where GSTheme has none, so a theme's overrides
   win, as they would over GSTheme's own.  For that reason none of them
   may use super. */

#import "GSWindowTabbingPrivate.h"

NSString *
GSWindowTabFittedTitle(NSString *title, NSDictionary *attributes,
                       CGFloat width)
{
  NSString *ellipsis = [NSString stringWithFormat: @"%C", (unichar)0x2026];
  NSUInteger low = 0;
  NSUInteger high;

  if (title == nil)
    {
      return @"";
    }
  if ([title sizeWithAttributes: attributes].width <= width)
    {
      return title;
    }
  /* A binary search for the longest start that fits with the ellipsis. */
  high = [title length];
  while (low < high)
    {
      NSUInteger middle = (low + high + 1) / 2;
      NSString *candidate;

      candidate = [[title substringToIndex: middle]
                    stringByAppendingString: ellipsis];
      if ([candidate sizeWithAttributes: attributes].width <= width)
        {
          low = middle;
        }
      else
        {
          high = middle - 1;
        }
    }
  if (low == 0)
    {
      return ellipsis;
    }
  return [[title substringToIndex: low] stringByAppendingString: ellipsis];
}

#ifndef GS_HAS_WINDOW_TABBING

/* A cross (the close button) or a plus (the "+" button) in rect, inset
   by inset. */
static void
GSWindowTabDrawCross(NSRect rect, CGFloat inset, BOOL plus)
{
  NSBezierPath *path = [NSBezierPath bezierPath];
  NSRect r = NSInsetRect(rect, inset, inset);

  if (plus)
    {
      [path moveToPoint: NSMakePoint(NSMidX(r), NSMinY(r))];
      [path lineToPoint: NSMakePoint(NSMidX(r), NSMaxY(r))];
      [path moveToPoint: NSMakePoint(NSMinX(r), NSMidY(r))];
      [path lineToPoint: NSMakePoint(NSMaxX(r), NSMidY(r))];
    }
  else
    {
      [path moveToPoint: NSMakePoint(NSMinX(r), NSMinY(r))];
      [path lineToPoint: NSMakePoint(NSMaxX(r), NSMaxY(r))];
      [path moveToPoint: NSMakePoint(NSMinX(r), NSMaxY(r))];
      [path lineToPoint: NSMakePoint(NSMaxX(r), NSMinY(r))];
    }
  [path setLineWidth: 1.5];
  [path stroke];
}

/* The selected tab is the content's colour with a line at each side;
   the others are the bar's, with a separator, and highlighted under the
   pointer. */
static void
GSWindowTabDrawBackground(NSRect rect, GSWindowTabState state)
{
  if (state & GSWindowTabSelected)
    {
      [[NSColor controlBackgroundColor] set];
      NSRectFill(rect);
      [[NSColor controlShadowColor] set];
      NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect),
                            1.0, NSHeight(rect)));
      NSRectFill(NSMakeRect(NSMaxX(rect) - 1.0, NSMinY(rect),
                            1.0, NSHeight(rect)));
      return;
    }
  if (state & GSWindowTabHovered)
    {
      [[NSColor controlHighlightColor] set];
      NSRectFill(rect);
    }
  [[NSColor controlShadowColor] set];
  NSRectFill(NSMakeRect(NSMaxX(rect) - 1.0, NSMinY(rect) + 5.0,
                        1.0, NSHeight(rect) - 10.0));
}

/* The tab's title, centred, a dot before it for unsaved changes, dimmed
   on tabs of a window that isn't key. */
static void
GSWindowTabDrawTitle(NSString *title, NSRect rect, GSWindowTabState state)
{
  NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
  NSColor *textColor = [NSColor controlTextColor];
  NSRect titleRect = NSInsetRect(rect, 26.0, 0.0);
  NSSize size;

  if ((state & (GSWindowTabWindowKey | GSWindowTabSelected)) == 0)
    {
      textColor = [NSColor disabledControlTextColor];
    }
  if (state & GSWindowTabEdited)
    {
      title = [NSString stringWithFormat: @"%C %@", (unichar)0x2022, title];
    }
  [attributes setObject: [NSFont systemFontOfSize: 0.0]
                 forKey: NSFontAttributeName];
  [attributes setObject: textColor forKey: NSForegroundColorAttributeName];
  title = GSWindowTabFittedTitle(title, attributes, NSWidth(titleRect));
  size = [title sizeWithAttributes: attributes];
  [title drawAtPoint: NSMakePoint(floor(NSMidX(titleRect) - size.width / 2.0),
                                  floor(NSMidY(rect) - size.height / 2.0))
      withAttributes: attributes];
}

@interface GSWindowTabbingTheme : GSTheme
@end

@implementation GSWindowTabbingTheme

- (CGFloat) windowTabBarHeightForWindow: (NSWindow *)window
{
  return 28.0;
}

- (GSWindowTabBarPlacement) windowTabBarPlacementForWindow: (NSWindow *)window
{
  return GSWindowTabBarAboveContent;
}

- (CGFloat) windowTabMinimumWidthForWindow: (NSWindow *)window
{
  return 80.0;
}

- (CGFloat) windowTabMaximumWidthForWindow: (NSWindow *)window
{
  return 240.0;
}

- (CGFloat) windowTabNewTabButtonWidthForWindow: (NSWindow *)window
{
  return 28.0;
}

- (CGFloat) windowTabBarMarginForWindow: (NSWindow *)window
{
  return 0.0;
}

- (CGFloat) windowTabSpacingForWindow: (NSWindow *)window
{
  return 0.0;
}

/* 14pt, centred vertically, 6pt from the tab's right edge; shown on
   the selected tab and the one under the pointer. */
- (NSRect) windowTabCloseButtonRectForTabRect: (NSRect)tabRect
                                        state: (GSWindowTabState)state
                                       window: (NSWindow *)window
{
  CGFloat size = 14.0;

  if ((state & (GSWindowTabSelected | GSWindowTabHovered)) == 0)
    {
      return NSZeroRect;
    }
  return NSMakeRect(NSMaxX(tabRect) - 6.0 - size,
                    floor(NSMidY(tabRect) - size / 2.0), size, size);
}

- (void) drawWindowTabBarBackgroundInRect: (NSRect)rect
                                   window: (NSWindow *)window
{
  [[NSColor controlColor] set];
  NSRectFill(rect);
  [[NSColor controlShadowColor] set];
  NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), 1.0));
}

- (void) drawWindowTab: (NSWindowTab *)tab
                inRect: (NSRect)rect
                 state: (GSWindowTabState)state
                window: (NSWindow *)window
{
  GSWindowTabDrawBackground(rect, state);
  GSWindowTabDrawTitle([tab title], rect, state);
}

- (void) drawWindowTabCloseButtonInRect: (NSRect)rect
                                  state: (GSWindowTabState)state
                                 window: (NSWindow *)window
{
  if (state & (GSWindowTabCloseHovered | GSWindowTabClosePressed))
    {
      if (state & GSWindowTabClosePressed)
        {
          [[NSColor controlShadowColor] set];
        }
      else
        {
          [[NSColor controlHighlightColor] set];
        }
      [[NSBezierPath bezierPathWithOvalInRect: rect] fill];
    }
  [[NSColor controlTextColor] set];
  GSWindowTabDrawCross(rect, 4.0, NO);
}

- (void) drawWindowTabNewTabButtonInRect: (NSRect)rect
                                   state: (GSWindowTabState)state
                                  window: (NSWindow *)window
{
  NSRect button = NSInsetRect(rect, 4.0, 4.0);

  if (state & (GSWindowTabHovered | GSWindowTabPressed))
    {
      if (state & GSWindowTabPressed)
        {
          [[NSColor controlShadowColor] set];
        }
      else
        {
          [[NSColor controlHighlightColor] set];
        }
      NSRectFill(button);
    }
  [[NSColor controlTextColor] set];
  GSWindowTabDrawCross(button, 6.0, YES);
}

- (CGFloat) windowTabBarScrollFadeWidthForWindow: (NSWindow *)window
{
  return 24.0;
}

/* The bar's colour, opaque at the edge and clear inwards, over the tabs
   that run out of sight.  In RGB: NSGradient draws nothing from a named
   colour such as controlColor. */
- (void) drawWindowTabBarScrollFadeInRect: (NSRect)rect
                                     edge: (NSRectEdge)edge
                                   window: (NSWindow *)window
{
  NSColor *colour = [[NSColor controlColor]
    colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSGradient *gradient;

  gradient = [[NSGradient alloc]
    initWithStartingColor: colour
              endingColor: [colour colorWithAlphaComponent: 0.0]];
  [gradient drawInRect: rect angle: (edge == NSMinXEdge) ? 0.0 : 180.0];
  RELEASE(gradient);
}

@end

#endif /* GS_HAS_WINDOW_TABBING */
