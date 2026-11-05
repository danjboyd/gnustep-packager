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

#import "GnomeTheme.h"
#import "Settings/GnomeThemeSettings.h"
#import "Settings/GnomeThemeMetrics.h"
#import "Rendering/GnomeThemePalette.h"
#import "Adapters/GnomeThemeWindowManager.h"
#import "Adapters/GnomeThemeSettingsMonitor.h"
#import "GSWindowTabbing.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <string.h>

static NSString *GnomeThemeRuntimeDefaultsDomain = @"GnomeThemeRuntimeDomain";

@interface GnomeTheme ()
- (void) applyRuntimeDefaults;
- (void) removeRuntimeDefaults;
- (void) windowNeedsMainMenu: (NSNotification *)notification;
- (void) defaultsDidChange: (NSNotification *)notification;
- (void) desktopSettingsDidChange: (NSNotification *)notification;
- (NSDictionary *) runtimeDefaultsDictionary;
- (void) addFont: (NSFont *)font
          forKey: (NSString *)key
     toDictionary: (NSMutableDictionary *)dictionary;
@end

/* -overriddenMethod:for: walks every override the theme registered, and
   the overrides ask for their original on every call: thousands of times
   when a long menu is sized (#46). The answer for a selector and a class
   only changes with the theme, so it is kept here, in a small table that
   is emptied when the theme changes; a collision just looks it up again. */
typedef struct
{
  SEL selector;
  Class cls;
  Class baseClass;
  IMP imp;
} GnomeThemeOriginalMethodEntry;

#define GNOME_THEME_ORIGINAL_METHOD_CACHE 1024

static GnomeThemeOriginalMethodEntry GnomeThemeOriginalMethodCache[GNOME_THEME_ORIGINAL_METHOD_CACHE];
static GSTheme *GnomeThemeOriginalMethodCacheTheme = nil;

/* An instance of exactly `cls`, used only as a lookup key: it is never
   initialised, messaged, or freed. */
static id
GnomeThemePrototype(Class cls)
{
  static NSMapTable *prototypes = nil;
  id prototype;

  if (prototypes == nil)
    {
      prototypes = [[NSMapTable alloc] initWithKeyOptions: NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality
                                             valueOptions: NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality
                                                 capacity: 16];
    }
  prototype = (id)NSMapGet (prototypes, (void *)cls);
  if (prototype == nil)
    {
      prototype = class_createInstance (cls, 0);
      NSMapInsert (prototypes, (void *)cls, (void *)prototype);
    }
  return prototype;
}

static IMP
GnomeThemeLookUpOriginalMethod(GSTheme *theme, SEL selector, id receiver, Class baseClass)
{
  IMP imp = [theme overriddenMethod: selector for: receiver];

  if (imp != NULL || baseClass == Nil)
    {
      return imp;
    }
  return [theme overriddenMethod: selector for: GnomeThemePrototype (baseClass)];
}

IMP
GnomeThemeOriginalMethod(SEL selector, id receiver, Class baseClass)
{
  GSTheme *theme = [GSTheme theme];
  Class cls = object_getClass (receiver);
  uintptr_t hash = ((uintptr_t)(void *)selector >> 3) ^ ((uintptr_t)cls >> 4) ^ ((uintptr_t)baseClass >> 5);
  GnomeThemeOriginalMethodEntry *entry = &GnomeThemeOriginalMethodCache[hash % GNOME_THEME_ORIGINAL_METHOD_CACHE];

  if (theme != GnomeThemeOriginalMethodCacheTheme)
    {
      memset (GnomeThemeOriginalMethodCache, 0, sizeof (GnomeThemeOriginalMethodCache));
      GnomeThemeOriginalMethodCacheTheme = theme;
    }
  if (entry->selector != selector || entry->cls != cls || entry->baseClass != baseClass)
    {
      entry->imp = GnomeThemeLookUpOriginalMethod (theme, selector, receiver, baseClass);
      entry->selector = selector;
      entry->cls = cls;
      entry->baseClass = baseClass;
    }
  return entry->imp;
}

/* `cls`'s own original, whatever the receiver's class: what an override
   that a subclass reaches through super must call, or a subclass the
   theme also overrides would call itself back. */
IMP
GnomeThemeOriginalMethodOfClass(SEL selector, Class cls)
{
  return GnomeThemeOriginalMethod (selector, GnomeThemePrototype (cls), Nil);
}

/* The originals change when the theme's overrides are installed or
   removed: forget them. */
void
GnomeThemeForgetOriginalMethods(void)
{
  memset (GnomeThemeOriginalMethodCache, 0, sizeof (GnomeThemeOriginalMethodCache));
  GnomeThemeOriginalMethodCacheTheme = nil;
}

/* NSParagraphStyle's class version went to 4 when libs-gui renumbered
   NSTextAlignment. */
static BOOL
GnomeThemeUsesAppKitAlignments(void)
{
  static int appKit = -1;

  if (appKit < 0)
    {
      appKit = [NSParagraphStyle version] >= 4 ? 1 : 0;
    }
  return appKit == 1;
}

