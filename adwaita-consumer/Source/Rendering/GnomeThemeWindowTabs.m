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

/* Window tabs (Apple's NSWindow tabbing API, from the shared code in
   Source/WindowTabbing) drawn as libadwaita 1.7's AdwTabBar, as in Text
   Editor and Console, measured from Reference/AdwaitaTabBar (#63):

   - a 40pt bar below the header bar, in its colour (the window's);
   - tabs 34pt high, 3pt from the bar's top, of equal width (at least
     126pt, no maximum: they share the bar), 5pt apart, 6pt from each end;
   - the selected tab a rounded rect (6pt) of the foreground at 10% over
     the bar, the one under the pointer at 7%; in high contrast both get a
     1pt outline, the foreground at 50%;
   - between two tabs neither of which is selected, a 1pt separator 27pt
     high in the separator colour (15%, 50% in high contrast);
   - titles in the interface font, regular, centred in the tab, in the
     header bar's text colour (dimmed when the window isn't focused), a
     dot before a document with unsaved changes;
   - a 24pt close button 4pt from the tab's end, on the selected tab and
     the one under the pointer: an 8pt cross, a circle behind it on hover;
   - the "+" (the end action's flat button): 34pt, 6pt from the bar's
     end, a 14pt cross with 2pt strokes.

   Phase 2 (#65): drag and scroll.

   - the dragged tab is AdwTabBar's tab:selected:active, the foreground at
     19% over the bar, opaque, with its close button; no shadow in the bar
     (the shadowed "dnd tab" is the drag icon outside it);
   - where tabs are scrolled out of sight, the bar's colour masks them:
     opaque for the 6pt at the edge of the tabs' area, fading out linearly
     over the next 36pt;
   - a tab from another window over the bar leaves an empty slot, as
     AdwTabBox's placeholder: nothing to draw. */

#import "../GnomeTheme.h"
#import "GSWindowTabbing.h"

#import <AppKit/AppKit.h>

static const CGFloat GnomeThemeTabBarHeight = 40.0;
static const CGFloat GnomeThemeTabHeight = 34.0;
static const CGFloat GnomeThemeTabRadius = 6.0;
static const CGFloat GnomeThemeTabCloseSize = 24.0;
static const CGFloat GnomeThemeTabCloseInset = 4.0;
static const CGFloat GnomeThemeTabTitlePadding = 8.0;
static const CGFloat GnomeThemeTabSeparatorHeight = 27.0;
static const CGFloat GnomeThemeTabSelectedAlpha = 0.10;
static const CGFloat GnomeThemeTabHoverAlpha = 0.07;
static const CGFloat GnomeThemeTabPressedAlpha = 0.16;
static const CGFloat GnomeThemeTabDraggedAlpha = 0.19;
static const CGFloat GnomeThemeTabFadeClear = 6.0;
static const CGFloat GnomeThemeTabFadeLength = 36.0;

/* The foreground at alpha over the bar, as libadwaita's
   alpha(currentColor, …) fills. */
static NSColor *
GnomeThemeTabFill(GnomeTheme *theme, CGFloat alpha)
{
  NSColor *bar = [NSColor windowBackgroundColor];
  NSColor *foreground = GnomeThemeColor (theme, @"GnomeThemeForegroundColor",
                                         [NSColor controlTextColor]);

  return [bar blendedColorWithFraction: alpha ofColor: foreground];
}

/* A tab's drawn part: the full width, 34pt high, centred in the bar. */
static NSRect
GnomeThemeTabShapeRect(NSRect tabRect)
{
  CGFloat height = MIN (GnomeThemeTabHeight, NSHeight (tabRect));

  return NSMakeRect (NSMinX (tabRect), NSMinY (tabRect) + floor ((NSHeight (tabRect) - height) / 2.0),
                     NSWidth (tabRect), height);
}

@implementation GnomeTheme (WindowTabs)

- (CGFloat) windowTabBarHeightForWindow: (NSWindow *)window
{
  return GnomeThemeTabBarHeight;
}

- (CGFloat) windowTabMinimumWidthForWindow: (NSWindow *)window
{
  return 126.0;
}

/* AdwTabBar's tabs share the bar (expand-tabs). */
- (CGFloat) windowTabMaximumWidthForWindow: (NSWindow *)window
{
  return 100000.0;
}

- (CGFloat) windowTabNewTabButtonWidthForWindow: (NSWindow *)window
{
  return 34.0;
}

- (CGFloat) windowTabBarMarginForWindow: (NSWindow *)window
{
  return 6.0;
}

- (CGFloat) windowTabSpacingForWindow: (NSWindow *)window
{
  return 5.0;
}

