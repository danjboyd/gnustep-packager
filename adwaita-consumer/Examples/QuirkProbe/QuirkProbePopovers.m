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

/* An app's popover panels as libadwaita's popover (#74): a panel that
   conforms to GSThemePopoverPanel, as ScreenshotTool's
   STFloatingPopoverWindow does, with the arrow it asks for. */

#import "QuirkProbe.h"

#import <GNUstepGUI/GSTheme.h>
#import <dlfcn.h>

@interface QuirkProbe (PopoversResults)
- (void) pass: (NSString *)ident detail: (NSString *)detail;
- (void) fail: (NSString *)ident detail: (NSString *)detail;
- (void) saveWindow: (NSWindow *)window named: (NSString *)name;
@end

@protocol GSThemePopoverPanel
@optional
- (NSRectEdge) popoverArrowEdge;
- (CGFloat) popoverArrowPosition;
- (CGFloat) popoverArrowHeight;
- (CGFloat) popoverArrowWidth;
@end

/* A popover panel as ScreenshotTool makes one: borderless, clear and not
   opaque, its content view drawing nothing, the arrow's room kept. */
@interface QuirkProbePopoverPanel : NSPanel <GSThemePopoverPanel>
{
@public
  NSRectEdge arrowEdge;
  CGFloat arrowPosition;
  CGFloat arrowHeight;
  CGFloat arrowWidth;
}
@end

@implementation QuirkProbePopoverPanel
- (NSRectEdge) popoverArrowEdge { return arrowEdge; }
- (CGFloat) popoverArrowPosition { return arrowPosition; }
- (CGFloat) popoverArrowHeight { return arrowHeight; }
- (CGFloat) popoverArrowWidth { return arrowWidth; }
- (BOOL) canBecomeKeyWindow { return YES; }
@end

@interface QuirkProbeClearView : NSView
@end

@implementation QuirkProbeClearView
- (BOOL) isOpaque { return NO; }
- (void) drawRect: (NSRect)rect { (void)rect; }
@end

static QuirkProbePopoverPanel *
QuirkProbeMakePopover(NSRect frame, CGFloat arrowHeight, CGFloat arrowPosition)
{
  QuirkProbePopoverPanel *panel = [[QuirkProbePopoverPanel alloc]
    initWithContentRect: frame
              styleMask: NSBorderlessWindowMask
                backing: NSBackingStoreBuffered
                  defer: NO];

  panel->arrowEdge = NSMaxYEdge;
  panel->arrowPosition = arrowPosition;
  panel->arrowHeight = arrowHeight;
  panel->arrowWidth = 24.0;
  [panel setOpaque: NO];
  [panel setHasShadow: YES];
  [panel setBackgroundColor: [NSColor clearColor]];
  [panel setLevel: NSPopUpMenuWindowLevel];
  [panel setReleasedWhenClosed: NO];
  [panel setContentView: AUTORELEASE ([[QuirkProbeClearView alloc]
                                        initWithFrame: NSMakeRect (0, 0, NSWidth (frame), NSHeight (frame))])];
  return panel;
}

/* r, g, b, a (0-255) at a pixel, from the top left. */
static void
QuirkProbePopoverPixel(NSBitmapImageRep *rep, NSInteger x, NSInteger y, long rgba[4])
{
  NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

  rgba[0] = lround ([color redComponent] * 255);
  rgba[1] = lround ([color greenComponent] * 255);
  rgba[2] = lround ([color blueComponent] * 255);
  rgba[3] = lround ([color alphaComponent] * 255);
}

static NSBitmapImageRep *
QuirkProbePopoverRender(NSWindow *window)
{
  NSView *frameView = [[window contentView] superview];
  NSRect bounds = [frameView bounds];
  NSBitmapImageRep *rep = [frameView bitmapImageRepForCachingDisplayInRect: bounds];

  [frameView cacheDisplayInRect: bounds toBitmapImageRep: rep];
  return rep;
}

@implementation QuirkProbe (Popovers)

/* The theme draws a GSThemePopoverPanel's panel in the menu's colour; a
   plain clear panel stays clear. Without a compositing manager (the
   probe's Xvfb) the panel is the whole window, square, with no arrow; the
   arrow and the shadow round the body are for the screenshots
   (-ProbeOnly popover-demo under GNOME Shell). */