NSTextAlignment
GnomeThemeCenterTextAlignment(void)
{
  return GnomeThemeUsesAppKitAlignments () ? 1 : 2;
}

NSTextAlignment
GnomeThemeRightTextAlignment(void)
{
  return GnomeThemeUsesAppKitAlignments () ? 2 : 1;
}

const CGFloat GnomeThemeApplicationMenuIconWidth = 16.0;

/* The title GSTheme gives the application item (-organizeMenu:isHorizontal:). */
static NSString *
GnomeThemeApplicationMenuTitle(void)
{
  NSString *title = [[[NSBundle mainBundle] localizedInfoDictionary]
                      objectForKey: @"ApplicationName"];

  return (title != nil) ? title : [[NSProcessInfo processInfo] processName];
}

/* The menu the app passed to -[NSApplication setAppleMenu:], which GNUstep
   itself ignores. */
static NSMenu *GnomeThemeAppleMenu = nil;

/* Whether `menu` holds items only a Cocoa application menu has: About,
   Hide, Hide Others, Show All. */
static BOOL
GnomeThemeMenuHasCocoaApplicationItems(NSMenu *menu)
{
  NSEnumerator *enumerator = [[menu itemArray] objectEnumerator];
  NSMenuItem *item;

  while ((item = [enumerator nextObject]) != nil)
    {
      SEL action = [item action];

      if (sel_isEqual (action, @selector(orderFrontStandardAboutPanel:))
        || sel_isEqual (action, @selector(hide:))
        || sel_isEqual (action, @selector(hideOtherApplications:))
        || sel_isEqual (action, @selector(unhideAllApplications:)))
        {
          return YES;
        }
    }
  return NO;
}

/* Cocoa treats the first item of the main menu as the application menu,
   whatever its title: menus built in code usually leave it untitled, and nibs
   often say "NewApplication". GSTheme only recognises an item titled with the
   app's name, so it adds an empty one and leaves the real one in the bar, as
   a blank or wrongly named item. Recognise it the way Cocoa apps mark it
   (untitled, passed to -setAppleMenu:, a nib's _NSAppleMenu, or holding
   About or Hide) and give it the app's name; macOS never shows that title.
   A GNUstep-style first menu (Info, File, ...) has none of these marks. */
static void
GnomeThemeAdoptCocoaApplicationMenu(NSMenu *menu)
{
  NSString *appTitle = GnomeThemeApplicationMenuTitle ();
  NSMenuItem *first;
  NSMenu *submenu;
  BOOL cocoa;

  if ([menu numberOfItems] == 0 || [menu itemWithTitle: appTitle] != nil)
    {
      return;
    }
  first = (NSMenuItem *)[menu itemAtIndex: 0];
  submenu = [first submenu];
  if (submenu == nil)
    {
      return;
    }
  cocoa = [[first title] length] == 0
    || submenu == GnomeThemeAppleMenu
    || ([submenu respondsToSelector: @selector(_name)]
        && [[submenu performSelector: @selector(_name)] isEqualToString: @"_NSAppleMenu"])
    || GnomeThemeMenuHasCocoaApplicationItems (submenu);
  if (cocoa)
    {
      [first setTitle: appTitle];
      [submenu setTitle: appTitle];
    }
}

/* GNOME has no Hide, Hide Others or Show All. GNUstep's -hide: orders the
   windows out and relies on its app icon to bring them back, which GNOME
   doesn't show (or, with GSSuppressAppIcon, leaves the windows up and puts a
   stray icon tile on the desktop). Leave them, and any separators they
   leave doubled, out of the main menu. */
static void
GnomeThemeRemoveHideItems(NSMenu *appMenu)
{
  NSInteger index;

  for (index = [appMenu numberOfItems] - 1; index >= 0; index--)
    {
      SEL action = [(NSMenuItem *)[appMenu itemAtIndex: index] action];

      if (sel_isEqual (action, @selector(hide:))
        || sel_isEqual (action, @selector(hideOtherApplications:))
        || sel_isEqual (action, @selector(unhideAllApplications:)))
        {
          [appMenu removeItemAtIndex: index];
        }
    }
  for (index = [appMenu numberOfItems] - 1; index >= 0; index--)
    {
      BOOL separator = [(NSMenuItem *)[appMenu itemAtIndex: index] isSeparatorItem];
      BOOL edge = (index == 0 || index == [appMenu numberOfItems] - 1);
      BOOL doubled = (index > 0 && [(NSMenuItem *)[appMenu itemAtIndex: index - 1] isSeparatorItem]);

      if (separator && (edge || doubled))
        {
          [appMenu removeItemAtIndex: index];
        }
    }
}

BOOL
GnomeThemeIsApplicationMenuItem(NSMenuItem *item)
{
  NSMenu *mainMenu = [NSApp mainMenu];

  if (item == nil || mainMenu == nil || [item menu] != mainMenu
    || [item hasSubmenu] == NO || [mainMenu indexOfItem: item] != 0)
    {
      return NO;
    }
  return [[item title] isEqualToString: GnomeThemeApplicationMenuTitle ()];
}

