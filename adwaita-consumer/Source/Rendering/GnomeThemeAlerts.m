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

#import "../GnomeTheme.h"
#import "../Settings/GnomeThemeSettings.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

/* AdwAlertDialog's geometry, measured from libadwaita: a 372px dialog, text
   centred in 312px, buttons 44px high with 24px margins and 12px between
   them. */
static const CGFloat GnomeThemeAlertWidth = 372.0;
static const CGFloat GnomeThemeAlertTextInset = 30.0;
static const CGFloat GnomeThemeAlertButtonInset = 24.0;
static const CGFloat GnomeThemeAlertButtonHeight = 44.0;
static const CGFloat GnomeThemeAlertButtonGap = 12.0;
static const CGFloat GnomeThemeAlertTopPadding = 30.0;
static const CGFloat GnomeThemeAlertHeadingGap = 10.0;
static const CGFloat GnomeThemeAlertBodyGap = 20.0;
static const CGFloat GnomeThemeAlertBottomPadding = 24.0;
/* libadwaita's title-2 heading over its 11pt body text. */
static const CGFloat GnomeThemeAlertHeadingScale = 15.0 / 11.0;
/* A text field's cell insets its text this much on each side. */
static const CGFloat GnomeThemeAlertCellInset = 2.0;
/* GNUstep's limit: an alert takes at most this much of the screen. */
static const CGFloat GnomeThemeAlertScreenFraction = 0.6;

static id
GnomeThemeAlertIvar(id panel, const char *name)
{
  Ivar ivar = class_getInstanceVariable ([panel class], name);

  return (ivar != NULL) ? object_getIvar (panel, ivar) : nil;
}

static BOOL
GnomeThemeAlertUses(NSView *control)
{
  return control != nil && [control superview] != nil;
}

static CGFloat
GnomeThemeAlertTextHeight(NSTextField *field, CGFloat width)
{
  if (GnomeThemeAlertUses (field) == NO || [[field stringValue] length] == 0)
    {
      return 0.0;
    }
  return ceil ([[field attributedStringValue] boundingRectWithSize: NSMakeSize (width, 1e6)
                                                            options: 0].size.height);
}

static void
GnomeThemeAlertStyleText(NSTextField *field, NSFont *font)
{
  [field setFont: font];
  [field setAlignment: GnomeThemeCenterTextAlignment ()];
  [[field cell] setWraps: YES];
  [[field cell] setLineBreakMode: NSLineBreakByWordWrapping];
}

@implementation GnomeTheme (Alerts)

/* Alerts laid out like libadwaita's AdwAlertDialog: no icon and no line, a
   centred bold heading over centred body text, and the buttons in a row of
   equal widths (stacked, full width, when their titles don't fit). The
   default button, which GNUstep puts at the right, stays there, and on top
   when stacked. */
