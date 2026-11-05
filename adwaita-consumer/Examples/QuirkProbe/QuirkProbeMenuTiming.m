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

/* -ProbeOnly menu-timing: the CPU time to fill a pop-up button with a long
   menu (1,500 items, like an app's font menu) and size it, under this theme
   and under GNUstep's default theme in the same process
   (plugins-themes-Adwaita#46).
   Run by `make check-menu-timing`. */

#import "QuirkProbe.h"

#import <GNUstepGUI/GSTheme.h>
#include <time.h>

@interface QuirkProbe (MenuTimingResults)
- (void) pass: (NSString *)ident detail: (NSString *)detail;
- (void) fail: (NSString *)ident detail: (NSString *)detail;
- (void) finish;
@end

/* -ProbeMenuItems overrides the count. */
static NSUInteger
QuirkProbeMenuTimingItems(void)
{
  NSInteger count = [[NSUserDefaults standardUserDefaults] integerForKey: @"ProbeMenuItems"];

  return count > 0 ? (NSUInteger)count : 1500;
}

/* A pop-up of `count` items, titled as font families (the machine's, then
   numbered ones), some with key equivalents. */
static NSPopUpButton *
QuirkProbeLongPopUp(NSUInteger count)
{
  NSPopUpButton *popUp = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (0, 0, 200, 26)
                                                                 pullsDown: NO]);
  NSArray *families = [[NSFontManager sharedFontManager] availableFontFamilies];
  NSMutableArray *titles = [NSMutableArray arrayWithCapacity: count];
  NSUInteger i;

  for (i = 0; i < count; i++)
    {
      NSString *title = (i < [families count]) ? [families objectAtIndex: i]
        : [NSString stringWithFormat: @"Font Family %04lu", (unsigned long)i];

      [titles addObject: [NSString stringWithFormat: @"%@ %lu", title, (unsigned long)i]];
    }
  [popUp addItemsWithTitles: titles];
  for (i = 0; i < count; i += 100)
    {
      [[popUp itemAtIndex: i] setKeyEquivalent: @"k"];
    }
  return popUp;
}

/* CPU seconds to fill a pop-up with the items and size its menu, as an
   app building a font menu does. */
static double
QuirkProbeMenuTime(void)
{
  clock_t start = clock ();
  NSPopUpButton *popUp = QuirkProbeLongPopUp (QuirkProbeMenuTimingItems ());
  NSMenuView *menuView = [[popUp menu] menuRepresentation];

  [menuView sizeToFit];
  [popUp sizeToFit];
  return (double)(clock () - start) / CLOCKS_PER_SEC;
}

@implementation QuirkProbe (MenuTiming)

- (void) checkMenuTiming
{
  NSString *name = [[GSTheme theme] name];
  double themed = 1e9, plain = 1e9;
  int i;

  /* Best of two, each with a fresh pop-up; then GNUstep's theme, in the
     same process (the probe quits after, without switching back). Filling
     a menu is quadratic in libs-gui itself, so more items or runs take the
     probe past its time limit. */
  for (i = 0; i < 2; i++)
    {
      themed = MIN (themed, QuirkProbeMenuTime ());
    }
  [GSTheme setTheme: nil];
  for (i = 0; i < 2; i++)
    {
      plain = MIN (plain, QuirkProbeMenuTime ());
    }

  printf ("# %lu-item pop-up: %.3fs with %s, %.3fs with GNUstep's theme\n",
          (unsigned long)QuirkProbeMenuTimingItems (), themed, [name UTF8String], plain);
  fflush (stdout);
  /* No slower than GNUstep's own theme, give or take a fifth and the
     clock's resolution. */
  if (themed <= 1.2 * plain + 0.05)
    {
      [self pass: @"menu-fill-time" detail: [NSString stringWithFormat: @"%.3fs against %.3fs", themed, plain]];
    }
  else
    {
      [self fail: @"menu-fill-time"
          detail: [NSString stringWithFormat: @"%.3fs against GNUstep's %.3fs", themed, plain]];
    }
  [self finish];
}

@end