/* Three short lines: GNOME's open-menu-symbolic. */
void
GnomeThemeDrawApplicationMenuIcon(NSRect rect, NSColor *color)
{
  CGFloat width = GnomeThemeApplicationMenuIconWidth - 2.0;
  CGFloat x = floor (NSMidX (rect) - width / 2.0);
  CGFloat y = floor (NSMidY (rect)) - 6.0;
  NSInteger line;

  [color set];
  for (line = 0; line < 3; line++)
    {
      NSRectFill (NSMakeRect (x, y + 5.0 * line, width, 2.0));
    }
}

/* `title` cut short with an ellipsis to fit `width`: at its head or middle
   when `mode` says so, at its end otherwise (wrapping and clipping too, as
   GTK's labels in buttons). */
static NSString *
GnomeThemeTruncatedTitle(NSString *title, NSDictionary *attributes, CGFloat width, NSLineBreakMode mode)
{
  NSString *ellipsis = [NSString stringWithFormat: @"%C", (unichar)0x2026];
  NSUInteger keep = [title length];

  while (keep > 0)
    {
      NSString *candidate;

      keep--;
      if (mode == NSLineBreakByTruncatingHead)
        {
          candidate = [ellipsis stringByAppendingString:
            [title substringFromIndex: [title length] - keep]];
        }
      else if (mode == NSLineBreakByTruncatingMiddle)
        {
          NSUInteger head = (keep + 1) / 2;

          candidate = [NSString stringWithFormat: @"%@%@%@",
            [title substringToIndex: head], ellipsis,
            [title substringFromIndex: [title length] - (keep - head)]];
        }
      else
        {
          /* Not inside a character made of several (an emoji, an accent). */
          keep = [title rangeOfComposedCharacterSequenceAtIndex: keep].location;
          candidate = [[[title substringToIndex: keep]
            stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]]
            stringByAppendingString: ellipsis];
        }
      if ([candidate sizeWithAttributes: attributes].width <= width)
        {
          return candidate;
        }
    }
  return ellipsis;
}

@implementation GnomeTheme

+ (NSString *)themeName
{
  return @"Adwaita";
}

- (id) initWithBundle: (NSBundle *)bundle
{
  /* Window tabs (Apple's NSWindow API, drawn by GnomeThemeWindowTabs.m),
     where NSWindow doesn't have them already. Before GSTheme's
     -initWithBundle: records the methods the theme overrides: the theme's
     -orderWindow:relativeTo:, -sendEvent: and the rest then call the
     tabbing code's hooks as their originals. Later calls do nothing. */
  GSWindowTabbingInstall ();
  self = [super initWithBundle: bundle];
  if (self != nil)
    {
      _settings = [GnomeThemeSettings new];
      _metrics = [GnomeThemeMetrics new];
      _nibMetrics = [GnomeThemeMetrics new];
      [self reloadConfiguration];
    }
  return self;
}

- (void) dealloc
{
  RELEASE (_settings);
  RELEASE (_metrics);
  RELEASE (_nibMetrics);
  RELEASE (_palette);
  [super dealloc];
}

- (void) reloadConfiguration
{
  [_settings reload];
  [_metrics reloadFromSettings: _settings];
  [_nibMetrics reloadFromSettings: _settings compact: YES];
  DESTROY (_palette);
}

- (GnomeThemeSettings *) settings
{
  return _settings;
}

- (GnomeThemeMetrics *) metrics
{
  return _metrics;
}

- (GnomeThemeMetrics *) metricsForView: (NSView *)view
{
  if ([_settings metricsFollowWindows] && GnomeThemeViewUsesNibMetrics (view))
    {
      return _nibMetrics;
    }
  return _metrics;
}

- (GnomeThemeMetrics *) metricsForCell: (NSCell *)cell inView: (NSView *)controlView
{
  if ([_settings metricsFollowWindows] && GnomeThemeCellUsesNibMetrics (cell, controlView))
    {
      return _nibMetrics;
    }
  return _metrics;
}

- (void) activate
{
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

  [self reloadConfiguration];
  [self applyRuntimeDefaults];
  GnomeThemeForgetOriginalMethods ();
  [super activate];
  GnomeThemeForgetOriginalMethods ();
  [center addObserver: self
             selector: @selector(windowNeedsMainMenu:)
                 name: NSWindowDidBecomeKeyNotification
               object: nil];
  [center addObserver: self
             selector: @selector(windowNeedsMainMenu:)
                 name: NSWindowDidBecomeMainNotification
               object: nil];
  [center addObserver: self
             selector: @selector(defaultsDidChange:)
                 name: NSUserDefaultsDidChangeNotification
               object: nil];
  [center addObserver: self
             selector: @selector(desktopSettingsDidChange:)
                 name: GnomeThemeDesktopSettingsDidChangeNotification
               object: nil];
  GnomeThemeSettingsMonitorStart ();
}