- (void) _overrideGSAlertPanelMethod_sizePanelToFit
{
  typedef void (*SizeIMP)(id, SEL);
  NSPanel *panel = (NSPanel *)self;
  NSView *content = [panel contentView];
  NSTextField *titleField = GnomeThemeAlertIvar (panel, "titleField");
  NSTextField *messageField = GnomeThemeAlertIvar (panel, "messageField");
  NSScrollView *scroll = GnomeThemeAlertIvar (panel, "scroll");
  NSButton *icon = GnomeThemeAlertIvar (panel, "icoButton");
  NSArray *candidates = nil;
  NSMutableArray *buttons = [NSMutableArray array];
  NSFont *bodyFont = [[(GnomeTheme *)[GSTheme theme] settings] interfaceFont];
  NSFont *headingFont = [[(GnomeTheme *)[GSTheme theme] settings] boldInterfaceFont];
  NSUInteger mask = [panel styleMask];
  NSEnumerator *enumerator = nil;
  NSView *subview = nil;
  NSButton *button = nil;
  NSScreen *screen = [panel screen];
  CGFloat textWidth = GnomeThemeAlertWidth - 2.0 * GnomeThemeAlertTextInset;
  CGFloat rowWidth = GnomeThemeAlertWidth - 2.0 * GnomeThemeAlertButtonInset;
  CGFloat buttonWidth = 0.0;
  CGFloat buttonsHeight = 0.0;
  CGFloat headingHeight, bodyHeight, bodyShown, height, maxHeight, y;
  BOOL stacked = NO;
  BOOL needsScroll = NO;
  NSRect frame;
  Ivar isGreen;

  if (titleField == nil || messageField == nil || scroll == nil)
    {
      SizeIMP originalIMP = (SizeIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSAlertPanel"));

      if (originalIMP != NULL)
        {
          originalIMP (self, _cmd);
        }
      return;
    }

  if (bodyFont == nil)
    {
      bodyFont = [NSFont systemFontOfSize: 0];
    }
  if (headingFont == nil)
    {
      headingFont = [NSFont boldSystemFontOfSize: 0];
    }
  headingFont = [[NSFontManager sharedFontManager]
                  convertFont: headingFont
                       toSize: round ([bodyFont pointSize] * GnomeThemeAlertHeadingScale)];

  [icon setHidden: YES];
  enumerator = [[content subviews] objectEnumerator];
  while ((subview = [enumerator nextObject]) != nil)
    {
      if ([subview isKindOfClass: [NSBox class]])
        {
          [subview setHidden: YES];
        }
    }
  GnomeThemeAlertStyleText (titleField, headingFont);
  GnomeThemeAlertStyleText (messageField, bodyFont);

  /* Left to right: GNUstep's order, the default button last. */
  candidates = [NSArray arrayWithObjects: GnomeThemeAlertIvar (panel, "othButton"),
                                          GnomeThemeAlertIvar (panel, "altButton"),
                                          GnomeThemeAlertIvar (panel, "defButton"),
                                          nil];
  enumerator = [candidates objectEnumerator];
  while ((button = [enumerator nextObject]) != nil)
    {
      if (GnomeThemeAlertUses (button))
        {
          [buttons addObject: button];
        }
    }
  if ([buttons count] > 0)
    {
      buttonWidth = floor ((rowWidth - GnomeThemeAlertButtonGap * ([buttons count] - 1))
                           / [buttons count]);
      enumerator = [buttons objectEnumerator];
      while ((button = [enumerator nextObject]) != nil)
        {
          [button sizeToFit];
          if (NSWidth ([button frame]) > buttonWidth)
            {
              stacked = YES;
            }
        }
      buttonsHeight = stacked
        ? [buttons count] * (GnomeThemeAlertButtonHeight + GnomeThemeAlertButtonGap) - GnomeThemeAlertButtonGap
        : GnomeThemeAlertButtonHeight;
    }

  headingHeight = GnomeThemeAlertTextHeight (titleField, textWidth);
  bodyHeight = GnomeThemeAlertTextHeight (messageField, textWidth);
  height = GnomeThemeAlertTopPadding + headingHeight
    + (bodyHeight > 0.0 ? GnomeThemeAlertHeadingGap + bodyHeight : 0.0)
    + GnomeThemeAlertBodyGap + buttonsHeight + GnomeThemeAlertBottomPadding;

  /* Too tall for the screen: the body scrolls. */
  if (screen == nil)
    {
      screen = [NSScreen mainScreen];
    }
  maxHeight = GnomeThemeAlertScreenFraction
    * [NSWindow contentRectForFrameRect: [screen frame] styleMask: mask].size.height;
  bodyShown = bodyHeight;
  if (height > maxHeight && bodyHeight > 0.0)
    {
      bodyShown = MAX (bodyHeight - (height - maxHeight), 3.0 * [bodyFont defaultLineHeightForFont]);
      height -= bodyHeight - bodyShown;
      needsScroll = YES;
    }

  frame = [NSWindow frameRectForContentRect: NSMakeRect (0.0, 0.0, GnomeThemeAlertWidth, height)
                                  styleMask: mask];
  [panel setMinSize: frame.size];
  [panel setMaxSize: frame.size];
  [panel setContentSize: NSMakeSize (GnomeThemeAlertWidth, height)];

  /* Bottom up: the buttons, then the body, then the heading. */
  y = GnomeThemeAlertBottomPadding;
  if (stacked)
    {
      enumerator = [buttons objectEnumerator];
      while ((button = [enumerator nextObject]) != nil)
        {
          [button setFrame: NSMakeRect (GnomeThemeAlertButtonInset, y,
                                        rowWidth, GnomeThemeAlertButtonHeight)];
          y += GnomeThemeAlertButtonHeight + GnomeThemeAlertButtonGap;
        }
    }
  else
    {
      CGFloat x = GnomeThemeAlertButtonInset;

      enumerator = [buttons objectEnumerator];
      while ((button = [enumerator nextObject]) != nil)
        {
          /* The last button takes what rounding left over. */
          CGFloat width = (button == [buttons lastObject])
            ? GnomeThemeAlertWidth - GnomeThemeAlertButtonInset - x
            : buttonWidth;

          [button setFrame: NSMakeRect (x, y, width, GnomeThemeAlertButtonHeight)];
          x += width + GnomeThemeAlertButtonGap;
        }
    }
  y = GnomeThemeAlertBottomPadding + buttonsHeight + GnomeThemeAlertBodyGap;

  if (bodyHeight > 0.0)
    {
      NSRect bodyRect = NSMakeRect (GnomeThemeAlertTextInset - GnomeThemeAlertCellInset, y,
                                    textWidth + 2.0 * GnomeThemeAlertCellInset, bodyShown);

      if (needsScroll)
        {
          NSSize inner;

          [messageField removeFromSuperview];
          [scroll setFrame: bodyRect];
          inner = [NSScrollView contentSizeForFrameSize: bodyRect.size
                                  hasHorizontalScroller: NO
                                    hasVerticalScroller: YES
                                             borderType: [scroll borderType]];
          [messageField setFrame: NSMakeRect (0.0, 0.0, inner.width,
                                              GnomeThemeAlertTextHeight (messageField, inner.width))];
          [scroll setDocumentView: messageField];
          if (GnomeThemeAlertUses (scroll) == NO)
            {
              [content addSubview: scroll];
            }
        }
      else
        {
          [messageField setFrame: bodyRect];
        }
      y += bodyShown + GnomeThemeAlertHeadingGap;
    }
  [titleField setFrame: NSMakeRect (GnomeThemeAlertTextInset - GnomeThemeAlertCellInset, y,
                                    textWidth + 2.0 * GnomeThemeAlertCellInset, headingHeight)];

  isGreen = class_getInstanceVariable ([panel class], "isGreen");
  if (isGreen != NULL)
    {
      *(BOOL *)((char *)panel + ivar_getOffset (isGreen)) = NO;
    }
  [content display];
}

@end
