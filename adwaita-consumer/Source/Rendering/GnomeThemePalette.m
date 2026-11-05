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

#import "GnomeThemePalette.h"
#import "../Settings/GnomeThemeSettings.h"

#import <AppKit/AppKit.h>
#include <math.h>

static NSColor *
GnomeThemeColorFromHex(NSString *hex)
{
  unsigned int value = 0;
  NSScanner *scanner = nil;

  if ([hex hasPrefix: @"#"])
    {
      hex = [hex substringFromIndex: 1];
    }

  scanner = [NSScanner scannerWithString: hex];
  if ([scanner scanHexInt: &value] == NO)
    {
      return [NSColor blackColor];
    }

  return [NSColor colorWithCalibratedRed: ((value >> 16) & 0xff) / 255.0
                                   green: ((value >> 8) & 0xff) / 255.0
                                    blue: (value & 0xff) / 255.0
                                   alpha: 1.0];
}

static void
GnomeThemePopulateLightPalette(NSColorList *colors)
{
  /* libadwaita 1.7's window_bg_color, with its slight blue. */
  [colors setColor: GnomeThemeColorFromHex (@"#fafafb") forKey: @"windowBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"controlBackgroundColor"];
  /* libadwaita's card colour (opaque): menus, pop-overs and the theme's
     own button, segment and switch shading. */
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"GnomeThemeCardColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ebebeb") forKey: @"controlColor"];
  /* The light edges of 3D bevels (GNUstep's grooves and bezels, as in Gorm's
     boxes), not selection colours: GNUstep's own are white. */
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"controlHighlightColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"controlLightHighlightColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#c7c7c7") forKey: @"controlShadowColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#8c8c8c") forKey: @"controlDarkShadowColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#1f1f1f") forKey: @"controlTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#7a7a7a") forKey: @"disabledControlTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#3584e4") forKey: @"selectedControlColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"selectedControlTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#99c1f1") forKey: @"alternateSelectedControlColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#102d4d") forKey: @"alternateSelectedControlTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#e6edf7") forKey: @"secondarySelectedControlColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#eceff3") forKey: @"selectedInactiveColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"textBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#1f1f1f") forKey: @"textColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#3584e4") forKey: @"selectedMenuItemColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"selectedMenuItemTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"menuBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"menuItemBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#d0d0d0") forKey: @"menuSeparatorColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#f6f6f6") forKey: @"menuBarBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#d6d6d6") forKey: @"menuBarBorderColor"];
  /* Toolbars sit on the window background, like a GNOME header bar, with a
     light bottom edge (GSTheme's fallback is dark grey). */
  [colors setColor: GnomeThemeColorFromHex (@"#fafafb") forKey: @"toolbarBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#e6e6e6") forKey: @"toolbarBorderColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#d6d6d6") forKey: @"menuBorderColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#c7c7c7") forKey: @"scrollBarColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#e8e8e8") forKey: @"headerColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#1f1f1f") forKey: @"headerTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#d6d6d6") forKey: @"gridColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#dfe6ef") forKey: @"highlightedTableRowBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#1f1f1f") forKey: @"highlightedTableRowTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"rowBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#f6f6f6") forKey: @"alternateRowBackgroundColor"];
  /* libadwaita's warning_bg_color and error_bg_color (yellow_5, red_3). */
  [colors setColor: GnomeThemeColorFromHex (@"#e5a50a") forKey: @"GnomeThemeWarningColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#e01b24") forKey: @"GnomeThemeErrorColor"];
  /* libadwaita's destructive_color, for destructive text: red_3 with its
     Oklab lightness at most 0.5. */
  [colors setColor: GnomeThemeColorFromHex (@"#c30000") forKey: @"GnomeThemeDestructiveTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#1c71d8") forKey: @"keyboardFocusIndicatorColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#3584e4") forKey: @"highlightColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#8c8c8c") forKey: @"shadowColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"windowFrameTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#4a4a4a") forKey: @"windowFrameColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#99c1f1") forKey: @"selectedTextBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#1f1f1f") forKey: @"selectedTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#1f1f1f") forKey: @"labelColor"];
  /* libadwaita's dimmed labels: the text colour at 55% over the window
     background; the next steps down at 40% and 25%. Unset, libs-gui gives
     them black (#51). */
  [colors setColor: GnomeThemeColorFromHex (@"#828282") forKey: @"secondaryLabelColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#a2a2a2") forKey: @"tertiaryLabelColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#c3c3c3") forKey: @"quaternaryLabelColor"];
  /* libadwaita's tool tips are 80% black over whatever is behind them; our
     tool tip windows are opaque, so this is that over the window
     background. */
  [colors setColor: GnomeThemeColorFromHex (@"#323232") forKey: @"toolTipColor"];
  [colors setColor: [NSColor whiteColor] forKey: @"toolTipTextColor"];
  /* libadwaita's slider knob: white over the trough, also in high
     contrast (#56). */
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"sliderKnobColor"];
}