/* GNOME's settings changed while the app runs (#64). What activating the
   theme takes from them is taken again (settings, metrics, palette, the
   runtime defaults with the fonts and GSFontHinting), and libs-gui is
   told as for a theme change: system colours are recached, menus sized,
   scroll views tiled (overlay scrollers on or off) and decorations
   redrawn. Controls that already hold a font keep it; see README. */
- (void) desktopSettingsDidChange: (NSNotification *)notification
{
  NSDictionary *oldDefaults = [self runtimeDefaultsDictionary];
  NSEnumerator *enumerator;
  NSWindow *window;

  [self reloadConfiguration];
  [self applyRuntimeDefaults];
  if ([oldDefaults isEqual: [self runtimeDefaultsDictionary]] == NO)
    {
      GnomeThemeSystemFontsDidChange ();
    }
  [[NSNotificationCenter defaultCenter]
    postNotificationName: GSThemeDidActivateNotification
                  object: self];
  GnomeThemeHeaderBarDesktopSettingsChanged ();
  enumerator = [[NSApp windows] objectEnumerator];
  while ((window = [enumerator nextObject]) != nil)
    {
      [[[window contentView] superview] setNeedsDisplay: YES];
      [window setViewsNeedDisplay: YES];
    }
}

/* Settings that apply to open windows, changed by the app or the user
   (NSUserDefaults notices a `defaults write` when it synchronises). */
- (void) defaultsDidChange: (NSNotification *)notification
{
  GnomeThemeHeaderBarToolbarSettingChanged ();
}

- (void) deactivate
{
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

  [center removeObserver: self name: NSWindowDidBecomeKeyNotification object: nil];
  [center removeObserver: self name: NSWindowDidBecomeMainNotification object: nil];
  [center removeObserver: self name: NSUserDefaultsDidChangeNotification object: nil];
  [center removeObserver: self name: GnomeThemeDesktopSettingsDidChangeNotification object: nil];
  GnomeThemeSettingsMonitorStop ();
  [self removeRuntimeDefaults];
  [super deactivate];
  GnomeThemeForgetOriginalMethods ();
}

/* With NSWindows95InterfaceStyle, GNUstep puts the main menu only into the
   windows that exist when the menu is first updated (-[NSMenu update] calls
   -updateAllWindowsWithMenu: once), so a window created after launch has no
   menu bar. Attach it when such a window becomes key or main. Windows given a
   menu of their own, and windows that can't become main (panels, menus), are
   left alone. */
- (void) windowNeedsMainMenu: (NSNotification *)notification
{
  NSWindow *window = [notification object];
  NSMenu *mainMenu = [NSApp mainMenu];

  if (mainMenu == nil || [window isKindOfClass: [NSWindow class]] == NO)
    {
      return;
    }
  if (NSInterfaceStyleForKey (@"NSMenuInterfaceStyle", nil) != NSWindows95InterfaceStyle)
    {
      return;
    }
  if ([window canBecomeMainWindow] == NO || [window menu] != nil)
    {
      return;
    }
  [self updateMenu: mainMenu forWindow: window];
}

/* GNUstep hides tool tips and drag images by shrinking their window to
   NSZeroRect and then ordering it out. Under Mutter with Xwayland, resizing a
   mapped window freezes its content until Mutter next paints it, which never
   happens once the window is unmapped: the tool tip or drag image then shows
   only the first time (GNOME/mutter#5080, gnustep/libs-gui#964; fixed in
   Mutter by its MR 5054). On Wayland, order them out without shrinking.
   Elsewhere the shrink stays, since libs-gui added it to avoid "ugly
   rectangles in some desktops". */
BOOL
GnomeThemeKeepsHiddenWindowSize(void)
{
  return getenv ("WAYLAND_DISPLAY") != NULL;
}

/* libadwaita's tool tip padding. GSToolTips sizes its window for the text
   plus 2pt on each side; the window grows by the rest. */
static const CGFloat GnomeThemeToolTipPaddingX = 10.0;
static const CGFloat GnomeThemeToolTipPaddingY = 6.0;
static const CGFloat GnomeThemeGSToolTipsInset = 2.0;

/* The tip window whose next frame needs the padding (its text was just
   set), and the one last padded, with how far its frame moved from where
   GSToolTips put it: GSToolTips keeps the tip at its own offset from the
   pointer as the pointer moves. Not retained: identity only. */
static NSWindow *GnomeThemeToolTipPendingWindow = nil;
static NSWindow *GnomeThemeToolTipPaddedWindow = nil;
static NSPoint GnomeThemeToolTipShift = { 0.0, 0.0 };

- (void) _overrideGSTTViewMethod_setText: (NSAttributedString *)text
{
  typedef void (*SetTextIMP)(id, SEL, NSAttributedString *);
  SetTextIMP originalIMP = (SetTextIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSTTView"));

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, text);
    }
  GnomeThemeToolTipPendingWindow = (text != nil) ? [(NSView *)self window] : nil;
}