- (NSRect) windowTabCloseButtonRectForTabRect: (NSRect)tabRect
                                        state: (GSWindowTabState)state
                                       window: (NSWindow *)window
{
  NSRect shape = GnomeThemeTabShapeRect (tabRect);

  if ((state & (GSWindowTabSelected | GSWindowTabHovered | GSWindowTabDragged)) == 0
    || NSWidth (shape) < 2.0 * (GnomeThemeTabCloseSize + GnomeThemeTabCloseInset))
    {
      return NSZeroRect;
    }
  return NSMakeRect (NSMaxX (shape) - GnomeThemeTabCloseInset - GnomeThemeTabCloseSize,
                     NSMidY (shape) - GnomeThemeTabCloseSize / 2.0,
                     GnomeThemeTabCloseSize, GnomeThemeTabCloseSize);
}

- (void) drawWindowTabBarBackgroundInRect: (NSRect)rect
                                   window: (NSWindow *)window
{
  [[NSColor windowBackgroundColor] set];
  NSRectFill (rect);
}

- (void) drawWindowTab: (NSWindowTab *)tab
                inRect: (NSRect)rect
                 state: (GSWindowTabState)state
                window: (NSWindow *)window
{
  NSRect shape = GnomeThemeTabShapeRect (rect);
  NSColor *outline = GnomeThemeColor (self, @"GnomeThemeOutlineColor", nil);
  NSColor *fill = nil;
  NSColor *text = GnomeThemeHeaderBarTextColor (window);
  NSFont *font = [NSFont systemFontOfSize: 0];
  NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
  NSString *title = [tab title];
  NSSize size;
  CGFloat room;

  if (state & GSWindowTabDragged)
    {
      fill = GnomeThemeTabFill (self, GnomeThemeTabDraggedAlpha);
    }
  else if (state & GSWindowTabSelected)
    {
      fill = GnomeThemeTabFill (self, GnomeThemeTabSelectedAlpha);
    }
  else if (state & GSWindowTabPressed)
    {
      fill = GnomeThemeTabFill (self, GnomeThemeTabPressedAlpha);
    }
  else if (state & GSWindowTabHovered)
    {
      fill = GnomeThemeTabFill (self, GnomeThemeTabHoverAlpha);
    }

  if (fill != nil)
    {
      NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect: shape
                                                           xRadius: GnomeThemeTabRadius
                                                           yRadius: GnomeThemeTabRadius];

      [fill set];
      [path fill];
      if (outline != nil)
        {
          path = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect (shape, 0.5, 0.5)
                                                 xRadius: GnomeThemeTabRadius - 0.5
                                                 yRadius: GnomeThemeTabRadius - 0.5];
          [outline set];
          [path setLineWidth: 1.0];
          [path stroke];
        }
    }
  else if ((state & (GSWindowTabFirst | GSWindowTabPreviousHighlighted)) == 0)
    {
      /* Before this tab, in the gap, unless either tab is filled. */
      NSColor *separator = GnomeThemeColor (self, @"GnomeThemeSeparatorColor", [NSColor gridColor]);
      CGFloat spacing = [self windowTabSpacingForWindow: window];
      CGFloat x = floor (NSMinX (shape) - spacing / 2.0);

      [separator set];
      NSRectFill (NSMakeRect (x, NSMidY (shape) - GnomeThemeTabSeparatorHeight / 2.0,
                              1.0, GnomeThemeTabSeparatorHeight));
    }

  if (state & GSWindowTabEdited)
    {
      title = [NSString stringWithFormat: @"%C %@", (unichar)0x2022, title];
    }
  [attributes setObject: font forKey: NSFontAttributeName];
  [attributes setObject: text forKey: NSForegroundColorAttributeName];
  /* Centred in the whole tab, clear of a close button at either end
     where the tab shows one; without one the title has the tab's width
     less its padding, as AdwTab's 126pt tabs show "Document 3.txt" in
     full. */
  if (NSIsEmptyRect ([self windowTabCloseButtonRectForTabRect: rect state: state window: window]))
    {
      room = NSWidth (shape) - 2.0 * GnomeThemeTabTitlePadding;
    }
  else
    {
      room = NSWidth (shape) - 2.0 * (GnomeThemeTabCloseSize + 2.0 * GnomeThemeTabCloseInset);
    }
  title = GSWindowTabFittedTitle (title, attributes, MAX (room, 0.0));
  size = [title sizeWithAttributes: attributes];
  [title drawAtPoint: NSMakePoint (floor (NSMidX (shape) - size.width / 2.0),
                                   floor (NSMidY (shape) - size.height / 2.0))
      withAttributes: attributes];
}