static void
GnomeThemePopulateDarkPalette(NSColorList *colors)
{
  [colors setColor: GnomeThemeColorFromHex (@"#222226") forKey: @"windowBackgroundColor"];
  /* libadwaita's view_bg_color, as lists and text views draw it: a view
     an app fills with controlBackgroundColor matches the lists beside it,
     as in the light palette (#94). */
  [colors setColor: GnomeThemeColorFromHex (@"#1d1d20") forKey: @"controlBackgroundColor"];
  /* libadwaita's card colour (opaque): menus, pop-overs and the theme's
     own button, segment and switch shading. */
  [colors setColor: GnomeThemeColorFromHex (@"#303030") forKey: @"GnomeThemeCardColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#3a3a3a") forKey: @"controlColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#484848") forKey: @"controlHighlightColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#555555") forKey: @"controlLightHighlightColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#1f1f1f") forKey: @"controlShadowColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#101010") forKey: @"controlDarkShadowColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#f5f5f5") forKey: @"controlTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#9a9a9a") forKey: @"disabledControlTextColor"];
  /* Fills are libadwaita's accent_bg_color with white accent_fg_color, as
     in the light palette; #78aeed (accent_color) is for accent text, links
     and focus rings (highlightColor, keyboardFocusIndicatorColor). */
  [colors setColor: GnomeThemeColorFromHex (@"#3584e4") forKey: @"selectedControlColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"selectedControlTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#4f7cb8") forKey: @"alternateSelectedControlColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#f5f5f5") forKey: @"alternateSelectedControlTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#3d4f66") forKey: @"secondarySelectedControlColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#36393d") forKey: @"selectedInactiveColor"];
  /* libadwaita's view_bg_color: text views and other content. */
  [colors setColor: GnomeThemeColorFromHex (@"#1d1d20") forKey: @"textBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#f5f5f5") forKey: @"textColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#4f7cb8") forKey: @"selectedMenuItemColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"selectedMenuItemTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#2b2b2b") forKey: @"menuBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#2b2b2b") forKey: @"menuItemBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#4a4a4a") forKey: @"menuSeparatorColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#222226") forKey: @"menuBarBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#3d3d3d") forKey: @"menuBarBorderColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#222226") forKey: @"toolbarBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#1a1a1a") forKey: @"toolbarBorderColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#3d3d3d") forKey: @"menuBorderColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#525252") forKey: @"scrollBarColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#303030") forKey: @"headerColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#f5f5f5") forKey: @"headerTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#3d3d3d") forKey: @"gridColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#355278") forKey: @"highlightedTableRowBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"highlightedTableRowTextColor"];
  /* libadwaita's view colour, as a plain GtkColumnView draws it over the
     window (#62); alternate rows the text colour at 3.5% over it. */
  [colors setColor: GnomeThemeColorFromHex (@"#1d1d20") forKey: @"rowBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#252528") forKey: @"alternateRowBackgroundColor"];
  /* libadwaita's dark warning_bg_color and error_bg_color (red_4). */
  [colors setColor: GnomeThemeColorFromHex (@"#cd9309") forKey: @"GnomeThemeWarningColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#c01c28") forKey: @"GnomeThemeErrorColor"];
  /* libadwaita's dark destructive_color: red_4 with its Oklab lightness at
     least 0.85. */
  [colors setColor: GnomeThemeColorFromHex (@"#ff938c") forKey: @"GnomeThemeDestructiveTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#78aeed") forKey: @"keyboardFocusIndicatorColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#78aeed") forKey: @"highlightColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#101010") forKey: @"shadowColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#ffffff") forKey: @"windowFrameTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#101010") forKey: @"windowFrameColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#78aeed") forKey: @"selectedTextBackgroundColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#0f1720") forKey: @"selectedTextColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#f5f5f5") forKey: @"labelColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#979797") forKey: @"secondaryLabelColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#787878") forKey: @"tertiaryLabelColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#585858") forKey: @"quaternaryLabelColor"];
  [colors setColor: GnomeThemeColorFromHex (@"#070707") forKey: @"toolTipColor"];
  [colors setColor: [NSColor whiteColor] forKey: @"toolTipTextColor"];
  /* libadwaita's dark slider knob, a light grey: the knob stays visible
     on the dark trough (#56). */
  [colors setColor: GnomeThemeColorFromHex (@"#d2d2d3") forKey: @"sliderKnobColor"];
}

