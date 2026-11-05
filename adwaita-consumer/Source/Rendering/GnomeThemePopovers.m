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

/* An application's popover panels as libadwaita's popover (#74).

   A window that conforms to the protocol GSThemePopoverPanel (checked by
   name, so neither side links the other) is a popover the theme draws:
   the app opts in when the theme's Info-gnustep.plist says
   GSThemeDrawsPopoverPanels, leaves the window clear, and its content view
   draws nothing. The theme draws the body: the menu's colour and border
   with 15pt corners, as its menus and combo box lists. With
   GSThemeDrawsPopoverArrows the panel also says where its arrow goes
   (-popoverArrowEdge, -popoverArrowPosition, -popoverArrowHeight,
   -popoverArrowWidth): the body is the window less the arrow's height on
   that edge, and the theme draws the arrow there, as GtkPopover's tail.

   The window is marked as a popover (NSUtilityWindowMask, as the theme's
   menus), so a libs-back with popover shadows gives it libadwaita's
   popover shadow. With an arrow, the theme tells that libs-back where the
   body is (-setPopoverBodyInsetLeft:right:top:bottom::), so the shadow
   follows the body and the arrow lies over it, as GTK 4 draws it. */

#import "../GnomeTheme.h"
#import "../Adapters/GnomeThemeWindowManager.h"

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <math.h>

/* libadwaita 1.7's popover: 15px corners, as its menus. */
static const CGFloat GnomeThemePopoverCornerRadius = 15.0;

@interface NSObject (GnomeThemePopoverPanel)
- (NSRectEdge) popoverArrowEdge;
- (CGFloat) popoverArrowPosition;
- (CGFloat) popoverArrowHeight;
- (CGFloat) popoverArrowWidth;
@end

@interface GSDisplayServer (GnomeThemePopoverBodyInset)
- (void) setPopoverBodyInsetLeft: (float)left
                           right: (float)right
                             top: (float)top
                          bottom: (float)bottom
                                : (int)win;
@end

static BOOL
GnomeThemeInfoFlag(NSString *key)
{
  id value = [[[GSTheme theme] infoDictionary] objectForKey: key];

  return [value respondsToSelector: @selector(boolValue)] && [value boolValue];
}

/* A window the theme draws as a popover: its class conforms to
   GSThemePopoverPanel, and this theme says it draws them. */
static BOOL
GnomeThemeIsPopoverPanel(NSWindow *window)
{
  static Protocol *protocol = nil;
  static BOOL looked = NO;

  if (looked == NO)
    {
      protocol = NSProtocolFromString (@"GSThemePopoverPanel");
      looked = YES;
    }
  return window != nil && protocol != nil
    && [window conformsToProtocol: protocol]
    && GnomeThemeInfoFlag (@"GSThemeDrawsPopoverPanels");
}

/* The arrow's height, edge, the middle of its base along that edge, and
   its base's width; NO when the popover has none. */
static BOOL
GnomeThemePopoverArrow(NSWindow *window, NSRectEdge *edge, CGFloat *position,
                       CGFloat *height, CGFloat *width)
{
  if (GnomeThemeInfoFlag (@"GSThemeDrawsPopoverArrows") == NO
    || [window respondsToSelector: @selector(popoverArrowHeight)] == NO
    || [window respondsToSelector: @selector(popoverArrowEdge)] == NO
    || [window respondsToSelector: @selector(popoverArrowPosition)] == NO
    || [window respondsToSelector: @selector(popoverArrowWidth)] == NO)
    {
      return NO;
    }
  *height = floor ([(id)window popoverArrowHeight]);
  *width = floor ([(id)window popoverArrowWidth]);
  *edge = [(id)window popoverArrowEdge];
  *position = [(id)window popoverArrowPosition];
  return *height > 0.0 && *width > 0.0;
}

/* The popover's body (the window less the arrow) and its outline, the
   arrow's sides included, as one path. */