/* libadwaita's tool tip: a dark box with light text, padded, without
   GNUstep's black border (the same in high contrast). Its 9pt rounded corners, 1pt light outline
   (white at 10%) and translucent box only where the tip's window has an
   alpha channel (a libs-back with GSBackBorderlessWindowAlpha, under a
   compositor): an opaque window would show the corners black. Otherwise
   the box is the colour the translucent one makes over the window
   background. */
static const CGFloat GnomeThemeToolTipRadius = 9.0;

- (void) _overrideGSTTViewMethod_drawRect: (NSRect)dirtyRect
{
  NSView *view = (NSView *)self;
  Ivar textIvar = class_getInstanceVariable ([view class], "_text");
  NSAttributedString *text = textIvar != NULL ? object_getIvar (view, textIvar) : nil;
  NSRect bounds = [view bounds];

  if (text == nil)
    {
      return;
    }
  if ([view window] != nil && GnomeThemeWindowManagerHasAlpha ([view window]))
    {
      NSBezierPath *box = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect (bounds, 0.5, 0.5)
                                                          xRadius: GnomeThemeToolTipRadius
                                                          yRadius: GnomeThemeToolTipRadius];

      NSRectFillUsingOperation (bounds, NSCompositeClear);
      /* libadwaita's own colour, 80% black, which the palette's
         toolTipColor is over the window background: what is behind the
         tip shows through, as GTK's. */
      [[NSColor colorWithCalibratedWhite: 0.0 alpha: 0.8] set];
      [box fill];
      [[NSColor colorWithCalibratedWhite: 1.0 alpha: 0.10] set];
      [box setLineWidth: 1.0];
      [box stroke];
    }
  else
    {
      [[NSColor toolTipColor] set];
      NSRectFill (bounds);
    }
  [text drawInRect: NSInsetRect (bounds, GnomeThemeToolTipPaddingX, GnomeThemeToolTipPaddingY)];
}

- (void) _overrideGSTTPanelMethod_setFrame: (NSRect)frameRect
                                   display: (BOOL)flag
{
  typedef void (*SetFrameIMP)(id, SEL, NSRect, BOOL);
  SetFrameIMP originalIMP = (SetFrameIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSTTPanel"));

  if (NSIsEmptyRect (frameRect) && GnomeThemeKeepsHiddenWindowSize ())
    {
      return;
    }
  if (NSIsEmptyRect (frameRect) == NO && self == (id)GnomeThemeToolTipPendingWindow)
    {
      /* A new tip: grow it downwards (it sits below the pointer), then keep
         it on the screen as GSToolTips did. */
      NSRect padded = frameRect;
      NSRect visible = [[NSScreen mainScreen] visibleFrame];

      GnomeThemeToolTipPendingWindow = nil;
      GnomeThemeToolTipPaddedWindow = (NSWindow *)self;
      padded.size.width += 2.0 * (GnomeThemeToolTipPaddingX - GnomeThemeGSToolTipsInset);
      padded.size.height += 2.0 * (GnomeThemeToolTipPaddingY - GnomeThemeGSToolTipsInset);
      padded.origin.y -= padded.size.height - frameRect.size.height;
      if (NSIsEmptyRect (visible) == NO)
        {
          padded.origin.x = MAX (NSMinX (visible), MIN (NSMinX (padded), NSMaxX (visible) - NSWidth (padded)));
          padded.origin.y = MAX (NSMinY (visible), MIN (NSMinY (padded), NSMaxY (visible) - NSHeight (padded)));
        }
      GnomeThemeToolTipShift = NSMakePoint (NSMinX (padded) - NSMinX (frameRect),
                                            NSMinY (padded) - NSMinY (frameRect));
      frameRect = padded;
    }
  else if (NSIsEmptyRect (frameRect) == NO && self == (id)GnomeThemeToolTipPaddedWindow
    && NSEqualSizes (frameRect.size, [(NSWindow *)self frame].size))
    {
      /* -setFrameOrigin: as the tip follows the pointer. */
      frameRect.origin.x += GnomeThemeToolTipShift.x;
      frameRect.origin.y += GnomeThemeToolTipShift.y;
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, frameRect, flag);
    }
}

