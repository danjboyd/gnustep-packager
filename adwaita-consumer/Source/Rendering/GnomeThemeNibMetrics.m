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

/* Compact metrics for the windows an app built in code loads from nib or
   Gorm files (#24). Such an app gets GNOME's metrics, but its nib windows
   (its own, or libs-gui's panels) were laid out at GNUstep's: 12pt text
   and GNUstep's button margins. Loading one through NSNib (which every
   loader goes through) marks the windows and views it made, and gives
   their controls' fonts GNUstep's size; metrics asked for a view in a
   marked window, or while a nib loads, are then compact ones
   (-[GnomeTheme metricsForView:]). The app's fonts and menus stay
   GNOME's: they are the app's, not a window's. */

#import "../GnomeTheme.h"
#import "../Settings/GnomeThemeSettings.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static char GnomeThemeNibMetricsKey;
/* Nib loads under way: what they make, and what its awakeFromNib methods
   size, is laid out at compact metrics. */
static NSInteger GnomeThemeNibLoadDepth = 0;
/* GnomeThemeSetMetricsView(). */
static NSView *GnomeThemeMetricsView = nil;

static GnomeTheme *
GnomeThemeNibMetricsTheme(void)
{
  GSTheme *theme = [GSTheme theme];

  return [theme isKindOfClass: [GnomeTheme class]] ? (GnomeTheme *)theme : nil;
}

NSView *
GnomeThemeSetMetricsView(NSView *view)
{
  NSView *previous = GnomeThemeMetricsView;

  GnomeThemeMetricsView = view;
  return previous;
}

static BOOL
GnomeThemeIsFromNib(id object)
{
  return object != nil && objc_getAssociatedObject (object, &GnomeThemeNibMetricsKey) != nil;
}

static void
GnomeThemeMarkFromNib(id object)
{
  objc_setAssociatedObject (object, &GnomeThemeNibMetricsKey,
                            [NSNumber numberWithBool: YES], OBJC_ASSOCIATION_RETAIN);
}

BOOL
GnomeThemeViewUsesNibMetrics(NSView *view)
{
  NSView *ancestor;

  if (GnomeThemeNibLoadDepth > 0)
    {
      return YES;
    }
  if (view == nil)
    {
      view = (GnomeThemeMetricsView != nil) ? GnomeThemeMetricsView : [NSView focusView];
    }
  /* A view from a nib, put into a window built in code, keeps its own. */
  for (ancestor = view; ancestor != nil; ancestor = [ancestor superview])
    {
      if (GnomeThemeIsFromNib (ancestor))
        {
          return YES;
        }
    }
  return view != nil && GnomeThemeIsFromNib ([view window]);
}

/* A cell knows its control only once it has drawn in it, and is asked
   for its size before that: the nib's cells are marked too. */
BOOL
GnomeThemeCellUsesNibMetrics(NSCell *cell, NSView *controlView)
{
  if (GnomeThemeIsFromNib (cell))
    {
      return YES;
    }
  return GnomeThemeViewUsesNibMetrics (controlView != nil ? controlView : [cell controlView]);
}

/* The font a nib control decoded at GNOME's size, at GNUstep's: Gorm
   archives the system fonts by role, so they decode at the app's size
   (NSFontSize, NSSmallFontSize, NSMiniFontSize: see -runtimeDefaultsDictionary).
   nil for other fonts, which the nib gave a size of their own. */
static NSFont *
GnomeThemeNibFont(NSFont *font, GnomeThemeSettings *settings)
{
  CGFloat gnome = [settings interfaceFontSize];
  CGFloat compact = [settings compactInterfaceFontSize];
  CGFloat size = [font pointSize];
  CGFloat target = 0.0;

  if (font == nil)
    {
      return nil;
    }
  if (fabs (size - gnome) < 0.01)
    {
      target = compact;
    }
  else if (fabs (size - MAX (10.0, gnome - 1.0)) < 0.01)
    {
      target = MAX (10.0, compact - 1.0);
    }
  else if (fabs (size - MAX (9.0, gnome - 2.0)) < 0.01)
    {
      target = MAX (9.0, compact - 2.0);
    }
  if (target <= 0.0 || fabs (target - size) < 0.01)
    {
      return nil;
    }
  return [NSFont fontWithName: [font fontName] size: target];
}

/* Marks the cell; its font only for a text cell: -[NSCell setFont:] makes
   any cell one. */
static void
GnomeThemeCompactCellFont(NSCell *cell, GnomeThemeSettings *settings)
{
  NSFont *font;

  if (cell == nil)
    {
      return;
    }
  GnomeThemeMarkFromNib (cell);
  if ([cell type] != NSTextCellType)
    {
      return;
    }
  font = GnomeThemeNibFont ([cell font], settings);
  if (font != nil)
    {
      [cell setFont: font];
    }
}