static NSBezierPath *
GnomeThemePopoverPath(NSRect bounds, BOOL hasArrow, NSRectEdge edge,
                      CGFloat position, CGFloat height, CGFloat width,
                      NSRect *bodyOut)
{
  NSRect body = bounds;
  CGFloat r = GnomeThemePopoverCornerRadius;
  NSBezierPath *path = [NSBezierPath bezierPath];
  CGFloat minX, maxX, minY, maxY;
  CGFloat half = floor (width / 2.0);
  CGFloat low, high, mid;

  if (hasArrow)
    {
      switch (edge)
        {
          case NSMaxYEdge: body.size.height -= height; break;
          case NSMinYEdge: body.origin.y += height; body.size.height -= height; break;
          case NSMinXEdge: body.origin.x += height; body.size.width -= height; break;
          default: body.size.width -= height; break;
        }
    }
  body = NSInsetRect (body, 0.5, 0.5);
  if (bodyOut != NULL)
    {
      *bodyOut = body;
    }
  minX = NSMinX (body); maxX = NSMaxX (body);
  minY = NSMinY (body); maxY = NSMaxY (body);
  r = MIN (r, MIN (NSWidth (body), NSHeight (body)) / 2.0);

  /* The arrow's base keeps clear of the rounded corners. */
  if (edge == NSMaxYEdge || edge == NSMinYEdge)
    {
      low = minX + r + half;
      high = maxX - r - half;
    }
  else
    {
      low = minY + r + half;
      high = maxY - r - half;
    }
  hasArrow = hasArrow && low <= high;
  mid = floor (MIN (MAX (position, low), high)) + 0.5;

  /* Counter-clockwise from the bottom left corner's end. */
  [path moveToPoint: NSMakePoint (minX + r, minY)];
  if (hasArrow && edge == NSMinYEdge)
    {
      [path lineToPoint: NSMakePoint (mid - half, minY)];
      [path lineToPoint: NSMakePoint (mid, minY - height)];
      [path lineToPoint: NSMakePoint (mid + half, minY)];
    }
  [path appendBezierPathWithArcWithCenter: NSMakePoint (maxX - r, minY + r)
                                   radius: r startAngle: 270.0 endAngle: 360.0];
  if (hasArrow && edge == NSMaxXEdge)
    {
      [path lineToPoint: NSMakePoint (maxX, mid - half)];
      [path lineToPoint: NSMakePoint (maxX + height, mid)];
      [path lineToPoint: NSMakePoint (maxX, mid + half)];
    }
  [path appendBezierPathWithArcWithCenter: NSMakePoint (maxX - r, maxY - r)
                                   radius: r startAngle: 0.0 endAngle: 90.0];
  if (hasArrow && edge == NSMaxYEdge)
    {
      [path lineToPoint: NSMakePoint (mid + half, maxY)];
      [path lineToPoint: NSMakePoint (mid, maxY + height)];
      [path lineToPoint: NSMakePoint (mid - half, maxY)];
    }
  [path appendBezierPathWithArcWithCenter: NSMakePoint (minX + r, maxY - r)
                                   radius: r startAngle: 90.0 endAngle: 180.0];
  if (hasArrow && edge == NSMinXEdge)
    {
      [path lineToPoint: NSMakePoint (minX, mid + half)];
      [path lineToPoint: NSMakePoint (minX - height, mid)];
      [path lineToPoint: NSMakePoint (minX, mid - half)];
    }
  [path appendBezierPathWithArcWithCenter: NSMakePoint (minX + r, minY + r)
                                   radius: r startAngle: 180.0 endAngle: 270.0];
  [path closePath];
  return path;
}

/* Tells a libs-back with popover shadows where the body is, so its
   shadow follows the body rather than the window. */
static void
GnomeThemeSetPopoverBodyInset(NSWindow *window, BOOL hasArrow,
                              NSRectEdge edge, CGFloat height)
{
  GSDisplayServer *server = GSServerForWindow (window);
  float inset[4] = { 0.0, 0.0, 0.0, 0.0 };

  if ([window windowNumber] <= 0
    || [server respondsToSelector:
         @selector(setPopoverBodyInsetLeft:right:top:bottom::)] == NO)
    {
      return;
    }
  if (hasArrow)
    {
      switch (edge)
        {
          case NSMinXEdge: inset[0] = height; break;
          case NSMaxXEdge: inset[1] = height; break;
          case NSMaxYEdge: inset[2] = height; break;
          default: inset[3] = height; break;
        }
    }
  [server setPopoverBodyInsetLeft: inset[0]
                            right: inset[1]
                              top: inset[2]
                           bottom: inset[3]
                                 : (int)[window windowNumber]];
}

@implementation GnomeTheme (Popovers)

- (void) drawWindowBackground: (NSRect)frame view: (NSView *)view
{
  NSWindow *window = [view window];
  NSColor *fill;
  NSColor *border;
  NSRectEdge edge = NSMaxYEdge;
  CGFloat position = 0.0, height = 0.0, width = 0.0;
  BOOL hasArrow;

  if (GnomeThemeIsPopoverPanel (window) == NO)
    {
      [super drawWindowBackground: frame view: view];
      return;
    }

  fill = GnomeThemeColor (self, @"menuBackgroundColor", [NSColor controlBackgroundColor]);
  border = GnomeThemeColor (self, @"menuBorderColor", [NSColor controlShadowColor]);
  hasArrow = GnomeThemePopoverArrow (window, &edge, &position, &height, &width);
  GnomeThemeSetPopoverBodyInset (window, hasArrow, edge, height);

  if (GnomeThemeWindowManagerHasAlpha (window))
    {
      NSBezierPath *path = GnomeThemePopoverPath (frame, hasArrow, edge, position,
                                                  height, width, NULL);

      [fill set];
      [path fill];
      [border set];
      [path setLineWidth: 1.0];
      [path stroke];
    }
  else
    {
      /* Without a compositing manager clear pixels show black: a plain
         panel over the whole window, as the theme's menus are then. */
      [fill set];
      NSRectFill (frame);
      [border set];
      NSFrameRectWithWidth (frame, 1.0);
    }
}

/* The panel is marked as a popover (NSUtilityWindowMask, which a
   borderless window has no other use for), so a libs-back with popover
   shadows (GSBackPopoverShadows) gives it libadwaita's popover shadow
   and corners. Only with the header bar, as the theme's menus: libs-back
   makes no margins when the window manager draws the decorations. */
- (id) _overrideNSPanelMethod_initWithContentRect: (NSRect)contentRect
                                        styleMask: (NSUInteger)style
                                          backing: (NSBackingStoreType)backing
                                            defer: (BOOL)flag
{
  typedef id (*InitIMP)(id, SEL, NSRect, NSUInteger, NSBackingStoreType, BOOL);
  /* NSPanel's own: subclasses the theme also overrides (NSMenuPanel,
     GSComboWindow) reach this through super. */
  InitIMP originalIMP = (InitIMP)GnomeThemeOriginalMethodOfClass (_cmd, [NSPanel class]);

  if (style == NSBorderlessWindowMask
    && GnomeThemeIsPopoverPanel ((NSWindow *)self)
    && GnomeThemeUsesHeaderBar ())
    {
      style |= NSUtilityWindowMask;
    }
  return originalIMP != NULL ? originalIMP (self, _cmd, contentRect, style, backing, flag) : self;
}

@end