- (void) _overrideGSDragViewMethod__clearupWindow
{
  typedef void (*ClearupIMP)(id, SEL);
  ClearupIMP originalIMP;

  if (GnomeThemeKeepsHiddenWindowSize ())
    {
      /* The drag view is the content view of the drag window. */
      [[(NSView *)self window] orderOut: nil];
      return;
    }
  originalIMP = (ClearupIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSDragView"));
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
}

- (NSColorList *) colors
{
  if (_palette == nil)
    {
      _palette = RETAIN ([GnomeThemePalette colorListForSettings: _settings]);
    }
  return _palette;
}

/* GSTheme reads these from a ThemeExtra colour list; the theme's colours are
   in its palette. */
- (NSColor *) toolbarBackgroundColor
{
  NSColor *color = [[self colors] colorWithKey: @"toolbarBackgroundColor"];

  return (color != nil) ? color : [super toolbarBackgroundColor];
}

- (NSColor *) toolbarBorderColor
{
  NSColor *color = [[self colors] colorWithKey: @"toolbarBorderColor"];

  return (color != nil) ? color : [super toolbarBorderColor];
}

- (BOOL) menuShouldShowIcon
{
  return NO;
}

- (CGFloat) menuBarHeight
{
  return [_metrics menuBarHeight];
}

- (CGFloat) menuItemHeight
{
  return [_metrics menuItemHeight];
}

- (CGFloat) menuSeparatorHeight
{
  return [_metrics menuSeparatorHeight];
}

- (float) defaultScrollerWidth
{
  return [_metrics scrollerWidth];
}

/* The theme's scrollers have no arrows (NSScrollerArrowsNone), but
   libs-gui still moves the knob one arrow's width along unless the arrows
   are "at the same end": the knob stopped 13pt short of the start and ran
   13pt past the end, under the corner and out of the scroller. */
- (BOOL) scrollerArrowsSameEndForScroller: (NSScroller *)aScroller
{
  if ([aScroller arrowsPosition] == NSScrollerArrowsNone)
    {
      return YES;
    }
  return [super scrollerArrowsSameEndForScroller: aScroller];
}

- (GSThemeMargins) buttonMarginsForCell: (NSCell *)cell
                                  style: (int)style
                                  state: (GSThemeControlState)state
{
  GSThemeMargins margins = [super buttonMarginsForCell: cell
                                                 style: style
                                                 state: state];
  GnomeThemeMetrics *metrics = [self metricsForCell: cell inView: nil];
  CGFloat horizontal = [metrics buttonHorizontalPadding];
  CGFloat vertical = [metrics buttonVerticalPadding];

  switch (style)
    {
      case NSRoundedBezelStyle:
      case NSRoundRectBezelStyle:
      case NSTexturedRoundedBezelStyle:
        margins.left = MAX (margins.left, horizontal);
        margins.right = MAX (margins.right, horizontal);
        margins.top = MAX (margins.top, vertical);
        margins.bottom = MAX (margins.bottom, vertical);
        break;

      default:
        break;
    }

  return margins;
}

- (CGFloat) tabHeightForType: (NSTabViewType)type
{
  CGFloat height = [super tabHeightForType: type];

  switch (type)
    {
      case NSTopTabsBezelBorder:
      case NSBottomTabsBezelBorder:
      case NSLeftTabsBezelBorder:
      case NSRightTabsBezelBorder:
        /* The tab view's window's (GnomeThemeSetMetricsView). */
        height = MAX (height, [[self metricsForView: nil] minimumTabHeight]);
        break;

      default:
        break;
    }

  return height;
}

- (CGFloat) proposedTitleWidth: (CGFloat)proposedWidth
                   forMenuView: (NSMenuView *)aMenuView
{
  CGFloat padding = [_metrics horizontalMenuTitlePadding];

  /* GTK's menu bar leaves about 20px between titles; NSMenuView adds its
     edge padding (4pt a side) to this. */
  if ([aMenuView isHorizontal] == YES)
    {
      return proposedWidth + 12.0;
    }
  return proposedWidth + padding;
}

- (void) drawTitleForMenuItemCell: (NSMenuItemCell *)cell
                        withFrame: (NSRect)cellFrame
                           inView: (NSView *)controlView
                            state: (GSThemeControlState)state
                     isHorizontal: (BOOL)isHorizontal
{
  NSRect titleRect = [cell titleRectForBounds: cellFrame];
  NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
  NSFont *font = nil;
  NSColor *textColor = nil;
  BOOL highlighted = [cell isHighlighted]
    || (state == GSThemeSelectedState)
    || (state == GSThemeSelectedFirstResponderState)
    || (state == GSThemeHighlightedState)
    || (state == GSThemeHighlightedFirstResponderState);
  NSDictionary *sizingAttributes = nil;
  NSSize titleSize;
  NSString *title = [[cell menuItem] title];

  if (isHorizontal)
    {
      font = [_settings menuBarFont];
    }
  else
    {
      font = [cell font];
      if (font == nil)
        {
          font = [_settings menuFont];
        }
    }

  if (font != nil)
    {
      [attributes setObject: font forKey: NSFontAttributeName];
    }

  /* A pop-up button's title is its selected item's, and that item stays
     enabled when the button is disabled: the button's own state counts too,
     or a disabled pop-up looked clickable (#69). */
  if (![[cell menuItem] isEnabled]
    || ([cell isKindOfClass: [NSPopUpButtonCell class]] && [cell isEnabled] == NO))
    {
      textColor = [NSColor disabledControlTextColor];
    }
  else if (highlighted && isHorizontal)
    {
      /* White on the menu bar's accent pill. */
      textColor = [NSColor selectedMenuItemTextColor];
    }
  else
    {
      /* A menu's hovered row is libadwaita's neutral one, and keeps the
         text colour (#67); it had been white, on the accent or, in a pop-up
         button's menu, on the pale inactive selection. */
      textColor = [NSColor controlTextColor];
    }

  if (textColor != nil)
    {
      [attributes setObject: textColor forKey: NSForegroundColorAttributeName];
    }

  if (isHorizontal && GnomeThemeIsApplicationMenuItem ([cell menuItem]))
    {
      GnomeThemeDrawApplicationMenuIcon (cellFrame, textColor);
      return;
    }

  if ([title length] == 0)
    {
      return;
    }

  sizingAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                        font, NSFontAttributeName,
                        nil];
  titleSize = [title sizeWithAttributes: sizingAttributes];
  /* A pop-up button's title is cut short with an ellipsis to fit before
     its chevron, as GtkDropDown's label: at the end, or where the cell's
     line break mode says (#67). It had wrapped out of sight word by word. */
  if ([cell isKindOfClass: [NSPopUpButtonCell class]]
    && titleSize.width > NSWidth (titleRect))
    {
      title = GnomeThemeTruncatedTitle (title, sizingAttributes, NSWidth (titleRect), [cell lineBreakMode]);
      titleSize = [title sizeWithAttributes: sizingAttributes];
    }
  if (isHorizontal)
    {
      titleRect.origin.x = floor (NSMidX (titleRect) - (titleSize.width / 2.0));
      titleRect.size.width = ceil (titleSize.width);
    }
  titleRect.origin.y = floor (NSMidY (titleRect) - (titleSize.height / 2.0));
  titleRect.size.height = ceil (titleSize.height);

  [title drawInRect: titleRect withAttributes: attributes];
}

