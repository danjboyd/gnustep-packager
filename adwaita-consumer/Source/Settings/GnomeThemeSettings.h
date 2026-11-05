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

typedef enum
{
  GnomeThemeColorSchemeDefault = 0,
  GnomeThemeColorSchemePreferLight = 1,
  GnomeThemeColorSchemePreferDark = 2
} GnomeThemeColorScheme;

@interface GnomeThemeSettings : NSObject
{
  NSString *_interfaceFontName;
  CGFloat _interfaceFontSize;
  NSString *_monospaceFontName;
  CGFloat _monospaceFontSize;
  NSString *_gtkThemeName;
  GnomeThemeColorScheme _colorScheme;
  NSString *_accentColorName;
  BOOL _highContrast;
  BOOL _overlayScrolling;
  NSInteger _fontHintStyle;
  CGFloat _textScalingFactor;
  BOOL _compactMetrics;
  BOOL _metricsFollowWindows;
  CGFloat _compactInterfaceFontSize;
  NSString *_buttonLayout;
  NSString *_titlebarDoubleClickAction;
  NSString *_titlebarMiddleClickAction;
  NSString *_titlebarRightClickAction;
}

- (void) reload;

- (NSString *) interfaceFontName;
- (CGFloat) interfaceFontSize;
- (NSString *) monospaceFontName;
- (CGFloat) monospaceFontSize;
- (NSString *) gtkThemeName;
- (BOOL) prefersDarkAppearance;
/* GNOME's accent colour by name (accent-color: blue, teal, green, yellow,
   orange, red, pink, purple or slate), or the app's GnomeThemeAccentColor;
   blue before GNOME 47. */
- (NSString *) accentColorName;
- (BOOL) highContrastEnabled;
/* GNOME's overlay-scrolling (on unless turned off): scrollbars that hide
   until needed, over the content. */
- (BOOL) overlayScrollingEnabled;
/* GNOME's font-hinting (none, slight, medium or full; slight when unset)
   as libs-back's hint style: 1 none, 2 slight, 3 medium, 4 full. */
- (NSInteger) fontHintStyle;
/* GNOME's text-scaling-factor (Large Text in the accessibility settings;
   1.0 when unset or outside GNOME's 0.5 to 3.0): the interface and
   monospace sizes are multiplied by it, as GTK's text is, and the metrics
   follow (#53). Compact metrics keep GNUstep's sizes. Read when the theme
   loads, like the other GNOME settings. */
- (CGFloat) textScalingFactor;
/* GNUstep's metrics (12pt text, GNUstep's button margins and tab height)
   instead of GNOME's, for apps whose windows come from Gorm or nib files and
   were laid out at those metrics. The GnomeThemeMetrics default chooses
   ("compact" or "gnome", for every window), then the same key in the app's
   Info.plist; otherwise ("auto", or no choice) apps with a main nib,
   storyboard or markup file get compact metrics. */
- (BOOL) compactMetrics;
/* An app built in code with no choice made ("auto"): GNOME's metrics, but
   compact metrics for the windows it loads from nib or Gorm files (#24). */
- (BOOL) metricsFollowWindows;
/* The interface font's size with compact metrics. */
- (CGFloat) compactInterfaceFontSize;

/* org.gnome.desktop.wm.preferences: button-layout (for example
   "appmenu:minimize,maximize,close") and the title bar's
   action-double-click-titlebar, action-middle-click-titlebar and
   action-right-click-titlebar (for example "toggle-maximize", "none",
   "menu"), with GNOME's defaults when unset. */
- (NSString *) buttonLayout;
- (NSString *) titlebarDoubleClickAction;
- (NSString *) titlebarMiddleClickAction;
- (NSString *) titlebarRightClickAction;

- (NSFont *) interfaceFont;
- (NSFont *) boldInterfaceFont;
- (NSFont *) menuFont;
- (NSFont *) menuBarFont;
- (NSFont *) fixedPitchFont;

@end
