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

#import <GNUstepGUI/GSTheme.h>

@class GnomeThemeSettings;
@class GnomeThemeMetrics;

/* The implementation a theme override replaced. GSTheme's -overriddenMethod:for:
   only matches the receiver's exact class, so when a subclass (for example
   GSToolbarButtonCell or NSMenuItemCell) reaches an override through `super`,
   it answers NULL and the override has nothing to fall back on. This looks the
   method up for `baseClass`, the class the override was installed on, instead. */
IMP GnomeThemeOriginalMethod(SEL selector, id receiver, Class baseClass);
IMP GnomeThemeOriginalMethodOfClass(SEL selector, Class cls);
void GnomeThemeForgetOriginalMethods(void);

/* Centred and right-aligned text as the running libs-gui numbers them.
   libs-gui after 0.32 numbers NSTextAlignment as AppKit does (centre 1,
   right 2; 0.32 has right 1, centre 2), so the constants a theme built
   against one release's headers mean the other alignment with the other
   release. */
NSTextAlignment GnomeThemeCenterTextAlignment(void);
NSTextAlignment GnomeThemeRightTextAlignment(void);

/* YES for the application-name item GNUstep puts first in a horizontal
   (NSWindows95InterfaceStyle) main menu (see -organizeMenu:isHorizontal:). The
   theme draws it as a GNOME main-menu icon instead of the app's name. */
BOOL GnomeThemeIsApplicationMenuItem(NSMenuItem *item);

/* Width of that icon. */
extern const CGFloat GnomeThemeApplicationMenuIconWidth;

/* Draws that icon (GNOME's open-menu-symbolic) centred in `rect`. */
void GnomeThemeDrawApplicationMenuIcon(NSRect rect, NSColor *color);

/* YES when the app asked for GNOME's primary menu instead of a menu bar
   (the GnomeThemeMenuStyle default set to "primary"). */
BOOL GnomeThemeUsesPrimaryMenu(void);
/* Where a context menu opened at `point` goes: GTK's place by the pointer,
   kept on `screen` (#20). */
NSPoint GnomeThemeContextMenuOrigin(NSPoint point, NSSize size, NSRect screen);
/* YES on Wayland, where Mutter leaves an XWayland window frozen if it's
   resized while on screen and hidden before its next paint
   (GNOME/mutter#5080): the theme then doesn't resize windows about to be
   hidden. */
BOOL GnomeThemeKeepsHiddenWindowSize(void);

/* YES when GNUstep draws the window decorations itself
   (GSX11HandlesWindowDecorations NO): the theme then draws libadwaita's
   header bar as the windows' title bar. */
BOOL GnomeThemeUsesHeaderBar(void);
/* Whether a toolbar is shown in its window's header bar row
   (GnomeThemeHeaderBarToolbar), not as a row of its own. */
BOOL GnomeThemeToolbarInHeaderBar(NSToolbar *toolbar);
/* Whether the GnomeThemeHeaderBarToolbar setting puts this app's toolbars
   in the header bar, and the call that applies a change to it to the open
   windows. */
BOOL GnomeThemeHeaderBarToolbarEnabled(void);
void GnomeThemeHeaderBarToolbarSettingChanged(void);
/* GNOME's settings changed while the app runs (#64): lay the window
   buttons out again (button-layout) and redraw open header bars. */
void GnomeThemeHeaderBarDesktopSettingsChanged(void);
/* GNOME's fonts changed while the app runs (#64): NSFont's role methods
   stop handing out the fonts they cached for the default size
   (Source/Settings/GnomeThemeSystemFonts.m). */
void GnomeThemeSystemFontsDidChange(void);
/* While the app waits for a modal dialog outside it (the portal's file
   chooser): a press in a header bar that moves its window, which then
   isn't dropped. YES when the press was taken. */
BOOL GnomeThemeHeaderBarMoveWindowFromModalPress(NSEvent *event);
/* Around libs-gui's share-out of a toolbar's flexible width: with the
   toolbar in the header bar, room for the title is kept in its first
   flexible space before items stay in the bar. */
void GnomeThemeHeaderBarReserveTitleRoom(NSView *toolbarView);
void GnomeThemeHeaderBarGiveTitleRoom(NSView *toolbarView);
/* A toolbar too narrow for its items: those that stay, by
   visibilityPriority (*fromEnd is YES when they're libs-gui's run from
   the start), and placing them after libs-gui's share-out. */
NSIndexSet *GnomeThemeToolbarKeptItems(NSView *toolbarView, BOOL *fromEnd);
/* While a table header draws a column with a sort indicator, the room
   its title leaves for it: after the title (positive) or before a
   right-aligned one (negative); 0 otherwise. */
