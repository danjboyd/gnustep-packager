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

/* Metrics per window (plugins-themes-Adwaita#24): the probe is built in
   code, so it has GNOME's metrics, but a window it loads from a Gorm file
   gets GNUstep's (compact), and -GnomeThemeMetrics gnome or compact
   gives every window the same. The Gorm file is made here, as Gorm makes
   one: a window archived in a GSNibContainer, with its fonts by role,
   loaded back through NSBundle as an app loads its own. */

#import "QuirkProbe.h"

#import <GNUstepGUI/GSTheme.h>
#import <GNUstepGUI/GSGormLoading.h>

@interface QuirkProbe (NibMetricsResults)
- (void) pass: (NSString *)ident detail: (NSString *)detail;
- (void) fail: (NSString *)ident detail: (NSString *)detail;
@end

/* A window like a small Gorm panel: a push button and a tab view, in the
   fonts a new control gets (the system font, by role). */
static NSWindow *
QuirkProbeNibMetricsWindow(NSButton **buttonOut, NSTabView **tabViewOut)
{
  NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect (100, 100, 320, 200)
                                                 styleMask: NSTitledWindowMask
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
  NSButton *button = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (10, 10, 120, 32)]);
  NSTabView *tabView = AUTORELEASE ([[NSTabView alloc] initWithFrame: NSMakeRect (10, 50, 300, 140)]);
  NSTabViewItem *item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier: @"one"]);
  NSTabViewItem *second = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier: @"two"]);

  [window setTitle: @"QuirkProbe Nib Metrics"];
  [button setTitle: @"Apply"];
  [button setBezelStyle: NSRoundedBezelStyle];
  [[window contentView] addSubview: button];
  /* GNUstep's Page Layout panel's first two tabs; descenders, to see them
     clear the underline. */
  [item setLabel: @"Page Attributes"];
  [tabView addTabViewItem: item];
  [second setLabel: @"Custom Paper Size"];
  [tabView addTabViewItem: second];
  [[window contentView] addSubview: tabView];
  if (buttonOut != NULL)
    {
      *buttonOut = button;
    }
  if (tabViewOut != NULL)
    {
      *tabViewOut = tabView;
    }
  return AUTORELEASE (window);
}

/* The control of `class` in `window`'s content view. */
static id
QuirkProbeNibMetricsControl(NSWindow *window, Class class)
{
  NSEnumerator *enumerator = [[[window contentView] subviews] objectEnumerator];
  NSView *view;

  while ((view = [enumerator nextObject]) != nil)
    {
      if ([view isKindOfClass: class])
        {
          return view;
        }
    }
  return nil;
}

/* "font 12, margins 0/0, cell 61x24, tab content 252x93" */
static NSString *
QuirkProbeNibMetricsDescription(NSButton *button, NSTabView *tabView)
{
  GSThemeMargins margins = [[GSTheme theme] buttonMarginsForCell: [button cell]
                                                           style: NSRoundedBezelStyle
                                                           state: GSThemeNormalState];
  NSSize cellSize = [[button cell] cellSize];
  NSRect content = [tabView contentRect];

  return [NSString stringWithFormat: @"font %g, margins %g/%g, cell %gx%g, tab content %gx%g",
    [[button font] pointSize], margins.left, margins.top,
    cellSize.width, cellSize.height, NSWidth (content), NSHeight (content)];
}

@implementation QuirkProbe (NibMetrics)

/* In a tab view's tab row (`rowHeight` from the top), the rows holding
   the label's text (dark or light against the row's colour, not the
   accent) and the accent underline's first row; -1 when there is none. */