/* GNOME apps have no menu named after the app. GSTheme puts one first in a
   horizontal main menu, collecting the menu's loose items (Info, Quit, ...);
   when there were none it is empty and drawn disabled, so remove it. A
   non-empty one is drawn as the GNOME main-menu icon (see
   -drawTitleForMenuItemCell:...) at the end of the bar (see
   -[NSMenuView rectOfItemAtIndex:] in the overrides). GNUstep can't hide menu
   items, and moving the item itself to the end doesn't last: GSTheme moves it
   back to the front. */
- (void) organizeMenu: (NSMenu *)menu
         isHorizontal: (BOOL)horizontal
{
  BOOL mainMenu = (menu == [NSApp mainMenu]);

  if (horizontal && mainMenu)
    {
      GnomeThemeAdoptCocoaApplicationMenu (menu);
    }

  [super organizeMenu: menu isHorizontal: horizontal];

  if (horizontal && [menu numberOfItems] > 0)
    {
      NSMenuItem *first = (NSMenuItem *)[menu itemAtIndex: 0];

      if (GnomeThemeIsApplicationMenuItem (first))
        {
          GnomeThemeRemoveHideItems ([first submenu]);
          if ([[first submenu] numberOfItems] == 0)
            {
              [menu removeItemAtIndex: 0];
            }
        }
    }
}

- (void) _overrideNSApplicationMethod_setAppleMenu: (NSMenu *)aMenu
{
  typedef void (*SetMenuIMP)(id, SEL, NSMenu *);
  SetMenuIMP originalIMP = (SetMenuIMP)GnomeThemeOriginalMethod (_cmd, self, [NSApplication class]);

  ASSIGN (GnomeThemeAppleMenu, aMenu);
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, aMenu);
    }
}

/* With GNOME's metrics, text is laid out and drawn at the font's own size,
   as GTK draws it. libs-back makes a screen font one whole pixel size up
   (GNOME's 11pt, 14.67px, became 15px), so text set in it ran 2-3% wider
   than GTK's at the same font and wrapped earlier. With compact metrics
   (whole sizes, nib layouts) GNUstep's screen fonts stay. */
- (NSFont *) _overrideNSFontMethod_screenFont
{
  typedef NSFont *(*ScreenFontIMP)(id, SEL);
  GnomeTheme *theme = (GnomeTheme *)[GSTheme theme];
  ScreenFontIMP originalIMP;

  if ([theme isKindOfClass: [GnomeTheme class]] && [[theme metrics] compact] == NO)
    {
      return (NSFont *)self;
    }
  originalIMP = (ScreenFontIMP)GnomeThemeOriginalMethod (_cmd, self, [NSFont class]);
  return originalIMP != NULL ? originalIMP (self, _cmd) : (NSFont *)self;
}

- (void) addFont: (NSFont *)font
          forKey: (NSString *)key
     toDictionary: (NSMutableDictionary *)dictionary
{
  if (font == nil || key == nil || dictionary == nil)
    {
      return;
    }

  [dictionary setObject: [font fontName] forKey: key];
  [dictionary setObject: [NSNumber numberWithFloat: [font pointSize]]
                 forKey: [NSString stringWithFormat: @"%@Size", key]];
}