CGFloat GnomeThemeTableHeaderIndicatorRoom(void);
void GnomeThemeToolbarPlaceKeptItems(NSView *toolbarView);

/* Template (symbolic) images: whether `image` is one (-isTemplate, or a
   name ending in "Template" or "-symbolic"), and its shape in `color`. */
BOOL GnomeThemeImageIsTemplate(NSImage *image);
/* Overlay scrollbars (GNOME's overlay-scrolling): whether they're in use,
   and drawing one (YES when the scroller is an overlay one). */
BOOL GnomeThemeUsesOverlayScrollers(void);
BOOL GnomeThemeDrawOverlayScrollerIfNeeded(NSScroller *scroller);
/* Whether a scroll view gets libadwaita's frame: it has a border and
   doesn't hold a table or outline view (those are plain areas). */
BOOL GnomeThemeScrollViewHasFrame(NSScrollView *scrollView);
/* A colour by name: the theme's palette (system colours and its own keys),
   then GSTheme's extra colour lists (-colorNamed:state:), then fallback.
   -colorNamed:state: alone reads only the extra lists, which this theme
   doesn't ship, so palette-only keys came back as the fallback. */
NSColor *GnomeThemeColor(GSTheme *theme, NSString *key, NSColor *fallback);
NSImage *GnomeThemeTintedImage(NSImage *image, NSColor *color);
/* A template image's colour in a control: the header bar's in a toolbar
   in the bar, the disabled colour when `dimmed`, else `text`. */
NSColor *GnomeThemeTemplateImageColorInView(NSView *controlView, BOOL dimmed, NSColor *text);

/* Whether a button cell asked for the accent style (-setGSThemeStyle:
   @"accent"): libadwaita's .suggested-action, as the default button. */
BOOL GnomeThemeButtonCellHasAccentStyle(NSCell *cell);
/* Whether a visible button in the window asked for the accent style:
   then the default button is drawn as a regular button, so the accent
   one is the window's only suggested action. */
BOOL GnomeThemeWindowHasAccentButton(NSWindow *window);

/* YES when the app's first preferred language is written right to left
   (or NSForceRightToLeftWritingDirection is set): the header bar is
   mirrored, as GTK mirrors it. */
BOOL GnomeThemeUsesRightToLeft(void);

/* The colour of a header bar's title and icons in `window`: the text
   colour, dimmed when the window isn't focused. */
NSColor *GnomeThemeHeaderBarTextColor(NSWindow *window);

/* Shows `menu` with its window's top-right corner (rightAligned) or
   top-left corner at `corner` (screen coordinates) and tracks it as
   GNOME's menus behave: it stays open until a click picks an item or lands
   outside it, or Escape is pressed. Call it after the click that opens it
   has been released. */
void GnomeThemeTrackMenu(NSMenu *menu, NSPoint corner, BOOL rightAligned);
/* A press on a narrow menu bar's overflow button (#25), from
   GnomeThemeMenusAndData.m: handles it and returns YES, or returns NO when
   the press is elsewhere. */
BOOL GnomeThemeMenuBarOverflowMouseDown(NSMenuView *menuView, NSEvent *event);

/* A new (retained) ☰ button for the header bar, from GnomeThemePrimaryMenu.m:
   a 34px button 6px from the view's right edge, centred vertically. */
NSView *GnomeThemeNewHeaderBarMenuButton(void);

/* Windows loaded from nib or Gorm files, in an app built in code (#24,
   GnomeThemeNibMetrics.m): whether `view` is in one (or one is loading),
   and the view that metrics are asked for while geometry is computed
   outside drawing; it returns the one it replaces, to put back. */
BOOL GnomeThemeViewUsesNibMetrics(NSView *view);
/* The same for a cell, which may not know its control yet. */
BOOL GnomeThemeCellUsesNibMetrics(NSCell *cell, NSView *controlView);
NSView *GnomeThemeSetMetricsView(NSView *view);

@interface GnomeTheme : GSTheme
{
  GnomeThemeSettings *_settings;
  GnomeThemeMetrics *_metrics;
  GnomeThemeMetrics *_nibMetrics;
  NSColorList *_palette;
}

- (void) reloadConfiguration;
- (GnomeThemeSettings *) settings;
/* The app's metrics. */
- (GnomeThemeMetrics *) metrics;
/* The metrics of the window `view` is in: compact ones for a window loaded
   from a nib or Gorm file in an app that otherwise has GNOME's. With no
   view, the view set by GnomeThemeSetMetricsView(), or the one being
   drawn. */
- (GnomeThemeMetrics *) metricsForView: (NSView *)view;
/* For `cell`, drawn in `controlView` (or nil). */
- (GnomeThemeMetrics *) metricsForCell: (NSCell *)cell inView: (NSView *)controlView;

@end