/* libadwaita's high contrast keeps the light or dark palette and makes
   its lines stronger (its base-hc.css): borders and separators are the
   text colour at 50% instead of 15%, disabled controls fade to 40%
   instead of 50%, so they stand apart from enabled ones, and dimmed
   labels are stronger. */
static void
GnomeThemeApplyHighContrast(NSColorList *colors)
{
  NSColor *text = [colors colorWithKey: @"controlTextColor"];
  NSColor *background = [colors colorWithKey: @"windowBackgroundColor"];
  NSColor *border = [background blendedColorWithFraction: 0.5 ofColor: text];
  NSColor *strongBorder = [background blendedColorWithFraction: 0.7 ofColor: text];
  NSColor *disabled = [background blendedColorWithFraction: 0.4 ofColor: text];
  NSArray *borders = [NSArray arrayWithObjects: @"controlShadowColor", @"menuBorderColor", @"menuBarBorderColor",
                              @"toolbarBorderColor", @"menuSeparatorColor", @"gridColor", nil];
  NSEnumerator *enumerator = [borders objectEnumerator];
  NSString *key;

  if (text == nil || background == nil)
    {
      return;
    }
  while ((key = [enumerator nextObject]) != nil)
    {
      [colors setColor: border forKey: key];
    }
  [colors setColor: strongBorder forKey: @"controlDarkShadowColor"];
  [colors setColor: disabled forKey: @"disabledControlTextColor"];
  /* Dimmed labels are libadwaita's --dim-opacity, 90% in high contrast (the
     next steps down at 75% and 60%), instead of 55%, 40% and 25%. */
  [colors setColor: [background blendedColorWithFraction: 0.9 ofColor: text] forKey: @"secondaryLabelColor"];
  [colors setColor: [background blendedColorWithFraction: 0.75 ofColor: text] forKey: @"tertiaryLabelColor"];
  [colors setColor: [background blendedColorWithFraction: 0.6 ofColor: text] forKey: @"quaternaryLabelColor"];
}

/* libadwaita 1.7 draws its controls in the foreground colour at an opacity
   over the window background (alpha(currentColor, …)): buttons, entries
   and pop-ups at 10%, troughs and unchecked check boxes' and radios' rings
   at 15% (30% in high contrast), checked toggles and pressed buttons at
   30%; disabled controls are those at half opacity (40% in high
   contrast). High contrast adds a 1px outline, the foreground at 50%.
   The foreground is libadwaita's window_fg_color as it shows over the
   window: rgba(0, 0, 6, 0.8) in the light style, white in the dark one.
   These are the theme's own keys (GnomeThemeColor() in the renderers
   reads them). */