static void
QuirkProbeTabRowInk(NSTabView *tabView, CGFloat rowHeight,
                    NSInteger *textTop, NSInteger *textBottom, NSInteger *accentTop)
{
  NSRect bounds = [tabView bounds];
  NSBitmapImageRep *rep = [tabView bitmapImageRepForCachingDisplayInRect: bounds];
  NSInteger x, y, rows = (NSInteger)rowHeight;
  NSColor *background;
  CGFloat backgroundSum;

  [tabView cacheDisplayInRect: bounds toBitmapImageRep: rep];
  background = [[rep colorAtX: (NSInteger)NSWidth (bounds) - 4 y: rows / 2]
    colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  backgroundSum = [background redComponent] + [background greenComponent] + [background blueComponent];
  *textTop = *textBottom = *accentTop = -1;
  for (y = 0; y < rows && y < [rep pixelsHigh]; y++)
    {
      for (x = 2; x < [rep pixelsWide] - 2; x++)
        {
          NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
          CGFloat r = [c redComponent], g = [c greenComponent], b = [c blueComponent];

          if (b > r + 0.12 && b > g + 0.04)
            {
              if (*accentTop < 0)
                {
                  *accentTop = y;
                }
            }
          else if (fabs (r + g + b - backgroundSum) > 0.9)
            {
              if (*textTop < 0)
                {
                  *textTop = y;
                }
              *textBottom = y;
            }
        }
    }
}

- (void) checkNibMetrics
{
  NSString *choice = [[NSUserDefaults standardUserDefaults] stringForKey: @"GnomeThemeMetrics"];
  BOOL perWindow = (choice == nil || [choice isEqualToString: @"auto"]);
  BOOL compact = [choice isEqualToString: @"compact"];
  NSString *path = [NSTemporaryDirectory () stringByAppendingPathComponent:
    [NSString stringWithFormat: @"QuirkProbeNibMetrics-%d.gorm", [[NSProcessInfo processInfo] processIdentifier]]];
  NSFileManager *manager = [NSFileManager defaultManager];
  GSNibContainer *container = AUTORELEASE ([GSNibContainer new]);
  NSWindow *archived = QuirkProbeNibMetricsWindow (NULL, NULL);
  NSButton *codeButton = nil;
  NSTabView *codeTabView = nil;
  NSWindow *codeWindow = QuirkProbeNibMetricsWindow (&codeButton, &codeTabView);
  NSMutableArray *topLevelObjects = [NSMutableArray array];
  NSDictionary *context;
  NSWindow *nibWindow = nil;
  NSButton *nibButton;
  NSTabView *nibTabView;
  NSArray *before;
  NSEnumerator *enumerator;
  id object;
  CGFloat codeSize, nibSize, codeMargin, nibMargin;
  NSString *detail;
  BOOL ok;

  /* Gorm's file: a directory holding objects.gorm. */
  [[container nameTable] setObject: archived forKey: @"QuirkProbeNibWindow"];
  [[container topLevelObjects] addObject: archived];
  [manager removeFileAtPath: path handler: nil];
  [manager createDirectoryAtPath: path attributes: nil];
  if ([NSArchiver archiveRootObject: container
                             toFile: [path stringByAppendingPathComponent: @"objects.gorm"]] == NO)
    {
      [self fail: @"nib-metrics-load" detail: @"couldn't write the Gorm file"];
      return;
    }

  /* As an app asks for its top level objects. */
  context = [NSDictionary dictionaryWithObjectsAndKeys:
    self, NSNibOwner, topLevelObjects, NSNibTopLevelObjects, nil];
  if ([NSBundle loadNibFile: path externalNameTable: context withZone: NSDefaultMallocZone ()])
    {
      enumerator = [topLevelObjects objectEnumerator];
      while ((object = [enumerator nextObject]) != nil)
        {
          if ([object isKindOfClass: [NSWindow class]])
            {
              nibWindow = object;
            }
        }
    }
  nibButton = QuirkProbeNibMetricsControl (nibWindow, [NSButton class]);
  nibTabView = QuirkProbeNibMetricsControl (nibWindow, [NSTabView class]);
  if (nibButton == nil || nibTabView == nil)
    {
      [self fail: @"nib-metrics-load"
          detail: [NSString stringWithFormat: @"%lu top level objects, window %@",
                     (unsigned long)[topLevelObjects count], nibWindow]];
      [manager removeFileAtPath: path handler: nil];
      return;
    }
  [self pass: @"nib-metrics-load" detail: @"window loaded from a Gorm file"];

  detail = [NSString stringWithFormat: @"%@: code window %@; Gorm window %@",
    choice != nil ? choice : @"auto",
    QuirkProbeNibMetricsDescription (codeButton, codeTabView),
    QuirkProbeNibMetricsDescription (nibButton, nibTabView)];
  codeSize = [[codeButton font] pointSize];
  nibSize = [[nibButton font] pointSize];
  codeMargin = [[GSTheme theme] buttonMarginsForCell: [codeButton cell]
                                                style: NSRoundedBezelStyle
                                                state: GSThemeNormalState].left;
  nibMargin = [[GSTheme theme] buttonMarginsForCell: [nibButton cell]
                                               style: NSRoundedBezelStyle
                                               state: GSThemeNormalState].left;
  if (perWindow)
    {
      /* The Gorm window at GNUstep's size and margins, with a shorter tab
         row; the code window at GNOME's. */
      ok = fabs (nibSize - 12.0) < 0.5 && codeSize > 13.0
        && nibMargin < codeMargin
        && [[nibButton cell] cellSize].height < [[codeButton cell] cellSize].height
        && NSHeight ([nibTabView contentRect]) > NSHeight ([codeTabView contentRect]);
    }
  else
    {
      /* Both windows the same, at the size the choice gives. */
      ok = fabs (nibSize - codeSize) < 0.01 && fabs (nibMargin - codeMargin) < 0.01
        && NSEqualSizes ([[nibButton cell] cellSize], [[codeButton cell] cellSize])
        && NSEqualRects ([nibTabView contentRect], [codeTabView contentRect])
        && (compact ? fabs (codeSize - 12.0) < 0.5 : codeSize > 13.0);
    }
  /* For comparing runs: the width of a line in the Gorm window's font. */
  printf ("# nib-metrics: text width %g at %gpt\n",
          [@"The quick brown fox jumps over the lazy dog"
            sizeWithAttributes: [NSDictionary dictionaryWithObject: [nibButton font]
                                                            forKey: NSFontAttributeName]].width,
          nibSize);
  fflush (stdout);
  if (ok)
    {
      [self pass: @"nib-metrics-per-window" detail: detail];
    }
  else
    {
      [self fail: @"nib-metrics-per-window" detail: detail];
    }

  /* The Gorm window's tab row is GNUstep's, 17pt: the label clear of the
     frame above it and of the selected tab's underline (it touched both,
     and GNUstep's own label showed at the top). */
  {
    NSInteger textTop, textBottom, accentTop;
    CGFloat rowHeight = NSMinY ([nibTabView contentRect]);

    [nibWindow orderFront: nil];
    [nibWindow display];
    QuirkProbeTabRowInk (nibTabView, rowHeight, &textTop, &textBottom, &accentTop);
    detail = [NSString stringWithFormat: @"%@: tab row %gpt; label rows %ld to %ld, underline from %ld",
      choice != nil ? choice : @"auto", rowHeight, (long)textTop, (long)textBottom, (long)accentTop];
    if (textTop >= 2 && accentTop > textBottom)
      {
        [self pass: @"nib-metrics-tab-label" detail: detail];
      }
    else
      {
        [self fail: @"nib-metrics-tab-label" detail: detail];
      }
    [nibWindow orderOut: nil];
  }

  /* Loaded without asking for the top level objects, as NSBundle's
     +loadNibNamed:owner: does: the window is still the Gorm file's. */
  before = [NSArray arrayWithArray: [NSApp windows]];
  nibWindow = nil;
  if ([NSBundle loadNibFile: path
          externalNameTable: [NSDictionary dictionaryWithObject: self forKey: NSNibOwner]
                   withZone: NSDefaultMallocZone ()])
    {
      enumerator = [[NSApp windows] objectEnumerator];
      while ((object = [enumerator nextObject]) != nil)
        {
          if ([before indexOfObjectIdenticalTo: object] == NSNotFound
            && [[object title] isEqualToString: @"QuirkProbe Nib Metrics"])
            {
              nibWindow = object;
            }
        }
    }
  nibButton = QuirkProbeNibMetricsControl (nibWindow, [NSButton class]);
  detail = [NSString stringWithFormat: @"%@: font %g in a window loaded without its top level objects",
    choice != nil ? choice : @"auto", [[nibButton font] pointSize]];
  if (nibButton != nil
    && fabs ([[nibButton font] pointSize] - (perWindow ? 12.0 : codeSize)) < 0.5)
    {
      [self pass: @"nib-metrics-no-top-level" detail: detail];
    }
  else
    {
      [self fail: @"nib-metrics-no-top-level" detail: detail];
    }
  [nibWindow orderOut: nil];
  [codeWindow orderOut: nil];
  [manager removeFileAtPath: path handler: nil];
}

@end