- (void) checkPopoverPanel
{
  typedef NSColor *(*LookupFunction)(GSTheme *, NSString *, NSColor *);
  LookupFunction lookup = (LookupFunction)dlsym (RTLD_DEFAULT, "GnomeThemeColor");
  QuirkProbePopoverPanel *popover = QuirkProbeMakePopover (NSMakeRect (80, 80, 220, 132), 12.0, 110.0);
  NSPanel *plain = [[NSPanel alloc] initWithContentRect: NSMakeRect (320, 80, 220, 132)
                                              styleMask: NSBorderlessWindowMask
                                                backing: NSBackingStoreBuffered
                                                  defer: NO];
  NSColor *menu = [(lookup != NULL ? lookup ([GSTheme theme], @"menuBackgroundColor", nil) : nil)
                    colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSDictionary *info = [[GSTheme theme] infoDictionary];
  long inPopover[4], inPlain[4], want[3];
  NSString *detail;
  BOOL ok;

  [plain setOpaque: NO];
  [plain setBackgroundColor: [NSColor clearColor]];
  [plain setContentView: AUTORELEASE ([[QuirkProbeClearView alloc] initWithFrame: NSMakeRect (0, 0, 220, 132)])];
  [popover orderFront: nil];
  [plain orderFront: nil];
  [popover display];
  [plain display];
  QuirkProbePopoverPixel (QuirkProbePopoverRender (popover), 110, 70, inPopover);
  QuirkProbePopoverPixel (QuirkProbePopoverRender (plain), 110, 70, inPlain);
  want[0] = lround ([menu redComponent] * 255);
  want[1] = lround ([menu greenComponent] * 255);
  want[2] = lround ([menu blueComponent] * 255);
  [self saveWindow: popover named: @"popover-panel"];
  [popover orderOut: nil];
  [plain orderOut: nil];

  ok = menu != nil
    && [[info objectForKey: @"GSThemeDrawsPopoverPanels"] boolValue]
    && [[info objectForKey: @"GSThemeDrawsPopoverArrows"] boolValue]
    && labs (inPopover[0] - want[0]) <= 2 && labs (inPopover[1] - want[1]) <= 2
    && labs (inPopover[2] - want[2]) <= 2 && inPopover[3] == 255
    && inPlain[3] == 0;
  detail = [NSString stringWithFormat:
    @"Info: panels %@, arrows %@; popover panel #%02lx%02lx%02lx alpha %ld (want #%02lx%02lx%02lx); "
    @"a plain clear panel alpha %ld (want 0); popover style mask %#lx",
    [info objectForKey: @"GSThemeDrawsPopoverPanels"], [info objectForKey: @"GSThemeDrawsPopoverArrows"],
    inPopover[0], inPopover[1], inPopover[2], inPopover[3], want[0], want[1], want[2],
    inPlain[3], (unsigned long)[popover styleMask]];
  /* Kept, as the probe's other windows: the window list doesn't retain
     them. */
  if (ok)
    {
      [self pass: @"popover-panel" detail: detail];
    }
  else
    {
      [self fail: @"popover-panel" detail: detail];
    }
}

/* -ProbeOnly popover-demo: a window with a button, the popover below it
   with its arrow at the button, and an arrowless one (a drop-down's), for
   screenshots beside GTK's. */
- (void) showPopoverDemo
{
  NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect (100, 300, 520, 360)
                                                 styleMask: NSTitledWindowMask | NSClosableWindowMask
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
  NSButton *button = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (60, 300, 120, 34)]);
  NSButton *other = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (300, 300, 160, 34)]);
  NSRect buttonOnScreen;
  QuirkProbePopoverPanel *arrow, *flat;
  NSTextField *label;
  NSSlider *slider;
  NSEnumerator *others = [[NSApp windows] objectEnumerator];
  NSWindow *each;

  while ((each = [others nextObject]) != nil)
    {
      if ([each isVisible] && [each canBecomeMainWindow])
        {
          [each orderOut: nil];
        }
    }
  [window setTitle: @"Popover"];
  [window setReleasedWhenClosed: NO];
  [button setTitle: @"Pen"];
  [other setTitle: @"Cantarell"];
  [[window contentView] addSubview: button];
  [[window contentView] addSubview: other];
  [window makeKeyAndOrderFront: nil];
  [window display];

  /* Below the button, the arrow's tip 6pt under it, pointing at its
     middle. */
  buttonOnScreen = [window convertRectToScreen: [button frame]];
  arrow = QuirkProbeMakePopover (NSMakeRect (NSMidX (buttonOnScreen) - 110, NSMinY (buttonOnScreen) - 6 - 144,
                                             220, 144), 12.0, 110.0);
  label = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (18, 82, 184, 22)]);
  [label setStringValue: @"Width"];
  [label setBezeled: NO];
  [label setDrawsBackground: NO];
  [label setEditable: NO];
  slider = AUTORELEASE ([[NSSlider alloc] initWithFrame: NSMakeRect (18, 40, 184, 30)]);
  [slider setDoubleValue: 0.4];
  [[arrow contentView] addSubview: label];
  [[arrow contentView] addSubview: slider];

  buttonOnScreen = [window convertRectToScreen: [other frame]];
  flat = QuirkProbeMakePopover (NSMakeRect (NSMinX (buttonOnScreen), NSMinY (buttonOnScreen) - 2 - 160,
                                            NSWidth (buttonOnScreen), 160), 0.0, 0.0);
  [arrow orderFront: nil];
  [flat orderFront: nil];
}

@end
