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

#ifndef GNOME_THEME_SETTINGS_MONITOR_H
#define GNOME_THEME_SETTINGS_MONITOR_H

#import <Foundation/Foundation.h>

/* Posted on the main thread, once for a batch of changes, when one of the
   GNOME settings the theme follows changed (colour scheme, high contrast,
   fonts, Large Text, font hinting, overlay scrolling, the window buttons'
   layout, the title bar's actions). */
extern NSString *GnomeThemeDesktopSettingsDidChangeNotification;

/* Starts listening, when the GSettings schemas are installed; later calls
   do nothing. */
void GnomeThemeSettingsMonitorStart(void);

/* Stops listening. */
void GnomeThemeSettingsMonitorStop(void);

#endif