static void
GnomeThemeCompactViewFonts(NSView *view, GnomeThemeSettings *settings)
{
  NSEnumerator *enumerator;
  id object;
  NSFont *font;

  if ([view isKindOfClass: [NSMatrix class]])
    {
      enumerator = [[(NSMatrix *)view cells] objectEnumerator];
      while ((object = [enumerator nextObject]) != nil)
        {
          GnomeThemeCompactCellFont (object, settings);
        }
      GnomeThemeCompactCellFont ([(NSMatrix *)view prototype], settings);
    }
  else if ([view isKindOfClass: [NSTableView class]])
    {
      enumerator = [[(NSTableView *)view tableColumns] objectEnumerator];
      while ((object = [enumerator nextObject]) != nil)
        {
          GnomeThemeCompactCellFont ([object dataCell], settings);
          GnomeThemeCompactCellFont ([object headerCell], settings);
        }
    }
  else if ([view isKindOfClass: [NSControl class]])
    {
      GnomeThemeCompactCellFont ([(NSControl *)view cell], settings);
    }
  else if ([view isKindOfClass: [NSBox class]])
    {
      font = GnomeThemeNibFont ([(NSBox *)view titleFont], settings);
      if (font != nil)
        {
          [(NSBox *)view setTitleFont: font];
        }
    }
  else if ([view isKindOfClass: [NSTabView class]])
    {
      font = GnomeThemeNibFont ([(NSTabView *)view font], settings);
      if (font != nil)
        {
          [(NSTabView *)view setFont: font];
        }
    }
  else if ([view isKindOfClass: [NSTextView class]])
    {
      font = GnomeThemeNibFont ([(NSTextView *)view font], settings);
      if (font != nil)
        {
          [(NSTextView *)view setFont: font];
        }
    }

  enumerator = [[view subviews] objectEnumerator];
  while ((object = [enumerator nextObject]) != nil)
    {
      GnomeThemeCompactViewFonts (object, settings);
    }
  [view setNeedsDisplay: YES];
}

@implementation GnomeTheme (NibMetrics)

- (BOOL) _overrideNSNibMethod_instantiateNibWithExternalNameTable: (NSDictionary *)table
                                                         withZone: (NSZone *)zone
{
  typedef BOOL (*InstantiateIMP)(id, SEL, NSDictionary *, NSZone *);
  InstantiateIMP originalIMP = (InstantiateIMP)GnomeThemeOriginalMethod (_cmd, self, [NSNib class]);
  GnomeTheme *theme = GnomeThemeNibMetricsTheme ();
  NSMutableArray *topLevelObjects = [table objectForKey: NSNibTopLevelObjects];
  NSDictionary *context = table;
  NSEnumerator *enumerator;
  id object;
  BOOL loaded = NO;

  if (originalIMP == NULL)
    {
      return NO;
    }
  if (theme == nil || [[theme settings] metricsFollowWindows] == NO)
    {
      return originalIMP (self, _cmd, table, zone);
    }

  /* The loaders retain the top level objects whether or not they're asked
     for, so asking for them changes nothing for the caller. */
  if ([topLevelObjects isKindOfClass: [NSMutableArray class]] == NO)
    {
      NSMutableDictionary *withObjects = [NSMutableDictionary dictionary];

      if (table != nil)
        {
          [withObjects addEntriesFromDictionary: table];
        }
      topLevelObjects = [NSMutableArray array];
      [withObjects setObject: topLevelObjects forKey: NSNibTopLevelObjects];
      context = withObjects;
    }

  GnomeThemeNibLoadDepth++;
  NS_DURING
    {
      loaded = originalIMP (self, _cmd, context, zone);
    }
  NS_HANDLER
    {
      GnomeThemeNibLoadDepth--;
      [localException raise];
    }
  NS_ENDHANDLER
  GnomeThemeNibLoadDepth--;

  enumerator = [topLevelObjects objectEnumerator];
  while (loaded && (object = [enumerator nextObject]) != nil)
    {
      if ([object isKindOfClass: [NSWindow class]])
        {
          GnomeThemeMarkFromNib (object);
          GnomeThemeCompactViewFonts ([[object contentView] superview] != nil
                                        ? [[object contentView] superview] : [object contentView],
                                      [theme settings]);
        }
      else if ([object isKindOfClass: [NSView class]])
        {
          GnomeThemeMarkFromNib (object);
          GnomeThemeCompactViewFonts (object, [theme settings]);
        }
    }
  return loaded;
}

@end
