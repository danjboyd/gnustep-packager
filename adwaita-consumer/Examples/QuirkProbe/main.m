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
#import "QuirkProbe.h"

int
main (int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSMenu *mainMenu;
  NSMenu *fileMenu;
  NSMenuItem *fileItem;
  QuirkProbe *probe;

  [NSApplication sharedApplication];

  mainMenu = [[NSMenu alloc] initWithTitle: @"QuirkProbe"];
  fileMenu = [[NSMenu alloc] initWithTitle: @"File"];
  [fileMenu addItemWithTitle: @"Quit"
                      action: @selector(terminate:)
               keyEquivalent: @"q"];
  fileItem = (NSMenuItem *)[mainMenu addItemWithTitle: @"File" action: NULL keyEquivalent: @""];
  [mainMenu setSubmenu: fileMenu forItem: fileItem];
  [NSApp setMainMenu: mainMenu];
  RELEASE (fileMenu);
  RELEASE (mainMenu);

  /* NSApp doesn't retain its delegate. */
  probe = [QuirkProbe new];
  [NSApp setDelegate: probe];
  [NSApp run];

  RELEASE (probe);
  [pool drain];
  return 0;
}
