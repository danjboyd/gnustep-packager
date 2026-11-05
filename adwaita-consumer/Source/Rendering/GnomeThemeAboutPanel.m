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

/* The standard About panel (-orderFrontStandardAboutPanel:) as the first
   page of libadwaita's AdwAboutWindow, measured from
   Reference/AboutDialog: a 350pt window with no title; the app's icon at
   128pt; its name in title-1 (bold, 181% of the interface font); the
   developer; the version in a pill, the accent's text colour on the accent
   at 12%. GNUstep has no navigation pages, so what AdwAboutWindow puts on
   its Details and Legal pages follows inline, dimmed: the description and
   website, then the copyright and its description, and last, as in
   GSInfoPanel, the current theme. A bitmap icon is never scaled up: its
   widest bitmap at 128pt, or at its own size when narrower. The values
   come from
   the same places as GSInfoPanel's: the options dictionary, then the
   app's Info.plist. GNUstep's panel had NeXT's layout, with a GNUstep
   watermark behind it. */

#import "../GnomeTheme.h"

#import <AppKit/AppKit.h>

static NSPanel *GnomeThemeAboutPanel = nil;

/* The icon for a `side`pt slot, never a bitmap scaled up. GNUstep picks
   a bitmap by its size in points, and an app's default icon is 48pt with
   a 48px and a 192px bitmap, so the 48px one was drawn at 128pt, jagged.
   An image of bitmaps only becomes one of its widest: at `side`pt when
   that is wide enough, else at its own size in pixels, which the slot
   shows in its middle. An image with any other representation (a
   vector one) is kept as it is. */
static NSImage *
GnomeThemeAboutIcon(NSImage *image, CGFloat side)
{
  NSEnumerator *enumerator = [[image representations] objectEnumerator];
  NSImageRep *rep, *widest = nil;
  NSImage *icon;
  CGFloat width;

  while ((rep = [enumerator nextObject]) != nil)
    {
      if ([rep isKindOfClass: [NSBitmapImageRep class]] == NO)
        {
          return image;
        }
      if (widest == nil || [rep pixelsWide] > [widest pixelsWide])
        {
          widest = rep;
        }
    }
  if (widest == nil)
    {
      return image;
    }
  width = MIN (side, (CGFloat)[widest pixelsWide]);
  widest = AUTORELEASE ([widest copy]);
  [widest setSize: NSMakeSize (width, width * [widest pixelsHigh] / MAX (1, [widest pixelsWide]))];
  icon = AUTORELEASE ([[NSImage alloc] initWithSize: [widest size]]);
  [icon addRepresentation: widest];
  return icon;
}

/* The first of `keys` with a value of `class`: in `options`, then in the
   app's Info.plist. */
static id
GnomeThemeAboutValue(NSDictionary *options, NSArray *keys, Class class)
{
  NSDictionary *info = [[NSBundle mainBundle] localizedInfoDictionary];
  NSEnumerator *enumerator;
  NSString *key;

  if (info == nil)
    {
      info = [[NSBundle mainBundle] infoDictionary];
    }
  enumerator = [keys objectEnumerator];
  while ((key = [enumerator nextObject]) != nil)
    {
      id value = [options objectForKey: key];

      if ([value isKindOfClass: class])
        {
          return value;
        }
    }
  enumerator = [keys objectEnumerator];
  while ((key = [enumerator nextObject]) != nil)
    {
      id value = [info objectForKey: key];

      if ([value isKindOfClass: class])
        {
          return value;
        }
    }
  return nil;
}

/* The size of `text` in `font`, wrapped at `width`. */
static NSSize
GnomeThemeAboutTextSize(NSString *text, NSFont *font, CGFloat width)
{
  NSTextStorage *storage = AUTORELEASE ([[NSTextStorage alloc] initWithString: text
    attributes: [NSDictionary dictionaryWithObject: font forKey: NSFontAttributeName]]);
  NSLayoutManager *layout = AUTORELEASE ([[NSLayoutManager alloc] init]);
  NSTextContainer *container = AUTORELEASE ([[NSTextContainer alloc]
    initWithContainerSize: NSMakeSize (width, 1.0e7)]);

  [container setLineFragmentPadding: 0.0];
  [layout addTextContainer: container];
  [storage addLayoutManager: layout];
  [layout glyphRangeForTextContainer: container];
  return [layout usedRectForTextContainer: container].size;
}