static void
GnomeThemeAddWidgetColors(NSColorList *colors, NSColor *foreground, BOOL highContrast)
{
  NSColor *window = [colors colorWithKey: @"windowBackgroundColor"];
  NSColor *button = nil;
  NSColor *trough = nil;

  if (window == nil || foreground == nil)
    {
      return;
    }
  button = [window blendedColorWithFraction: 0.10 ofColor: foreground];
  trough = [window blendedColorWithFraction: (highContrast ? 0.30 : 0.15) ofColor: foreground];
  [colors setColor: foreground forKey: @"GnomeThemeForegroundColor"];
  [colors setColor: button forKey: @"GnomeThemeButtonColor"];
  [colors setColor: [window blendedColorWithFraction: 0.30 ofColor: foreground]
            forKey: @"GnomeThemeButtonPressedColor"];
  [colors setColor: [button blendedColorWithFraction: (highContrast ? 0.6 : 0.5) ofColor: window]
            forKey: @"GnomeThemeButtonDisabledColor"];
  [colors setColor: trough forKey: @"GnomeThemeTroughColor"];
  /* Separators inside a control (a spin button's): the trough's 15%, or
     the outline in high contrast. */
  [colors setColor: (highContrast
                       ? [window blendedColorWithFraction: 0.5 ofColor: foreground]
                       : [window blendedColorWithFraction: 0.15 ofColor: foreground])
            forKey: @"GnomeThemeSeparatorColor"];
  if (highContrast)
    {
      [colors setColor: [window blendedColorWithFraction: 0.5 ofColor: foreground]
                forKey: @"GnomeThemeOutlineColor"];
    }
}

/* Keys the renderers ask for by name, set from the colours they are drawn
   in. Before the renderers read the palette first (GnomeThemeColor()),
   these keys never reached them: menus, the menu bar and their borders
   were drawn in the view, window and border colours, and those stay. A
   selected row is libadwaita's (measured from its GtkColumnView): the
   accent at 25% over the row's colour, whether or not the view has focus,
   with the row's own text colour; it had been
   alternateSelectedControlColor with white text. */
static void
GnomeThemeAddLookupColors(NSColorList *colors)
{
  NSColor *card = [colors colorWithKey: @"GnomeThemeCardColor"];
  NSColor *border = [colors colorWithKey: @"controlShadowColor"];
  NSColor *window = [colors colorWithKey: @"windowBackgroundColor"];
  NSColor *row = [colors colorWithKey: @"rowBackgroundColor"];
  NSColor *accent = [colors colorWithKey: @"selectedControlColor"];
  NSColor *text = [colors colorWithKey: @"controlTextColor"];
  NSColor *selection;

  if (card != nil)
    {
      [colors setColor: card forKey: @"menuBackgroundColor"];
    }
  if (border != nil)
    {
      [colors setColor: border forKey: @"menuBorderColor"];
      [colors setColor: border forKey: @"menuBarBorderColor"];
    }
  if (window != nil)
    {
      [colors setColor: window forKey: @"menuBarBackgroundColor"];
    }
  if (row != nil && accent != nil)
    {
      selection = [row blendedColorWithFraction: 0.25 ofColor: accent];
      [colors setColor: selection forKey: @"highlightedTableRowBackgroundColor"];
      [colors setColor: selection forKey: @"selectedInactiveColor"];
    }
  if (text != nil)
    {
      [colors setColor: text forKey: @"highlightedTableRowTextColor"];
    }
}

/* GNOME's accent colour (org.gnome.desktop.interface accent-color, GNOME
   47), as libadwaita's accent_bg_color. Blue keeps the palettes above as
   they are. */
static NSString *
GnomeThemeAccentHex(NSString *name)
{
  static NSDictionary *accents = nil;

  if (accents == nil)
    {
      accents = [[NSDictionary alloc] initWithObjectsAndKeys:
        @"#3584e4", @"blue", @"#2190a4", @"teal", @"#3a944a", @"green",
        @"#c88800", @"yellow", @"#ed5b00", @"orange", @"#e62d42", @"red",
        @"#d56199", @"pink", @"#9141ac", @"purple", @"#6f8396", @"slate", nil];
    }
  return (name != nil) ? [accents objectForKey: name] : nil;
}

static CGFloat
GnomeThemeLinear(CGFloat c)
{
  return (c <= 0.04045) ? c / 12.92 : pow ((c + 0.055) / 1.055, 2.4);
}

static CGFloat
GnomeThemeGamma(CGFloat c)
{
  c = MAX (0.0, MIN (1.0, c));
  return (c <= 0.0031308) ? c * 12.92 : 1.055 * pow (c, 1.0 / 2.4) - 0.055;
}

/* libadwaita's accent_color, the accent for text and focus rings:
   accent_bg_color in Oklab with its lightness at most 0.5 (light) or at
   least 0.85 (dark). */