- (void) drawWindowTabCloseButtonInRect: (NSRect)rect
                                  state: (GSWindowTabState)state
                                 window: (NSWindow *)window
{
  NSBezierPath *cross = [NSBezierPath bezierPath];
  NSPoint centre = NSMakePoint (floor (NSMidX (rect)) + 0.5, floor (NSMidY (rect)) + 0.5);
  CGFloat arm = 4.0;

  if (state & (GSWindowTabCloseHovered | GSWindowTabClosePressed))
    {
      CGFloat alpha = (state & GSWindowTabClosePressed) ? GnomeThemeTabPressedAlpha
                                                        : GnomeThemeTabHoverAlpha;
      /* Over the tab's own fill: the flat button's alpha on top of it. */
      NSColor *base = GnomeThemeTabFill (self, (state & GSWindowTabDragged)
                                               ? GnomeThemeTabDraggedAlpha
                                               : GnomeThemeTabSelectedAlpha);
      NSColor *foreground = GnomeThemeColor (self, @"GnomeThemeForegroundColor", [NSColor controlTextColor]);

      [[base blendedColorWithFraction: alpha
                              ofColor: foreground] set];
      [[NSBezierPath bezierPathWithOvalInRect: rect] fill];
    }
  [cross moveToPoint: NSMakePoint (centre.x - arm, centre.y - arm)];
  [cross lineToPoint: NSMakePoint (centre.x + arm, centre.y + arm)];
  [cross moveToPoint: NSMakePoint (centre.x - arm, centre.y + arm)];
  [cross lineToPoint: NSMakePoint (centre.x + arm, centre.y - arm)];
  [cross setLineWidth: 1.5];
  [cross setLineCapStyle: NSRoundLineCapStyle];
  [GnomeThemeHeaderBarTextColor (window) set];
  [cross stroke];
}

- (CGFloat) windowTabBarScrollFadeWidthForWindow: (NSWindow *)window
{
  return GnomeThemeTabFadeClear + GnomeThemeTabFadeLength;
}

/* The bar's colour over the tabs, opaque for 6pt at the edge, then fading
   out linearly over 36pt; a narrower rect (the tabs' area less than twice
   the fade wide) keeps the 6pt and shortens the fade. */
- (void) drawWindowTabBarScrollFadeInRect: (NSRect)rect
                                     edge: (NSRectEdge)edge
                                   window: (NSWindow *)window
{
  NSColor *bar = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  CGFloat clear = MIN (GnomeThemeTabFadeClear, NSWidth (rect));
  NSRect solid, fade;
  NSGradient *gradient;

  if (bar == nil)
    {
      return;
    }
  NSDivideRect (rect, &solid, &fade, clear, edge);
  [bar set];
  NSRectFillUsingOperation (solid, NSCompositeSourceOver);
  if (NSWidth (fade) > 0.0)
    {
      gradient = [[NSGradient alloc] initWithStartingColor: bar
                                               endingColor: [bar colorWithAlphaComponent: 0.0]];
      [gradient drawInRect: fade angle: (edge == NSMinXEdge) ? 0.0 : 180.0];
      RELEASE (gradient);
    }
}

- (void) drawWindowTabNewTabButtonInRect: (NSRect)rect
                                   state: (GSWindowTabState)state
                                  window: (NSWindow *)window
{
  NSRect button = GnomeThemeTabShapeRect (rect);
  NSBezierPath *cross = [NSBezierPath bezierPath];
  NSPoint centre;
  CGFloat arm = 7.0;

  button = NSMakeRect (NSMidX (button) - NSHeight (button) / 2.0, NSMinY (button),
                       NSHeight (button), NSHeight (button));
  if (state & (GSWindowTabHovered | GSWindowTabPressed))
    {
      NSColor *fill = GnomeThemeTabFill (self, (state & GSWindowTabPressed)
                                               ? GnomeThemeTabPressedAlpha
                                               : GnomeThemeTabHoverAlpha);

      [fill set];
      [[NSBezierPath bezierPathWithRoundedRect: button
                                       xRadius: GnomeThemeTabRadius
                                       yRadius: GnomeThemeTabRadius] fill];
    }
  centre = NSMakePoint (floor (NSMidX (button)), floor (NSMidY (button)));
  [cross moveToPoint: NSMakePoint (centre.x - arm, centre.y)];
  [cross lineToPoint: NSMakePoint (centre.x + arm, centre.y)];
  [cross moveToPoint: NSMakePoint (centre.x, centre.y - arm)];
  [cross lineToPoint: NSMakePoint (centre.x, centre.y + arm)];
  [cross setLineWidth: 2.0];
  [GnomeThemeHeaderBarTextColor (window) set];
  [cross stroke];
}

@end