- (NSDictionary *) runtimeDefaultsDictionary
{
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  NSFont *interfaceFont = [_settings interfaceFont];
  NSFont *boldInterfaceFont = [_settings boldInterfaceFont];
  NSFont *menuFont = [_settings menuFont];
  NSFont *menuBarFont = [_settings menuBarFont];
  NSFont *fixedPitchFont = [_settings fixedPitchFont];
  CGFloat baseFontSize = [_settings interfaceFontSize];

  [self addFont: interfaceFont forKey: @"NSFont" toDictionary: dictionary];
  [self addFont: boldInterfaceFont forKey: @"NSBoldFont" toDictionary: dictionary];
  [self addFont: interfaceFont forKey: @"NSUserFont" toDictionary: dictionary];
  [self addFont: interfaceFont forKey: @"NSControlContentFont" toDictionary: dictionary];
  [self addFont: interfaceFont forKey: @"NSLabelFont" toDictionary: dictionary];
  [self addFont: interfaceFont forKey: @"NSMessageFont" toDictionary: dictionary];
  [self addFont: interfaceFont forKey: @"NSToolTipsFont" toDictionary: dictionary];
  [self addFont: menuFont forKey: @"NSMenuFont" toDictionary: dictionary];
  [self addFont: menuBarFont forKey: @"NSMenuBarFont" toDictionary: dictionary];
  [self addFont: fixedPitchFont forKey: @"NSUserFixedPitchFont" toDictionary: dictionary];

  [dictionary setObject: [NSNumber numberWithFloat: baseFontSize]
                 forKey: @"NSFontSize"];
  [dictionary setObject: [NSNumber numberWithFloat: MAX (10.0, baseFontSize - 1.0)]
                 forKey: @"NSSmallFontSize"];
  [dictionary setObject: [NSNumber numberWithFloat: MAX (9.0, baseFontSize - 2.0)]
                 forKey: @"NSMiniFontSize"];
  [dictionary setObject: [NSNumber numberWithFloat: [_metrics menuBarHeight]]
                 forKey: @"GSMenuBarHeight"];
  [dictionary setObject: [NSNumber numberWithFloat: [_metrics menuItemHeight]]
                 forKey: @"GSMenuItemHeight"];
  [dictionary setObject: [NSNumber numberWithFloat: [_metrics menuSeparatorHeight]]
                 forKey: @"GSMenuSeparatorHeight"];
  [dictionary setObject: [NSNumber numberWithFloat: [_metrics scrollerWidth]]
                 forKey: @"GSScrollerDefaultWidth"];
  if ([_metrics compact] == NO)
    {
      /* GNOME's hint style for the outlines (font-hinting), with hinted
         metrics as libs-back's default has them (GSFontHinting's high
         nibble 2): whole-pixel advances and line heights. GTK 4 doesn't
         hint the metrics, but libs-gui sizes tool tips, menus and cells
         from text without rounding, so fractional metrics give windows
         fractional frames. Scaled (GSScaleFactor not 1), metrics hinting
         off (nibble 1), as libs-back's own default is then: hinted
         advances at a scale broke the spacing between glyphs ("must
         align" drawn "mustalign" at 2x). A user's own GSFontHinting
         still wins. */
      float scale = [[NSUserDefaults standardUserDefaults] floatForKey: @"GSScaleFactor"];
      NSInteger metrics = (scale == 0.0f || scale == 1.0f) ? 32 : 16;

      [dictionary setObject: [NSNumber numberWithInteger: metrics + [_settings fontHintStyle]]
                     forKey: @"GSFontHinting"];
      [dictionary setObject: [NSNumber numberWithFloat: [_metrics minimumTabHeight]]
                     forKey: @"GSMinimumTabHeight"];
      [dictionary setObject: [NSNumber numberWithFloat: [_metrics maximumTabHeight]]
                     forKey: @"GSMaximumTabHeightPrivate"];
    }

  return dictionary;
}

- (void) applyRuntimeDefaults
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray *searchList = [[defaults searchList] mutableCopy];
  NSUInteger index = NSNotFound;

  /* Replaced as a whole when GNOME's settings change (#64):
     NSUserDefaults won't set a volatile domain that exists. */
  [defaults removeVolatileDomainForName: GnomeThemeRuntimeDefaultsDomain];
  [defaults setVolatileDomain: [self runtimeDefaultsDictionary]
                      forName: GnomeThemeRuntimeDefaultsDomain];

  if ([searchList containsObject: GnomeThemeRuntimeDefaultsDomain] == NO)
    {
      index = [searchList indexOfObject: @"GSThemeDomain"];
      if (index == NSNotFound)
        {
          index = [searchList indexOfObject: GSConfigDomain];
        }
      if (index == NSNotFound)
        {
          index = [searchList indexOfObject: NSRegistrationDomain];
        }
      if (index == NSNotFound)
        {
          index = [searchList count];
        }

      [searchList insertObject: GnomeThemeRuntimeDefaultsDomain atIndex: index];
      [defaults setSearchList: searchList];
    }

  RELEASE (searchList);
}

- (void) removeRuntimeDefaults
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray *searchList = [[defaults searchList] mutableCopy];

  [searchList removeObject: GnomeThemeRuntimeDefaultsDomain];
  [defaults setSearchList: searchList];
  [defaults removeVolatileDomainForName: GnomeThemeRuntimeDefaultsDomain];

  RELEASE (searchList);
}

@end