static NSColor *
GnomeThemeStandaloneAccent(NSColor *background, BOOL dark)
{
  NSColor *rgb = [background colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  CGFloat r = GnomeThemeLinear ([rgb redComponent]);
  CGFloat g = GnomeThemeLinear ([rgb greenComponent]);
  CGFloat b = GnomeThemeLinear ([rgb blueComponent]);
  CGFloat l = cbrt (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  CGFloat m = cbrt (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  CGFloat s = cbrt (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  CGFloat L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  CGFloat A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  CGFloat B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;

  L = dark ? MAX (L, 0.85) : MIN (L, 0.5);
  l = L + 0.3963377774 * A + 0.2158037573 * B;
  m = L - 0.1055613458 * A - 0.0638541728 * B;
  s = L - 0.0894841775 * A - 1.2914855480 * B;
  l = l * l * l;
  m = m * m * m;
  s = s * s * s;
  return [NSColor colorWithCalibratedRed: GnomeThemeGamma (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
                                   green: GnomeThemeGamma (-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
                                    blue: GnomeThemeGamma (-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
                                   alpha: 1.0];
}

/* The accent's colours, for an accent other than blue: fills are
   accent_bg_color, text and focus rings accent_color, and the paler
   selections the accent over the view colour as blue's are. */
static void
GnomeThemeApplyAccent(NSColorList *colors, NSString *name, BOOL dark)
{
  NSString *hex = GnomeThemeAccentHex (name);
  NSColor *accent, *standalone, *view;

  if (hex == nil || [name isEqualToString: @"blue"])
    {
      return;
    }
  accent = GnomeThemeColorFromHex (hex);
  standalone = GnomeThemeStandaloneAccent (accent, dark);
  view = [colors colorWithKey: @"textBackgroundColor"];
  [colors setColor: accent forKey: @"selectedControlColor"];
  [colors setColor: standalone forKey: @"keyboardFocusIndicatorColor"];
  if (dark)
    {
      [colors setColor: standalone forKey: @"highlightColor"];
      [colors setColor: standalone forKey: @"selectedTextBackgroundColor"];
      [colors setColor: [standalone blendedColorWithFraction: 0.55 ofColor: view]
                forKey: @"alternateSelectedControlColor"];
      [colors setColor: [standalone blendedColorWithFraction: 0.55 ofColor: view]
                forKey: @"selectedMenuItemColor"];
      [colors setColor: [view blendedColorWithFraction: 0.3 ofColor: accent]
                forKey: @"secondarySelectedControlColor"];
    }
  else
    {
      [colors setColor: accent forKey: @"highlightColor"];
      [colors setColor: accent forKey: @"selectedMenuItemColor"];
      [colors setColor: [view blendedColorWithFraction: 0.5 ofColor: accent]
                forKey: @"selectedTextBackgroundColor"];
      [colors setColor: [view blendedColorWithFraction: 0.5 ofColor: accent]
                forKey: @"alternateSelectedControlColor"];
      [colors setColor: [accent blendedColorWithFraction: 0.7 ofColor: [NSColor blackColor]]
                forKey: @"alternateSelectedControlTextColor"];
      [colors setColor: [view blendedColorWithFraction: 0.12 ofColor: accent]
                forKey: @"secondarySelectedControlColor"];
    }
}

@implementation GnomeThemePalette

+ (NSColorList *) colorListForSettings: (GnomeThemeSettings *)settings
{
  NSColorList *colors = AUTORELEASE ([[NSColorList alloc] initWithName: @"System"
                                                              fromFile: nil]);
  BOOL dark = [settings prefersDarkAppearance];
  BOOL highContrast = [settings highContrastEnabled];

  if (dark)
    {
      GnomeThemePopulateDarkPalette (colors);
    }
  else
    {
      GnomeThemePopulateLightPalette (colors);
    }
  GnomeThemeApplyAccent (colors, [settings accentColorName], dark);
  if (highContrast)
    {
      GnomeThemeApplyHighContrast (colors);
    }
  GnomeThemeAddWidgetColors (colors,
                             GnomeThemeColorFromHex (dark ? @"#ffffff" : @"#323237"),
                             highContrast);
  GnomeThemeAddLookupColors (colors);

  return colors;
}

@end