/* A centred, wrapping label. */
static NSTextField *
GnomeThemeAboutLabel(NSString *text, NSFont *font, NSColor *color, CGFloat width)
{
  NSTextField *label = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (0.0, 0.0, width, 20.0)]);
  NSSize size;

  [label setStringValue: text];
  [label setFont: font];
  [label setTextColor: color];
  [label setAlignment: GnomeThemeCenterTextAlignment ()];
  [label setBezeled: NO];
  [label setBordered: NO];
  [label setDrawsBackground: NO];
  [label setEditable: NO];
  [label setSelectable: NO];
  [[label cell] setWraps: YES];
  /* The cell measures a wrapping string as one line, so lay the text out
     at the label's width, less the cell's 2pt inset each side. */
  size = GnomeThemeAboutTextSize (text, font, width - 4.0);
  [label setFrameSize: NSMakeSize (width, ceil (size.height) + 4.0)];
  return label;
}

/* The version pill: the accent's text colour on the accent at 12%. */
@interface GnomeThemeAboutPill : NSView
{
  NSString *_text;
  NSDictionary *_attributes;
  NSColor *_fill;
}
- (id) initWithText: (NSString *)text font: (NSFont *)font
          textColor: (NSColor *)textColor fill: (NSColor *)fill;
@end

@implementation GnomeThemeAboutPill

- (id) initWithText: (NSString *)text font: (NSFont *)font
          textColor: (NSColor *)textColor fill: (NSColor *)fill
{
  NSSize size;

  _attributes = RETAIN (([NSDictionary dictionaryWithObjectsAndKeys:
    font, NSFontAttributeName, textColor, NSForegroundColorAttributeName, nil]));
  size = [text sizeWithAttributes: _attributes];
  self = [super initWithFrame: NSMakeRect (0.0, 0.0, ceil (size.width) + 24.0, 30.0)];
  if (self != nil)
    {
      ASSIGN (_text, text);
      ASSIGN (_fill, fill);
    }
  return self;
}

- (void) dealloc
{
  RELEASE (_text);
  RELEASE (_attributes);
  RELEASE (_fill);
  [super dealloc];
}

- (void) drawRect: (NSRect)rect
{
  NSRect bounds = [self bounds];
  NSSize size = [_text sizeWithAttributes: _attributes];

  [_fill set];
  [[NSBezierPath bezierPathWithRoundedRect: bounds
                                   xRadius: NSHeight (bounds) / 2.0
                                   yRadius: NSHeight (bounds) / 2.0] fill];
  [_text drawAtPoint: NSMakePoint (floor (NSMidX (bounds) - size.width / 2.0),
                                   floor (NSMidY (bounds) - size.height / 2.0))
      withAttributes: _attributes];
}

@end

