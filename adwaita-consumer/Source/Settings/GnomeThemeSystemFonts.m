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

/* System fonts that follow a change of GNOME's fonts while the app runs
   (#64).

   NSFont keeps the font it first made for each role at the default size
   (+systemFontOfSize: 0 and the others), and nothing but
   +setUserFont: / +setUserFixedPitchFont: empties that cache, and those
   write the user's defaults. So once the fonts change, the role methods
   are given the size the defaults say now instead of 0: the font name
   is read from the defaults on every call already, and asking with a
   size bypasses the stale cache. Until a change, nothing is replaced. */

#import "../GnomeTheme.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

typedef struct
{
  const char *selector;
  NSString *key;
  IMP original;
} GnomeThemeFontRole;

static GnomeThemeFontRole GnomeThemeFontRoles[] = {
  { "systemFontOfSize:", @"NSFont", NULL },
  { "boldSystemFontOfSize:", @"NSBoldFont", NULL },
  { "userFontOfSize:", @"NSUserFont", NULL },
  { "userFixedPitchFontOfSize:", @"NSUserFixedPitchFont", NULL },
  { "controlContentFontOfSize:", @"NSControlContentFont", NULL },
  { "labelFontOfSize:", @"NSLabelFont", NULL },
  { "menuFontOfSize:", @"NSMenuFont", NULL },
  { "menuBarFontOfSize:", @"NSMenuBarFont", NULL },
  { "messageFontOfSize:", @"NSMessageFont", NULL },
  { "paletteFontOfSize:", @"NSPaletteFont", NULL },
  { "titleBarFontOfSize:", @"NSTitleBarFont", NULL },
  { "toolTipsFontOfSize:", @"NSToolTipsFont", NULL },
  { NULL, nil, NULL }
};

static BOOL GnomeThemeFontsChanged = NO;

/* The size NSFont would use for the role at the default size. */
static CGFloat
GnomeThemeDefaultSizeForRole(NSString *key)
{
  CGFloat size = [[NSUserDefaults standardUserDefaults] floatForKey:
                    [key stringByAppendingString: @"Size"]];

  return size > 0.0 ? size : [NSFont systemFontSize];
}

static id
GnomeThemeRoleFontOfSize(id self, SEL _cmd, CGFloat size)
{
  GnomeThemeFontRole *role;

  for (role = GnomeThemeFontRoles; role->selector != NULL; role++)
    {
      if (sel_isEqual (_cmd, sel_registerName (role->selector)))
        {
          if (GnomeThemeFontsChanged && size <= 0.0)
            {
              size = GnomeThemeDefaultSizeForRole (role->key);
            }
          return ((id (*)(id, SEL, CGFloat))role->original) (self, _cmd, size);
        }
    }
  return nil;
}

void
GnomeThemeSystemFontsDidChange(void)
{
  GnomeThemeFontRole *role;

  if (GnomeThemeFontsChanged)
    {
      return;
    }
  for (role = GnomeThemeFontRoles; role->selector != NULL; role++)
    {
      Method method = class_getClassMethod ([NSFont class], sel_registerName (role->selector));

      if (method != NULL)
        {
          role->original = method_setImplementation (method, (IMP)GnomeThemeRoleFontOfSize);
        }
    }
  GnomeThemeFontsChanged = YES;
}
