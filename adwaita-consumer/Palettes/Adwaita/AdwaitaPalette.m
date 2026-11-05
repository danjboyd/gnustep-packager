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

/* A Gorm palette of controls at GNOME's sizes: libadwaita's 34px buttons,
   entries, search fields and pop-ups, a suggested (default) button,
   checkboxes, radios, and body and heading labels. Gorm's own palettes make
   22pt controls, sized for GNUstep's metrics; these are for apps that run
   with the theme's GNOME metrics (GnomeThemeMetrics = gnome in their
   Info.plist). Fonts are left at the system font's default size, which Gorm
   archives as "the system font", so they follow the metrics the app runs
   with. The controls are built here rather than in a Gorm file, so their
   sizes are plain to read and change. */

#import <AppKit/AppKit.h>
#import <InterfaceBuilder/InterfaceBuilder.h>

/* libadwaita's control height. */
static const CGFloat AdwaitaControlHeight = 34.0;
/* A checkbox or radio row. */
static const CGFloat AdwaitaToggleHeight = 24.0;
/* Gorm's palette area. */
static const NSSize AdwaitaPaletteSize = {272.0, 200.0};
static const CGFloat AdwaitaMargin = 12.0;
static const CGFloat AdwaitaRowGap = 8.0;

@interface AdwaitaPalette : IBPalette
@end

@implementation AdwaitaPalette

/* A frame `top` points below the palette's top edge. */
static NSRect
AdwaitaFrame(CGFloat x, CGFloat top, CGFloat width, CGFloat height)
{
  return NSMakeRect (x, AdwaitaPaletteSize.height - top - height, width, height);
}

static NSButton *
AdwaitaButton(NSString *title, NSRect frame, NSButtonType type)
{
  NSButton *button = [[NSButton alloc] initWithFrame: frame];

  [button setButtonType: type];
  if (type == NSMomentaryPushInButton)
    {
      [button setBezelStyle: NSRoundedBezelStyle];
    }
  [button setTitle: title];
  return AUTORELEASE (button);
}

static NSTextField *
AdwaitaLabel(NSString *text, NSRect frame, NSFont *font)
{
  NSTextField *label = [[NSTextField alloc] initWithFrame: frame];

  [label setStringValue: text];
  [label setBezeled: NO];
  [label setBordered: NO];
  [label setDrawsBackground: NO];
  [label setEditable: NO];
  [label setSelectable: NO];
  if (font != nil)
    {
      [label setFont: font];
    }
  return AUTORELEASE (label);
}

- (void) finishInstantiate
{
  NSWindow *window;
  NSView *content;
  NSButton *suggested;
  NSTextField *entry;
  NSSearchField *search;
  NSPopUpButton *popUp;
  /* Gorm edits pop-up items only in its own subclass (saved as an
     NSPopUpButton); its Controls palette, loaded first, provides it. */
  Class popUpClass = NSClassFromString (@"GormNSPopUpButton");
  CGFloat top = AdwaitaMargin;

  window = [[NSWindow alloc] initWithContentRect: NSMakeRect (0, 0, AdwaitaPaletteSize.width,
                                                              AdwaitaPaletteSize.height)
                                       styleMask: NSBorderlessWindowMask
                                         backing: NSBackingStoreRetained
                                           defer: YES];
  [window setTitle: @"Adwaita"];
  content = [window contentView];

  /* Buttons: a regular one and the suggested action (the default button,
     which the theme draws in the accent colour). */
  [content addSubview: AdwaitaButton (@"Button", AdwaitaFrame (AdwaitaMargin, top, 112, AdwaitaControlHeight),
                                      NSMomentaryPushInButton)];
  suggested = AdwaitaButton (@"Done", AdwaitaFrame (AdwaitaMargin + 120, top, 112, AdwaitaControlHeight),
                             NSMomentaryPushInButton);
  [suggested setKeyEquivalent: @"\r"];
  [content addSubview: suggested];
  top += AdwaitaControlHeight + AdwaitaRowGap;

  /* An entry and a pop-up. */
  entry = AUTORELEASE ([[NSTextField alloc] initWithFrame: AdwaitaFrame (AdwaitaMargin, top, 128,
                                                                          AdwaitaControlHeight)]);
  [entry setBezeled: YES];
  [entry setEditable: YES];
  [entry setSelectable: YES];
  [[entry cell] setPlaceholderString: @"Entry"];
  [content addSubview: entry];
  popUp = AUTORELEASE ([[(popUpClass != Nil ? popUpClass : [NSPopUpButton class]) alloc]
                         initWithFrame: AdwaitaFrame (AdwaitaMargin + 136, top, 112, AdwaitaControlHeight)
                             pullsDown: NO]);
  [popUp addItemsWithTitles: [NSArray arrayWithObjects: @"Item 1", @"Item 2", @"Item 3", nil]];
  [content addSubview: popUp];
  top += AdwaitaControlHeight + AdwaitaRowGap;

  search = AUTORELEASE ([[NSSearchField alloc] initWithFrame: AdwaitaFrame (AdwaitaMargin, top,
                                                                             AdwaitaPaletteSize.width - 2 * AdwaitaMargin,
                                                                             AdwaitaControlHeight)]);
  [[search cell] setPlaceholderString: @"Search"];
  [content addSubview: search];
  top += AdwaitaControlHeight + AdwaitaRowGap;

  [content addSubview: AdwaitaButton (@"Check", AdwaitaFrame (AdwaitaMargin, top, 104, AdwaitaToggleHeight),
                                      NSSwitchButton)];
  [content addSubview: AdwaitaButton (@"Option", AdwaitaFrame (AdwaitaMargin + 112, top, 104, AdwaitaToggleHeight),
                                      NSRadioButton)];
  top += AdwaitaToggleHeight + AdwaitaRowGap;

  /* Labels: a heading (the bold system font) and body text. */
  [content addSubview: AdwaitaLabel (@"Heading", AdwaitaFrame (AdwaitaMargin, top, 104, 22),
                                     [NSFont boldSystemFontOfSize: 0])];
  [content addSubview: AdwaitaLabel (@"Label", AdwaitaFrame (AdwaitaMargin + 112, top, 104, 22), nil)];

  originalWindow = window;
}

@end
