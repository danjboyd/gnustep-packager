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

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#import "AppController.h"

static NSString *ThemeDemoLaunchOptionsDomain = @"ThemeDemoLaunchOptions";
static NSString *ThemeDemoSelectedPageKey = @"ThemeDemoSelectedPage";
static NSString *ThemeDemoOpenMenuKey = @"ThemeDemoOpenMenu";
static NSString *ThemeDemoQuitAfterKey = @"ThemeDemoQuitAfter";
static NSString *ThemeDemoWindowTitleKey = @"ThemeDemoWindowTitle";
static NSString *ThemeDemoCaptureMenuKey = @"ThemeDemoCaptureMenu";
static NSString *ThemeDemoCaptureMenuOutputKey = @"ThemeDemoCaptureMenuOutput";
static NSString *ThemeDemoCaptureMenuHighlightKey = @"ThemeDemoCaptureMenuHighlight";
static NSString *ThemeDemoDumpMenuGeometryKey = @"ThemeDemoDumpMenuGeometry";
static NSString *ThemeDemoDumpTabGeometryKey = @"ThemeDemoDumpTabGeometry";
static NSString *ThemeDemoDumpTypographyKey = @"ThemeDemoDumpTypography";
static NSString *ThemeDemoCommandScriptKey = @"ThemeDemoCommandScript";
static NSString *ThemeDemoCommandFIFOKey = @"ThemeDemoCommandFIFO";
static NSString *ThemeDemoScreenshotOutputKey = @"ThemeDemoScreenshotOutput";

static void
ThemeDemoApplyLaunchOptions(int argc, const char **argv)
{
  NSMutableDictionary *options = [NSMutableDictionary dictionary];
  NSInteger index = 1;
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray *searchList = nil;

  while (index < argc)
    {
      NSString *arg = [NSString stringWithUTF8String: argv[index]];

      if ([arg isEqualToString: @"--page"] && (index + 1) < argc)
        {
          [options setObject: [NSString stringWithUTF8String: argv[index + 1]]
                      forKey: ThemeDemoSelectedPageKey];
          index += 2;
        }
      else if ([arg isEqualToString: @"--open-menu"] && (index + 1) < argc)
        {
          [options setObject: [NSString stringWithUTF8String: argv[index + 1]]
                      forKey: ThemeDemoOpenMenuKey];
          index += 2;
        }
      else if ([arg isEqualToString: @"--quit-after"] && (index + 1) < argc)
        {
          [options setObject: [NSNumber numberWithDouble: atof (argv[index + 1])]
                      forKey: ThemeDemoQuitAfterKey];
          index += 2;
        }
      else if ([arg isEqualToString: @"--window-title"] && (index + 1) < argc)
        {
          [options setObject: [NSString stringWithUTF8String: argv[index + 1]]
                      forKey: ThemeDemoWindowTitleKey];
          index += 2;
        }
      else if ([arg isEqualToString: @"--capture-menu"] && (index + 1) < argc)
        {
          [options setObject: [NSString stringWithUTF8String: argv[index + 1]]
                      forKey: ThemeDemoCaptureMenuKey];
          index += 2;
        }
      else if ([arg isEqualToString: @"--capture-menu-output"] && (index + 1) < argc)
        {
          [options setObject: [NSString stringWithUTF8String: argv[index + 1]]
                      forKey: ThemeDemoCaptureMenuOutputKey];
          index += 2;
        }
      else if ([arg isEqualToString: @"--capture-menu-highlight"] && (index + 1) < argc)
        {
          [options setObject: [NSNumber numberWithInteger: atoi (argv[index + 1])]
                      forKey: ThemeDemoCaptureMenuHighlightKey];
          index += 2;
        }
      else if ([arg isEqualToString: @"--dump-menu-geometry"] && (index + 1) < argc)
        {
          [options setObject: [NSString stringWithUTF8String: argv[index + 1]]
                      forKey: ThemeDemoDumpMenuGeometryKey];
          index += 2;
        }
      else if ([arg isEqualToString: @"--dump-tab-geometry"])
        {
          [options setObject: @"YES" forKey: ThemeDemoDumpTabGeometryKey];
          index += 1;
        }
      else if ([arg isEqualToString: @"--dump-typography"])
        {
          [options setObject: @"YES" forKey: ThemeDemoDumpTypographyKey];
          index += 1;
        }
      else if ([arg isEqualToString: @"--command-script"] && (index + 1) < argc)
        {
          [options setObject: [NSString stringWithUTF8String: argv[index + 1]]
                      forKey: ThemeDemoCommandScriptKey];
          index += 2;
        }
      else if ([arg isEqualToString: @"--command-fifo"] && (index + 1) < argc)
        {
          [options setObject: [NSString stringWithUTF8String: argv[index + 1]]
                      forKey: ThemeDemoCommandFIFOKey];
          index += 2;
        }
      else if ([arg isEqualToString: @"--screenshot"] && (index + 1) < argc)
        {
          [options setObject: [NSString stringWithUTF8String: argv[index + 1]]
                      forKey: ThemeDemoScreenshotOutputKey];
          index += 2;
        }
      else
        {
          index++;
        }
    }

  if ([options count] == 0)
    {
      return;
    }

  [defaults setVolatileDomain: options forName: ThemeDemoLaunchOptionsDomain];
  searchList = [[defaults searchList] mutableCopy];

  if ([searchList containsObject: ThemeDemoLaunchOptionsDomain] == NO)
    {
      [searchList insertObject: ThemeDemoLaunchOptionsDomain atIndex: 0];
      [defaults setSearchList: searchList];
    }

  RELEASE (searchList);
}

int
main(int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL(pool);

  [NSApplication sharedApplication];
  ThemeDemoApplyLaunchOptions (argc, argv);

  AppController *controller = [AppController new];
  [NSApp setDelegate: controller];

  [NSApp run];

  DESTROY(pool);
  return 0;
}