/* Lays the views out from the top, centred, with the gap before each. */
static NSPanel *
GnomeThemeMakeAboutPanel(GSTheme *theme, NSDictionary *options)
{
  CGFloat width = 350.0, margin = 24.0, textWidth = width - 2.0 * margin;
  NSFont *body = [NSFont systemFontOfSize: 0];
  CGFloat size = [body pointSize];
  NSColor *text = GnomeThemeColor (theme, @"controlTextColor", [NSColor controlTextColor]);
  NSColor *window = GnomeThemeColor (theme, @"windowBackgroundColor", [NSColor windowBackgroundColor]);
  NSColor *dim = [window blendedColorWithFraction: 0.55 ofColor: text];
  NSColor *accent = GnomeThemeColor (theme, @"selectedControlColor", [NSColor selectedControlColor]);
  BOOL dark = [[window colorUsingColorSpaceName: NSCalibratedRGBColorSpace] redComponent] < 0.5;
  /* libadwaita's accent_color: the accent darker for text on the light
     palette, lighter on the dark one. */
  NSColor *accentText = dark ? [accent blendedColorWithFraction: 0.35 ofColor: [NSColor whiteColor]]
                             : [accent blendedColorWithFraction: 0.25 ofColor: [NSColor blackColor]];
  NSString *name, *developer, *version, *description, *website, *copyright, *license;
  NSArray *authors;
  NSImage *icon;
  NSMutableArray *views = [NSMutableArray array];
  NSMutableArray *gaps = [NSMutableArray array];
  NSPanel *panel;
  NSView *content;
  NSEnumerator *enumerator;
  NSView *view;
  CGFloat height = 12.0, y;
  NSUInteger index;

  name = GnomeThemeAboutValue (options, [NSArray arrayWithObjects: @"ApplicationName",
    @"NSHumanReadableShortName", @"CFBundleName", nil], [NSString class]);
  if (name == nil)
    {
      name = [[NSProcessInfo processInfo] processName];
    }
  authors = GnomeThemeAboutValue (options, [NSArray arrayWithObject: @"Authors"], [NSArray class]);
  developer = (authors != nil) ? [authors componentsJoinedByString: @", "]
    : GnomeThemeAboutValue (options, [NSArray arrayWithObject: @"Authors"], [NSString class]);
  version = GnomeThemeAboutValue (options, [NSArray arrayWithObjects: @"ApplicationRelease",
    @"ApplicationVersion", @"NSAppVersion", @"CFBundleShortVersionString", @"CFBundleVersion", nil],
    [NSString class]);
  description = GnomeThemeAboutValue (options, [NSArray arrayWithObject: @"ApplicationDescription"],
    [NSString class]);
  website = GnomeThemeAboutValue (options, [NSArray arrayWithObject: @"URL"], [NSString class]);
  copyright = GnomeThemeAboutValue (options, [NSArray arrayWithObjects: @"Copyright",
    @"NSHumanReadableCopyright", nil], [NSString class]);
  license = GnomeThemeAboutValue (options, [NSArray arrayWithObject: @"CopyrightDescription"],
    [NSString class]);
  icon = GnomeThemeAboutValue (options, [NSArray arrayWithObject: @"ApplicationIcon"], [NSImage class]);
  if (icon == nil)
    {
      NSString *iconName = GnomeThemeAboutValue (options, [NSArray arrayWithObject: @"ApplicationIcon"],
                                                 [NSString class]);

      icon = (iconName != nil) ? [NSImage imageNamed: iconName] : nil;
    }
  if (icon == nil)
    {
      icon = [NSApp applicationIconImage];
    }

  if (icon != nil)
    {
      NSImageView *iconView = AUTORELEASE ([[NSImageView alloc] initWithFrame: NSMakeRect (0, 0, 128, 128)]);

      icon = GnomeThemeAboutIcon (icon, 128.0);
      [iconView setImage: icon];
      [iconView setImageScaling: [[icon representations] count] == 1
        && [[[icon representations] objectAtIndex: 0] isKindOfClass: [NSBitmapImageRep class]]
        ? NSImageScaleProportionallyDown : NSImageScaleProportionallyUpOrDown];
      [views addObject: iconView];
      [gaps addObject: [NSNumber numberWithDouble: 0.0]];
    }
  [views addObject: GnomeThemeAboutLabel (name, [NSFont boldSystemFontOfSize: floor (size * 1.81)],
                                          text, textWidth)];
  [gaps addObject: [NSNumber numberWithDouble: 18.0]];
  if ([developer length] > 0)
    {
      [views addObject: GnomeThemeAboutLabel (developer, body, text, textWidth)];
      [gaps addObject: [NSNumber numberWithDouble: 6.0]];
    }
  if ([version length] > 0)
    {
      [views addObject: AUTORELEASE ([[GnomeThemeAboutPill alloc]
        initWithText: version font: [NSFont boldSystemFontOfSize: floor (size * 0.9)]
           textColor: accentText fill: [window blendedColorWithFraction: 0.12 ofColor: accent]])];
      [gaps addObject: [NSNumber numberWithDouble: 12.0]];
    }
  if ([description length] > 0)
    {
      [views addObject: GnomeThemeAboutLabel (description, body, dim, textWidth)];
      [gaps addObject: [NSNumber numberWithDouble: 24.0]];
    }
  if ([website length] > 0)
    {
      [views addObject: GnomeThemeAboutLabel (website, body, accentText, textWidth)];
      [gaps addObject: [NSNumber numberWithDouble: 12.0]];
    }
  if ([copyright length] > 0 || [license length] > 0)
    {
      NSString *legal = ([copyright length] > 0 && [license length] > 0)
        ? [NSString stringWithFormat: @"%@\n%@", copyright, license]
        : ([copyright length] > 0 ? copyright : license);

      [views addObject: GnomeThemeAboutLabel (legal, [NSFont systemFontOfSize: floor (size * 0.82 + 0.5)],
                                              dim, textWidth)];
      [gaps addObject: [NSNumber numberWithDouble: 24.0]];
    }
  /* As GSInfoPanel's last line, the theme in use, by its name: a dim
     caption. */
  [views addObject: GnomeThemeAboutLabel ([NSString stringWithFormat: @"%@: %@",
      NSLocalizedStringFromTableInBundle (@"Current theme", nil, [NSBundle bundleForLibrary: @"gnustep-gui"], @""),
      [theme name]], [NSFont systemFontOfSize: floor (size * 0.82 + 0.5)], dim, textWidth)];
  [gaps addObject: [NSNumber numberWithDouble: ([copyright length] > 0 || [license length] > 0) ? 6.0 : 24.0]];

  for (index = 0; index < [views count]; index++)
    {
      height += [[gaps objectAtIndex: index] doubleValue] + NSHeight ([[views objectAtIndex: index] frame]);
    }
  height += 30.0;

  panel = [[NSPanel alloc] initWithContentRect: NSMakeRect (0, 0, width, height)
                                     styleMask: NSTitledWindowMask | NSClosableWindowMask
                                       backing: NSBackingStoreBuffered
                                         defer: NO];
  [panel setTitle: @""];
  [panel setReleasedWhenClosed: NO];
  [panel setHidesOnDeactivate: NO];
  content = [panel contentView];
  y = height - 12.0;
  enumerator = [views objectEnumerator];
  index = 0;
  while ((view = [enumerator nextObject]) != nil)
    {
      NSRect frame = [view frame];

      y -= [[gaps objectAtIndex: index++] doubleValue] + NSHeight (frame);
      frame.origin = NSMakePoint (floor ((width - NSWidth (frame)) / 2.0), floor (y));
      [view setFrame: frame];
      [content addSubview: view];
    }
  [panel center];
  /* On whole points: GNUstep's X11 backend draws nothing in a window whose
     origin is a half point, as -center gives an odd height. */
  {
    NSRect frame = [panel frame];

    [panel setFrameOrigin: NSMakePoint (floor (NSMinX (frame)), floor (NSMinY (frame)))];
  }
  return panel;
}

@implementation GnomeTheme (AboutPanel)

/* -orderFrontStandardAboutPanelWithOptions: comes here. As GNUstep's, one
   panel per app; made again each time it isn't on screen, so its options
   and its current theme line are this call's. */
- (void) _overrideNSApplicationMethod_orderFrontStandardInfoPanelWithOptions: (NSDictionary *)options
{
  if (GnomeThemeAboutPanel != nil && [GnomeThemeAboutPanel isVisible] == NO)
    {
      DESTROY (GnomeThemeAboutPanel);
    }
  if (GnomeThemeAboutPanel == nil)
    {
      GnomeThemeAboutPanel = GnomeThemeMakeAboutPanel ([GSTheme theme], options);
    }
  [GnomeThemeAboutPanel makeKeyAndOrderFront: nil];
}

@end
